const http = require('node:http');
const https = require('node:https');
const tls = require('node:tls');
const fs = require('node:fs');
const path = require('node:path');
const { pipeline } = require('node:stream/promises');
const { Readable } = require('node:stream');
const { validateTarget, resolveStaticPath } = require('./security.cjs');
const { parseVideo } = require('./parser.cjs');
const { captcha } = require('./captcha.cjs');
const { createRuntimeBridge } = require('./runtime.cjs');
const { serveStatic } = require('./static_assets.cjs');

// 开发预览可复用同一代理，正式 Web 默认仍服务 build/web。
const root = process.env.KAZUMI_WEB_ROOT
  ? path.resolve(process.env.KAZUMI_WEB_ROOT)
  : path.resolve(__dirname, '../../build/web');
const port = Number(process.env.KAZUMI_WEB_PORT || 8930);
const sourceApiPort = Number(process.env.KAZUMI_SOURCE_API_PORT || 8940);
const bangumiEchPort = Number(process.env.PLAYRA_BANGUMI_ECH_PORT || 0);
const runtimeBridge = createRuntimeBridge({
  port: process.env.PLAYRA_SOURCE_RUNTIME_PORT
    ? Number(process.env.PLAYRA_SOURCE_RUNTIME_PORT) : undefined,
});
const proxy = process.env.HTTPS_PROXY || process.env.HTTP_PROXY;
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'application/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.css': 'text/css',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.ttf': 'font/ttf', '.woff2': 'font/woff2' };
const dnsCache = new Map();
const dns = require('node:dns/promises');

async function publicLookup(host) {
  try { return await dohLookup(host); } catch (_) {
    // 公共 DoH 不可达时使用系统解析；validateTarget 仍检查所有地址并固定连接。
    return dns.lookup(host, { all: true });
  }
}

async function dohLookup(host) {
  const cached = dnsCache.get(host);
  if (cached && cached.expires > Date.now()) return cached.addresses;
  // 使用固定的公共 DoH 入口，避免本机 DNS 污染，同时保留地址检查与连接固定。
  const request = await upstreamRequest(`https://dns.google/resolve?name=${encodeURIComponent(host)}&type=A`, 'GET', {}, true);
  const result = new Promise((resolve, reject) => {
    request.once('error', reject);
    request.once('response', async (response) => {
      try {
        const chunks = []; let size = 0;
        for await (const chunk of response) { size += chunk.length; if (size > 65536) throw new Error('DNS 响应过大'); chunks.push(chunk); }
        const data = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        const addresses = (data.Answer || []).filter((a) => a.type === 1).map((a) => ({ address: a.data, family: 4 }));
        if (!addresses.length) throw new Error('DNS 无有效公网记录');
        dnsCache.set(host, { addresses, expires: Date.now() + 60000 });
        resolve(addresses);
      } catch (error) { reject(error); }
    });
  });
  request.end();
  return result;
}

// 仅绑定回环；拒绝跨站调用，公网 URL 经过验证并将连接固定到已检查的 IP。
function verifyOrigin(req) {
  const expected = `http://${req.headers.host}`;
  if (req.headers.origin && req.headers.origin !== expected) throw new Error('跨站请求不允许');
  const site = req.headers['sec-fetch-site'];
  if (site && !['same-origin', 'none'].includes(site)) throw new Error('跨站请求不允许');
  if (!['127.0.0.1', 'localhost'].includes(req.headers.host?.split(':')[0])) throw new Error('Host 不允许');
}

async function upstreamRequest(target, method, headers = {}, bootstrap = false) {
  const requested = new URL(target);
  if (!bootstrap && bangumiEchPort && requested.protocol === 'https:' &&
      !requested.username && !requested.password && !requested.port &&
      ['api.bgm.tv', 'next.bgm.tv', 'lain.bgm.tv'].includes(requested.hostname)) {
    const forwarded = { 'x-kazumi-request': '1' };
    for (const [name, value] of Object.entries(headers)) {
      if (['accept', 'content-type', 'user-agent'].includes(name.toLowerCase())) forwarded[name] = value;
    }
    const request = http.request({ hostname: '127.0.0.1', port: bangumiEchPort,
      path: `/relay?url=${encodeURIComponent(target)}`, method, headers: forwarded });
    request.setTimeout(35000, () => request.destroy(new Error('Bangumi 网络请求超时')));
    return request;
  }
  const { url, address } = await validateTarget(target, bootstrap ?
    async () => [{ address: '8.8.8.8', family: 4 }] : publicLookup);
  const host = url.hostname.replace(/^\[|\]$/g, '');
  const filtered = {};
  for (const [key, value] of Object.entries(headers)) {
    if (!['host', 'connection', 'content-length', 'origin', 'accept-encoding', 'transfer-encoding'].includes(key.toLowerCase())) {
      if (value != null) filtered[key.toLowerCase()] = String(value);
    }
  }
  filtered.host = url.host;
  // SDK 的空 UA 是显式协议要求，只有未提供该头时才能安装默认值。
  filtered['user-agent'] ??= 'Kazumi-Web/1.0 (https://github.com/Predidit/Kazumi)';
  filtered['accept-encoding'] = 'identity';
  const options = { method, hostname: host, port: url.port || (url.protocol === 'https:' ? 443 : 80),
    path: url.pathname + url.search, headers: filtered, agent: false,
    lookup: (_host, _options, cb) => _options.all ?
      cb(null, [{ address: address.address, family: address.family }]) :
      cb(null, address.address, address.family) };
  if (proxy) {
    const gateway = new URL(proxy);
    if (gateway.protocol !== 'http:') throw new Error('本地代理必须是 HTTP 代理');
    if (url.protocol === 'https:') {
      const destination = address.family === 6 ? `[${address.address}]` : address.address;
      const socket = await new Promise((resolve, reject) => {
        const connect = http.request({ hostname: gateway.hostname, port: gateway.port || 80,
          method: 'CONNECT', path: `${destination}:${options.port}`, headers: { host: url.host } });
        connect.setTimeout(20000, () => connect.destroy(new Error('代理连接超时')));
        connect.once('error', reject);
        connect.once('connect', (response, connection, head) => {
          if (response.statusCode !== 200) { connection.destroy(); reject(new Error('代理连接失败')); return; }
          if (head.length) connection.unshift(head);
          resolve(connection);
        });
        connect.end();
      });
      const agent = new https.Agent({ keepAlive: false });
      agent.createConnection = () => tls.connect({ socket, servername: host });
      options.agent = agent;
    } else {
      options.hostname = gateway.hostname;
      options.port = gateway.port || 80;
      const destination = address.family === 6 ? `[${address.address}]` : address.address;
      options.path = `http://${destination}:${url.port || 80}${url.pathname}${url.search}`;
      delete options.lookup;
    }
  }
  const client = url.protocol === 'https:' ? https : http;
  const request = client.request(options);
  request.setTimeout(30000, () => request.destroy(new Error('远端响应超时')));
  return request;
}

async function relay(req, res, url) {
  let activeRequest, activeResponse, cancelled = false;
  const cancel = () => {
    cancelled = true;
    activeResponse?.destroy();
    activeRequest?.destroy(new Error('媒体请求已取消'));
  };
  const closed = () => { if (!res.writableEnded) cancel(); };
  req.once('aborted', cancel);
  res.once('close', closed);
  try {
  if (!req.headers['x-kazumi-request'] && req.method !== 'GET') throw new Error('缺少请求标记');
  const rawHeaders = req.headers['x-kazumi-headers'] || url.searchParams.get('headers');
  if (rawHeaders && rawHeaders.length > 32768) throw new Error('请求头过大');
  const headers = rawHeaders ? JSON.parse(Buffer.from(rawHeaders, 'base64url').toString('utf8')) : {};
  if (req.headers.range) headers.range = req.headers.range;
  if (req.headers['content-type']) headers['content-type'] = req.headers['content-type'];
  const target = url.searchParams.get('url');
  let current = target;
  let method = req.method;
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 16 * 1024 * 1024) throw new Error('请求体过大');
    chunks.push(chunk);
  }
  let body = Buffer.concat(chunks);
  for (let count = 0; count < 8; count++) {
    const request = await upstreamRequest(current, method, headers);
    activeRequest = request;
    const responsePromise = new Promise((resolve, reject) => {
      request.once('response', resolve);
      request.once('error', reject);
    });
    if (cancelled) request.destroy(new Error('媒体请求已取消'));
    else request.end(body);
    const response = await responsePromise;
    activeResponse = response;
    if ([301, 302, 303, 307, 308].includes(response.statusCode) && response.headers.location) {
      response.resume();
      const next = new URL(response.headers.location, current).href;
      if (new URL(next).origin !== new URL(current).origin) {
        for (const key of Object.keys(headers)) {
          if (['authorization', 'cookie'].includes(key.toLowerCase())) delete headers[key];
        }
      }
      if (response.statusCode === 303 || ([301, 302].includes(response.statusCode) && method === 'POST')) {
        method = 'GET'; body = Buffer.alloc(0);
      }
      current = next;
      continue;
    }
    // 部分来源把清单伪装成图片 MIME；只预读短前缀，二进制继续流式传输。
    const iterator = response[Symbol.asyncIterator]();
    const prefix = []; let prefixBytes = 0;
    while (prefixBytes < 32) {
      const next = await iterator.next();
      if (next.done) break;
      prefix.push(next.value); prefixBytes += next.value.length;
      const head = Buffer.concat(prefix).subarray(0, 128).toString('utf8').trimStart();
      if ((head && !'#EXTM3U'.startsWith(head) && !head.startsWith('#EXTM3U')) || head.startsWith('#EXTM3U')) break;
    }
    const isHls = /^\s*#EXTM3U/.test(Buffer.concat(prefix).subarray(0, 128).toString('utf8')) ||
      /mpegurl/i.test(String(response.headers['content-type'])) || /\.m3u8(?:\?|$)/i.test(current);
    if (isHls && response.statusCode === 206) {
      // 清单重写会改变字节偏移；先重新获取完整清单，不能拼接上游的局部响应。
      const rangeKeys = Object.keys(headers).filter((key) => key.toLowerCase() === 'range');
      if (!rangeKeys.length) throw new Error('上游未返回完整播放列表');
      for (const key of rangeKeys) delete headers[key];
      response.destroy();
      continue;
    }
    res.statusCode = response.statusCode;
    if (response.headers['set-cookie']) {
      res.setHeader('X-Kazumi-Set-Cookie', Buffer.from(JSON.stringify(response.headers['set-cookie'])).toString('base64url'));
    }
    for (const header of ['content-type', 'content-length', 'content-range', 'accept-ranges', 'etag', 'last-modified', 'www-authenticate', 'dav', 'allow']) {
      if (response.headers[header]) res.setHeader(header, response.headers[header]);
    }
    if (isHls) {
      const parts = [...prefix]; let length = prefixBytes;
      if (length > 4 * 1024 * 1024) throw new Error('播放列表过大');
      for (;;) {
        const next = await iterator.next();
        if (next.done) break;
        length += next.value.length;
        if (length > 4 * 1024 * 1024) throw new Error('播放列表过大');
        parts.push(next.value);
      }
      // 使用重定向后允许的头，不能把已清除的凭据重新放回子请求。
      const childHeaders = Object.fromEntries(Object.entries(headers).filter(([key]) => !['range', 'content-type'].includes(key.toLowerCase())));
      const encodedHeaders = Object.keys(childHeaders).length ? Buffer.from(JSON.stringify(childHeaders)).toString('base64url') : null;
      const proxied = (value) => '/api/proxy?' + new URLSearchParams({ url: new URL(value, current).href,
        ...(encodedHeaders ? { headers: encodedHeaders } : {}) });
      const text = Buffer.concat(parts).toString('utf8').split('\n').map((line) => {
        if (line.trim() && !line.startsWith('#')) return proxied(line.trim());
        return line.replace(/URI="([^"]+)"/g, (_, value) => `URI="${proxied(value)}"`);
      }).join('\n');
      res.setHeader('content-type', 'application/vnd.apple.mpegurl');
      // 返回的是新的完整表示，原清单的 Range、长度和校验信息已失效。
      for (const header of ['content-length', 'content-range', 'accept-ranges', 'etag', 'last-modified']) res.removeHeader(header);
      res.end(text); return;
    }
    await pipeline(Readable.from((async function* () {
      yield* prefix;
      for (;;) { const next = await iterator.next(); if (next.done) break; yield next.value; }
    })()), res);
    return;
  }
  throw new Error('重定向次数过多');
  } finally {
    activeResponse?.destroy();
    activeRequest?.destroy();
    req.removeListener('aborted', cancel);
    res.removeListener('close', closed);
  }
}

const server = http.createServer(async (req, res) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'same-origin');
  res.setHeader('Cache-Control', 'no-store');
  try {
    verifyOrigin(req);
    const url = new URL(req.url, `http://${req.headers.host}`);
    if (url.pathname.startsWith('/api/runtime/')) {
      await runtimeBridge(req, res, url); return;
    }
    if (url.pathname.startsWith('/api/v1/')) {
      // 固定本机业务服务，保持 Web 同源；不允许客户端指定转发目标。
      const headers = { ...req.headers, host: `127.0.0.1:${sourceApiPort}` };
      const outgoing = http.request({ hostname: '127.0.0.1', port: sourceApiPort,
        path: url.pathname + url.search, method: req.method, headers });
      const response = new Promise((resolve, reject) => {
        outgoing.once('response', resolve); outgoing.once('error', reject);
      });
      req.pipe(outgoing);
      const incoming = await response;
      res.statusCode = incoming.statusCode;
      for (const [name, value] of Object.entries(incoming.headers)) {
        if (value != null && !['connection', 'transfer-encoding'].includes(name)) res.setHeader(name, value);
      }
      res.once('close', () => { outgoing.destroy(); incoming.destroy(); });
      await pipeline(incoming, res); return;
    }
    if (url.pathname === '/api/health') {
      res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ status: 'ok' })); return;
    }
    if (url.pathname === '/api/proxy') { await relay(req, res, url); return; }
    if (['/api/parse', '/api/captcha'].includes(url.pathname) && req.method === 'POST') {
      if (req.headers['x-kazumi-request'] !== '1') throw new Error('缺少请求标记');
      const chunks = []; let size = 0;
      for await (const chunk of req) { size += chunk.length; if (size > 32768) throw new Error('请求过大'); chunks.push(chunk); }
      const data = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      const abort = new AbortController();
      res.once('close', () => abort.abort());
      const output = url.pathname === '/api/parse' ? await parseVideo(data, upstreamRequest, { signal: abort.signal }) : await captcha(data, upstreamRequest);
      res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(output)); return;
    }
    if (!['GET', 'HEAD'].includes(req.method)) { res.statusCode = 405; res.end(); return; }
    let file = resolveStaticPath(root, url.pathname === '/' ? '/index.html' : url.pathname);
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(root, 'index.html');
    await serveStatic(req, res, file, mime[path.extname(file)] || 'application/octet-stream');
  } catch (error) {
    if (!res.headersSent) { res.statusCode = 502; res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ error: error.message })); }
    else res.destroy();
  }
});
server.listen(port, '127.0.0.1', () => console.log(`Kazumi Web: http://127.0.0.1:${port}`));
