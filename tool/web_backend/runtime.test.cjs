const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { createRuntimeBridge } = require('./runtime.cjs');

async function listen(handler) {
  const server = http.createServer(handler);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  return { server, port: server.address().port,
    close: () => new Promise((resolve) => { server.closeAllConnections(); server.close(resolve); }) };
}
function request(port, path, { method = 'GET', body } = {}) {
  return new Promise((resolve, reject) => {
    const value = body == null ? '' : body;
    const req = http.request({ hostname: '127.0.0.1', port, path, method,
      headers: { 'X-Kazumi-Request': '1', 'content-type': 'application/json',
        'content-length': Buffer.byteLength(value) } }, (res) => {
      const chunks = []; res.on('data', (chunk) => chunks.push(chunk));
      res.once('end', () => resolve({ status: res.statusCode, data: JSON.parse(Buffer.concat(chunks)) }));
    });
    req.once('error', reject); req.end(value);
  });
}
function handler(bridge) {
  return (req, res) => bridge(req, res, new URL(req.url, 'http://localhost'));
}
test('disabled runtime and invalid routes do not forward', async () => {
  const web = await listen(handler(createRuntimeBridge()));
  try {
    assert.equal((await request(web.port, '/api/runtime/v1/health')).data.error.code, 'RUNTIME_UNAVAILABLE');
    assert.equal((await request(web.port, '/api/runtime/v1/scripts/run')).status, 422);
  } finally { await web.close(); }
});

test('Lumina uses only the fixed SDK route and preserves opaque episode references', async () => {
  const received = [];
  const upstream = await listen(async (req, res) => {
    const chunks = []; for await (const chunk of req) chunks.push(chunk);
    received.push({ path: req.url, body: JSON.parse(Buffer.concat(chunks)) });
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ data: { status: 'ready', media: {
      url: 'https://media.example/episode.m3u8', format: 'hls', headers: { 'User-Agent': '' },
    } } }));
  });
  const web = await listen(handler(createRuntimeBridge({ port: upstream.port })));
  try {
    const payload = { operation: 'play', payload: {
      videoId: '18446744073709551616', playFormat: 'mp4', part: '特别篇·上',
    } };
    const result = await request(web.port, '/api/runtime/v1/adapters/lumina/sdk',
      { method: 'POST', body: JSON.stringify(payload) });
    assert.equal(result.status, 200);
    assert.deepEqual(received, [{ path: '/v1/adapters/lumina/sdk', body: payload }]);
    assert.deepEqual(result.data.data.media.headers, { 'User-Agent': '' });
    assert.equal((await request(web.port, '/api/runtime/v1/adapters/lumina/sdk')).status, 422);
    assert.equal((await request(web.port, '/api/runtime/v1/adapters/unknown/sdk',
      { method: 'POST', body: '{}' })).status, 422);
    assert.equal(received.length, 1);
  } finally { await web.close(); await upstream.close(); }
});
test('bridge forwards a fixed protocol route, query and POST body', async () => {
  const received = [];
  const upstream = await listen(async (req, res) => {
    const chunks = []; for await (const chunk of req) chunks.push(chunk);
    received.push({ path: req.url, headers: req.headers, body: Buffer.concat(chunks).toString() });
    res.setHeader('content-type', 'application/json'); res.end('{"data":{"ok":true}}');
  });
  const web = await listen(handler(createRuntimeBridge({ port: upstream.port })));
  try {
    await request(web.port, '/api/runtime/v1/adapters/template/episodes?source=test');
    await request(web.port, '/api/runtime/v1/adapters/template/resolve',
      { method: 'POST', body: '{"episodeUrl":"test"}' });
    assert.equal(received[0].path, '/v1/adapters/template/episodes?source=test');
    assert.equal(received[1].body, '{"episodeUrl":"test"}');
    assert.equal(received[1].headers.host, `127.0.0.1:${upstream.port}`);
    assert.equal(received[1].headers['x-kazumi-request'], '1');
    assert.equal(received[1].headers.cookie, undefined);
    await request(web.port, '/api/runtime/v1/adapters/miomedia/sdk',
      { method: 'POST', body: '{"operation":"recommend","payload":{}}' });
    assert.equal(received[2].path, '/v1/adapters/miomedia/sdk');
    assert.equal(received[2].body, '{"operation":"recommend","payload":{}}');
    assert.equal((await request(web.port, '/api/runtime/v1/adapters/template/resolve',
      { method: 'POST', body: 'x'.repeat(33000) })).status, 413);
    assert.equal(received.length, 3);
  } finally { await web.close(); await upstream.close(); }
});
test('bridge times out and cancels the upstream request', async () => {
  let closed = false;
  const upstream = await listen((req, res) => res.once('close', () => { closed = true; }));
  const web = await listen(handler(createRuntimeBridge({ port: upstream.port, timeoutMs: 60 })));
  try {
    const result = await request(web.port, '/api/runtime/v1/health');
    assert.equal(result.status, 504);
    assert.equal(result.data.error.code, 'TIMEOUT');
    await new Promise((resolve) => setTimeout(resolve, 30));
    assert.equal(closed, true);
  } finally { await web.close(); await upstream.close(); }
});
test('client disconnect aborts fixed forwarding', async () => {
  let closed = false;
  let started;
  const ready = new Promise((resolve) => { started = resolve; });
  const upstream = await listen((req, res) => {
    res.once('close', () => { closed = true; }); started();
  });
  const web = await listen(handler(createRuntimeBridge({ port: upstream.port })));
  try {
    const req = http.get(`http://127.0.0.1:${web.port}/api/runtime/v1/health`);
    req.on('error', () => {}); await ready; req.destroy();
    await new Promise((resolve) => setTimeout(resolve, 40));
    assert.equal(closed, true);
  } finally { await web.close(); await upstream.close(); }
});
test('oversized and redirect responses are rejected', async () => {
  let count = 0;
  const upstream = await listen((req, res) => {
    if (count++ === 0) res.end('x'.repeat(2 * 1024 * 1024 + 1));
    else { res.writeHead(302, { location: 'http://127.0.0.1:1' }); res.end('{}'); }
  });
  const web = await listen(handler(createRuntimeBridge({ port: upstream.port })));
  try {
    assert.equal((await request(web.port, '/api/runtime/v1/health')).data.error.code, 'RESPONSE_TOO_LARGE');
    assert.equal((await request(web.port, '/api/runtime/v1/health')).data.error.code, 'RUNTIME_ERROR');
  } finally { await web.close(); await upstream.close(); }
});
