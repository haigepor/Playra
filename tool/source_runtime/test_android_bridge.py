import errno
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

from android_bridge import AndroidRuntime
from adapters import RuntimeFailure
from vendor.miomedia import Client


class FakeAdapter:
    def manifest(self):
        return {'id': 'miomedia', 'implemented': True}

    def sdk_call(self, operation, payload, context):
        context.check_active()
        return {'data': {'operation': operation, 'videoId': payload.get('videoId'),
                         'deviceSecret': 'private', 'adToken': 'private'}}


class AndroidBridgeTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.runtime = AndroidRuntime(self.directory.name, adapter=FakeAdapter())

    def request(self, body, request_id='test-1', path='adapters/miomedia/sdk', method='POST'):
        value = {'path': path, 'method': method, 'query': {}, 'body': body}
        return json.loads(self.runtime.request(json.dumps(value), request_id, 1000))

    def test_sdk_envelope_preserves_string_id_and_removes_private_fields(self):
        response = self.request({'operation': 'detail', 'payload': {'videoId': '9007199254740993'}})
        self.assertEqual(response['data']['videoId'], '9007199254740993')
        self.assertNotIn('deviceSecret', response['data'])
        self.assertNotIn('adToken', response['data'])

    def test_fixed_routes_reject_arbitrary_modules_and_unknown_operations(self):
        self.assertEqual(self.request({}, path='eval')['error']['code'], 'UNSUPPORTED')
        self.assertEqual(self.request({'operation': 'eval', 'payload': {}})['error']['code'], 'UNSUPPORTED')

    def test_utf8_size_limit_and_budget_are_enforced(self):
        value = {'path': 'health', 'method': 'GET', 'query': {}, 'body': '字' * 12000}
        self.assertEqual(json.loads(self.runtime.request(json.dumps(value, ensure_ascii=False), 'big', 1000))['error']['code'], 'PAYLOAD_TOO_LARGE')
        self.assertEqual(json.loads(self.runtime.request('{}', 'budget', 60001))['error']['code'], 'INVALID_ARGUMENT')

    def test_cancel_before_dispatch_prevents_execution(self):
        self.runtime.cancel('cancelled')
        response = self.request({'operation': 'recommend', 'payload': {}}, request_id='cancelled')
        self.assertEqual(response['error']['code'], 'CANCELLED')

    def test_running_operation_observes_cancel(self):
        entered = threading.Event()
        class Waiting(FakeAdapter):
            def sdk_call(self, operation, payload, context):
                entered.set()
                context.cancelled.wait(2)
                context.check_active()
                raise RuntimeFailure('TIMEOUT', 504)
        self.runtime = AndroidRuntime(self.directory.name, adapter=Waiting())
        responses = []
        thread = threading.Thread(target=lambda: responses.append(self.request({'operation': 'recommend', 'payload': {}})))
        thread.start(); self.assertTrue(entered.wait(1))
        self.runtime.cancel('test-1'); thread.join(2)
        self.assertFalse(thread.is_alive())
        self.assertEqual(responses[0]['error']['code'], 'CANCELLED')

    def test_internal_errors_do_not_return_stack_or_message(self):
        class Broken(FakeAdapter):
            def sdk_call(self, *args):
                raise ValueError('private-config-value')
        self.runtime = AndroidRuntime(self.directory.name, adapter=Broken())
        result = self.request({'operation': 'recommend', 'payload': {}})
        self.assertEqual(result['error']['code'], 'RUNTIME_ERROR')
        self.assertNotIn('private-config-value', json.dumps(result))

    def test_identity_uses_supplied_private_directory(self):
        runtime = AndroidRuntime(self.directory.name)
        path = runtime.adapter.sdk.identity_path
        self.assertEqual(path, Path(self.directory.name) / 'miomedia' / 'device.json')
        runtime.adapter.sdk._create_identity()
        before = path.read_bytes()
        restarted = AndroidRuntime(self.directory.name)
        restarted.adapter.sdk._create_identity()
        self.assertEqual(before, path.read_bytes())

    def test_first_content_request_succeeds_without_android_hardlinks(self):
        def handshake(client):
            return 200, {'code': 200, 'success': True, 'data': {
                'deviceId': client.device_id, 'deviceSecret': client.device_secret,
                'protocol': 'v3', 'serverTime': 1, 'keyVersion': 1}}

        self.runtime = AndroidRuntime(self.directory.name)
        with patch('miomedia_adapter.os.link', side_effect=PermissionError(errno.EPERM, 'denied')), \
                patch.object(Client, 'handshake', handshake), \
                patch.object(Client, 'request', return_value=(200, {
                    'code': 200, 'success': True, 'data': {'videos': [{'id': '123', 'title': '测试电影'}]}})):
            result = self.request({'operation': 'catalog', 'payload': {'pageIndex': 1, 'pageSize': 20}})
        self.assertNotIn('error', result)
        self.assertEqual(result['data']['videos'][0]['id'], '123')
        self.assertTrue(self.runtime.adapter.sdk.identity_path.exists())


if __name__ == '__main__':
    unittest.main()
