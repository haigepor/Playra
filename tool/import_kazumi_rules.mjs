import { readFile, writeFile, mkdir, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const revision = '135ef2c2ef2a09f6fbde0f73957403b2c03bfe00';
const repository = 'https://github.com/Predidit/KazumiRules';
const names = JSON.parse(await readFile(path.join(root, 'assets/migrations/anifive-v1.json'), 'utf8'))
  .legacyRules.map(rule => rule.name);
const receiptPath = path.join(root, 'assets/migrations/kazumi-v1.json');
const verify = process.argv.includes('--verify');
const inputIndex = process.argv.indexOf('--input-dir');
const input = inputIndex < 0 ? null : path.resolve(process.argv[inputIndex + 1]);
const receipt = JSON.parse(await readFile(receiptPath, 'utf8'));
const sha256 = value => createHash('sha256').update(value).digest('hex');
const canonical = value => JSON.stringify(sort(value));
function sort(value) {
  if (Array.isArray(value)) return value.map(sort);
  return value && typeof value === 'object'
    ? Object.fromEntries(Object.keys(value).sort().map(key => [key, sort(value[key])]))
    : value;
}

await mkdir(path.join(root, 'assets/plugins'), { recursive: true });
const entries = [];
if (verify) {
  const files = (await readdir(path.join(root, 'assets/plugins'))).filter(file => file.endsWith('.json'));
  if (files.length !== names.length || files.some(file => !names.includes(file.slice(0, -5)))) {
    throw new Error('Bundled rule set differs from the original sixteen');
  }
}
for (const name of names) {
  const file = path.join(root, `assets/plugins/${name}.json`);
  const recorded = receipt.rules?.find(rule => rule.name === name);
  if (verify) {
    const local = JSON.parse(await readFile(file, 'utf8'));
    if (local.sourceConfig?.managedBy !== 'playra-kazumi' || local.sourceConfig?.officialName !== name) {
      throw new Error(`Invalid managed identity: ${name}`);
    }
    delete local.sourceConfig;
    if (sha256(canonical(local)) !== recorded?.ruleSha256) throw new Error(`Rule changed: ${name}`);
    continue;
  }
  let bytes;
  if (input) {
    bytes = await readFile(path.join(input, `${name}.json`));
  } else {
    const response = await fetch(`https://raw.githubusercontent.com/Predidit/KazumiRules/${revision}/${name}.json`);
    if (!response.ok) throw new Error(`${name}: HTTP ${response.status}`);
    bytes = Buffer.from(await response.arrayBuffer());
  }
  const rule = JSON.parse(bytes.toString('utf8'));
  if (recorded && sha256(bytes) !== recorded.upstreamSha256) throw new Error(`Upstream bytes changed: ${name}`);
  if (rule.name !== name || rule.type !== 'anime' || Number(rule.api) > 9) throw new Error(`Invalid rule: ${name}`);
  const ruleSha256 = sha256(canonical(rule));
  entries.push({ name, version: rule.version, upstreamSha256: sha256(bytes), ruleSha256 });
  rule.sourceConfig = { managedBy: 'playra-kazumi', officialName: name, repository, revision };
  await writeFile(file, `${JSON.stringify(rule, null, 2)}\n`, 'utf8');
}
if (!verify) {
  await writeFile(receiptPath, `${JSON.stringify({ ...receipt, repository, revision, rules: entries }, null, 2)}\n`, 'utf8');
}
process.stdout.write(`${verify ? 'Verified' : 'Imported'} ${names.length} official Kazumi rules at ${revision}\n`);
