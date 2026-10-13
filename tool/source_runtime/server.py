"""本机算法协议骨架。正式公网部署应换用成熟服务器与鉴权层。"""
import argparse
import json
import re
import select
import socket
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import BoundedSemaphore
from urllib.parse import parse_qs, urlsplit

from adapters import RuntimeContext, RuntimeFailure, registered_adapters

MAX_BODY = 32768
MAX_RESPONSE = 2 * 1024 * 1024
ROUTE = re.compile(r"^/v1/adapters/([A-Za-z0-9_-]{1,64})/(search|episodes|resolve|sdk)$")


class RuntimeServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, port, registry=None, max_workers=4):
        self.registry = registered_adapters() if registry is None else registry
        self.pool = ThreadPoolExecutor(max_workers=max_workers)
        self.slots = BoundedSemaphore(max_workers)
        super().__init__(("127.0.0.1", port), RuntimeHandler)

    def server_close(self):
        super().server_close()
        self.pool.shutdown(wait=False, cancel_futures=True)


class RuntimeHandler(BaseHTTPRequestHandler):
    # 单请求连接避免未消费异常请求体污染下一个请求。
    protocol_version = "HTTP/1.0"
    server_version = "PlayraRuntime/1"
    sys_version = ""

    def setup(self):
        super().setup()
        self.connection.settimeout(5)

    def log_message(self, *_):
        # 不把带 token/URL 的请求行写入日志。
        pass

    def do_GET(self):
        self.handle_runtime()

    def do_POST(self):
        self.handle_runtime()

    def do_OPTIONS(self):
        self.reply(405, {"error": {"code": "UNSUPPORTED", "message": "UNSUPPORTED"}})

    do_PUT = do_OPTIONS
    do_DELETE = do_OPTIONS
    do_PATCH = do_OPTIONS

    def reply(self, status, value):
        raw = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        if len(raw) > MAX_RESPONSE:
            status, raw = 502, b'{"error":{"code":"RESPONSE_TOO_LARGE","message":"RESPONSE_TOO_LARGE"}}'
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass

    def read_body(self, fields=frozenset({"episodeUrl"})):
        if self.headers.get("Transfer-Encoding"):
            raise RuntimeFailure("INVALID_ARGUMENT", 400)
        try:
            size = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            raise RuntimeFailure("INVALID_ARGUMENT", 400) from None
        if size < 0 or size > MAX_BODY:
            raise RuntimeFailure("PAYLOAD_TOO_LARGE", 413)
        if not self.headers.get("Content-Type", "").startswith("application/json"):
            raise RuntimeFailure("INVALID_ARGUMENT", 400)
        try:
            value = json.loads(self.rfile.read(size))
        except (ValueError, UnicodeError):
            raise RuntimeFailure("INVALID_ARGUMENT", 400) from None
        if not isinstance(value, dict) or set(value) != fields:
            raise RuntimeFailure("INVALID_ARGUMENT", 400)
        return value

    def disconnected(self):
        try:
            readable, _, _ = select.select([self.connection], [], [], 0)
            return bool(readable) and self.connection.recv(1, socket.MSG_PEEK) == b""
        except OSError:
            return True

    def execute(self, operation, context):
        if not self.server.slots.acquire(blocking=False):
            raise RuntimeFailure("BUSY", 429)
        try:
            future = self.server.pool.submit(operation)
        except BaseException:
            self.server.slots.release()
            raise
        # 忽略取消的脚本仍占用名额，不能在超时后无限启动更多线程。
        future.add_done_callback(lambda _: self.server.slots.release())
        try:
            while True:
                context.check_active()
                if self.disconnected():
                    context.cancelled.set()
                    raise RuntimeFailure("CANCELLED", 409)
                try:
                    result = future.result(timeout=0.05)
                    context.check_active()
                    return result
                except FutureTimeout:
                    continue
        finally:
            context.cancelled.set()
            future.cancel()

    @staticmethod
    def required_text(value, maximum=8192):
        if not isinstance(value, str) or not value.strip() or len(value) > maximum:
            raise RuntimeFailure("INVALID_ARGUMENT", 400)
        return value

    def handle_runtime(self):
        try:
            url = urlsplit(self.path)
            if len(self.path) > 10000 or url.fragment:
                raise RuntimeFailure("INVALID_ARGUMENT", 400)
            query = parse_qs(url.query, keep_blank_values=True, max_num_fields=8)
            if any(len(value) != 1 for value in query.values()):
                raise RuntimeFailure("INVALID_ARGUMENT", 400)
            if self.command == "GET" and url.path in ("/v1/health", "/v1/adapters"):
                if query:
                    raise RuntimeFailure("INVALID_ARGUMENT", 400)
                manifests = [adapter.manifest() for adapter in self.server.registry.values()]
                value = {"service": "playra-source-runtime", "status": "ok", "apiVersion": "1", "adapters": len(manifests)} \
                    if url.path.endswith("health") else {"data": manifests}
                self.reply(200, value)
                return
            match = ROUTE.fullmatch(url.path)
            if not match:
                raise RuntimeFailure("NOT_FOUND", 404)
            adapter_id, action = match.groups()
            if action == "sdk" and adapter_id != "miomedia":
                raise RuntimeFailure("NOT_FOUND", 404)
            if self.command != ("POST" if action in ("resolve", "sdk") else "GET"):
                raise RuntimeFailure("UNSUPPORTED", 405)
            if self.headers.get("X-Kazumi-Request") != "1":
                raise RuntimeFailure("INVALID_ARGUMENT", 400)
            adapter = self.server.registry.get(adapter_id)
            if adapter is None:
                raise RuntimeFailure("NOT_FOUND", 404)
            budget = int(self.headers.get("X-Playra-Timeout-Ms", "20000"))
            if budget < 1 or budget > 60000:
                raise RuntimeFailure("INVALID_ARGUMENT", 400)
            context = RuntimeContext(budget)
            if action == "sdk":
                if query:
                    raise RuntimeFailure("INVALID_ARGUMENT", 400)
                body = self.read_body(frozenset({"operation", "payload"}))
                name = self.required_text(body["operation"], 32)
                if not isinstance(body["payload"], dict):
                    raise RuntimeFailure("INVALID_ARGUMENT", 400)
                operation = lambda: adapter.sdk_call(name, body["payload"], context)
            elif action == "search":
                if set(query) - {"q", "page", "pageSize"}:
                    raise RuntimeFailure("INVALID_ARGUMENT", 400)
                keyword = self.required_text(query.get("q", [""])[0], 300)
                page, size = int(query.get("page", ["1"])[0]), int(query.get("pageSize", ["20"])[0])
                if page < 1 or page > 1000000 or size < 1 or size > 100:
                    raise RuntimeFailure("INVALID_ARGUMENT", 400)
                operation = lambda: adapter.search(keyword, page, size, context)
            elif action == "episodes":
                if set(query) != {"source"}:
                    raise RuntimeFailure("INVALID_ARGUMENT", 400)
                source = self.required_text(query["source"][0])
                operation = lambda: adapter.episodes(source, context)
            else:
                if query:
                    raise RuntimeFailure("INVALID_ARGUMENT", 400)
                body = self.read_body()
                episode_url = self.required_text(body.get("episodeUrl"))
                operation = lambda: adapter.resolve(episode_url, context)
            if action not in adapter.capabilities:
                raise RuntimeFailure("UNSUPPORTED", 422)
            result = self.execute(operation, context)
            if not isinstance(result, dict):
                raise RuntimeFailure("PARSE_ERROR", 502)
            self.reply(200, result)
        except RuntimeFailure as error:
            self.reply(error.status, {"error": {"code": error.code, "message": error.code}})
        except (ValueError, UnicodeError):
            self.reply(400, {"error": {"code": "INVALID_ARGUMENT", "message": "INVALID_ARGUMENT"}})
        except (TimeoutError, socket.timeout):
            self.reply(504, {"error": {"code": "TIMEOUT", "message": "TIMEOUT"}})
        except Exception:
            # 未公开适配器异常、密钥或堆栈。
            self.reply(502, {"error": {"code": "RUNTIME_ERROR", "message": "RUNTIME_ERROR"}})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8945)
    arguments = parser.parse_args()
    with RuntimeServer(arguments.port) as server:
        print(f"Playra algorithm runtime: http://127.0.0.1:{server.server_port}/v1/", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
