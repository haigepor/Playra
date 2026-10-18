const { chromium } = require('playwright');
const fs = require('node:fs');
const { validateTarget } = require('./security.cjs');
let browser;
let launching;
let active = 0;

// Kazumi 简易解析只读取 iframe 查询参数中的直链，完整保留媒体签名参数。
// https://github.com/Predidit/Kazumi/blob/025dcb5c2f62db881382c72f191d08b49a9feb41/lib/utils/media.dart
function decodeLegacyIframe(raw) {
  try {
    for (const value of new URL(raw).searchParams.values()) {
      if (!/^https?:\/\/.+\.(?:m3u8|mp4)(?:[?#]|$)/i.test(value)) continue;
      const media = new URL(value);
      if (!media.username && !media.password) return value;
    }
  } catch { /* 非 URL iframe 保持原来的网络解析路径。 */ }
  return null;
}

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

function mediaPath(raw) {
  try { return /\.(m3u8|mp4|webm|mkv)$/i.test(new URL(raw).pathname); } catch { return false; }
}

async function createPublicContext(upstreamRequest, detect = () => {}, options = {}) {
  const { initialReferer, ...contextOptions } = options;
  const context = await (await getBrowser()).newContext({ serviceWorkers: 'block', ...contextOptions });
  await context.routeWebSocket('**/*', (route) => route.close());
    await context.route('**/*', async (route) => {
      const request = route.request();
      const target = request.url();
      const headers = request.headers();
      // 入口 Referer 仅用于主文档首跳；子页面需要浏览器生成的真实页面上下文。
      if (initialReferer && request.isNavigationRequest() && !request.redirectedFrom() &&
          request.frame().parentFrame() === null) headers.referer = initialReferer;
      detect(target, '', headers);
      try {
        const outgoing = await upstreamRequest(target, request.method(), headers);
        const responsePromise = new Promise((done, reject) => {
          outgoing.once('response', done); outgoing.once('error', reject);
        });
        outgoing.end(request.postDataBuffer() || undefined);
        const response = await responsePromise;
        detect(target, response.headers['content-type'], headers);
        const chunks = []; let length = 0;
        for await (const chunk of response) {
          length += chunk.length;
          if (length > 16 * 1024 * 1024) { response.destroy(); throw new Error('解析资源过大'); }
          chunks.push(chunk);
        }
        const responseHeaders = {};
        for (const [name, value] of Object.entries(response.headers)) {
          if (!['content-length', 'transfer-encoding', 'connection', 'content-encoding'].includes(name) && value != null) {
            responseHeaders[name] = Array.isArray(value) ? value.join('\n') : value;
          }
        }
        await route.fulfill({ status: response.statusCode, headers: responseHeaders, body: Buffer.concat(chunks) });
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
  if (mediaPath(raw)) return { url: raw };
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
    const detect = (url, contentType = '', requestHeaders = {}) => {
      if (/googleads|googlesyndication|adtrafficquality/i.test(url)) return;
      if (mediaPath(url) || /^(video\/|application\/(?:vnd\.apple\.|x-)?mpegurl)/i.test(contentType)) resolve({ url,
        format: /\.m3u8$/i.test(new URL(url).pathname) || /mpegurl/i.test(contentType) ? 'hls' : 'auto',
        // 仅传递媒体加载所需的公开上下文，不把页面 Cookie 或鉴权头带到播放器。
        headers: Object.fromEntries(Object.entries(requestHeaders).filter(([name]) =>
          ['referer', 'user-agent', 'origin'].includes(name.toLowerCase()))) });
    };
    const referer = input.headers?.referer;
    const creating = createPublicContext(upstreamRequest, detect, {
      userAgent: input.userAgent || undefined,
      ...(referer ? { initialReferer: String(referer) } : {}) });
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
    if (input.useLegacyParser === true) {
      page.on('framenavigated', (frame) => {
        if (frame === page.mainFrame()) return;
        const media = decodeLegacyIframe(frame.url());
        if (media) detect(media);
      });
    }
    await Promise.race([page.goto(raw, { waitUntil: 'domcontentloaded', timeout: 20000 }).catch(() => {}), cancelled]);
    const element = await Promise.race([page.evaluate(() => document.querySelector('video')?.getAttribute('src')).catch(() => null), cancelled]);
    if (element && !element.startsWith('blob:')) detect(new URL(element, raw).href);
    if (input.useLegacyParser === true) {
      const frames = await page.evaluate(() => Array.from(document.querySelectorAll('iframe[src]'), e => e.src));
      for (const frame of frames) {
        const media = decodeLegacyIframe(frame);
        if (media) detect(media);
      }
    }
    let timer;
    try {
      const result = await Promise.race([found, cancelled, new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error('未找到可播放的视频地址')), 20000);
      })]);
      await validateTarget(result.url);
      return result;
    } finally { clearTimeout(timer); }
  } finally {
    signal?.removeEventListener('abort', abort);
    try { await context?.close(); } finally { active--; }
  }
}
module.exports = { parseVideo, createPublicContext, decodeLegacyIframe, closeBrowser: async () => browser?.close() };
