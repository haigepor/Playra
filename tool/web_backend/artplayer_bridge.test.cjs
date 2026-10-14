const { test } = require('node:test');
const assert = require('node:assert/strict');
const createBridge = require('../../web/player/artplayer_bridge.js');

function fixture() {
  const video = {
    src: 'blob:owned-by-media-kit', currentSrc: 'blob:owned-by-media-kit',
    volume: 0.37, muted: true, playbackRate: 1.75, readyState: 4,
    controls: false, style: {}, className: 'original-video',
    pauseCalls: 0, loadCalls: 0,
    listeners: {},
    addEventListener(event, fn) { this.listeners[event] = fn; },
    removeEventListener(event, fn) { if (this.listeners[event] === fn) delete this.listeners[event]; },
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

test('compact toolbar keeps secondary actions in settings without remounting media', () => {
  const { video, container, bridge, FakeArtplayer } = fixture();
  let next = 0;
  const mounted = bridge.mount(container, video, { onNext: () => next++ });
  const art = FakeArtplayer.instances[0];
  const more = art.options.settings.find(s => s.name === 'playra-more');
  more.onSelect(more.selector.find(s => s.value === 'next'));
  assert.equal(next, 1);
  assert.equal(video.loadCalls, 0);
  assert.equal(FakeArtplayer.instances.length, 1);
  mounted.destroy();
});

test('play control exposes the current action and releases keyboard/media listeners', () => {
  const { video, container, bridge, FakeArtplayer } = fixture();
  const attributes = {};
  const handlers = {};
  let clicks = 0;
  const playControl = {
    setAttribute(name, value) { attributes[name] = value; },
    querySelectorAll() { return []; },
    addEventListener(name, fn) { handlers[name] = fn; },
    removeEventListener(name, fn) { if (handlers[name] === fn) delete handlers[name]; },
    click() { clicks++; },
  };
  class AccessibleArtplayer extends FakeArtplayer {
    constructor(options) {
      super(options);
      this.template = { $player: {
        classList: { add() {} },
        querySelector() { return playControl; },
        querySelectorAll() { return [playControl]; },
      } };
    }
  }
  video.paused = true;
  const mounted = createBridge(AccessibleArtplayer).mount(container, video);
  assert.equal(attributes['aria-label'], '播放');
  assert.equal(attributes.role, 'button');
  assert.equal(playControl.tabIndex, 0);
  video.paused = false;
  video.listeners.play();
  assert.equal(attributes['aria-label'], '暂停');
  handlers.keydown({ key: 'Enter', preventDefault() {}, stopPropagation() {} });
  assert.equal(clicks, 1);
  mounted.destroy();
  assert.deepEqual(video.listeners, {});
  assert.deepEqual(handlers, {});
});
