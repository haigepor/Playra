"""实际 SDK 加密报文通过本机 HTTP 的回归检查。"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest

from adapters import RuntimeContext
from miomedia_adapter import MioMediaSdk
from vendor.miomedia import config, derive_device_secret, sign_request, V3Session


class SdkHttpTests(unittest.TestCase):
    def test_real_sdk_headers_encryption_session_and_restart(self):
        observed = []
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def do_POST(self):
                try:
                    device_id = self.headers['X-Device-Id']
                    expected = sign_request(int(self.headers['X-Timestamp']), self.headers['X-Nonce'],
                                            config.APP_ID, config.FALLBACK_SESSION_CONFIG['signSecret'])[0]
                    assert self.headers['X-Signature'] == expected
                    secret = derive_device_secret(config.FALLBACK_SESSION_CONFIG['masterSecret'], device_id)
                    negotiate = self.path.endswith('/auth/negotiate')
                    material = config.FALLBACK_SESSION_CONFIG['masterSecret'] if negotiate else secret
                    wire = self.rfile.read(int(self.headers['Content-Length']))
                    payload = json.loads(V3Session(material).unseal(wire))
                    observed.append((self.path, device_id, payload))
                    data = {'deviceId': device_id, 'deviceSecret': secret, 'protocol': 'v3',
                            'serverTime': int(time.time() * 1000), 'keyVersion': 1} if negotiate else \
                        {'videos': [{'id': '329257153645817856', 'title': '本机加密接口测试'}]}
                    response = V3Session(secret).seal(json.dumps({'code': 200, 'success': True, 'data': data}).encode())
                    self.send_response(200)
                    self.send_header('Content-Length', str(len(response)))
                    self.end_headers()
                    self.wfile.write(response)
                except Exception:
                    self.send_error(400)
        upstream = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=upstream.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as directory:
                identity = Path(directory) / 'device.json'
                endpoint = f'http://127.0.0.1:{upstream.server_port}'
                first = MioMediaSdk(identity, base_url=endpoint)
                result = first.call('recommend', {}, RuntimeContext(3000))
                self.assertEqual(result['data']['videos'][0]['id'], '329257153645817856')
                second = MioMediaSdk(identity, base_url=endpoint)
                self.assertEqual(second.call('recommend', {}, RuntimeContext(3000)), result)
                self.assertEqual(len({item[1] for item in observed}), 1)
                self.assertEqual(observed[1][0], config.API_PREFIX + '/home/recommend')
                self.assertEqual(observed[1][2], {})
        finally:
            upstream.shutdown()
            upstream.server_close()
            thread.join(timeout=2)


if __name__ == '__main__':
    unittest.main()
