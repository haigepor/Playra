import concurrent.futures
import errno
import http.client
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
import urllib.error
from unittest.mock import patch

from adapters import RuntimeContext, RuntimeFailure
from miomedia_adapter import MioMediaSdk, MioMediaAdapter
from server import RuntimeServer


class FakeClient:
    handshakes = 0
    requests = 0
    mismatch = False
    failure = None
    interruptions = 0
    request_error = None
    after_request = None

    def __init__(self, device_id=None, **kwargs):
        self.device_id = device_id or 'a' * 64
        self.device_secret = 'b' * 64
        self.time_offset_ms = 0

    def save_identity(self, path):
        Path(path).write_text(json.dumps({'device_id': self.device_id, 'hwfp': None}), encoding='utf-8')

    @classmethod
    def load_identity(cls, path, **kwargs):
        return cls(device_id=json.loads(Path(path).read_text(encoding='utf-8'))['device_id'])

    def handshake(self):
        type(self).handshakes += 1
        time.sleep(0.015)
        self.time_offset_ms = 3000
        return 200, {'code': 200, 'success': True, 'data': {
            'deviceId': self.device_id, 'deviceSecret': 'x' if self.mismatch else self.device_secret,
            'serverTime': int(time.time() * 1000), 'protocol': 'v3', 'keyVersion': 1}}

    def request(self, path, payload):
        type(self).requests += 1
        if self.request_error:
            raise self.request_error
        if type(self).after_request:
            type(self).after_request()
        if self.interruptions:
            type(self).interruptions -= 1
            raise http.client.IncompleteRead(b'', 20)
        if self.failure:
            return 200, {'code': self.failure, 'success': False, 'data': {}}
        return 200, {'code': 200, 'success': True, 'data': {
            'videos': [{'id': '329257153645817856', 'title': '测试作品'}],
            'deviceSecret': 'must not leave SDK', 'clock': self.time_offset_ms}}


class MioMediaTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'device.json'
        FakeClient.handshakes = FakeClient.requests = FakeClient.interruptions = 0
        FakeClient.mismatch = False
        FakeClient.failure = None
        FakeClient.request_error = FakeClient.after_request = None
        self.sdk = MioMediaSdk(self.path, client_factory=FakeClient)

    def tearDown(self):
        self.temp.cleanup()

    def call(self, operation='recommend', payload=None, context=None):
        return self.sdk.call(operation, payload or {}, context or RuntimeContext(3000))

    def test_identity_survives_restart_and_response_is_safe(self):
        first = self.call()
        identity = self.path.read_bytes()
        second = MioMediaSdk(self.path, client_factory=FakeClient).call('recommend', {}, RuntimeContext(3000))
        self.assertEqual(self.path.read_bytes(), identity)
        self.assertEqual(first['data']['videos'], second['data']['videos'])
        self.assertNotIn('deviceSecret', first['data'])
        self.assertEqual(first['data']['clock'], 3000)

    def test_concurrent_calls_share_one_handshake(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda _: self.call(), range(4)))
        self.assertEqual(len(results), 4)
        self.assertEqual(FakeClient.handshakes, 1)

    def test_secret_mismatch_blocks_business_requests(self):
        FakeClient.mismatch = True
        with self.assertRaisesRegex(RuntimeFailure, 'SESSION_MISMATCH'):
            self.call()
        self.assertEqual(FakeClient.requests, 0)

    def test_corrupt_identity_is_not_overwritten(self):
        self.path.write_text('{invalid', encoding='utf-8')
        with self.assertRaisesRegex(RuntimeFailure, 'IDENTITY_ERROR'):
            self.call()
        self.assertEqual(self.path.read_text(encoding='utf-8'), '{invalid')

    def test_first_identity_works_when_hardlinks_are_forbidden(self):
        with patch('miomedia_adapter.os.link', side_effect=PermissionError(errno.EPERM, 'denied')):
            result = self.call()
            before = self.path.read_bytes()
            restarted = MioMediaSdk(self.path, client_factory=FakeClient)
            restarted.call('recommend', {}, RuntimeContext(3000))
        self.assertTrue(result['data']['videos'])
        self.assertEqual(self.path.read_bytes(), before)

    def test_concurrent_instances_publish_only_one_identity(self):
        class UniqueClient(FakeClient):
            guard = threading.Lock()
            generated = 0

            def __init__(self, device_id=None, **kwargs):
                if device_id is None:
                    with self.guard:
                        type(self).generated += 1
                        device_id = f'{self.generated:064x}'
                super().__init__(device_id=device_id, **kwargs)

        instances = [MioMediaSdk(self.path, client_factory=UniqueClient) for _ in range(8)]
        with patch('miomedia_adapter.os.link', side_effect=PermissionError(errno.EPERM, 'denied')):
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                list(pool.map(lambda sdk: sdk._create_identity(), instances))
        self.assertEqual(UniqueClient.generated, 1)
        self.assertEqual(json.loads(self.path.read_text(encoding='utf-8'))['device_id'], f'{1:064x}')

    def test_failed_publication_leaves_no_partial_identity_and_can_retry(self):
        with patch('miomedia_adapter.os.replace', side_effect=PermissionError(errno.EACCES, 'denied')):
            with self.assertRaisesRegex(RuntimeFailure, '^IDENTITY_ERROR$'):
                self.call()
        self.assertFalse(self.path.exists())
        self.assertFalse(list(self.path.parent.glob('.device-*')))
        self.assertTrue(self.call()['data']['videos'])

    def test_identity_lock_wait_obeys_request_budget(self):
        other = MioMediaSdk(self.path, client_factory=FakeClient)
        with self.sdk._identity_creation_lock(RuntimeContext(3000)):
            with self.assertRaisesRegex(RuntimeFailure, '^TIMEOUT$'):
                other._create_identity(RuntimeContext(50))
        self.assertFalse(self.path.exists())
        self.assertTrue(self.call()['data']['videos'])

    def test_unsupported_writes_and_invalid_payload_never_connect(self):
        for operation, payload in [('auth/login', {}), ('recommend', {'url': 'http://x'}),
                                   ('detail', {'videoId': 123}),
                                   ('qualities', {'videoId': '123', 'code': 'x', 'episodeNum': 1, 'caps': ['v2ts']})]:
            with self.assertRaises(RuntimeFailure):
                self.call(operation, payload)
        self.assertEqual(FakeClient.handshakes, 0)

    def test_business_rejection_does_not_retry(self):
        FakeClient.failure = 4031
        with self.assertRaisesRegex(RuntimeFailure, 'AD_REQUIRED'):
            self.call()
        self.assertEqual(FakeClient.requests, 1)

    def test_network_retry_is_bounded(self):
        FakeClient.interruptions = 1
        self.assertTrue(self.call()['data']['videos'])
        self.assertEqual(FakeClient.requests, 2)
        FakeClient.requests = 0
        FakeClient.interruptions = 3
        with self.assertRaisesRegex(RuntimeFailure, 'UPSTREAM_UNAVAILABLE'):
            self.call()
        self.assertEqual(FakeClient.requests, 2)

    def test_cancelled_context_does_not_initialize(self):
        context = RuntimeContext(3000)
        context.cancelled.set()
        with self.assertRaisesRegex(RuntimeFailure, 'CANCELLED'):
            self.call(context=context)
        self.assertEqual(FakeClient.handshakes, 0)

    def test_decryption_error_is_not_retried_or_exposed(self):
        FakeClient.request_error = ValueError('sensitive upstream payload')
        with self.assertRaisesRegex(RuntimeFailure, '^DECRYPT_ERROR$'):
            self.call()
        self.assertEqual(FakeClient.requests, 1)

    def test_missing_sdk_resource_is_not_reported_as_network_failure(self):
        FakeClient.request_error = FileNotFoundError(errno.ENOENT, 'private file', 'bf_tables.bin')
        with self.assertRaisesRegex(RuntimeFailure, '^SDK_RESOURCE_MISSING$'):
            self.call()
        self.assertEqual(FakeClient.requests, 1)

    def test_network_errors_have_safe_specific_codes(self):
        cases = [
            (PermissionError(errno.EACCES, 'private permission detail'), 'UPSTREAM_PERMISSION_DENIED'),
            (OSError(errno.ENETUNREACH, 'private network detail'), 'UPSTREAM_NETWORK_UNREACHABLE'),
            (ConnectionRefusedError(errno.ECONNREFUSED, 'private socket detail'), 'UPSTREAM_CONNECTION_REFUSED'),
            (ConnectionResetError(errno.ECONNRESET, 'private reset detail'), 'UPSTREAM_CONNECTION_RESET'),
        ]
        for reason, expected in cases:
            with self.subTest(expected=expected):
                FakeClient.request_error = urllib.error.URLError(reason)
                with self.assertRaisesRegex(RuntimeFailure, f'^{expected}$'):
                    self.call()

    def test_cancellation_during_sdk_request_drops_result(self):
        context = RuntimeContext(3000)
        FakeClient.after_request = context.cancelled.set
        with self.assertRaisesRegex(RuntimeFailure, 'CANCELLED'):
            self.call(context=context)

    def test_expired_session_renegotiates_same_identity(self):
        self.sdk.session_ttl = 0
        self.call()
        identity = self.path.read_bytes()
        self.call()
        self.assertEqual(FakeClient.handshakes, 2)
        self.assertEqual(self.path.read_bytes(), identity)

    def test_sdk_http_contract_and_lazy_health(self):
        server = RuntimeServer(0, {'miomedia': MioMediaAdapter(self.sdk)})
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        def request(method, path, body=None):
            connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=3)
            try:
                connection.request(method, path, body=json.dumps(body) if body else None,
                                   headers={'X-Kazumi-Request': '1', 'Content-Type': 'application/json'})
                response = connection.getresponse()
                return response.status, json.loads(response.read())
            finally:
                connection.close()
        try:
            self.assertEqual(request('GET', '/v1/health')[0], 200)
            status, manifest = request('GET', '/v1/adapters')
            self.assertEqual(status, 200)
            self.assertEqual(manifest['data'][0]['playbackHealth'],
                             {'strategy': 'token', 'rotations': 0, 'attempts': 0, 'adRequired': 0})
            self.assertFalse(self.path.exists())
            status, result = request('POST', '/v1/adapters/miomedia/sdk', {'operation': 'recommend', 'payload': {}})
            self.assertEqual(status, 200)
            self.assertEqual(result['meta']['providerId'], 'miomedia')
            self.assertEqual(request('POST', '/v1/adapters/miomedia/sdk', {'operation': 'auth/login', 'payload': {}})[0], 422)
            self.assertEqual(request('GET', '/v1/adapters/miomedia/sdk')[0], 405)
            self.assertEqual(request('POST', '/v1/adapters/miomedia/sdk?url=x', {'operation': 'recommend', 'payload': {}})[0], 400)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == '__main__':
    unittest.main()
