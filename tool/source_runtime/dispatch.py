"""HTTP 与 Android 共用的固定业务路由；拒绝额外字段。"""
import re
from adapters import RuntimeFailure

ROUTE = re.compile(r'adapters/([A-Za-z0-9_-]{1,64})/(search|episodes|resolve|sdk)')


def text(value, maximum=8192):
    if not isinstance(value, str) or not value.strip() or len(value) > maximum:
        raise RuntimeFailure('INVALID_ARGUMENT', 400)
    return value


def operation(registry, path, method, query, body, context):
    match = ROUTE.fullmatch(path) if isinstance(path, str) else None
    if not match:
        raise RuntimeFailure('UNSUPPORTED', 422)
    adapter_id, action = match.groups()
    if method != ('POST' if action in ('resolve', 'sdk') else 'GET'):
        raise RuntimeFailure('UNSUPPORTED', 405)
    adapter = registry.get(adapter_id)
    if adapter is None:
        raise RuntimeFailure('NOT_FOUND', 404)
    if action == 'sdk':
        if adapter_id not in ('miomedia', 'lumina'):
            raise RuntimeFailure('UNSUPPORTED', 422)
        if query or not isinstance(body, dict) or set(body) != {'operation', 'payload'}:
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
        if adapter_id == 'lumina':
            from lumina_adapter import validate_payload
        else:
            from miomedia_adapter import validate_payload
        validate_payload(body['operation'], body['payload'])
        return lambda: adapter.sdk_call(body['operation'], body['payload'], context)
    if action not in adapter.capabilities:
        raise RuntimeFailure('UNSUPPORTED', 422)
    if action == 'search':
        if body is not None or set(query) - {'q', 'page', 'pageSize'}:
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
        keyword = text(query.get('q'), 300)
        try:
            page, size = int(query.get('page', 1)), int(query.get('pageSize', 20))
        except (TypeError, ValueError):
            raise RuntimeFailure('INVALID_ARGUMENT', 400) from None
        if not 1 <= page <= 1000000 or not 1 <= size <= 100:
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
        return lambda: adapter.search(keyword, page, size, context)
    if action == 'episodes':
        if body is not None or set(query) != {'source'}:
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
        source = text(query['source'])
        return lambda: adapter.episodes(source, context)
    if query or not isinstance(body, dict) or set(body) != {'episodeUrl'}:
        raise RuntimeFailure('INVALID_ARGUMENT', 400)
    url = text(body['episodeUrl'])
    return lambda: adapter.resolve(url, context)
