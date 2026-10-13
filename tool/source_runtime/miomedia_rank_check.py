"""榜单 SDK 与真实 HTTP 桥接对照；复用持久身份，不修改账户或播放态。"""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

from vendor.miomedia import Client


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8948)
    parser.add_argument('--identity', default=str(Path(__file__).resolve().parents[2] / '.dart_tool/miomedia/device.json'))
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    identity = Path(args.identity)
    before = hashlib.sha256(identity.read_bytes()).hexdigest()
    client = Client.load_identity(identity, timeout=20)
    status, response = client.handshake()
    assert status == 200 and response.get('success') is True
    assert response['data']['deviceSecret'] == client.device_secret
    evidence = []
    for category in ('0', '317182404551585792'):
        payload = {'categoryId': category, 'pageIndex': 1, 'pageSize': 20}
        snapshots = []
        source = None
        for _ in range(2):
            status, result = client.request('/video/modules', payload)
            assert status == 200 and result.get('success') is True
            source = next(m for m in result['data']['list'] if m.get('id') == 'MOD_818368')
            snapshots.append([v['id'] for v in source['items'][:10]])
        assert snapshots[0] == snapshots[1]
        body = json.dumps({'operation': 'hotRank', 'payload': payload}).encode('utf-8')
        req = urllib.request.Request('http://127.0.0.1:%d/v1/adapters/miomedia/sdk' % args.port,
            data=body, headers={'Content-Type':'application/json', 'X-Kazumi-Request':'1', 'X-Playra-Timeout-Ms':'20000'})
        with urllib.request.urlopen(req, timeout=25) as response:
            assert response.status == 200
            raw = response.read()
            data = json.loads(raw)['data']
        actual = data['list'][0]
        assert [v['id'] for v in actual['items']] == snapshots[1]
        assert actual['name'] == source['name'] and actual['k'] == source['k']
        assert actual['boardTabs'] == source['boardTabs']
        assert len(actual['items']) == 10
        assert data['categoryId'] == category and data['window'] is None and data['metric'] is None
        evidence.append({'categoryId':category, 'id':actual['id'], 'name':actual['name'],
            'k':actual['k'], 'boardTabs':actual['boardTabs'], 'count':len(actual['items']),
            'positions':[{'rank':i+1, 'id':v['id'], 'title':v['title']} for i,v in enumerate(actual['items'])],
            'repeatOrderSame':True, 'bridgeOrderSame':True, 'bridgeBytes':len(raw), 'window':None,'metric':None})
    assert [v['id'] for v in evidence[0]['positions']] != [v['id'] for v in evidence[1]['positions']]
    assert before == hashlib.sha256(identity.read_bytes()).hexdigest()
    result = {'result':'PASS', 'identityUnchanged':True, 'categoriesDifferent':True, 'boards':evidence}
    Path(args.output).write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    for e in evidence:
        print('id=%s name=%s k=%s boardTabs=%s count=%d categoryId=%s bytes=%d' %
              (e['id'], e['name'], e['k'], e['boardTabs'], e['count'], e['categoryId'], e['bridgeBytes']))
        for v in e['positions']: print('%2d. %s %s' % (v['rank'], v['id'], v['title']))
    print('RANK CHECK ALL PASS; identity unchanged')


if __name__ == '__main__':
    main()
