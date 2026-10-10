const { chromium } = require('playwright');
const fs = require('node:fs');
const { validateTarget } = require('./security.cjs');
let browser;
let launching;
let active = 0;

async function getBrowser() {
  if (browser?.isConnected()) return browser;
  launching ||= (async () => {
    const chrome = process.env.KAZUMI_CHROME || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
    browser = await chromium.launch({ headless: true, chromiumSandbox: true,
      ...(fs.existsSync(chrome) ? { executablePath: chrome } : {}) });
    return browser;
  })().finally(() => { launching = undefined; });
  return launching;
}

async function createPublicContext(upstreamRequest, detect = () => {}, options = {}) {
  const context = await (await getBrowser()).newContext({ serviceWorkers: 'block', ...options });
  await context.routeWebSocket('**/*', (route) => route.close());
    await context.route('**/*', async (route) => {
      const request = route.request();
      const target = request.url();
      detect(target);
      try {
        const outgoing = await upstreamRequest(target, request.method(), request.headers());
        const responsePromise = new Promise((done, reject) => {
          outgoing.once('response', done); outgoing.once('error', reject);
        });
        outgoing.end(request.postDataBuffer() || undefined);
        const response = await responsePromise;
        detect(target, response.headers['content-type']);
        const chunks = []; let length = 0;
        for await (const chunk of response) {
          length += chunk.length;
          if (length > 16 * 1024 * 1024) { response.destroy(); throw new Error('解析资源过大'); }
          chunks.push(chunk);
        }
        const headers = {};
        for (const [name, value] of Object.entries(response.headers)) {
          if (!['content-length', 'transfer-encoding', 'connection', 'content-encoding'].includes(name) && value != null) {
            headers[name] = Array.isArray(value) ? value.join('\n') : value;
          }
        }
        await route.fulfill({ status: response.statusCode, headers, body: Buffer.concat(chunks) });
      } catch { await route.abort().catch(() => {}); }
    });
  return context;
}

async function parseVideo(input, upstreamRequest, { signal } = {}) {
  if (active >= 4) throw new Error('解析任务过多，请稍后重试');
  const raw = String(input.url || '');
  if (raw.length > 8192) throw new Error('地址过长');
  // 后续页面及所有子请求由网关重新校验，防止跨域脚本访问本机服务。
  await validateTarget(raw);
  if (/\.(m3u8|mp4|webm|mkv)(?:\?|$)/i.test(raw)) return { url: raw };
  active++;
  let context;
  let rejectCancelled;
  const cancelled = new Promise((_, reject) => { rejectCancelled = reject; });
  // 创建页面及导航也需参与取消竞争，不能等 goto 自身超时后才观察取消。
  cancelled.catch(() => {});
  const abort = () => {
    rejectCancelled(new Error('解析已取消'));
    context?.close().catch(() => {});
  };
  signal?.addEventListener('abort', abort, { once: true });
  try {
    if (signal?.aborted) throw new Error('解析已取消');
    let resolve;
    const found = new Promise((done) => { resolve = done; });
    const detect = (url, contentType = '') => {
      if (/googleads|googlesyndication|adtrafficquality/i.test(url)) return;
      if (/\.(m3u8|mp4|webm)(?:\?|$)/i.test(url) || /^(video\/|application\/(x-)?mpegurl)/i.test(contentType)) resolve({ url,
        format: /\.m3u8(?:\?|$)/i.test(url) || /mpegurl/i.test(contentType) ? 'hls' : 'auto' });
    };
    const referer = input.headers?.referer;
    const creating = createPublicContext(upstreamRequest, detect, {
      userAgent: input.userAgent || undefined,
      ...(referer ? { extraHTTPHeaders: { referer: String(referer) } } : {}) });
    creating.then((created) => {
      if (signal?.aborted) created.close().catch(() => {});
    }, () => {});
    context = await Promise.race([creating, cancelled]);
    if (signal?.aborted) throw new Error('解析已取消');
    if (input.cookie) {
      const cookies = String(input.cookie).split(';').filter((part) => part.includes('=')).map((part) => {
        const index = part.indexOf('=');
        return { name: part.slice(0, index).trim(), value: part.slice(index + 1).trim(), url: raw };
      });
      await context.addCookies(cookies);
    }
    const page = await Promise.race([context.newPage(), cancelled]);
    await Promise.race([page.goto(raw, { waitUntil: 'domcontentloaded', timeout: 20000 }).catch(() => {}), cancelled]);
    const element = await Promise.race([page.evaluate(() => document.querySelector('video')?.getAttribute('src')).catch(() => null), cancelled]);
    if (element && !element.startsWith('blob:')) detect(new URL(element, raw).href);
    let timer;
    try {
      return await Promise.race([found, cancelled, new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error('未找到可播放的视频地址')), 20000);
      })]);
    } finally { clearTimeout(timer); }
  } finally {
    signal?.removeEventListener('abort', abort);
    try { await context?.close(); } finally { active--; }
  }
}
module.exports = { parseVideo, createPublicContext, closeBrowser: async () => browser?.close() };
