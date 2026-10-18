const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { Readable } = require('node:stream');
const { parseVideo, closeBrowser, decodeLegacyIframe } = require('./parser.cjs');
const { captcha } = require('./captcha.cjs');
after(closeBrowser);

test('legacy iframe extraction preserves the complete signed media URL', () => {
  const media = 'https://example.org/main.m3u8?token=a%2Fb&expires=123';
  assert.equal(decodeLegacyIframe(`https://example.org/player?url=${encodeURIComponent(media)}`), media);
  assert.equal(decodeLegacyIframe('https://example.org/player?url=javascript%3Aalert(1)'), null);
  assert.equal(decodeLegacyIframe('https://example.org/player?url=https%3A%2F%2Fu%3Ap%40example.org%2Fa.mp4'), null);
});

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
test('official legacy mode extracts a signed iframe link before media requests exist', async () => {
  const media = 'https://example.org/legacy.m3u8?token=a%2Fb&expires=123';
  const result = await parseVideo({ url: 'https://example.org/', useLegacyParser: true },
    upstream(`<iframe src="https://example.org/player?url=${encodeURIComponent(media)}"></iframe>`));
  assert.equal(result.url, media);
});
test('Chromium executes JavaScript and detects a dynamically created video', async () => {
  const result = await parseVideo({ url: 'https://example.org/' }, upstream(
    '<script>const v=document.createElement("video");v.src="https://example.org/movie.mp4";document.documentElement.append(v)</script>'));
  assert.equal(result.url, 'https://example.org/movie.mp4');
});
test('iframe query containing m3u8 is not a media URL and subrequests keep their page referer', async () => {
  const iframe = 'https://example.org/player.html?url=https://example.org/movie.m3u8';
  const seen = [];
  const result = await parseVideo({ url: 'https://example.org/watch', headers: { referer: 'https://example.org/' } },
    async (url, method, headers) => {
      seen.push({ url, headers });
      const html = url.includes('/watch') ? `<iframe src="${iframe}"></iframe>`
        : url.includes('/player.html') ? '<script>fetch("/actual.m3u8")</script>' : '#EXTM3U';
      return upstream(html)(url, method, headers);
    });
  assert.equal(result.url, 'https://example.org/actual.m3u8');
  assert.equal(seen.find(r => r.url === iframe).headers.referer, 'https://example.org/watch');
  assert.equal(result.headers.referer, iframe);
  assert.match(result.headers['user-agent'], /Chrome/);
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
