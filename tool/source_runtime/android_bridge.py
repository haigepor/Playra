"""应用内固定 SDK 入口；仅接受业务 JSON，不加载客户端指定脚本。"""
import json
from pathlib import Path
import re
import threading

from adapters import RuntimeContext, RuntimeFailure
from dispatch import operation
from anifive_adapter import registered_anifive
from miomedia_adapter import MioMediaAdapter, MioMediaSdk, public_data, validate_payload

MAX_BODY = 32768
MAX_RESPONSE = 2 * 1024 * 1024


class AndroidRuntime:
    def __init__(self, private_directory, adapter=None):
        directory = Path(private_directory)
        if not directory.is_absolute():
            raise ValueError('Private directory must be absolute')
        self.adapter = adapter or MioMediaAdapter(
            sdk=MioMediaSdk(directory / 'miomedia' / 'device.json'))
        self.registry = {'miomedia': self.adapter, **registered_anifive()}
        self._lock = threading.Lock()
        self._requests = {}
        self._early_cancelled = set()

    @staticmethod
    def _error(code):
        return {'error': {'code': code, 'message': code}}

    def cancel(self, request_id):
        if not isinstance(request_id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', request_id):
            return
        with self._lock:
            context = self._requests.get(request_id)
            if context is not None:
                context.cancelled.set()
            else:
                # 覆盖取消先于 Python 上下文注册的短暂窗口，保持数量有界。
                if len(self._early_cancelled) >= 64:
                    self._early_cancelled.clear()
                self._early_cancelled.add(request_id)

    def request(self, raw, request_id, timeout_ms):
        context = None
        registered = False
        try:
            if not isinstance(raw, str) or len(raw.encode('utf-8')) > MAX_BODY:
                raise RuntimeFailure('PAYLOAD_TOO_LARGE', 413)
            if type(timeout_ms) is not int or not 1 <= timeout_ms <= 60000 or \
                    not isinstance(request_id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', request_id):
                raise RuntimeFailure('INVALID_ARGUMENT', 400)
            try:
                request = json.loads(raw)
            except (ValueError, UnicodeError):
                raise RuntimeFailure('INVALID_ARGUMENT', 400) from None
            if not isinstance(request, dict) or set(request) != {'path', 'method', 'query', 'body'} or \
                    not isinstance(request['query'], dict):
                raise RuntimeFailure('INVALID_ARGUMENT', 400)
            context = RuntimeContext(timeout_ms)
            with self._lock:
                if request_id in self._requests:
                    raise RuntimeFailure('INVALID_ARGUMENT', 400)
                self._requests[request_id] = context
                registered = True
                if request_id in self._early_cancelled:
                    self._early_cancelled.remove(request_id)
                    context.cancelled.set()
            context.check_active()
            path, method, body = request['path'], request['method'], request['body']
            if path == 'health' and method == 'GET' and body is None and not request['query']:
                response = {'data': {'service': 'playra-source-runtime', 'apiVersion': '1', 'embedded': True}}
            elif path == 'adapters' and method == 'GET' and body is None and not request['query']:
                response = {'data': {'adapters': [a.manifest() for a in self.registry.values()]}}
            else:
                response = operation(self.registry, path, method, request['query'], body, context)()
            context.check_active()
            encoded = json.dumps(public_data(response), ensure_ascii=False, allow_nan=False, separators=(',', ':'))
            if len(encoded.encode('utf-8')) > MAX_RESPONSE:
                raise RuntimeFailure('RESPONSE_TOO_LARGE', 502)
            return encoded
        except RuntimeFailure as error:
            return json.dumps(self._error(error.code), separators=(',', ':'))
        except Exception:
            return json.dumps(self._error('RUNTIME_ERROR'), separators=(',', ':'))
        finally:
            if registered:
                with self._lock:
                    self._requests.pop(request_id, None)
                    self._early_cancelled.discard(request_id)


_runtime = None
_startup_lock = threading.Lock()


def configure(private_directory):
    global _runtime
    with _startup_lock:
        if _runtime is None:
            _runtime = AndroidRuntime(private_directory)


def request(raw, request_id, timeout_ms):
    if _runtime is None:
        return json.dumps(AndroidRuntime._error('RUNTIME_UNAVAILABLE'))
    return _runtime.request(raw, request_id, timeout_ms)


def cancel(request_id):
    if _runtime is not None:
        _runtime.cancel(request_id)
