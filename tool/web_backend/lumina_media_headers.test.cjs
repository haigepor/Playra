const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');

test('real upstream transport preserves an explicitly empty SDK User-Agent', async () => {
  const filename = path.join(__dirname, 'server.cjs');
  const localRequire = createRequire(filename);
  const requests = [];
  const transport = {
    request: (options) => { requests.push(options); return { setTimeout() {}, destroy() {} }; },
    createServer: () => ({ listen() {} }),
  };
  const context = {
    require: (name) => {
      if (name === 'node:http' || name === 'node:https') return transport;
      if (name === 'node:tls') return { ...localRequire(name),
        getCACertificates: kind => kind === 'system' ? ['system-root'] : ['node-root'] };
      if (name === './security.cjs') return {
        ...localRequire(name),
        validateTarget: async (target) => ({ url: new URL(target), address: { address: '8.8.8.8', family: 4 } }),
      };
      return localRequire(name);
    },
    module: { exports: {} }, __dirname, Buffer, URL, URLSearchParams,
    process: { env: {} }, console, AbortController, setTimeout, clearTimeout,
  };
  vm.runInNewContext(fs.readFileSync(filename, 'utf8') + '\nmodule.exports = upstreamRequest;', context, { filename });
  const upstream = context.module.exports;
  await upstream('https://media.example/video.m3u8', 'GET', {
    'User-Agent': '', Referer: 'https://source.example/',
  });
  assert.equal(requests[0].headers['user-agent'], '');
  assert.equal(requests[0].headers.referer, 'https://source.example/');
  assert.deepEqual(Array.from(requests[0].ca || []), ['node-root', 'system-root']);
  assert.notEqual(requests[0].rejectUnauthorized, false);
  await upstream('https://media.example/other.m3u8', 'GET', {});
  assert.match(requests[1].headers['user-agent'], /Kazumi-Web/);
});
