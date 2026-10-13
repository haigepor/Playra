"""榜单只读请求、顺序和分类投影回归。"""
import tempfile
from pathlib import Path
import unittest

from adapters import RuntimeContext, RuntimeFailure
from miomedia_adapter import MioMediaSdk, validate_payload
from test_miomedia import FakeClient


class HotRankTests(unittest.TestCase):
    def test_required_one_based_payload(self):
        valid = {'categoryId': '0', 'pageIndex': 1, 'pageSize': 20}
        self.assertEqual(validate_payload('hotRank', valid), valid)
        for payload in ({}, {'pageIndex': 1, 'pageSize': 20},
                        {**valid, 'categoryId': 0}, {**valid, 'pageIndex': 0},
                        {**valid, 'pageSize': False}, {**valid, 'sortBy': 'playCount'}):
            with self.assertRaises(RuntimeFailure):
                validate_payload('hotRank', payload)

    def test_projection_preserves_title_order_and_string_ids(self):
        class RankClient(FakeClient):
            def request(self, path, payload):
                assert path == '/video/modules'
                assert payload['pageIndex'] == 1 and payload['pageSize'] == 20
                return 200, {'code': 200, 'success': True, 'data': {'list': [
                    {'id': 'another', 'items': []},
                    {'id': 'MOD_818368', 'name': '平台原始榜名', 'k': 'hot',
                     'items': [{'id': str(9007199254740993+i), 'title': '作品%d' % i,
                                'playCount': (i % 2)*10000000,
                                'adToken': 'private'} for i in range(12)]}]}}
        with tempfile.TemporaryDirectory() as folder:
            sdk = MioMediaSdk(Path(folder)/'device.json', client_factory=RankClient)
            result = sdk.call('hotRank', {'categoryId': '42', 'pageIndex': 1,
                                         'pageSize': 20}, RuntimeContext(5000))['data']
            self.assertEqual(result['categoryId'], '42')
            self.assertIsNone(result['window'])
            self.assertIsNone(result['metric'])
            self.assertEqual(len(result['list']), 1)
            rank = result['list'][0]
            self.assertEqual(rank['name'], '平台原始榜名')
            self.assertEqual([v['id'] for v in rank['items']],
                             [str(9007199254740993+i) for i in range(10)])
            self.assertNotIn('adToken', rank['items'][0])

    def test_absent_is_empty_and_malformed_is_error(self):
        class RankClient(FakeClient):
            data = {'list': []}
            def request(self, *_):
                return 200, {'code': 200, 'success': True, 'data': self.data}
        with tempfile.TemporaryDirectory() as folder:
            sdk = MioMediaSdk(Path(folder)/'device.json', client_factory=RankClient)
            payload = {'categoryId': '0', 'pageIndex': 1, 'pageSize': 20}
            self.assertEqual(sdk.call('hotRank', payload, RuntimeContext(5000))['data']['list'], [])
            for data in ({}, {'list': [{'id': 'MOD_818368', 'items': 'bad'}]}):
                RankClient.data = data
                with self.assertRaisesRegex(RuntimeFailure, 'PARSE_ERROR'):
                    sdk.call('hotRank', payload, RuntimeContext(5000))


if __name__ == '__main__':
    unittest.main()
