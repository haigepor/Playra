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
    let art;
    const actions = [
      { value: 'screenshot', html: '截取当前画面' },
      { value: 'fullscreenWeb', html: '网页全屏' },
      { value: 'pip', html: '画中画' },
      { value: 'mute', html: '切换静音' },
      ...(options.onNext ? [{ value: 'next', html: '下一集' }] : []),
      ...(options.onDanmaku ? [{ value: 'danmaku', html: '切换弹幕' }] : []),
    ];
    art = new Artplayer({
      container, proxy: () => video,
      url: video.currentSrc || video.src || 'about:blank',
      type: 'playra-owned', customType: { 'playra-owned': () => {} },
      autoplay: false, volume: state.volume, muted: state.muted,
      theme: options.theme || '#a7b7ff', lang: 'zh-cn',
      setting: true, playbackRate: true, aspectRatio: true,
      fullscreen: true, fullscreenWeb: true, pip: true, hotkey: true,
      screenshot: true, autoSize: false, autoMini: false,
      mutex: false, playsInline: true, controls,
      settings: [{
        name: 'playra-more', html: '更多播放操作', selector: actions,
        onSelect(item) {
          // 窄屏收起的操作仍可从设置面板访问，不重建 video 或重载媒体。
          try {
            switch (item.value) {
              case 'screenshot':
                Promise.resolve(art.screenshot()).catch(() => { art.notice.show = '截图暂不可用'; });
                break;
              case 'fullscreenWeb': art.fullscreenWeb = !art.fullscreenWeb; break;
              case 'pip': art.pip = !art.pip; break;
              case 'mute': art.muted = !art.muted; break;
              case 'next': options.onNext(); break;
              case 'danmaku': options.onDanmaku(); break;
            }
          } catch (_) { art.notice.show = '当前浏览器暂不支持此操作'; }
          return '更多播放操作';
        },
      }],
    });
    // 在真实播放器容器上查询尺寸，窄屏/分栏/全屏都使用同一套响应式规则。
    const playerElement = art.template?.$player;
    playerElement?.classList.add('playra-artplayer');
    const playControl = playerElement?.querySelector('.art-control-playAndPause');
    const syncPlayLabel = () => playControl?.setAttribute('aria-label', video.paused ? '播放' : '暂停');
    syncPlayLabel();
    // 图标上的提示不能替代可聚焦按钮名称；播放状态变化时同步外层名称。
    playControl?.querySelectorAll('[aria-label]').forEach(icon => icon.setAttribute('aria-hidden', 'true'));
    video.addEventListener('play', syncPlayLabel);
    video.addEventListener('pause', syncPlayLabel);
    const keyboardControls = [];
    playerElement?.querySelectorAll('.art-control[aria-label]').forEach(control => {
      control.setAttribute('role', 'button');
      control.tabIndex = 0;
      const onKey = event => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault(); event.stopPropagation(); control.click();
        }
      };
      control.addEventListener('keydown', onKey);
      keyboardControls.push([control, onKey]);
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
        video.removeEventListener('play', syncPlayLabel);
        video.removeEventListener('pause', syncPlayLabel);
        for (const [control, onKey] of keyboardControls) control.removeEventListener('keydown', onKey);
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
