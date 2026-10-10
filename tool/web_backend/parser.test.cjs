const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { Readable } = require('node:stream');
const { parseVideo, closeBrowser } = require('./parser.cjs');
const { captcha } = require('./captcha.cjs');
after(closeBrowser);

function upstream(html) {
  return async () => {
    const request = new EventEmitter();
    request.end = () => {
      const response = Readable.from([Buffer.from(html)]);
      response.statusCode = 200;
      response.headers = { 'content-type': 'text/html' };
      request.emit('response', response);
    };
    return request;
  };
}
test('Chromium executes JavaScript and detects a dynamically created video', async () => {
  const result = await parseVideo({ url: 'https://example.org/' }, upstream(
    '<script>const v=document.createElement("video");v.src="https://example.org/movie.mp4";document.documentElement.append(v)</script>'));
  assert.equal(result.url, 'https://example.org/movie.mp4');
});
test('button verification exports the resulting page and closes its isolated session', async () => {
  const request = upstream('<button onclick="this.remove();document.body.dataset.verified=1">Verify</button>');
  const { id } = await captcha({ action: 'open', url: 'https://example.org/', mode: 'button', buttonXpath: '//button' }, request);
  try {
    await captcha({ action: 'poll', id }, request);
    assert.equal((await captcha({ action: 'poll', id }, request)).done, true);
    assert.match((await captcha({ action: 'data', id }, request)).html, /data-verified="1"/);
  } finally { await captcha({ action: 'close', id }, request); }
});
test('cancellation closes parsing context and permits a subsequent request', { timeout: 10000 }, async () => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 150);
  try {
    await assert.rejects(parseVideo({ url: 'https://example.org/' },
      upstream('<html><body>waiting</body></html>'), { signal: controller.signal }), /取消/);
  } finally { clearTimeout(timer); }
  const result = await parseVideo({ url: 'https://example.org/' }, upstream(
    '<video src="https://example.org/after-cancel.mp4"></video>'));
  assert.equal(result.url, 'https://example.org/after-cancel.mp4');
});
