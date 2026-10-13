"""接口与播放线路诊断；复用身份，计时报告不含密钥、凭证或媒体地址。"""
import argparse
import hashlib
import hmac
import json
from pathlib import Path
import statistics
import time
import urllib.error
import urllib.request
from urllib.parse import urljoin

from adapters import RuntimeContext
from miomedia_adapter import MioMediaSdk
from vendor.miomedia import Client
from vendor.miomedia import transport, signature, device

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / '.dart_tool/interface-playback-audit-20261012'


class TimedClient(Client):
    records = []

    def _post(self, path, body, headers):
        start = time.perf_counter()
        status, wire = super()._post(path, body, headers)
        network = (time.perf_counter() - start) * 1000
        self.records.append({'path': path, 'http': status, 'networkMs': round(network, 3),
                             'wireBytes': len(wire), 'requestBytes': len(body)})
        return status, wire

    def measured(self, path, action):
        start = time.perf_counter()
        before = len(self.records)
        try:
            result = action()
            if len(self.records) > before:
                row = self.records[-1]
                row['totalMs'] = round((time.perf_counter() - start) * 1000, 3)
                row['localMs'] = round(row['totalMs'] - row['networkMs'], 3)
                row['businessCode'] = result[1].get('code') if isinstance(result[1], dict) else None
            return result
        except Exception as error:
            self.records.append({'path': path, 'error': type(error).__name__,
                                 'totalMs': round((time.perf_counter() - start) * 1000, 3)})
            raise

    def handshake(self):
        return self.measured('/auth/negotiate', lambda: super(TimedClient, self).handshake())

    def request(self, path, payload):
        return self.measured(path, lambda: super(TimedClient, self).request(path, payload))


def json_call(url, body=None, budget=20000):
    data = None if body is None else json.dumps(body).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={
        'Content-Type': 'application/json', 'X-Kazumi-Request': '1',
        'X-Playra-Timeout-Ms': str(budget)})
    with urllib.request.urlopen(req, timeout=budget / 1000 + 2) as response:
        return json.load(response)


def fetch_media(url, headers, maximum, ranged=False):
    extra = {'Range': 'bytes=0-%d' % (maximum - 1)} if ranged else {}
    with urllib.request.urlopen(urllib.request.Request(url, headers={**headers, **extra}), timeout=15) as r:
        body = r.read(maximum)
        return r.status, r.headers.get_content_type(), body, r.geturl()


def verify_media(media):
    status, mime, body, final = fetch_media(media['url'], media.get('headers', {}), 262144, True)
    out = {'http': status, 'mime': mime, 'bytesRead': len(body)}
    if body.lstrip().startswith(b'#EXTM3U'):
        out['kind'] = 'hls'
        out['mimeCorrect'] = mime in ('application/vnd.apple.mpegurl', 'application/x-mpegurl')
        for _ in range(4):
            lines = body.decode('utf-8-sig').splitlines()
            targets = [s.strip() for s in lines if s.strip() and not s.startswith('#')]
            if not targets:
                raise ValueError('EmptyPlaylist')
            if any(s.startswith('#EXT-X-STREAM-INF') for s in lines):
                status, mime, body, final = fetch_media(urljoin(final, targets[0]), media.get('headers', {}), 262144)
                if not body.lstrip().startswith(b'#EXTM3U'):
                    raise ValueError('InvalidChildPlaylist')
                continue
            # 清单存在并不等于可播放：核验必要密钥、初始化段与首个分片。
            import re
            for tag in ('#EXT-X-KEY:', '#EXT-X-MAP:'):
                entries = [s for s in lines if s.startswith(tag)]
                for entry in entries[:1]:
                    match = re.search(r'URI="([^"]+)"', entry)
                    if not match:
                        continue
                    st, typ, content, _ = fetch_media(urljoin(final, match[1]), media.get('headers', {}), 65536)
                    out['keyHttp' if tag.startswith('#EXT-X-KEY') else 'initHttp'] = st
                    if st != 200 or not content or b'<html' in content[:64].lower():
                        raise ValueError('InvalidHlsDependency')
            st, typ, segment, _ = fetch_media(urljoin(final, targets[0]), media.get('headers', {}), 65536, True)
            out.update(segmentHttp=st, segmentMime=typ, segmentBytes=len(segment))
            out['segmentValid'] = st in (200, 206) and len(segment) > 188 and not (
                segment.lstrip().startswith((b'<', b'{')) or typ in ('text/html', 'application/json'))
            out['pass'] = out['mimeCorrect'] and out['segmentValid']
            return out
        raise ValueError('PlaylistDepthExceeded')
    out.update(kind='mp4' if body[4:8] == b'ftyp' else 'unknown',
               mimeCorrect=mime == 'video/mp4',
               **{'pass': status in (200, 206) and mime == 'video/mp4' and body[4:8] == b'ftyp'})
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--play', action='store_true')
    args = parser.parse_args()
    identity = ROOT / '.dart_tool/miomedia/device.json'
    before = hashlib.sha256(identity.read_bytes()).digest()
    sdk = MioMediaSdk(identity, client_factory=TimedClient)
    report = {'checkedAt': '2026-10-12', 'scope': '已接入操作与发现的线路抽样',
              'requests': TimedClient.records, 'operations': [], 'videos': [], 'playback': []}
    REPORT.mkdir(parents=True, exist_ok=True)

    def save():
        report['identityPreserved'] = before == hashlib.sha256(identity.read_bytes()).digest()
        report['playbackHealth'] = sdk.playback_health()
        (REPORT / 'miomedia-live.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    def call(op, payload):
        start = time.perf_counter()
        row = {'operation': op}
        try:
            data = sdk.call(op, payload, RuntimeContext(60000))['data']
            row.update(status='PASS', keys=list(data), elapsedMs=round((time.perf_counter() - start) * 1000, 2))
            report['operations'].append(row)
            save()
            return data
        except Exception as e:
            row.update(status='FAIL', error=getattr(e, 'code', type(e).__name__),
                       elapsedMs=round((time.perf_counter() - start) * 1000, 2))
            report['operations'].append(row)
            save()
            return {}

    pool = {}
    def ingest(values):
        for v in values:
            if isinstance(v, dict) and isinstance(v.get('id'), str):
                pool[v['id']] = v

    for _ in range(2):
        recommend = call('recommend', {})
        ingest(recommend.get('guessYouLike', {}).get('videos', []))
        call('banners', {})
        config = call('searchConfig', {})
        ingest([v.get('video', {}) for v in config.get('hotSearchData', {}).get('items', [])])
        ingest(call('catalog', {'pageIndex': 1, 'pageSize': 50}).get('videos', []))
        call('hotRank', {'categoryId': '0', 'pageIndex': 1, 'pageSize': 20})
        ingest(call('search', {'keyword': '吞噬星空', 'pageIndex': 1, 'pageSize': 20}).get('videos', []))
    selected = {}
    for v in pool.values():
        category = v.get('categoryName', '')
        if category in ('电影大全', '剧集大全', '综艺节目', '国产动漫', '日本动漫', '漫剧', '动漫电影'):
            selected.setdefault(category, v)
        if v.get('title') == '吞噬星空':
            selected['国产动漫'] = v
    for category in ('电影大全', '剧集大全', '综艺节目', '漫剧'):
        if category not in selected:
            for v in call('search', {'keyword': category[:2], 'pageIndex': 1, 'pageSize': 20}).get('videos', []):
                if v.get('categoryName') == category:
                    selected[category] = v
                    break
    tasks = []
    for category, v in selected.items():
        detail = call('detail', {'videoId': v['id']}).get('video', {})
        lines = detail.get('player', [])
        entry = {'category': category, 'id': v['id'], 'title': v['title'],
                 'lines': [{'code': s.get('playerCode'), 'name': s.get('playerName', s.get('name', ''))} for s in lines]}
        report['videos'].append(entry)
        call('catalog', {'categoryId': v['categoryId'], 'pageIndex': 1, 'pageSize': 3})
        for line in lines:
            code = line.get('playerCode')
            episodes = call('episodes', {'videoId': v['id'], 'code': code}).get('episodes', [])
            entry.setdefault('episodes', {})[code] = len(episodes)
            if episodes:
                tasks.append({'videoId': v['id'], 'code': code, 'episodeNum': episodes[0]['episodeNum'],
                              'title': v['title'], 'category': category})
    report['lineCodes'] = sorted({t['code'] for t in tasks})
    save()
    print(json.dumps({'discoveredVideos': len(pool), 'samples': report['videos'], 'lineCodes': report['lineCodes']}, ensure_ascii=False), flush=True)
    if args.play:
        for task in tasks:
            start = time.perf_counter()
            result = call('play', {k: task[k] for k in ('videoId', 'code', 'episodeNum')})
            row = {**task, 'status': result.get('status', 'request_failed'),
                   'resolveMs': round((time.perf_counter() - start) * 1000, 2)}
            if row['status'] == 'ready':
                try:
                    row['media'] = verify_media(result['media'])
                except Exception as e:
                    row['media'] = {'pass': False, 'error': type(e).__name__}
            report['playback'].append(row)
            save()
            print(json.dumps(row, ensure_ascii=False), flush=True)
    # 单独测稳定的本地开销，不把网络变化混进签名与设备算法结论。
    client = Client.load_identity(identity)
    profile = {}
    for name, action in (
        ('loadIdentity', lambda: Client.load_identity(identity)),
        ('buildHeaders', client.build_headers),
        ('deriveDeviceSecret', lambda: device.derive_device_secret(client.session_config['masterSecret'], client.device_id)),
        ('sealSmallRequest', lambda: transport.V3Session(client.device_secret).seal(b'{"pageIndex":1,"pageSize":20}'))):
        times = []
        for _ in range(30):
            t = time.perf_counter()
            action()
            times.append((time.perf_counter() - t) * 1000)
        profile[name] = {'medianMs': round(statistics.median(times), 3), 'maxMs': round(max(times), 3)}
    report['localProfile'] = profile
    save()
    print(json.dumps({'localProfile': profile, 'playbackHealth': report['playbackHealth'],
                      'identityPreserved': report['identityPreserved']}, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
