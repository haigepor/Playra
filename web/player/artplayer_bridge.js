(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory;
  else root.PlayraArtPlayer = factory(root.Artplayer);
})(typeof globalThis !== 'undefined' ? globalThis : this, function (Artplayer) {
  'use strict';

  function mount(container, video, options = {}) {
    const original = { controls: video.controls, className: video.className };
    let destroyed = false;
    if (!Artplayer) {
      container.replaceChildren(video);
      video.controls = true;
      return { destroy() { video.controls = original.controls; } };
    }

    // media_kit 持有 HLS/MSE 和媒体生命周期；ArtPlayer 只接管同一个 video 的控件。
    // https://github.artplayer.org/document/en/start/option.html#proxy
    Artplayer.REMOVE_SRC_WHEN_DESTROY = false;
    Artplayer.RECONNECT_TIME_MAX = 0;
    const state = { volume: video.volume, muted: video.muted, rate: video.playbackRate };
    const controls = [];
    if (options.onNext) controls.push({
      name: 'playra-next', position: 'left', index: 20, html: '下一集',
      tooltip: '下一集', click: () => options.onNext(),
    });
    if (options.onDanmaku) controls.push({
      name: 'playra-danmaku', position: 'right', html: '弹幕',
      tooltip: '切换弹幕', click: () => options.onDanmaku(),
    });
    const art = new Artplayer({
      container, proxy: () => video,
      url: video.currentSrc || video.src || 'about:blank',
      type: 'playra-owned', customType: { 'playra-owned': () => {} },
      autoplay: false, volume: state.volume, muted: state.muted,
      theme: options.theme || '#a7b7ff', lang: 'zh-cn',
      setting: true, playbackRate: true, aspectRatio: true,
      fullscreen: true, fullscreenWeb: true, pip: true, hotkey: true,
      screenshot: true, autoSize: false, autoMini: false,
      mutex: false, playsInline: true, controls,
    });
    video.volume = state.volume;
    video.muted = state.muted;
    video.playbackRate = state.rate;
    video.controls = false;
    video.style.objectFit = options.fit || 'contain';

    // 可能在解码已就绪之后挂载控件，补交就绪状态但不重载媒体或重新起播。
    if (video.readyState >= 3) {
      art.emit('video:canplay');
      art.loading.show = false;
      art.controls.show = true;
      art.mask.show = video.paused;
      art.isReady = true;
    }
    return {
      destroy() {
        if (destroyed) return;
        destroyed = true;
        art.destroy(false);
        video.controls = original.controls;
        video.className = original.className;
      },
    };
  }

  function mountHandle(container, handle, options) {
    const video = globalThis['$com.alexmercerind.media_kit.instances']?.[handle];
    if (!video) throw new Error('Playra video instance is unavailable');
    return mount(container, video, options);
  }
  return { mount, mountHandle };
});
