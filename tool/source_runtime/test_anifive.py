import gzip
import http.client
import io
import json
import socket
import ssl
import tempfile
import threading
import unittest
from contextlib import contextmanager
from unittest.mock import patch
from urllib.parse import urlencode

from adapters import RuntimeContext, RuntimeFailure
from android_bridge import AndroidRuntime
from anifive_adapter import AniFiveAdapter, registered_anifive
from anifive_transport import BoundedTransport, Response, public_addresses
from dispatch import operation
from server import RuntimeServer


class FakeSdk:
    def __init__(self, hits=None, roads=None, result=None):
        self.hits, self.roads = hits or [], roads or []
        self.result = result or {'direct_url': 'https://media.example/opaque', 'headers': {}}
        self.calls = []

    def search(self, *arguments):
        self.calls.append(('search', arguments))
        return self.hits

    def detail(self, *arguments):
        self.calls.append(('detail', arguments))
        return {'title': '测试动漫', 'roads': self.roads}

    def play(self, *arguments):
        self.calls.append(('play', arguments))
        return self.result


class FakeNetwork:
    def __init__(self, sample=b'#EXTM3U\n#EXT-X-ENDLIST\n'):
        self.sample, self.calls = sample, []

    def request(self, method, url, **options):
        self.calls.append((method, url, options))
        return Response(206, self.sample, {}, url)


def adapter(source='a', **sdk_options):
    sdk, network = FakeSdk(**sdk_options), FakeNetwork()
    value = AniFiveAdapter(source, sdk=sdk, transport_factory=lambda *_: network)
    return value, sdk, network


class AniFiveContractTests(unittest.TestCase):
    def context(self):
        return RuntimeContext(2000)

    def assert_failure(self, code, call):
        with self.assertRaises(RuntimeFailure) as caught:
            call()
        self.assertEqual(caught.exception.code, code)

    def test_registration_is_four_anime_sources_without_initializing_sdk(self):
        values = registered_anifive()
        self.assertEqual(set(values), {'anifive-a', 'anifive-b', 'anifive-c', 'anifive-d'})
        for item in values.values():
            self.assertEqual(item.manifest()['domains'], ['anime'])
            self.assertEqual(item.manifest()['capabilities'], ['search', 'episodes', 'resolve'])
            self.assertIsNone(item.sdk)

    def test_c_only_publishes_actual_road_two_and_preserves_episode_reference(self):
        value, sdk, _ = adapter('c', roads=[
            [('Anime9', 1, 9, '第一线路')],
            [('Anime9', 2, 174, '第174集'), ('Anime9', 2, 175, '特别篇')],
            [('Anime9', 3, 1, '第三线路')],
        ])
        roads = value.episodes('https://www.akianime.cc/bgmdetail/Anime9.html', self.context())['data']['roads']
        self.assertEqual([road['name'] for road in roads], ['线路 2'])
        self.assertEqual([episode['name'] for episode in roads[0]['episodes']], ['第174集', '特别篇'])
        self.assertEqual(roads[0]['episodes'][0]['url'], 'https://www.akianime.cc/bgmplay/Anime9-2-174.html')
        value.resolve(roads[0]['episodes'][0]['url'], self.context())
        self.assertEqual(sdk.calls[-1], ('play', ('C', 'Anime9', 2, 174)))
        self.assert_failure('INVALID_ARGUMENT', lambda: value.resolve('/bgmplay/Anime9-1-174.html', self.context()))

    def test_a_descending_and_special_episodes_keep_paths_labels_and_road_numbers(self):
        value, sdk, _ = adapter(roads=[[
            ('42', 4, 175, '第175集'), ('42', 4, 174, '第174集'), ('42', 4, 999, 'SP：前夜'),
        ]])
        roads = value.episodes('/v/42.html', self.context())['data']['roads']
        self.assertEqual(roads[0]['name'], '线路 4')
        self.assertEqual(roads[0]['episodes'], [
            {'name': '第175集', 'url': 'https://dmbus.cc/p/42-4-175.html'},
            {'name': '第174集', 'url': 'https://dmbus.cc/p/42-4-174.html'},
            {'name': 'SP：前夜', 'url': 'https://dmbus.cc/p/42-4-999.html'},
        ])
        value.resolve(roads[0]['episodes'][2]['url'], self.context())
        self.assertEqual(sdk.calls[-1], ('play', ('A', '42', 4, 999)))

    def test_b_preserves_opaque_episode_path_instead_of_assigning_an_episode_number(self):
        value, sdk, _ = adapter('b', roads=[[
            ('/play/abc-special.html', 'OVA 后日谈', None), ('/play/abc-001.html', '第01集', 1),
        ]])
        episodes = value.episodes('/detail/abc.html', self.context())['data']['roads'][0]['episodes']
        self.assertEqual(episodes[0], {'name': 'OVA 后日谈', 'url': 'https://www.dcc3.com/play/abc-special.html'})
        value.resolve(episodes[0]['url'], self.context())
        self.assertEqual(sdk.calls[-1], ('play', ('B', '/play/abc-special.html')))

    def test_search_locally_pages_one_cached_batch_and_does_not_repeat_details(self):
        value, sdk, _ = adapter(hits=[('41', '作品甲'), ('42', '作品乙')], roads=[[('42', 1, 1, '第1集')]])
        first = value.search('作品', 1, 1, self.context())
        second = value.search('作品', 2, 1, self.context())
        self.assertTrue(first['hasMore'])
        self.assertFalse(second['hasMore'])
        self.assertEqual(second['data'][0]['url'], 'https://dmbus.cc/v/42.html')
        initial = value.episodes('/v/42.html', self.context())
        initial['data']['roads'][0]['episodes'][0]['name'] = 'caller mutation'
        repeated = value.episodes('https://dmbus.cc/v/42.html', self.context())
        self.assertEqual(repeated['data']['roads'][0]['episodes'][0]['name'], '第1集')
        self.assertEqual([name for name, _ in sdk.calls], ['search', 'detail'])

    def test_external_targets_user_information_and_unsupported_ports_are_rejected(self):
        value, sdk, _ = adapter('b')
        for target in ['https://evil.example/play/1.html', '//evil.example/play/1.html',
                       'https://user:password@www.dcc3.com/play/1.html',
                       'http://www.dcc3.com/play/1.html', 'https://www.dcc3.com:444/play/1.html',
                       '/play/1.html?redirect=other', '/play/1.html#fragment']:
            with self.subTest(target=target):
                self.assert_failure('INVALID_ARGUMENT', lambda: value.resolve(target, self.context()))
        self.assertEqual(sdk.calls, [])

    def test_html_is_not_accepted_as_playable_media(self):
        value, _, network = adapter()
        for sample in [b'<!doctype html><title>Access denied</title>', b'<html>ftyp is unsupported</html>']:
            with self.subTest(sample=sample):
                network.sample = sample
                self.assert_failure('NOT_MEDIA', lambda: value.resolve('/p/42-1-1.html', self.context()))

    def test_resolve_replaces_inherited_headers_and_never_returns_private_fields(self):
        value, _, network = adapter(result={
            'direct_url': 'https://media.example/opaque',
            'headers': {'User-Agent': 'Fixture/1', 'Referer': 'https://player.example/',
                        'Cookie': 'private', 'Authorization': 'private'},
            'raw': {'token': 'private'}, 'screen_url': 'https://player.example/private',
            'expires_at': '2000-01-01T00:00:00Z',
        })
        result = value.resolve('/p/42-1-1.html', self.context())['data']
        self.assertEqual(result, {'url': 'https://media.example/opaque', 'format': 'hls',
                                 'headerPolicy': 'replace',
                                 'headers': {'User-Agent': 'Fixture/1', 'Referer': 'https://player.example/'}})
        self.assertTrue(network.calls[0][2]['probe'])
        self.assertEqual(network.calls[0][2]['headers']['Range'], 'bytes=0-4095')

    def test_bare_media_headers_do_not_inherit_referer_or_origin(self):
        value, _, _ = adapter(result={'direct_url': 'https://video.photo.qq.com/opaque',
                                     'headers': {'Referer': 'https://player.example', 'Origin': 'https://player.example'}})
        result = value.resolve('/p/42-1-1.html', self.context())['data']
        self.assertEqual(result['headers'], {})
        self.assertEqual(result['headerPolicy'], 'replace')

    def test_cancelled_waiter_exits_without_releasing_or_occupying_the_active_lock(self):
        value, sdk, _ = adapter()
        context = self.context()
        value._lock.acquire()
        errors, entered = [], threading.Event()
        def waiting():
            entered.set()
            try:
                value.search('测试', 1, 20, context)
            except RuntimeFailure as error:
                errors.append(error.code)
        thread = threading.Thread(target=waiting)
        thread.start()
        try:
            self.assertTrue(entered.wait(1))
            context.cancelled.set()
            thread.join(1)
            self.assertFalse(thread.is_alive())
            self.assertEqual(errors, ['CANCELLED'])
            self.assertTrue(value._lock.locked())
            self.assertEqual(sdk.calls, [])
        finally:
            value._lock.release()
            thread.join(1)
        self.assertEqual(value.search('测试', 1, 20, self.context())['data'], [])


class DispatchParityTests(unittest.TestCase):
    def setUp(self):
        self.adapter, self.sdk, self.network = adapter(hits=[('42', '测试作品')], roads=[[('42', 1, 9, '第9集')]])
        self.directory = tempfile.TemporaryDirectory()
        self.android = AndroidRuntime(self.directory.name)
        self.android.registry = {self.adapter.adapter_id: self.adapter}
        self.server = RuntimeServer(0, self.android.registry)
        self.thread = threading.Thread(target=lambda: self.server.serve_forever(poll_interval=.02), daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(1)
        self.directory.cleanup()

    def both(self, action, query=None, body=None, method=None):
        method = method or ('POST' if action == 'resolve' else 'GET')
        path = 'adapters/anifive-a/' + action
        query = query or {}
        request = {'path': path, 'method': method, 'query': query, 'body': body}
        android = json.loads(self.android.request(json.dumps(request), 'fixture', 2000))
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=2)
        try:
            connection.request(method, '/v1/' + path + ('?' + urlencode(query) if query else ''),
                               body=None if body is None else json.dumps(body),
                               headers={'X-Kazumi-Request': '1', 'Content-Type': 'application/json'})
            response = connection.getresponse()
            http_result = json.loads(response.read())
        finally:
            connection.close()
        self.assertEqual(android, http_result)
        return android

    def test_search_episodes_and_resolve_have_the_same_android_and_http_envelope(self):
        self.assertEqual(self.both('search', {'q': '作品', 'page': '1', 'pageSize': '20'})['total'], 1)
        self.assertEqual(self.both('episodes', {'source': '/v/42.html'})['data']['roads'][0]['episodes'][0]['name'], '第9集')
        self.assertEqual(self.both('resolve', body={'episodeUrl': '/p/42-1-9.html'})['data']['headerPolicy'], 'replace')

    def test_errors_are_identical_for_unknown_fields_bad_pagination_and_wrong_method(self):
        cases = [('search', {'q': '作品', 'script': 'evil.py'}, None, 'GET', 'INVALID_ARGUMENT'),
                 ('search', {'q': '作品', 'pageSize': '0'}, None, 'GET', 'INVALID_ARGUMENT'),
                 ('resolve', {}, {'episodeUrl': '/p/42-1-9.html', 'headers': {}}, 'POST', 'INVALID_ARGUMENT'),
                 ('resolve', {}, None, 'GET', 'UNSUPPORTED')]
        for action, query, body, method, code in cases:
            with self.subTest(action=action, query=query, body=body):
                self.assertEqual(self.both(action, query, body, method)['error']['code'], code)

    def test_malformed_port_is_a_public_argument_error_on_both_platforms(self):
        result = self.both('episodes', {'source': 'https://dmbus.cc:invalid/v/42.html'})
        self.assertEqual(result['error']['code'], 'INVALID_ARGUMENT')

    def test_dispatch_does_not_run_sdk_for_rejected_fields(self):
        with self.assertRaises(RuntimeFailure) as caught:
            operation(self.android.registry, 'adapters/anifive-a/search', 'GET',
                      {'q': '作品', 'module': 'os'}, None, RuntimeContext(2000))
        self.assertEqual(caught.exception.code, 'INVALID_ARGUMENT')
        self.assertEqual(self.sdk.calls, [])


class MemorySocket:
    def __init__(self, wire):
        self.wire, self.sent, self.connected, self.closed = wire, bytearray(), None, False

    def settimeout(self, _timeout):
        pass

    def connect(self, address):
        self.connected = address

    def sendall(self, content):
        self.sent.extend(content)

    def makefile(self, *_args):
        return io.BytesIO(self.wire)

    def close(self):
        self.closed = True


class BoundedTransportTests(unittest.TestCase):
    def wire(self, content, declared=None, encoding=None):
        headers = f'HTTP/1.1 200 OK\r\nContent-Length: {len(content) if declared is None else declared}\r\n'
        if encoding:
            headers += f'Content-Encoding: {encoding}\r\n'
        return headers.encode() + b'\r\n' + content

    @contextmanager
    def connection(self, wire, *, tls_error=None):
        sock = MemorySocket(wire)
        tls_context = ssl.create_default_context()
        address = (socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, '', ('93.184.216.34', 443))
        with patch('anifive_transport.socket.getaddrinfo', return_value=[address]), \
                patch('anifive_transport.socket.socket', return_value=sock), \
                patch('anifive_transport.ssl.create_default_context', return_value=tls_context), \
                patch.object(tls_context, 'wrap_socket', return_value=sock, side_effect=tls_error) as wrap:
            yield sock, tls_context, wrap

    def transport(self, limit=128):
        return BoundedTransport(RuntimeContext(2000), {'fixture.example'}, limit=limit)

    def assert_failure(self, code, call):
        with self.assertRaises(RuntimeFailure) as caught:
            call()
        self.assertEqual(caught.exception.code, code)

    def test_host_and_tls_identity_are_preserved_while_connecting_to_checked_ip(self):
        with self.connection(self.wire(b'ok')) as (sock, tls_context, wrap):
            result = self.transport().request('GET', 'https://fixture.example:443/path?q=1')
        self.assertEqual(result.body, b'ok')
        self.assertEqual(sock.connected, ('93.184.216.34', 443))
        self.assertIn(b'GET /path?q=1 HTTP/1.1\r\n', sock.sent)
        self.assertIn(b'Host: fixture.example:443\r\n', sock.sent)
        self.assertNotIn(b'Host: 93.184.216.34', sock.sent)
        self.assertTrue(tls_context.check_hostname)
        self.assertEqual(tls_context.verify_mode, ssl.CERT_REQUIRED)
        self.assertEqual(wrap.call_args.kwargs['server_hostname'], 'fixture.example')
        self.assertTrue(sock.closed)

    def test_invalid_certificate_fails_without_an_unverified_retry(self):
        with self.connection(self.wire(b'ok'), tls_error=ssl.SSLCertVerificationError('fixture certificate rejected')) as (sock, _, wrap):
            self.assert_failure('UPSTREAM_UNAVAILABLE', lambda: self.transport().request('GET', 'https://fixture.example/path'))
        self.assertEqual(wrap.call_count, 1)
        self.assertTrue(sock.closed)
        self.assertEqual(sock.sent, b'')

    def test_oversized_body_is_rejected_and_socket_closed(self):
        with self.connection(self.wire(b'x' * 129)) as (sock, _, _):
            self.assert_failure('RESPONSE_TOO_LARGE', lambda: self.transport().request('GET', 'https://fixture.example/path'))
        self.assertTrue(sock.closed)

    def test_gzip_expansion_cannot_bypass_the_response_limit(self):
        with self.connection(self.wire(gzip.compress(b'x' * 300), encoding='gzip')):
            self.assert_failure('RESPONSE_TOO_LARGE', lambda: self.transport().request('GET', 'https://fixture.example/path'))

    def test_truncated_content_length_is_not_returned_as_success(self):
        with self.connection(self.wire(b'partial', declared=30)):
            self.assert_failure('UPSTREAM_TRUNCATED', lambda: self.transport().request('GET', 'https://fixture.example/path'))

    def test_probe_reads_only_four_kibibytes_when_server_ignores_range(self):
        with self.connection(self.wire(b'x' * 10000)) as (sock, _, _):
            result = self.transport().request('GET', 'https://media.example/video', probe=True)
        self.assertEqual(len(result.body), 4096)
        self.assertTrue(sock.closed)

    def test_private_dns_answers_and_unlisted_metadata_hosts_never_connect(self):
        addresses = [(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, '', ('127.0.0.1', 443))]
        with patch('anifive_transport.socket.getaddrinfo', return_value=addresses), \
                patch('anifive_transport.socket.socket') as connect:
            self.assert_failure('INVALID_ARGUMENT', lambda: public_addresses('https://fixture.example/path'))
            self.assert_failure('UPSTREAM_HOST_REJECTED', lambda: self.transport().request('GET', 'https://evil.example/path'))
        connect.assert_not_called()


if __name__ == '__main__':
    unittest.main()
