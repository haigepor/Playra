const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const { restoreBuffer } = require('./lumina-native-input.cjs');
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
