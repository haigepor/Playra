"""默认平台的受限内容联调；不打印设备身份、密钥或解析脚本。"""
import hashlib
import json
from pathlib import Path
import time

from adapters import RuntimeContext, RuntimeFailure
from miomedia_adapter import MioMediaAdapter


def main():
    adapter = MioMediaAdapter()
    evidence = []
    def call(operation, payload=None):
        started = time.monotonic()
        try:
            result = adapter.sdk_call(operation, payload or {}, RuntimeContext(20000))
            data = result['data']
            evidence.append({'operation': operation, 'status': 'PASS',
                             'elapsedMs': round((time.monotonic() - started) * 1000),
                             'dataKeys': list(data)})
            return data
        except RuntimeFailure as error:
            evidence.append({'operation': operation, 'status': 'FAIL', 'error': error.code})
            return None
    recommend = call('recommend')
    banners = call('banners')
    catalog = call('catalog')
    if recommend:
        videos = recommend.get('guessYouLike', {}).get('videos', [])
        evidence[0]['items'] = len(videos)
    if banners:
        evidence[1]['items'] = len(banners.get('banners', []))
    if catalog and catalog.get('videos'):
        videos = catalog['videos']
        evidence[2]['items'] = len(videos)
        video_id = videos[0]['id']
        detail = call('detail', {'videoId': video_id})
        players = (detail or {}).get('video', {}).get('player', [])
        if detail:
            evidence[-1]['videoFields'] = list(detail.get('video', {}))
        if players:
            code = players[0]['playerCode']
            episodes = call('episodes', {'videoId': video_id, 'code': code})
            if episodes:
                items = episodes.get('episodes', [])
                evidence[-1]['items'] = len(items)
                if items: evidence[-1]['episodeFields'] = list(items[0])
            args = {'videoId': video_id, 'code': code, 'episodeNum': 1, 'caps': []}
            qualities = call('qualities', args)
            free = [q for q in (qualities or {}).get('qualities', []) if q.get('isVipOnly') is False]
            if free and qualities.get('exchangeToken'):
                exchange = call('exchange', {**args, 'quality': free[0]['quality'],
                                             'exchangeToken': qualities['exchangeToken']})
                if exchange:
                    evidence[-1].update(hasMediaUrl=bool(exchange.get('playUrl')),
                                        requiresClientParsing=exchange.get('isClientParse') is True,
                                        hasParsingMaterial=bool(exchange.get('luaScript')))
    path = adapter.sdk.identity_path
    digest = hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None
    # 重建 facade 后再次调用，验证落盘身份没有被覆盖。
    restarted = MioMediaAdapter()
    try:
        restarted.sdk_call('recommend', {}, RuntimeContext(20000))
        reused = digest is not None and digest == hashlib.sha256(path.read_bytes()).hexdigest()
    except RuntimeFailure:
        reused = False
    report = {'checkedAt': '2026-10-12', 'sessionSecretVerified': adapter.sdk._device_id is not None,
              'identityReusedAfterRestart': reused, 'operations': evidence}
    output = Path(__file__).resolve().parents[2] / '.dart_tool' / 'miomedia' / 'live-check.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if len(evidence) == 7 and all(row['status'] == 'PASS' for row in evidence) and reused else 1


if __name__ == '__main__':
    raise SystemExit(main())
