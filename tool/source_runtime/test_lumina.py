"""Lumina 固定业务契约、身份与媒体边界的离线回归。"""
import json
import io
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
import platform
import sys
from types import SimpleNamespace

from adapters import RuntimeContext, RuntimeFailure
from dispatch import operation
from lumina_adapter import LuminaAdapter, LuminaSdk, validate_payload
import lumina_adapter


def envelope(data, code=20000):
    return {'http': 200, 'json': {'code': code, 'data': data},
            'raw': b'private', 'plain': b'private'}


class FakeClient:
    instances = []
    response = envelope({})
    calls = []

    def __init__(self, **kwargs):
        self.timeout = kwargs.get('timeout')
        self.instances.append(self)

    def config(self):
        return self.response

    def channel_top(self):
        return self.response

    def banners(self, channel_id):
        self.calls.append(('banners', channel_id))
        return self.response

    def video_list(self, channel, **kwargs):
        self.calls.append(('catalog', channel, kwargs))
        return self.response

    def get(self, path, params=None):
        self.calls.append(('get', path, params))
        return self.response

    def video_detail(self, video_id):
        return self.response

    def play(self, video_id, **kwargs):
        self.calls.append(('play', video_id, kwargs))
        return self.response


class FakePlay:
    @staticmethod
    def lua_params(_text):
        return {'parser': 'https://resolver.example/parse?url=', 'salt': 'private',
                'aes_key': 'private', 'aes_iv': 'private'}

    @staticmethod
    def sign_resolver(*args):
        return 'private-sign1', 'private-sign2'

    @staticmethod
    def parse_resolver(*args):
        return {'url': 'https://media.example/stream.mp4', 'private': 'hidden'}

    @staticmethod
    def play_direct_links(*args):
        return [{'url': 'https://media.example/stream.mp4', 'format': 'mp4',
                 'headers': {'User-Agent': '', 'Referer': 'https://media.example/stream.mp4'},
                 'name': '高清', 'aes_key': 'private'}]


class RecordingSocket:
    """保留真实 http.client 序列化，仅替换网络端口。"""
    def __init__(self):
        self.sent = bytearray()

    def connect(self, _address):
        pass

    def settimeout(self, _timeout):
        pass

    def sendall(self, value):
        self.sent.extend(value)

    def makefile(self, _mode):
        return io.BytesIO(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}')

    def close(self):
        pass


class LuminaTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        FakeClient.instances, FakeClient.calls = [], []
        FakeClient.response = envelope({})
        self.transport_calls = []
        self.sdk = LuminaSdk(Path(self.directory.name) / 'device.json',
                             host='api.example', client_factory=FakeClient,
                             play_module=FakePlay, engine_available=lambda: True,
                             transport=self.transport)
        self.adapter = LuminaAdapter(self.sdk)

    def transport(self, method, url, headers, body, context):
        context.check_active()
        self.transport_calls.append((method, url, headers))
        return 200, b'{}'

    def call(self, name, payload=None, context=None):
        return self.sdk.call(name, payload or {}, context or RuntimeContext(1000))['data']

    def test_constructor_and_manifest_do_not_initialize_or_make_network_requests(self):
        self.assertEqual(FakeClient.instances, [])
        self.assertFalse(self.sdk.identity_path.exists())
        self.assertEqual(self.adapter.manifest()['id'], 'lumina')
        self.assertEqual(FakeClient.instances, [])

    def test_banner_uses_source_video_name_without_sdk_placeholder(self):
        FakeClient.response = envelope([{'id': 7, 'vid': 113045,
            'vname': 'JOJO的奇妙冒险 第七部',
            'img': 'https://images.example/banner.jpg', 'internal': 'private'}])
        result = self.call('banners', {'channelId': '1'})['banners'][0]
        self.assertEqual(result['videoId'], '113045')
        self.assertEqual(result['title'], 'JOJO的奇妙冒险 第七部')
        self.assertEqual(result['cover'], 'https://images.example/banner.jpg')
        self.assertNotIn('private', json.dumps(result))

    def test_detail_retains_source_episode_identity_and_only_public_fields(self):
        FakeClient.response = envelope({'id': 9007199254740993, 'name': '作品',
            'pic': 'https://images.example/cover.jpg', 'content': '<p>简介</p>',
            'deviceSecret': 'private', 'parts': [{'play': 'mp4_2', 'play_zh': '线路二',
                'oid': 7, 'part': ['第02集', 'OVA 上篇'], 'parse': 'private'}]})
        result = self.call('detail', {'videoId': '9007199254740993'})
        self.assertEqual(result['video']['id'], '9007199254740993')
        self.assertEqual(result['parts'][0]['play'], 'mp4_2')
        self.assertEqual([e['part'] for e in result['parts'][0]['episodes']], ['第02集', 'OVA 上篇'])
        self.assertEqual(result['video']['summary'], '简介')
        self.assertNotIn('private', json.dumps(result))

    def test_catalog_counts_real_items_without_fabricating_episodes(self):
        FakeClient.response = envelope({'total': 1, 'items': [{'id': 4, 'name': '作品', 'total': 12, 'continu': 2}]})
        result = self.call('catalog', {'channelId': '1', 'pageIndex': 2, 'pageSize': 24})
        self.assertEqual(result['videos'][0]['updatedTo'], 2)
        self.assertEqual(result['videos'][0]['totalEpisodes'], 12)
        self.assertNotIn('episodes', result['videos'][0])
        self.assertEqual(result['pageInfo'], {'pageIndex': 2, 'pageSize': 24, 'total': 1})

    def test_search_uses_original_key_and_includes_page(self):
        FakeClient.response = envelope({'total': 0, 'items': []})
        self.call('search', {'keyword': ' 动漫 ', 'pageIndex': 3, 'pageSize': 12})
        self.assertEqual(FakeClient.calls[-1], ('get', '/app/video/search', {'key': '动漫', 'limit': 12, 'page': 3}))

    def test_config_does_not_publish_internal_configuration(self):
        FakeClient.response = envelope({'key': 'private', 'hosts': ['private']})
        self.assertEqual(self.call('config'), {'available': True})

    def test_channels_are_public_and_bounded(self):
        FakeClient.response = envelope([{'id': 1, 'name': '动漫', 'types': ['weight'], 'key': 'private'}])
        self.assertEqual(self.call('channels'), {'channels': [{'id': '1', 'name': '动漫', 'types': ['weight']}]})

    def test_play_resolves_without_autoplay_and_keeps_explicit_empty_user_agent(self):
        FakeClient.response = envelope([{'url': 'opaque-source', 'parse': 'private'}])
        result = self.call('play', {'videoId': '4', 'playFormat': 'mp4_2', 'part': 'OVA 上篇'})
        self.assertEqual(result['status'], 'ready')
        self.assertEqual(result['media']['headers']['User-Agent'], '')
        self.assertEqual(FakeClient.calls[-1], ('play', '4', {'play_fmt': 'mp4_2', 'part': 'OVA 上篇', 'resolve': False}))
        self.assertEqual(len(self.transport_calls), 1)
        self.assertNotIn('expiresAt', result['media'])
        self.assertNotIn('private', json.dumps(result))

    def test_empty_resolver_is_a_stable_failure_without_source_or_keys(self):
        FakeClient.response = envelope([{'url': 'opaque-source', 'parse': 'private'}])
        with patch.object(FakePlay, 'play_direct_links', return_value=[]):
            result = self.call('play', {'videoId': '4', 'playFormat': 'mp4', 'part': '第1集'})
        self.assertEqual(result, {'status': 'unavailable', 'error': 'NO_DIRECT_LINK'})

    def test_private_media_targets_are_rejected(self):
        FakeClient.response = envelope([{'url': 'opaque-source'}])
        for url in ('http://127.0.0.1/secret', 'http://10.0.0.1/video', 'file:///tmp/video', 'https://user:password@media.example/video'):
            with self.subTest(url=url), patch.object(FakePlay, 'play_direct_links', return_value=[{'url': url, 'headers': {}}]):
                with self.assertRaisesRegex(RuntimeFailure, '^INVALID_MEDIA$'):
                    self.call('play', {'videoId': '4', 'playFormat': 'mp4', 'part': '第1集'})

    def test_header_injection_and_credentials_are_rejected(self):
        FakeClient.response = envelope([{'url': 'opaque-source'}])
        for headers in ({'User-Agent': 'x\r\nCookie: private'}, {'Authorization': 'private'}):
            with self.subTest(headers=headers), patch.object(FakePlay, 'play_direct_links', return_value=[{'url': 'https://media.example/a', 'headers': headers}]):
                with self.assertRaisesRegex(RuntimeFailure, '^INVALID_MEDIA$'):
                    self.call('play', {'videoId': '4', 'playFormat': 'mp4', 'part': '第1集'})

    def test_cancellation_before_call_creates_no_identity_or_client(self):
        context = RuntimeContext(1000)
        context.cancelled.set()
        with self.assertRaisesRegex(RuntimeFailure, '^CANCELLED$'):
            self.call('config', context=context)
        self.assertEqual(FakeClient.instances, [])
        self.assertFalse(self.sdk.identity_path.exists())

    def test_engine_unavailable_is_explicit_and_does_not_import_optional_emu(self):
        self.sdk.engine_available = lambda: False
        with self.assertRaisesRegex(RuntimeFailure, '^ENGINE_UNAVAILABLE$'):
            self.call('config')
        self.assertEqual(FakeClient.instances, [])

    def test_identity_is_persistent_and_clients_are_per_thread(self):
        self.call('config')
        fingerprint = json.loads(self.sdk.identity_path.read_text(encoding='utf-8'))['deviceFingerprint']
        self.assertRegex(fingerprint, r'^[a-f0-9]{32}$')
        self.call('config')
        self.assertEqual(len(FakeClient.instances), 1)
        errors = []
        def run():
            try:
                self.call('config')
            except Exception as error:
                errors.append(error)
        worker = threading.Thread(target=run)
        worker.start()
        worker.join(2)
        self.assertEqual(errors, [])
        self.assertEqual(len(FakeClient.instances), 2)
        self.assertEqual(json.loads(self.sdk.identity_path.read_text(encoding='utf-8'))['deviceFingerprint'], fingerprint)

    def test_corrupt_identity_is_not_silently_rotated(self):
        self.sdk.identity_path.write_text('{invalid', encoding='utf-8')
        with self.assertRaisesRegex(RuntimeFailure, '^IDENTITY_ERROR$'):
            self.call('config')
        self.assertEqual(self.sdk.identity_path.read_text(encoding='utf-8'), '{invalid')

    def test_business_and_envelope_failures_are_stable_and_private(self):
        for response, code in ((envelope(None, 50008), 'BUSINESS_REJECTED'),
                               ({'http': 200, 'error': 'private', 'json': None}, 'DECRYPT_ERROR'),
                               ({'http': 503, 'json': None}, 'UPSTREAM_HTTP_ERROR')):
            FakeClient.response = response
            with self.subTest(code=code), self.assertRaisesRegex(RuntimeFailure, '^' + code + '$'):
                self.call('config')

    def test_extra_fields_arbitrary_hosts_and_incomplete_episode_identity_are_rejected(self):
        for op, payload in (('search', {'keyword': 'x', 'host': 'private'}),
                            ('play', {'videoId': '4', 'playFormat': 'mp4'}),
                            ('detail', {'videoId': '4&host=private'}),
                            ('catalog', {'channelId': '1', 'pageIndex': 0}),
                            ('search', {'keyword': 'x', 'pageSize': True})):
            with self.subTest(op=op, payload=payload), self.assertRaisesRegex(RuntimeFailure, '^INVALID_ARGUMENT$'):
                validate_payload(op, payload)

    def test_fixed_route_accepts_only_registered_sdk_operation(self):
        FakeClient.response = envelope({'total': 0, 'items': []})
        task = operation({'lumina': self.adapter}, 'adapters/lumina/sdk', 'POST', {},
                         {'operation': 'search', 'payload': {'keyword': '动漫'}}, RuntimeContext(1000))
        self.assertEqual(task()['data']['videos'], [])
        with self.assertRaisesRegex(RuntimeFailure, '^UNSUPPORTED$'):
            operation({'lumina': self.adapter}, 'adapters/lumina/sdk', 'POST', {},
                      {'operation': 'login', 'payload': {}}, RuntimeContext(1000))

    def test_android_arm32_does_not_register_lumina(self):
        from android_bridge import AndroidRuntime
        with patch.dict('os.environ', {'ANDROID_ROOT': '/system'}), patch.object(platform, 'machine', return_value='armv7l'):
            runtime = AndroidRuntime(self.directory.name)
        self.assertNotIn('lumina', runtime.registry)
        self.assertIn('miomedia', runtime.registry)

    def test_android_32_bit_process_on_arm64_kernel_does_not_register_lumina(self):
        from android_bridge import AndroidRuntime
        with patch.dict('os.environ', {'ANDROID_ROOT': '/system'}), \
                patch.object(platform, 'machine', return_value='aarch64'), \
                patch.object(sys, 'maxsize', 2 ** 31 - 1):
            runtime = AndroidRuntime(self.directory.name)
        self.assertNotIn('lumina', runtime.registry)

    def test_android_arm64_native_engine_path_stays_in_application_library_directory(self):
        from android_bridge import AndroidRuntime
        with patch.dict('os.environ', {'ANDROID_ROOT': '/system'}), patch.object(platform, 'machine', return_value='aarch64'):
            runtime = AndroidRuntime(self.directory.name, native_library_directory=self.directory.name)
        self.assertEqual(runtime.registry['lumina'].sdk.engine_directory, Path(self.directory.name))
        self.assertFalse(runtime.registry['lumina'].sdk.identity_path.exists())

    def test_native_loader_uses_read_only_library_and_private_persistent_identity(self):
        sdk = LuminaSdk(Path(self.directory.name) / 'native' / 'device.json',
                        engine_directory=Path(self.directory.name) / 'readonly-lib')
        profile = SimpleNamespace()
        modules = {
            'vendor.lumina.config': SimpleNamespace(API_HOST='api.example', API_PORT=27990),
            'vendor.lumina.profile': profile,
            'vendor.lumina.client': SimpleNamespace(Client=FakeClient),
            'vendor.lumina.play': FakePlay,
            'vendor.lumina._fuse': SimpleNamespace(available=lambda: True),
        }
        with patch.dict('os.environ', {}, clear=True), \
                patch.object(lumina_adapter, '_PROFILE_BINDING', None), \
                patch('lumina_adapter.importlib.import_module', side_effect=modules.__getitem__):
            sdk._initialize(RuntimeContext(1000))
            self.assertEqual(Path(lumina_adapter.os.environ['LUMINA_SOLOADER_PATH']),
                             sdk.engine_directory / 'libcore.so')
            self.assertEqual(Path(lumina_adapter.os.environ['LUMINA_SOLOADER_FILES']),
                             sdk.cache_directory / 'soloader')
            fingerprint = json.loads(sdk.identity_path.read_text(encoding='utf-8'))['deviceFingerprint']
            self.assertEqual(lumina_adapter.os.environ['LUMINA_DEVICE_ID'], fingerprint)
            self.assertEqual(profile.DEVICE_FP, fingerprint)
            self.assertNotIn('LUMINA_SOLOADER', lumina_adapter.os.environ)
            self.assertNotIn('LUMINA_DEVICE', lumina_adapter.os.environ)

    def test_dns_to_private_target_is_rejected_before_any_connection(self):
        address = (2, 1, 6, '', ('127.0.0.1', 80))
        with patch('lumina_adapter.socket.getaddrinfo', return_value=[address]), patch('lumina_adapter.socket.socket') as connect:
            with self.assertRaisesRegex(RuntimeFailure, '^UPSTREAM_HOST_REJECTED$'):
                lumina_adapter.bounded_request('GET', 'http://resolver.example/a', {}, None, RuntimeContext(1000))
        connect.assert_not_called()

    def test_actual_http_serialization_has_one_host_and_preserves_empty_user_agent(self):
        sock = RecordingSocket()
        address = (2, 1, 6, '', ('8.8.8.8', 27990))
        with patch('lumina_adapter.socket.getaddrinfo', return_value=[address]), \
                patch('lumina_adapter.socket.socket', return_value=sock):
            status, _body = lumina_adapter.bounded_request('GET', 'http://api.example:27990/app/config',
                {'host': 'old.example:27990', 'USER-AGENT': '', 'Connection': 'keep-alive',
                 'Proxy-Authorization': 'private', 'Transfer-Encoding': 'chunked'}, None, RuntimeContext(1000))
        self.assertEqual(status, 200)
        headers = sock.sent.decode('iso-8859-1').split('\r\n')[1:]
        hosts = [line for line in headers if line.lower().startswith('host:')]
        self.assertEqual(hosts, ['Host: api.example:27990'])
        self.assertEqual([line for line in headers if line.lower().startswith('user-agent:')], ['USER-AGENT: '])
        self.assertFalse(any(line.lower().startswith(('connection:', 'proxy-authorization:', 'transfer-encoding:')) for line in headers))

    def test_declared_huge_response_is_rejected_without_reading_body(self):
        address = (2, 1, 6, '', ('8.8.8.8', 80))
        with patch('lumina_adapter.socket.getaddrinfo', return_value=[address]), \
                patch('lumina_adapter.socket.socket'), \
                patch('lumina_adapter.http.client.HTTPConnection') as factory:
            response = factory.return_value.getresponse.return_value
            response.getheader.return_value = str(lumina_adapter.MAX_RESPONSE + 1)
            with self.assertRaisesRegex(RuntimeFailure, '^RESPONSE_TOO_LARGE$'):
                lumina_adapter.bounded_request('GET', 'http://resolver.example/a', {}, None, RuntimeContext(1000))
        response.read1.assert_not_called()

    def test_cancellation_during_connect_prevents_credentials_from_being_sent(self):
        context = RuntimeContext(1000)
        address = (2, 1, 6, '', ('8.8.8.8', 80))
        with patch('lumina_adapter.socket.getaddrinfo', return_value=[address]), \
                patch('lumina_adapter.socket.socket') as socket_factory, \
                patch('lumina_adapter.http.client.HTTPConnection') as connection_factory:
            socket_factory.return_value.connect.side_effect = lambda _address: context.cancelled.set()
            with self.assertRaisesRegex(RuntimeFailure, '^CANCELLED$'):
                lumina_adapter.bounded_request('GET', 'http://resolver.example/a', {}, None, context)
            connection_factory.return_value.request.assert_not_called()

    def test_cancel_after_credentials_does_not_call_external_resolver(self):
        context = RuntimeContext(1000)
        def credential(*args, **kwargs):
            context.cancelled.set()
            return envelope([{'url': 'opaque-source'}])
        with patch.object(FakeClient, 'play', side_effect=credential):
            with self.assertRaisesRegex(RuntimeFailure, '^CANCELLED$'):
                self.call('play', {'videoId': '4', 'playFormat': 'mp4', 'part': '第1集'}, context)
        self.assertEqual(self.transport_calls, [])

    def test_upstream_error_does_not_expose_resolver_response_excerpt(self):
        FakeClient.response = envelope([{'url': 'opaque-source'}])
        with patch.object(FakePlay, 'parse_resolver', side_effect=ValueError('private signed-url body')):
            with self.assertRaisesRegex(RuntimeFailure, '^PARSE_ERROR$'):
                self.call('play', {'videoId': '4', 'playFormat': 'mp4', 'part': '第1集'})


class ImportLuminaTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def package(self):
        from import_lumina import REQUIRED_FILES, ANDROID_MACHINES
        source = self.root / 'source'
        for name in REQUIRED_FILES:
            path = source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'# original\n' if path.suffix == '.py' else b'binary-asset')
            if name in ANDROID_MACHINES:
                header = bytearray(64)
                header[:6] = b'\x7fELF\x02\x01'
                header[18:20] = ANDROID_MACHINES[name].to_bytes(2, 'little')
                path.write_bytes(header)
        (source / 'config.py').write_text("import os\nAPI_HOST = os.environ.get('LUMINA_API_HOST', '<HOST>')\nAPI_PORT = int(os.environ.get('LUMINA_API_PORT', '27990'))\n", encoding='utf-8')
        return source

    def test_import_preserves_algorithm_bytes_and_manifests_no_binding_values(self):
        from import_lumina import install, verify
        source = self.package()
        target, manifest = self.root / 'vendor', self.root / 'manifest.json'
        install(source, target=target, manifest_path=manifest, host='43.145.33.254')
        self.assertEqual((target / 'client.py').read_bytes(), (source / 'client.py').read_bytes())
        self.assertIn('43.145.33.254', (target / 'config.py').read_text(encoding='utf-8'))
        self.assertNotIn('43.145.33.254', manifest.read_text(encoding='utf-8'))
        self.assertTrue(verify(target=target, manifest_path=manifest))
        self.assertIn("'<HOST>'", (source / 'config.py').read_text(encoding='utf-8'))

    def test_import_includes_original_in_process_loader_and_arm64_library(self):
        from import_lumina import install
        source = self.package()
        target, manifest = self.root / 'vendor', self.root / 'manifest.json'
        result = install(source, target=target, manifest_path=manifest)
        for name in ('_soloader/__init__.py', '_soloader/assets/libcore.so'):
            self.assertEqual((target / name).read_bytes(), (source / name).read_bytes())
        self.assertEqual(result['responseDecryption'], {'preferred': 'soloader', 'nativeAbis': ['arm64-v8a'],
                                                       'fallback': 'sdk-default'})

    def test_tampered_algorithm_or_missing_image_is_not_a_valid_sdk(self):
        from import_lumina import install, verify
        source = self.package()
        target, manifest = self.root / 'vendor', self.root / 'manifest.json'
        install(source, target=target, manifest_path=manifest)
        (target / 'play.py').write_bytes(b'# modified\n')
        with self.assertRaisesRegex(ValueError, 'SDK_INTEGRITY_ERROR'):
            verify(target=target, manifest_path=manifest)
        (target / 'play.py').write_bytes((source / 'play.py').read_bytes())
        (target / '_fuse/assets/fuse_image.bin.gz').unlink()
        with self.assertRaisesRegex(ValueError, 'SDK_INTEGRITY_ERROR'):
            verify(target=target, manifest_path=manifest)

    def test_incomplete_or_unsupported_input_fails_before_creating_target(self):
        from import_lumina import install
        source = self.package()
        (source / 'client.py').unlink()
        target = self.root / 'vendor'
        with self.assertRaisesRegex(ValueError, 'SDK_INPUT_INCOMPLETE'):
            install(source, target=target, manifest_path=self.root / 'manifest.json')
        self.assertFalse(target.exists())

    def test_verified_previous_receipt_can_upgrade_but_cannot_pass_as_current(self):
        from import_lumina import install, verify, PREVIOUS_REQUIRED_FILES
        source = self.package()
        target, manifest = self.root / 'vendor', self.root / 'manifest.json'
        receipt = install(source, target=target, manifest_path=manifest)
        receipt['integrationVersion'] = 1
        receipt['files'] = [row for row in receipt['files'] if row['file'] in PREVIOUS_REQUIRED_FILES]
        manifest.write_text(json.dumps(receipt), encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'SDK_INTEGRITY_ERROR'):
            verify(target=target, manifest_path=manifest)
        install(source, target=target, manifest_path=manifest)
        self.assertTrue(verify(target=target, manifest_path=manifest))

    def test_missing_official_library_fails_before_replacing_existing_input(self):
        from import_lumina import install, verify
        source = self.package()
        target, manifest = self.root / 'vendor', self.root / 'manifest.json'
        install(source, target=target, manifest_path=manifest)
        (source / '_soloader/assets/libcore.so').unlink()
        with self.assertRaisesRegex(ValueError, 'SDK_INPUT_INCOMPLETE'):
            install(source, target=target, manifest_path=manifest)
        self.assertTrue(verify(target=target, manifest_path=manifest))

    def test_wrong_native_library_abi_is_rejected_before_creating_target(self):
        from import_lumina import install
        source = self.package()
        wrong = bytearray(64)
        wrong[:6] = b'\x7fELF\x02\x01'
        wrong[18:20] = (62).to_bytes(2, 'little')
        (source / '_soloader/assets/libcore.so').write_bytes(wrong)
        target = self.root / 'vendor'
        with self.assertRaisesRegex(ValueError, 'SDK_NATIVE_ABI_INVALID'):
            install(source, target=target, manifest_path=self.root / 'manifest.json')
        self.assertFalse(target.exists())


if __name__ == '__main__':
    unittest.main()
