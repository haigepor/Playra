const { test } = require('node:test');
const assert = require('node:assert/strict');
const createBridge = require('../../web/player/artplayer_bridge.js');

function fixture() {
  const video = {
    src: 'blob:owned-by-media-kit', currentSrc: 'blob:owned-by-media-kit',
    volume: 0.37, muted: true, playbackRate: 1.75, readyState: 4,
    controls: false, style: {}, className: 'original-video',
    pauseCalls: 0, loadCalls: 0,
    pause() { this.pauseCalls++; }, load() { this.loadCalls++; },
  };
  class FakeArtplayer {
    static instances = [];
    constructor(options) {
      this.options = options;
      this.listeners = {};
      this.loading = { show: true }; this.mask = { show: true };
      this.controls = { show: false }; this.notice = {};
      this.video = options.proxy();
      this.video.volume = 1; this.video.playbackRate = 1;
      options.customType[options.type](this.video, options.url, this);
      FakeArtplayer.instances.push(this);
    }
    on(event, fn) { this.listeners[event] = fn; }
    emit(event) { this.listeners[event]?.(); }
    destroy() {
      if (FakeArtplayer.REMOVE_SRC_WHEN_DESTROY) {
        this.video.src = ''; this.video.load();
      }
      this.destroyed = true;
    }
  }
  const container = { replaceChildren() {} };
  return { video, container, FakeArtplayer, bridge: createBridge(FakeArtplayer) };
}

test('mount keeps the owned HLS source, volume, mute and speed', () => {
  const { video, container, bridge, FakeArtplayer } = fixture();
  const mounted = bridge.mount(container, video, { theme: '#a7b7ff' });
  assert.equal(video.src, 'blob:owned-by-media-kit');
  assert.equal(video.volume, 0.37);
  assert.equal(video.muted, true);
  assert.equal(video.playbackRate, 1.75);
  assert.equal(video.pauseCalls, 0);
  assert.equal(video.loadCalls, 0);
  assert.equal(FakeArtplayer.instances[0].options.proxy(), video);
  assert.equal(FakeArtplayer.instances[0].isReady, true);
  mounted.destroy();
});

test('source changes stay owned by media_kit and late ready events are harmless', () => {
  const { video, container, bridge, FakeArtplayer } = fixture();
  const mounted = bridge.mount(container, video, {});
  const art = FakeArtplayer.instances[0];
  video.src = 'blob:second-episode';
  video.volume = 0.6; video.playbackRate = 2;
  art.emit('ready');
  assert.equal(video.src, 'blob:second-episode');
  assert.equal(video.volume, 0.6);
  assert.equal(video.playbackRate, 2);
  mounted.destroy(); mounted.destroy();
  assert.equal(art.destroyed, true);
  assert.equal(video.src, 'blob:second-episode');
  assert.equal(video.loadCalls, 0);
  assert.equal(video.className, 'original-video');
});

test('next episode action delegates to the real selection owner', () => {
  const { video, container, bridge, FakeArtplayer } = fixture();
  let next = 0;
  bridge.mount(container, video, { onNext: () => next++ });
  const control = FakeArtplayer.instances[0].options.controls.find(c => c.name === 'playra-next');
  control.click();
  assert.equal(next, 1);
});

test('missing assets leave working browser controls and clean up safely', () => {
  const { video, container } = fixture();
  const mounted = createBridge(null).mount(container, video, {});
  assert.equal(video.controls, true);
  mounted.destroy();
  assert.equal(video.controls, false);
  assert.equal(video.src, 'blob:owned-by-media-kit');
});
