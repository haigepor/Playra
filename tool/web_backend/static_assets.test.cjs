const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const { serveStatic } = require('./static_assets.cjs');

test('static bytes revalidate without caching APIs or hiding a new build', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'playra-static-'));
  const file = path.join(root, 'main.dart.js');
  await fs.writeFile(file, 'first build');
  const server = http.createServer((req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    if (req.url === '/api/health') { res.end('{}'); return; }
    serveStatic(req, res, file, 'application/javascript').catch(() => res.destroy());
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => { await new Promise(resolve => server.close(resolve)); await fs.rm(root, { recursive: true }); });
  const url = `http://127.0.0.1:${server.address().port}`;
  const first = await fetch(url);
  assert.equal(await first.text(), 'first build');
  assert.match(first.headers.get('cache-control'), /must-revalidate/);
  const etag = first.headers.get('etag');
  assert.ok(etag);
  const repeated = await fetch(url, { headers: { 'If-None-Match': etag } });
  assert.equal(repeated.status, 304);
  assert.equal(await repeated.text(), '');
  await fs.writeFile(file, 'second changed build');
  const changed = await fetch(url, { headers: { 'If-None-Match': etag } });
  assert.equal(changed.status, 200);
  assert.equal(await changed.text(), 'second changed build');
  assert.notEqual(changed.headers.get('etag'), etag);
  const head = await fetch(url, { method: 'HEAD' });
  assert.equal(head.status, 200);
  assert.equal(await head.text(), '');
  assert.equal((await fetch(`${url}/api/health`)).headers.get('cache-control'), 'no-store');
});
