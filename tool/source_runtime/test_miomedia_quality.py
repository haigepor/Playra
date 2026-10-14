"""Quality selection through the real adapter and token playback session."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from adapters import RuntimeContext
from miomedia_adapter import MioMediaSdk
from test_miomedia import FakeClient


class MioMediaQualityTests(unittest.TestCase):
    def play_fixture(self, qualities, *, requested=None, variants=None):
        """Only transport is replaced; SDK selection and adapter validation run."""
        exchanges = []
        requests = []

        class QualityClient(FakeClient):
            def request(self, path, payload):
                requests.append(path)
                if path == '/ad/getConfig':
                    data = {'nonce': 'fixture-nonce'}
                elif path == '/ad/claimReward':
                    data = {'adToken': 'fixture-ad-token'}
                elif path == '/resolve/qualities':
                    data = {'exchangeToken': 'fixture-exchange-token',
                            'qualities': qualities}
                elif path == '/resolve/exchange':
                    exchanges.append(payload['quality'])
                    if variants is None:
                        data = {'playUrl': 'https://media.example.com/movie.m3u8',
                                'quality': payload['quality']}
                    else:
                        data = {'isClientParse': True,
                                'originalUrl': 'fixture__asset',
                                'quality': payload['quality']}
                else:
                    raise AssertionError('Unexpected endpoint')
                return 200, {'code': 200, 'success': True, 'data': data}

        with tempfile.TemporaryDirectory() as directory:
            sdk = MioMediaSdk(Path(directory) / 'device.json',
                              client_factory=QualityClient)
            sdk._ensure_session(RuntimeContext(5000))
            identity = sdk.identity_path.read_bytes()
            payload = {'videoId': '123', 'code': 'ffm3u8', 'episodeNum': 1}
            if requested is not None:
                payload['quality'] = requested
            parse_body = json.dumps({'code': 200, 'type': 'multi',
                                     'url': variants or []})
            with patch.object(sdk, '_parse_get', return_value=parse_body):
                result = sdk.call('play', payload, RuntimeContext(5000))['data']
            self.assertEqual(result['status'], 'ready')
            self.assertEqual(identity, sdk.identity_path.read_bytes())
        self.assertEqual(len(exchanges), 1, 'Quality choice must not replay exchange')
        self.assertEqual(requests.count('/ad/claimReward'), 1)
        return result, exchanges[0]

    def test_automatic_exchange_chooses_highest_declared_resolution(self):
        _, exchanged = self.play_fixture([
            {'quality': '720p'}, {'quality': '2160p'}, {'quality': '1080p'},
        ])
        self.assertEqual(exchanged, '2160p')

    def test_explicit_quality_is_preserved_even_when_higher_is_available(self):
        _, exchanged = self.play_fixture([
            {'quality': '2160p'}, {'quality': '720p'}, {'quality': '1080p'},
        ], requested='720p')
        self.assertEqual(exchanged, '720p')

    def test_unknown_origin_is_not_reported_as_a_known_resolution(self):
        result, exchanged = self.play_fixture([
            {'quality': 'origin', 'name': '原画'},
        ])
        self.assertEqual(exchanged, 'origin')
        self.assertEqual(result['media']['name'], 'origin')
        self.assertNotIn('1080', str(result))
        self.assertNotIn('2160', str(result))

    def test_automatic_parse_multi_chooses_highest_named_variant(self):
        result, _ = self.play_fixture([{'quality': 'origin'}], variants=[
            {'name': '720p', 'url': 'https://media.example.com/low.m3u8'},
            {'name': '2160p', 'url': 'https://media.example.com/high.m3u8'},
            {'name': '1080p', 'url': 'https://media.example.com/mid.m3u8'},
        ])
        self.assertEqual(result['media']['url'],
                         'https://media.example.com/high.m3u8')

    def test_explicit_parse_quality_does_not_switch_to_higher_variant(self):
        result, exchanged = self.play_fixture([
            {'quality': '2160p'}, {'quality': '720p'},
        ], requested='720p', variants=[
            {'name': '2160p', 'url': 'https://media.example.com/high.m3u8'},
            {'name': '720p', 'url': 'https://media.example.com/low.m3u8'},
        ])
        self.assertEqual(exchanged, '720p')
        self.assertEqual(result['media']['url'],
                         'https://media.example.com/low.m3u8')

    def test_parse_unknown_names_keep_provider_order_without_invented_rank(self):
        result, _ = self.play_fixture([{'quality': 'origin'}], variants=[
            {'name': '原画', 'url': 'https://media.example.com/first.m3u8'},
            {'name': '蓝光超清+', 'url': 'https://media.example.com/second.m3u8'},
        ])
        self.assertEqual(result['media']['url'],
                         'https://media.example.com/first.m3u8')
        self.assertNotIn('2160', str(result))

    def test_parse_height_evidence_survives_sdk_normalization(self):
        result, _ = self.play_fixture([{'quality': 'origin'}], variants=[
            {'name': 'A', 'height': 720, 'url': 'https://media.example.com/low.m3u8'},
            {'name': 'B', 'height': 2160, 'url': 'https://media.example.com/high.m3u8'},
        ])
        self.assertEqual(result['media']['url'], 'https://media.example.com/high.m3u8')
        self.assertEqual(result['media']['quality'], '2160p')

    def test_declared_quality_does_not_reject_parser_unknown_names(self):
        result, _ = self.play_fixture([{'quality': '1080p'}], requested='1080p', variants=[
            {'name': '高清', 'url': 'https://media.example.com/first.m3u8'},
            {'name': '超清', 'url': 'https://media.example.com/second.m3u8'},
        ])
        self.assertEqual(result['media']['url'], 'https://media.example.com/first.m3u8')

    def test_declared_quality_accepts_string_parser_variants(self):
        result, _ = self.play_fixture([{'quality': '1080p'}], requested='1080p', variants=[
            'https://media.example.com/first.m3u8', 'https://media.example.com/second.m3u8',
        ])
        self.assertEqual(result['media']['url'], 'https://media.example.com/first.m3u8')

    def test_parser_lower_resolution_is_reported_as_actual_fallback(self):
        result, _ = self.play_fixture([{'quality': '1080p'}], requested='1080p', variants=[
            {'name': '480p', 'url': 'https://media.example.com/low.m3u8'},
            {'name': '720p', 'url': 'https://media.example.com/mid.m3u8'},
        ])
        self.assertEqual(result['media']['quality'], '720p')

    def test_parse_dimensions_evidence_does_not_depend_on_display_name(self):
        result, _ = self.play_fixture([{'quality': 'origin'}], variants=[
            {'name': 'A', 'resolution': '1280x720', 'url': 'https://media.example.com/low.m3u8'},
            {'name': 'B', 'resolution': '3840x2160', 'url': 'https://media.example.com/high.m3u8'},
        ])
        self.assertEqual(result['media']['url'], 'https://media.example.com/high.m3u8')


if __name__ == '__main__':
    unittest.main()
