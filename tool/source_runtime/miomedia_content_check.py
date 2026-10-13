"""持续复用独立测试身份的内容与播放联调；只输出脱敏验收结果。"""
import argparse
import hashlib
import json
from pathlib import Path
import time
import urllib.request

from adapters import RuntimeContext, RuntimeFailure
from miomedia_adapter import MioMediaSdk


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--state-dir', default='.dart_tool/miomedia-content-validation')
    args = parser.parse_args()
    state = Path(args.state_dir).resolve()
    sdk = MioMediaSdk(state / 'device.json')
    rows = []

    def call(operation, payload=None):
        started = time.monotonic()
        result = sdk.call(operation, payload or {}, RuntimeContext(30000))['data']
        rows.append({'operation': operation, 'status': 'PASS',
                     'elapsedMs': round((time.monotonic() - started) * 1000),
                     'dataKeys': list(result)})
        return result

    report = {'checkedAt': '2026-10-12', 'operations': rows}
    try:
        call('recommend')
        call('banners')
        first = call('catalog', {'pageIndex': 1, 'pageSize': 3})
        second = call('catalog', {'pageIndex': 2, 'pageSize': 3})
        report['differentCatalogPages'] = [v['id'] for v in first['videos']] != [v['id'] for v in second['videos']]
        config = call('searchConfig')
        search = call('search', {'keyword': '流浪地球', 'pageIndex': 1, 'pageSize': 20})
        movies = [v for v in search.get('videos', []) if v.get('categoryName') == '电影大全']
        if not movies:
            raise RuntimeFailure('NO_MOVIE_RESULT', 502)
        report['searchMovieCount'] = len(movies)
        category = call('catalog', {'categoryId': movies[0]['categoryId'], 'pageIndex': 1, 'pageSize': 3})
        report['categoryMatched'] = bool(category.get('videos')) and all(v.get('categoryId') == movies[0]['categoryId'] for v in category['videos'])
        detail = call('detail', {'videoId': movies[0]['id']})['video']
        line = detail['player'][0]['playerCode']
        episodes = call('episodes', {'videoId': detail['id'], 'code': line})['episodes']
        report['episodeCount'] = len(episodes)
        selection = {'videoId': detail['id'], 'code': line, 'episodeNum': episodes[0]['episodeNum'], 'caps': []}
        qualities = call('qualities', selection)
        report['qualityCount'] = len(qualities.get('qualities', []))
        playback = call('play', selection)
        report['playbackStatus'] = playback.get('status')
        # 不因广告额度或其他业务状态创建、替换身份或重试换取。
        if playback.get('status') == 'ready':
            media = playback['media']
            request = urllib.request.Request(media['url'], headers=media.get('headers', {}))
            with urllib.request.urlopen(request, timeout=15) as response:
                body = response.read(1048576)
                content_type = response.headers.get_content_type()
                report['media'] = {'httpStatus': response.status, 'contentType': content_type,
                                   'isHls': body.lstrip().startswith(b'#EXTM3U'),
                                   'corsAllowed': response.headers.get('Access-Control-Allow-Origin') == '*'}
            report['mediaVerified'] = report['media']['httpStatus'] == 200 and report['media']['isHls'] and content_type in ('application/vnd.apple.mpegurl', 'application/x-mpegurl')
        identity = hashlib.sha256(sdk.identity_path.read_bytes()).digest()
        MioMediaSdk(sdk.identity_path).call('recommend', {}, RuntimeContext(30000))
        report['identityReused'] = identity == hashlib.sha256(sdk.identity_path.read_bytes()).digest()
        report['sessionSecretVerified'] = sdk._device_id is not None
        report['status'] = 'PASS' if all(report.get(k) for k in ('differentCatalogPages', 'categoryMatched', 'mediaVerified', 'identityReused', 'sessionSecretVerified')) else 'PARTIAL'
    except RuntimeFailure as error:
        report.update(status='FAIL', error=error.code)
    except Exception as error:
        # 不打印包含媒体令牌的 URL、上游原文或设备密钥。
        report.update(status='FAIL', error=type(error).__name__)
    state.mkdir(parents=True, exist_ok=True)
    (state / 'content-check.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
