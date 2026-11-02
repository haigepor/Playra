'use strict';
// 私有输入仅允许清单内固定文件；恢复过程不执行 SDK 中任何脚本。
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const zlib = require('node:zlib');
const root = path.resolve(__dirname, '..');
const digest = data => crypto.createHash('sha256').update(data).digest('hex');
async function manifest() { return JSON.parse(await fs.readFile(path.join(root, 'packages/lumina_engine/inputs.json'), 'utf8')); }
function entries(m) {
  return [...Object.entries(m.files).map(([name, hash]) => [`packages/lumina_engine/native/${name}`, hash]),
    ...Object.entries(m.assets).map(([name, hash]) => [`assets/lumina_private/${name}`, hash])];
}
async function verify() {
  const m = await manifest();
  for (const [name, hash] of entries(m)) {
    if (digest(await fs.readFile(path.join(root, name))) !== hash) throw Error(`Input integrity mismatch: ${name}`);
  }
  const compressed = await fs.readFile(path.join(root, 'assets/lumina_private/fuse_image.bin.gz'));
  if (digest(zlib.gunzipSync(compressed, { maxOutputLength: 100 * 1024 * 1024 })) !== m.imageSha256) throw Error('Image integrity mismatch');
  console.log('Lumina native inputs verified');
}
async function restoreBuffer(buffer) {
  const bundle = JSON.parse(zlib.gunzipSync(buffer, { maxOutputLength: 48 * 1024 * 1024 }).toString('utf8'));
  const m = await manifest(), expected = entries(m);
  if (bundle.version !== 1 || !bundle.files || Object.keys(bundle.files).length !== expected.length) throw Error('Invalid input bundle');
  const decoded = [];
  for (const [name, hash] of expected) {
    if (typeof bundle.files[name] !== 'string') throw Error('Missing input');
    const bytes = Buffer.from(bundle.files[name], 'base64');
    if (digest(bytes) !== hash) throw Error(`Input integrity mismatch: ${name}`);
    decoded.push([name, bytes]);
  }
  // 全量校验通过后再修改工作目录。文件名全部来自受版本控制的清单。
  for (const [name, bytes] of decoded) {
    const destination = path.resolve(root, name);
    if (!destination.startsWith(root + path.sep)) throw Error('Invalid destination');
    await fs.mkdir(path.dirname(destination), { recursive: true });
    await fs.writeFile(destination + '.part', bytes);
    await fs.rename(destination + '.part', destination);
  }
  await verify();
}

// 私有输入包含响应私钥，仓库公开，所以分发包是 openssl 兼容的 AES-256-CBC
// （口令经 PBKDF2 派生，随机盐写在 "Salted__" 头里）。口令只存于 Actions secrets。
function decryptBundle(bytes) {
  const passphrase = process.env.PLAYRA_LUMINA_INPUT_PASSPHRASE;
  if (!passphrase) throw Error('Encrypted input requires PLAYRA_LUMINA_INPUT_PASSPHRASE');
  if (bytes.length < 32 || bytes.subarray(0, 8).toString('latin1') !== 'Salted__') throw Error('Invalid encrypted input');
  const salt = bytes.subarray(8, 16);
  const derived = crypto.pbkdf2Sync(passphrase, salt, 200000, 48, 'sha256');
  const decipher = crypto.createDecipheriv('aes-256-cbc', derived.subarray(0, 32), derived.subarray(32, 48));
  return Buffer.concat([decipher.update(bytes.subarray(16)), decipher.final()]);
}

async function main(args) {
  switch (args[0]) {
    case 'verify': await verify(); break;
    case 'export': {
      if (!args[1]) throw Error('export requires a private output path');
      await verify(); const files = {};
      for (const [name] of entries(await manifest())) files[name] = (await fs.readFile(path.join(root, name))).toString('base64');
      const bytes = zlib.gzipSync(Buffer.from(JSON.stringify({ version: 1, files })));
      await fs.writeFile(path.resolve(args[1]), bytes);
      console.log(`Private bundle written; sha256=${digest(bytes)}`); break;
    }
    case 'restore': {
      if (args[1]) { await restoreBuffer(await fs.readFile(path.resolve(args[1]))); break; }
      const url = process.env.PLAYRA_LUMINA_NATIVE_INPUT_URL;
      const expected = process.env.PLAYRA_LUMINA_NATIVE_INPUT_SHA256;
      if (!url || !/^[a-f0-9]{64}$/.test(expected || '')) throw Error('Configure PLAYRA_LUMINA_NATIVE_INPUT_URL and PLAYRA_LUMINA_NATIVE_INPUT_SHA256');
      const uri = new URL(url);
      if (uri.protocol !== 'https:' || uri.username || uri.password) throw Error('Input bundle requires HTTPS');
      // 发布资产会 302 到 objects.githubusercontent.com；只允许 HTTPS 跳转，
      // 内容完整性最终由 SHA-256 兜底。
      const response = await fetch(uri, { redirect: 'follow', signal: AbortSignal.timeout(120000) });
      if (!response.ok) throw Error('Input bundle download failed');
      if (new URL(response.url).protocol !== 'https:') throw Error('Input bundle downgraded to plaintext');
      const chunks = []; let size = 0;
      for await (const chunk of response.body) { size += chunk.length; if (size > 32 * 1024 * 1024) throw Error('Input bundle too large'); chunks.push(chunk); }
      let bytes = Buffer.concat(chunks);
      if (process.env.PLAYRA_LUMINA_INPUT_PASSPHRASE) bytes = decryptBundle(bytes);
      if (digest(bytes) !== expected) throw Error('Input bundle checksum mismatch');
      await restoreBuffer(bytes); break;
    }
    default: throw Error('Usage: node tool/lumina-native-input.cjs verify|export <private.gz>|restore [private.gz]');
  }
}
if (require.main === module) main(process.argv.slice(2)).catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = { verify, restoreBuffer, decryptBundle };
