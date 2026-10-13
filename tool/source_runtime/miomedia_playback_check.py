"""隔离身份验证三策略与直链，只记录脱敏结果，不操作应用设备态。"""
import argparse
import hashlib
import hmac
import json
from pathlib import Path
import tempfile
import urllib.request

from adapters import RuntimeContext
from miomedia_adapter import MioMediaSdk
from vendor.miomedia import Client, PlaybackClient


def verify_media(media):
    request = urllib.request.Request(media['url'], headers=media.get('headers', {}))
    with urllib.request.urlopen(request, timeout=20) as response:
        body = response.read(4096)
        content_type = response.headers.get_content_type().lower()
        hls = response.status == 200 and body.lstrip().startswith(b'#EXTM3U') and \
            content_type in ('application/vnd.apple.mpegurl', 'application/x-mpegurl')
        # 部分剧集返回 MP4，使用容器魔数与 MIME 一起核验，不能当成 HLS 失败。
        mp4 = response.status == 200 and content_type == 'video/mp4' and body[4:8] == b'ftyp'
        return {'http': response.status, 'contentType': content_type,
                'isHls': hls, 'isMp4': mp4, 'isMedia': hls or mp4}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--episodes', type=int, default=5)
    parser.add_argument('--strategy', choices=['auto', 'token', 'rotate'], default='auto')
    parser.add_argument('--bridge', action='store_true')
    parser.add_argument('--report', required=True)
    args = parser.parse_args()
    if not 1 <= args.episodes <= 20 or (args.bridge and args.strategy != 'token'):
        parser.error('bridge requires token; episodes must be 1..20')
    report = {'strategy': args.strategy, 'bridge': args.bridge, 'episodes': [],
              'rotations': 0, 'handshakeVerified': False}
    try:
        with tempfile.TemporaryDirectory(prefix='playra-playback-check-') as directory:
            identity = Path(directory) / 'device.json'
            if args.bridge:
                sdk = MioMediaSdk(identity)
                sdk._ensure_session(RuntimeContext(30000))
                report['handshakeVerified'] = sdk._device_id is not None
                original = identity.read_bytes()
            else:
                client = Client()
                client.save_identity(identity)
                client = Client.load_identity(identity)
                status, obj = client.handshake()
                report['handshakeVerified'] = status == 200 and hmac.compare_digest(
                    (obj.get('data') or {}).get('deviceSecret', ''), client.device_secret)
                original = client.device_id
                playback = PlaybackClient(client, strategy=args.strategy)
            if not report['handshakeVerified']:
                raise ValueError('SESSION_MISMATCH')
            for episode in range(1, args.episodes + 1):
                selection = {'videoId': '318186806611144716', 'code': 'dym3u8', 'episodeNum': episode}
                result = sdk.call('play', selection, RuntimeContext(60000))['data'] if args.bridge else \
                    playback.play(selection['videoId'], selection['code'], episode, caps=[])
                row = {'episode': episode, 'status': result.get('status'),
                       'strategy': result.get('strategy'), 'rotated': result.get('rotated', False)}
                if row['status'] == 'ready':
                    row['media'] = verify_media(result['media'])
                report['episodes'].append(row)
                report['rotations'] = sdk.playback_health()['rotations'] if args.bridge else playback.rotations
            report['identityPreserved'] = original == (identity.read_bytes() if args.bridge else client.device_id)
            if args.bridge:
                restarted = MioMediaSdk(identity)
                restarted.call('recommend', {}, RuntimeContext(30000))
                report['identityReusedAfterRestart'] = original == identity.read_bytes()
            ready = all(row['status'] == 'ready' and row.get('media', {}).get('isMedia')
                        for row in report['episodes'])
            expected = args.episodes if args.strategy == 'rotate' else 0
            report['status'] = 'PASS' if ready and report['rotations'] == expected and \
                (args.strategy == 'rotate' or report['identityPreserved']) else 'FAIL'
    except Exception as error:
        # 异常文本可能含地址和会话材料，仅记录异常类型。
        report.update(status='FAIL', error=type(error).__name__)
    destination = Path(args.report).resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
