import http.client
import json
import threading
import time
import unittest

from adapters import TemplateAdapter, RuntimeFailure
from server import RuntimeServer


class FixtureAdapter(TemplateAdapter):
    adapter_id = "fixture"
    capabilities = ("search", "episodes", "resolve")

    def search(self, keyword, page, page_size, context):
        if keyword == "decrypt-error":
            raise RuntimeFailure("DECRYPT_ERROR")
        if keyword in ("slow", "cancel"):
            for _ in range(100):
                context.check_active()
                time.sleep(0.01)
        return {"data": [{"name": f"仅测试电影 {page}", "url": "fixture-content"}],
                "total": 2, "hasMore": page == 1}


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.server = RuntimeServer(0, {"template": TemplateAdapter(), "fixture": FixtureAdapter()})
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def call(self, path, method="GET", body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
        try:
            request_headers = {"X-Kazumi-Request": "1", "Content-Type": "application/json"}
            request_headers.update(headers or {})
            connection.request(method, path, body=body, headers=request_headers)
            response = connection.getresponse()
            return response.status, json.loads(response.read())
        finally:
            connection.close()

    def test_health_and_template_have_no_film_resources(self):
        self.assertEqual(self.call("/v1/health")[1]["apiVersion"], "1")
        manifest = self.call("/v1/adapters")[1]["data"][0]
        self.assertEqual(manifest["capabilities"], [])
        status, result = self.call("/v1/adapters/template/search?q=x")
        self.assertEqual((status, result["error"]["code"]), (422, "UNSUPPORTED"))

    def test_lumina_http_boundary_accepts_only_registered_sdk_operations(self):
        class LuminaFixture:
            capabilities = ('sdk',)
            def sdk_call(self, operation, payload, context):
                context.check_active()
                return {'data': {'part': payload['part'], 'headers': {'User-Agent': ''}}}
        self.server.registry['lumina'] = LuminaFixture()
        payload = {'operation': 'play', 'payload': {
            'videoId': '18446744073709551616', 'playFormat': 'mp4', 'part': '特别篇·上'}}
        status, value = self.call('/v1/adapters/lumina/sdk', 'POST', json.dumps(payload))
        self.assertEqual(status, 200)
        self.assertEqual(value['data'], {'part': '特别篇·上', 'headers': {'User-Agent': ''}})
        self.assertEqual(self.call('/v1/adapters/lumina/sdk')[0], 405)
        payload['payload']['host'] = 'private.invalid'
        self.assertEqual(self.call('/v1/adapters/lumina/sdk', 'POST', json.dumps(payload))[0], 400)

    def test_pagination_and_business_errors(self):
        self.assertFalse(self.call("/v1/adapters/fixture/search?q=x&page=2")[1]["hasMore"])
        self.assertEqual(self.call("/v1/adapters/fixture/search?q=decrypt-error")[1]["error"]["code"], "DECRYPT_ERROR")

    def test_paths_arguments_and_payload_bounds(self):
        self.assertEqual(self.call("/v1/adapters/../script")[0], 404)
        self.assertEqual(self.call("/v1/adapters/fixture/search?q=x&script=evil.py")[0], 400)
        self.assertEqual(self.call("/v1/adapters/fixture/search?q=x&pageSize=0")[0], 400)
        self.assertEqual(self.call("/v1/adapters/fixture/resolve", "POST", "x" * 33000)[0], 413)
        self.assertEqual(self.call("/v1/adapters/fixture/resolve", "POST", "{}")[0], 400)

    def test_timeout_cooperatively_releases_worker(self):
        status, result = self.call("/v1/adapters/fixture/search?q=slow",
                                   headers={"X-Playra-Timeout-Ms": "30"})
        self.assertEqual((status, result["error"]["code"]), (504, "TIMEOUT"))
        time.sleep(0.1)
        self.assertTrue(self.server.slots.acquire(blocking=False))
        self.server.slots.release()

    def test_disconnect_cooperatively_releases_worker(self):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
        connection.request("GET", "/v1/adapters/fixture/search?q=cancel", headers={"X-Kazumi-Request": "1"})
        time.sleep(0.05)
        connection.close()
        time.sleep(0.15)
        # 检查全部名额，避免只有部分线程停止却被视为完整取消。
        acquired = [self.server.slots.acquire(blocking=False) for _ in range(4)]
        for value in acquired:
            if value: self.server.slots.release()
        self.assertEqual(acquired, [True] * 4)


if __name__ == "__main__":
    unittest.main()
