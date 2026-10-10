const { randomBytes } = require('node:crypto');
const { validateTarget } = require('./security.cjs');
const { createPublicContext } = require('./parser.cjs');
const sessions = new Map();

async function close(id) {
  const session = sessions.get(id);
  if (!session) return;
  sessions.delete(id);
  clearTimeout(session.expiry);
  await session.context.close();
}

async function captcha(input, upstreamRequest) {
  if (input.action === 'open') {
    if (sessions.size >= 4) throw new Error('验证任务过多，请稍后重试');
    await validateTarget(input.url);
    const context = await createPublicContext(upstreamRequest);
    const page = await context.newPage();
    const id = randomBytes(24).toString('hex');
    const session = { context, page, input, image: '', found: false, clicked: false, done: false };
    sessions.set(id, session);
    session.expiry = setTimeout(() => close(id).catch(() => {}), 120000);
    session.expiry.unref();
    try {
      if (input.mode === 'script') {
        await context.exposeBinding('kazumiCaptchaDone', () => { session.done = true; });
        await context.addInitScript((script) => {
          window.KazumiCaptcha = { log() {}, clicked() {}, done() { window.kazumiCaptchaDone(); }, fail() {} };
          window.addEventListener('DOMContentLoaded', () => {
            try { const result = (0, eval)(script); if (result === true) window.kazumiCaptchaDone();
              else if (result?.then) result.then((value) => { if (value === true) window.kazumiCaptchaDone(); });
            } catch {}
          });
        }, input.script || '');
      }
      await page.goto(input.url, { waitUntil: 'domcontentloaded', timeout: 20000 });
      return { id };
    } catch (error) { await close(id); throw error; }
  }
  if (input.action === 'close') { await close(input.id); return {}; }
  const session = sessions.get(input.id);
  if (!session) throw new Error('验证会话已过期');
  const { page } = session;
  if (input.action === 'submit') {
    const field = page.locator(`xpath=${input.inputXpath}`).first();
    const button = page.locator(`xpath=${input.buttonXpath}`).first();
    await field.fill(String(input.code), { timeout: 5000 });
    session.clicked = true;
    await button.click({ timeout: 5000 });
    return {};
  }
  if (input.action === 'data') {
    const cookies = await session.context.cookies(session.input.url);
    return { html: await page.content(), cookie: cookies.map((c) => `${c.name}=${c.value}`).join('; '),
      userAgent: await page.evaluate(() => navigator.userAgent) };
  }
  if (input.action !== 'poll') throw new Error('验证操作不支持');
  if (session.input.mode === 'button') {
    const button = page.locator(`xpath=${session.input.buttonXpath}`).first();
    if (!session.clicked && await button.count()) {
      session.clicked = true;
      await button.click({ timeout: 5000 });
    } else if (session.clicked && !await button.count()) session.done = true;
  } else if (session.input.mode === 'image') {
    const image = page.locator(`xpath=${session.input.captchaXpath}`).first();
    if (await image.count()) {
      if (session.input.inputXpath) {
        await page.locator(`xpath=${session.input.inputXpath}`).first().focus({ timeout: 2000 }).catch(() => {});
      }
      const src = await image.getAttribute('src');
      if (src !== session.image) {
        session.image = src;
        session.found = true;
        return { image: 'data:image/png;base64,' + (await image.screenshot({ timeout: 5000 })).toString('base64') };
      }
    } else if (session.found) session.done = true;
  }
  return { done: session.done };
}
module.exports = { captcha };
