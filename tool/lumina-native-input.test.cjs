const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const crypto = require('node:crypto');
const { restoreBuffer, decryptBundle } = require('./lumina-native-input.cjs');
const receipt = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../packages/lumina_engine/inputs.json'), 'utf8'));
const bundle = value => zlib.gzipSync(Buffer.from(JSON.stringify(value)));
test('native restore rejects unknown bundle versions', async () => {
  await assert.rejects(restoreBuffer(bundle({ version: 2, files: {} })), /Invalid input bundle/);
});
test('native restore rejects traversal and unexpected files before writing', async () => {
  await assert.rejects(restoreBuffer(bundle({ version: 1, files: { '../outside': 'YQ==' } })), /Invalid input bundle/);
});
test('native restore verifies all checksums before replacing any input', async () => {
  const files = Object.fromEntries([
    ...Object.keys(receipt.files).map(name => [`packages/lumina_engine/native/${name}`, 'YQ==']),
    ...Object.keys(receipt.assets).map(name => [`assets/lumina_private/${name}`, 'YQ==']),
  ]);
  const candidate = path.resolve(__dirname, '../packages/lumina_engine/native/fuse_core.dll');
  const before = fs.existsSync(candidate) ? fs.readFileSync(candidate) : null;
  await assert.rejects(restoreBuffer(bundle({ version: 1, files })), /integrity mismatch/);
  if (before) assert.deepEqual(fs.readFileSync(candidate), before);
});
test('encrypted input follows the openssl aes-256-cbc envelope', () => {
  const passphrase = 'test-passphrase';
  process.env.PLAYRA_LUMINA_INPUT_PASSPHRASE = passphrase;
  try {
    const salt = Buffer.from('0123456789abcdef', 'hex');
    const derived = crypto.pbkdf2Sync(passphrase, salt, 200000, 48, 'sha256');
    const cipher = crypto.createCipheriv('aes-256-cbc', derived.subarray(0, 32), derived.subarray(32, 48));
    const plain = Buffer.from('encrypted-input-canary');
    const sealed = Buffer.concat([
      Buffer.from('Salted__', 'latin1'),
      salt,
      cipher.update(plain),
      cipher.final(),
    ]);
    assert.deepEqual(decryptBundle(sealed), plain);
    delete process.env.PLAYRA_LUMINA_INPUT_PASSPHRASE;
    assert.throws(() => decryptBundle(sealed), /PLAYRA_LUMINA_INPUT_PASSPHRASE/);
  } finally {
    delete process.env.PLAYRA_LUMINA_INPUT_PASSPHRASE;
  }
});
