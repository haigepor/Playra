const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function fixture({ ua = 'Chrome/155.0', mse = true, hls = true } = {}) {
  const original = function (type) { return type.includes('mpegurl') ? 'maybe' : 'probably'; };
  const video = { canPlayType: original, src: 'owned-media', currentTime: 42 };
  const context = { navigator: { userAgent: ua },
    Hls: hls ? { isSupported: () => mse } : undefined,
    '$com.alexmercerind.media_kit.instances': { 7: video },
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../../web/player/media_compat.js'), 'utf8'), context);
  return { video, original, compat: context.PlayraMediaCompatibility };
}

test('Chromium prefers the existing media_kit HLS engine only for HLS MIME on its owned video', () => {
  const { video, compat } = fixture();
  assert.equal(compat.preferMseHls(7), true);
  assert.equal(video.canPlayType('application/vnd.apple.mpegurl'), '');
  assert.equal(video.canPlayType('application/x-mpegURL; codecs="avc1.42E01E"'), '');
  assert.equal(video.canPlayType('video/mp4'), 'probably');
  assert.equal(video.src, 'owned-media');
  assert.equal(video.currentTime, 42);
  const wrapped = video.canPlayType;
  compat.preferMseHls(7);
  assert.equal(video.canPlayType, wrapped);
  assert.equal(compat.preferMseHls(99), false);
});

test('Safari, iOS Chrome and unavailable MSE/HLS retain native capability probing', () => {
  for (const options of [{ ua: 'Version/18 Safari/605' }, { ua: 'CriOS/155 Mobile Safari/605' }, { mse: false }, { hls: false }]) {
    const { video, original, compat } = fixture(options);
    assert.equal(compat.preferMseHls(7), false);
    assert.equal(video.canPlayType, original);
  }
});
