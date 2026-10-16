const http = require('node:http');

const prefix = '/api/runtime/v1/';
const route = /^adapters\/[A-Za-z0-9_-]{1,64}\/(search|episodes|resolve)$/;

function allowed(path, method) {
  if (method === 'GET' && ['health', 'adapters'].includes(path)) return true;
  if (['adapters/miomedia/sdk', 'adapters/lumina/sdk'].includes(path) && method === 'POST') return true;
  const match = route.exec(path);
  return !!match && method === (match[1] === 'resolve' ? 'POST' : 'GET');
}

function createRuntimeBridge({ port, timeoutMs = 20000 } = {}) {
  if (port != null && (!Number.isInteger(port) || port < 1 || port > 65535)) {
    throw new Error('算法运行端口无效');
  }
  return async function forward(req, res, url) {
    let outgoing;
    let timer;
    const fail = (code, status = 502) => {
      if (!res.headersSent && !res.destroyed) {
        res.writeHead(status, { 'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store', 'connection': 'close' });
        res.end(JSON.stringify({ error: { code, message: code } }));
      }
      outgoing?.destroy();
    };
    const path = url.pathname.slice(prefix.length);
    if (!url.pathname.startsWith(prefix) || !allowed(path, req.method)) {
      fail('UNSUPPORTED', 422); return;
    }
    if (port == null) { fail('RUNTIME_UNAVAILABLE', 503); return; }
    const length = req.headers['content-length'];
    if (length && (!/^\d+$/.test(length) || Number(length) > 32768)) {
      fail('PAYLOAD_TOO_LARGE', 413); req.resume(); return;
    }
    if (req.method === 'POST' && req.headers['x-kazumi-request'] !== '1') {
      fail('INVALID_ARGUMENT', 400); req.resume(); return;
    }
    const requested = Number(req.headers['x-playra-timeout-ms'] || timeoutMs);
    if (!Number.isInteger(requested) || requested < 1 || requested > 60000) {
      fail('INVALID_ARGUMENT', 400); req.resume(); return;
    }
    const budget = Math.min(requested, timeoutMs);
    timer = setTimeout(() => fail('TIMEOUT', 504), budget);
    const finish = () => clearTimeout(timer);
    res.once('finish', finish);
    res.once('close', () => { finish(); outgoing?.destroy(); });
    req.once('aborted', () => { finish(); outgoing?.destroy(); });
    try {
      const body = await new Promise((resolve, reject) => {
        const chunks = []; let size = 0;
        req.on('data', (chunk) => {
          size += chunk.length;
          if (size > 32768) { reject(new Error('PAYLOAD_TOO_LARGE')); return; }
          chunks.push(chunk);
        });
        req.once('end', () => resolve(Buffer.concat(chunks)));
        req.once('error', reject);
        req.once('aborted', () => reject(new Error('CANCELLED')));
      });
      if (res.writableEnded || res.destroyed) return;
      if (req.method === 'GET' && body.length) { fail('INVALID_ARGUMENT', 400); return; }
      // 固定 loopback 目标，不使用调用方 Host、URL、Cookie 或鉴权头。
      outgoing = http.request({ hostname: '127.0.0.1', port,
        path: `/v1/${path}${url.search}`, method: req.method,
        headers: { 'content-type': 'application/json', 'content-length': body.length,
          'X-Kazumi-Request': '1', 'X-Playra-Timeout-Ms': `${budget}` } });
      outgoing.once('error', () => fail('RUNTIME_UNAVAILABLE', 503));
      outgoing.once('response', (incoming) => {
        const chunks = []; let size = 0;
        incoming.on('data', (chunk) => {
          size += chunk.length;
          if (size > 2 * 1024 * 1024) {
            fail('RESPONSE_TOO_LARGE'); incoming.destroy(); return;
          }
          chunks.push(chunk);
        });
        incoming.once('error', () => fail('RUNTIME_UNAVAILABLE', 503));
        incoming.once('end', () => {
          if (res.writableEnded || res.destroyed) return;
          if (incoming.statusCode >= 300 && incoming.statusCode < 400) {
            fail('RUNTIME_ERROR'); return;
          }
          res.writeHead(incoming.statusCode, { 'content-type': 'application/json; charset=utf-8',
            'cache-control': 'no-store' });
          res.end(Buffer.concat(chunks));
        });
      });
      outgoing.end(body);
    } catch (error) {
      fail(error.message === 'PAYLOAD_TOO_LARGE' ? 'PAYLOAD_TOO_LARGE' : 'RUNTIME_ERROR',
        error.message === 'PAYLOAD_TOO_LARGE' ? 413 : 502);
    }
  };
}

module.exports = { createRuntimeBridge, allowed };
