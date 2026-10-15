(function (root) {
  'use strict';
  const configured = new WeakSet();

  function preferMseHls(handle) {
    const video = root['$com.alexmercerind.media_kit.instances']?.[handle];
    if (!video || !/Chrome\/|Chromium\//.test(root.navigator?.userAgent || '') ||
        !root.Hls?.isSupported()) return false;
    if (configured.has(video)) return true;
    const nativeCanPlayType = video.canPlayType;
    // 当前 media_kit 只要原生报告 maybe 就跳过 hls.js；Chromium 对部分合法 TS 清单
    // 仍会解析失败。只调整本实例的 HLS 探测，让 media_kit 继续拥有同一个 video/MSE。
    video.canPlayType = function (type) {
      if (/^application\/(?:vnd\.apple\.mpegurl|x-mpegurl)(?:\s*;|$)/i.test(type)) return '';
      return nativeCanPlayType.call(this, type);
    };
    configured.add(video);
    return true;
  }

  root.PlayraMediaCompatibility = { preferMseHls };
})(globalThis);
