const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');

// 执行真实 relay，仅替换外网连接和启动监听；媒体逻辑不在测试中复制。
function loadRelay(upstreamRequest) {
  const filename = path.join(__dirname, 'server.cjs');
  const localRequire = createRequire(filename);
  const context = {
    require: (name) => name === 'node:http'
      ? { ...http, createServer: () => ({ listen() {} }) }
      : localRequire(name),
    module: { exports: {} }, __dirname, Buffer, URL, URLSearchParams,
    process: { env: {} }, console, AbortController, setTimeout, clearTimeout,
    __upstreamRequest: upstreamRequest,
  };
  vm.runInNewContext(fs.readFileSync(filename, 'utf8') +
    '\nupstreamRequest = __upstreamRequest; module.exports = relay;', context,
  { filename });
  return context.module.exports;
}

async function listen(t, handler) {
  const server = http.createServer(handler);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise((resolve) => {
    server.closeAllConnections(); server.close(resolve);
  }));
  return `http://127.0.0.1:${server.address().port}`;
}

async function gateway(t) {
  const relay = loadRelay(async (url, method, headers) =>
    http.request(url, { method, headers, agent: false }));
  return listen(t, (req, res) => {
    relay(req, res, new URL(req.url, `http://${req.headers.host}`)).catch((error) => {
      if (res.destroyed) return;
      if (res.headersSent) { res.destroy(error); return; }
      res.writeHead(502, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: error.message }));
    });
  });
}

function proxyUrl(web, target, headers) {
  const query = new URLSearchParams({ url: target });
  if (headers) query.set('headers', Buffer.from(JSON.stringify(headers)).toString('base64url'));
  return `${web}/api/proxy?${query}`;
}

function request(url, headers = {}) {
  return new Promise((resolve, reject) => {
    const req = http.get(url, { headers, agent: false }, (res) => {
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.once('error', reject);
      res.once('end', () => resolve({
        status: res.statusCode, headers: res.headers,
        body: Buffer.concat(chunks), text: Buffer.concat(chunks).toString('utf8'),
      }));
    });
    req.setTimeout(2000, () => req.destroy(new Error('Fixture request timed out')));
    req.once('error', reject);
  });
}

function mediaLines(text) {
  return text.split(/\r?\n/).filter((line) => line && !line.startsWith('#'));
}

function resourceUrl(web, value) {
  assert.match(value, /^\/api\/proxy\?/);
  return new URL(value, web).href;
}

async function closedWithin(closed) {
  let timer;
  try {
    return await Promise.race([
      closed.then(() => true),
      new Promise((resolve) => { timer = setTimeout(() => resolve(false), 500); }),
    ]);
  } finally { clearTimeout(timer); }
}

test('extensionless HLS with an image MIME is detected, typed and rewritten', async (t) => {
  const manifest = '#EXTM3U\n#EXT-X-TARGETDURATION:5\n#EXTINF:5,\nchunks/one.ts\n#EXT-X-ENDLIST\n';
  const upstream = await listen(t, (_req, res) => {
    res.writeHead(200, { 'content-type': 'image/jpeg', 'content-length': Buffer.byteLength(manifest) });
    // 将标记拆开，确保识别不依赖第一次收到完整的 #EXTM3U。
    res.write(manifest.slice(0, 3));
    setImmediate(() => res.end(manifest.slice(3)));
  });
  const web = await gateway(t);
  const result = await request(proxyUrl(web, `${upstream}/opaque/resource?id=123`));
  assert.equal(result.status, 200);
  assert.match(result.headers['content-type'], /mpegurl/i);
  const segment = new URL(resourceUrl(web, mediaLines(result.text)[0]));
  assert.equal(segment.searchParams.get('url'), `${upstream}/opaque/chunks/one.ts`);
  assert.notEqual(Number(result.headers['content-length']), Buffer.byteLength(manifest));
});

test('cross-origin redirect credentials stay removed from rewritten child playlists', async (t) => {
  const received = [];
  const cdn = await listen(t, (req, res) => {
    received.push({ path: req.url, headers: req.headers });
    res.setHeader('content-type', 'application/vnd.apple.mpegurl');
    res.end(req.url === '/video/master.m3u8'
      ? '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nchild.m3u8\n'
      : '#EXTM3U\n#EXT-X-ENDLIST\n');
  });
  const origin = await listen(t, (_req, res) => {
    res.writeHead(302, { location: `${cdn}/video/master.m3u8` }); res.end();
  });
  const web = await gateway(t);
  const result = await request(proxyUrl(web, `${origin}/entry`, {
    Authorization: 'Bearer fixture-only', Cookie: 'session=fixture-only', 'User-Agent': 'Fixture/1',
  }));
  assert.equal(received[0].headers.authorization, undefined);
  assert.equal(received[0].headers.cookie, undefined);
  await request(resourceUrl(web, mediaLines(result.text)[0]));
  assert.equal(received[1].headers.authorization, undefined);
  assert.equal(received[1].headers.cookie, undefined);
  assert.equal(received[1].headers['user-agent'], 'Fixture/1');
});

test('master, child, relative segment, initialization map and key stay on the gateway', async (t) => {
  const received = [];
  const upstream = await listen(t, (req, res) => {
    received.push(req.url);
    if (req.url === '/show/master.m3u8') {
      res.setHeader('content-type', 'application/vnd.apple.mpegurl');
      res.end('#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",URI="audio/playlist"\n' +
        '#EXT-X-STREAM-INF:BANDWIDTH=1000,AUDIO="audio"\nvideo/playlist\n');
    } else if (req.url === '/show/video/playlist') {
      res.setHeader('content-type', 'application/vnd.apple.mpegurl');
      res.end('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="../keys/key.bin?token=fixture"\n' +
        '#EXT-X-MAP:URI="init.mp4"\n#EXTINF:5,\n../chunks/0001.ts?part=1\n#EXT-X-ENDLIST\n');
    } else if (req.url === '/show/audio/playlist') {
      res.setHeader('content-type', 'application/vnd.apple.mpegurl');
      res.end('#EXTM3U\n#EXT-X-ENDLIST\n');
    } else { res.end('fixture-media'); }
  });
  const web = await gateway(t);
  const master = await request(proxyUrl(web, `${upstream}/show/master.m3u8`));
  const audio = master.text.match(/URI="([^"]+)"/)[1];
  await request(resourceUrl(web, audio));
  const child = await request(resourceUrl(web, mediaLines(master.text)[0]));
  for (const match of child.text.matchAll(/URI="([^"]+)"/g)) {
    assert.equal((await request(resourceUrl(web, match[1]))).text, 'fixture-media');
  }
  assert.equal((await request(resourceUrl(web, mediaLines(child.text)[0]))).text, 'fixture-media');
  assert.deepEqual(received, [
    '/show/master.m3u8', '/show/audio/playlist', '/show/video/playlist',
    '/show/keys/key.bin?token=fixture', '/show/video/init.mp4', '/show/chunks/0001.ts?part=1',
  ]);
});

test('binary media keeps Range, response status, content range and exact bytes', async (t) => {
  let receivedRange;
  const bytes = Buffer.from([0, 255, 1, 128]);
  const upstream = await listen(t, (req, res) => {
    receivedRange = req.headers.range;
    res.writeHead(206, { 'content-type': 'video/mp4', 'content-range': 'bytes 10-13/100',
      'content-length': bytes.length, 'accept-ranges': 'bytes' });
    res.end(bytes);
  });
  const web = await gateway(t);
  const result = await request(proxyUrl(web, `${upstream}/media.bin`), { range: 'bytes=10-13' });
  assert.equal(receivedRange, 'bytes=10-13');
  assert.equal(result.status, 206);
  assert.equal(result.headers['content-range'], 'bytes 10-13/100');
  assert.equal(result.headers['accept-ranges'], 'bytes');
  assert.equal(result.headers['content-length'], '4');
  assert.deepEqual(result.body, bytes);
});

test('client cancellation before response headers closes the upstream connection', async (t) => {
  let markStarted, markClosed;
  const started = new Promise((resolve) => { markStarted = resolve; });
  const closed = new Promise((resolve) => { markClosed = resolve; });
  const upstream = await listen(t, (_req, res) => {
    res.once('close', markClosed); markStarted();
  });
  const web = await gateway(t);
  const req = http.get(proxyUrl(web, `${upstream}/pending`));
  req.on('error', () => {});
  await started; req.destroy();
  assert.equal(await closedWithin(closed), true, 'pending upstream must close when the browser disconnects');
});

test('client cancellation while buffering an HLS playlist closes the upstream connection', async (t) => {
  let markStarted, markClosed;
  const started = new Promise((resolve) => { markStarted = resolve; });
  const closed = new Promise((resolve) => { markClosed = resolve; });
  const upstream = await listen(t, (_req, res) => {
    res.once('close', markClosed);
    res.writeHead(200, { 'content-type': 'application/vnd.apple.mpegurl' });
    res.write('#EXTM3U\n'); markStarted();
  });
  const web = await gateway(t);
  const req = http.get(proxyUrl(web, `${upstream}/pending.m3u8`));
  req.on('error', () => {});
  await started; req.destroy();
  assert.equal(await closedWithin(closed), true, 'playlist buffering must stop when the browser disconnects');
});

test('client cancellation during binary media streaming closes the upstream connection', async (t) => {
  let markClosed;
  const closed = new Promise((resolve) => { markClosed = resolve; });
  const upstream = await listen(t, (_req, res) => {
    res.once('close', markClosed);
    res.writeHead(200, { 'content-type': 'video/mp4' });
    res.write('first-media-chunk');
  });
  const web = await gateway(t);
  await new Promise((resolve, reject) => {
    const req = http.get(proxyUrl(web, `${upstream}/pending.mp4`), (res) => {
      res.once('data', () => { req.destroy(); resolve(); });
    });
    req.once('error', (error) => { if (error.code !== 'ECONNRESET') reject(error); });
  });
  assert.equal(await closedWithin(closed), true, 'binary streaming must stop when the browser disconnects');
});

test('HLS Range responses become complete rewritten 200 playlists without stale range metadata', async (t) => {
  const playlist = Buffer.from('#EXTM3U\n#EXT-X-TARGETDURATION:5\n' +
    '#EXTINF:5,\nchunks/one.ts\n#EXTINF:5,\nchunks/two.ts\n#EXTINF:5,\nchunks/three.ts\n#EXT-X-ENDLIST\n');
  for (const extensionless of [false, true]) {
    for (const partial of [true, false]) {
      await t.test(`${extensionless ? 'extensionless image MIME' : 'known m3u8'} with ${partial ? 'partial' : 'complete'} upstream 206`, async (caseTest) => {
        const upstream = await listen(caseTest, (req, res) => {
          const requestedRange = Boolean(req.headers.range);
          // 开放字节范围也可能只拿到清单前段，代理必须取齐后才能重写。
          const content = requestedRange && partial
            ? playlist.subarray(0, playlist.indexOf('chunks/two.ts') + 6)
            : playlist;
          res.writeHead(requestedRange ? 206 : 200, {
            'content-type': extensionless ? 'image/jpeg' : 'application/vnd.apple.mpegurl',
            'content-length': content.length,
            'accept-ranges': 'bytes',
            ...(requestedRange ? { 'content-range': `bytes 0-${content.length - 1}/${playlist.length}` } : {}),
          });
          res.end(content);
        });
        const web = await gateway(caseTest);
        const targetPath = extensionless ? '/show/opaque-resource' : '/show/main.m3u8';
        const result = await request(proxyUrl(web, `${upstream}${targetPath}`), { range: 'bytes=0-' });

        assert.equal(result.status, 200, 'rewritten HLS is a complete representation, not the upstream byte range');
        assert.equal(result.headers['content-range'], undefined, 'upstream byte offsets are invalid after URL rewriting');
        assert.equal(result.headers['accept-ranges'], undefined, 'rewritten playlist must not advertise upstream byte ranges');
        assert.match(result.headers['content-type'], /mpegurl/i);
        assert.match(result.text, /#EXT-X-ENDLIST\s*$/, 'a partial upstream playlist must be fetched completely');
        const segments = mediaLines(result.text).map((line) =>
          new URL(resourceUrl(web, line)).searchParams.get('url'));
        assert.deepEqual(segments, ['one.ts', 'two.ts', 'three.ts'].map((name) => `${upstream}/show/chunks/${name}`));
        if (result.headers['content-length'] !== undefined) {
          assert.equal(Number(result.headers['content-length']), result.body.length);
        }
      });
    }
  }
});

test('MP4 and TS Range responses remain byte-exact streaming 206 responses', async (t) => {
  for (const [extension, contentType] of [['mp4', 'video/mp4'], ['ts', 'video/mp2t']]) {
    await t.test(extension, async (caseTest) => {
      const payload = Buffer.from(Array.from({ length: 256 }, (_, index) => index));
      const selected = payload.subarray(32, 132);
      const requests = [];
      let finishUpstream, upstreamResponse, streamedBeforeComplete = false;
      const upstream = await listen(caseTest, (req, res) => {
        requests.push(req.headers.range);
        upstreamResponse = res;
        res.writeHead(206, {
          'content-type': contentType,
          'content-length': selected.length,
          'content-range': 'bytes 32-131/256',
          'accept-ranges': 'bytes',
        });
        // 后半段只有在浏览器收到前半段后才发送，防止整段缓存伪装成流式通过。
        finishUpstream = () => res.end(selected.subarray(17));
        res.write(selected.subarray(0, 17));
      });
      const web = await gateway(caseTest);
      const result = await new Promise((resolve, reject) => {
        const req = http.get(proxyUrl(web, `${upstream}/movie.${extension}`),
          { headers: { range: 'bytes=32-131' }, agent: false }, (res) => {
            const chunks = [];
            res.on('data', (chunk) => {
              chunks.push(chunk);
              if (finishUpstream) {
                streamedBeforeComplete = !upstreamResponse.writableEnded;
                const finish = finishUpstream;
                finishUpstream = null;
                finish();
              }
            });
            res.once('error', reject);
            res.once('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
          });
        req.setTimeout(2000, () => req.destroy(new Error('Binary Range was buffered instead of streamed')));
        req.once('error', reject);
      });

      assert.equal(streamedBeforeComplete, true);
      assert.deepEqual(requests, ['bytes=32-131'], 'binary ranges must not trigger a full-resource retry');
      assert.equal(result.status, 206);
      assert.equal(result.headers['content-type'], contentType);
      assert.equal(result.headers['content-range'], 'bytes 32-131/256');
      assert.equal(result.headers['accept-ranges'], 'bytes');
      assert.equal(Number(result.headers['content-length']), selected.length);
      assert.deepEqual(result.body, selected);
    });
  }
});

test('unsolicited partial HLS fails without retrying or forwarding stale range metadata', async (t) => {
  let calls = 0;
  const upstream = await listen(t, (_req, res) => {
    calls++;
    res.writeHead(206, {
      'content-type': 'application/vnd.apple.mpegurl',
      'content-range': 'bytes 0-7/999', 'content-length': '8',
    });
    res.end('#EXTM3U\n');
  });
  const result = await request(proxyUrl(await gateway(t), `${upstream}/video.m3u8`));
  assert.equal(result.status, 502);
  assert.equal(calls, 1);
  assert.equal(result.headers['content-range'], undefined);
  assert.match(result.text, /上游未返回完整播放列表/);
});
