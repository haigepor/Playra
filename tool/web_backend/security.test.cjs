const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { isPublicAddress, validateTarget, resolveStaticPath } = require('./security.cjs');

test('gateway rejects private, mapped and reserved IP addresses', () => {
  for (const ip of ['127.0.0.1', '10.2.3.4', '192.168.1.2', '169.254.169.254',
    '172.16.1.1', '0.0.0.0', '::1', '::ffff:127.0.0.1', 'fe80::1', 'fc00::1']) {
    assert.equal(isPublicAddress(ip), false, ip);
  }
  assert.equal(isPublicAddress('1.1.1.1'), true);
  assert.equal(isPublicAddress('2606:4700:4700::1111'), true);
});
test('target validation refuses credentials, local hosts and unsupported schemes', async () => {
  for (const url of ['file:///etc/passwd', 'http://localhost/admin',
    'https://user:password@example.com', 'http://127.0.0.1', 'http://example.com:22']) {
    await assert.rejects(validateTarget(url));
  }
});
test('static serving cannot escape the configured directory', () => {
  assert.throws(() => resolveStaticPath('C:\\project\\web', '/../secret.txt'));
  assert.throws(() => resolveStaticPath('C:\\project\\web', '/%2e%2e/secret'));
  assert.equal(resolveStaticPath('/project/web', '/main.dart.js'), path.resolve('/project/web/main.dart.js'));
});
