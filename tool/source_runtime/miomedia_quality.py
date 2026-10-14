"""Select only evidenced resolutions; do not infer quality from source names."""
import json
import math
import re


def resolution(value):
    if type(value) in (int, float) and math.isfinite(value) and value == int(value) and 144 <= value <= 16384:
        return int(value)
    if not isinstance(value, str):
        return None
    text = value.strip().lower()
    match = re.fullmatch(r'(\d{3,5})p(?:\d{2,3})?', text)
    if match:
        return resolution(int(match[1]))
    match = re.fullmatch(r'\d{3,5}\s*[x\u00d7]\s*(\d{3,5})', text)
    if match:
        return resolution(int(match[1]))
    return {'4k': 2160, '8k': 4320}.get(text)


def quality_height(item):
    if not isinstance(item, dict):
        return None
    for field in ('height', 'resolution', 'quality', 'label', 'name'):
        height = resolution(item.get(field))
        if height is not None:
            return height
    return None


def rank_qualities(data):
    """Stable ordering preserves upstream preference among equal/unknown ranks."""
    if not isinstance(data.get('qualities'), list):
        return data
    return {**data, 'qualities': sorted(data['qualities'],
            key=lambda q: quality_height(q) or 0, reverse=True)}


def select_parse_variant(body, requested, normalize_urls):
    try:
        obj = json.loads(body)
    except (ValueError, TypeError):
        return body, None
    if not isinstance(obj, dict) or str(obj.get('code')) != '200':
        return body, None
    variants = normalize_urls(obj)
    # SDK 标准化会丢掉独立的 height/resolution，按地址关联原响应的画质证据。
    raw = obj.get('url')
    if not isinstance(raw, list):
        data = obj.get('data')
        raw = data.get('playAddr', []) if isinstance(data, dict) else []
    evidence = {}
    for item in raw if isinstance(raw, list) else []:
        if isinstance(item, dict):
            address = next((item.get(k) for k in ('url', 'playUrl', 'play_url', 'link', 'src', 'm3u8', 'hls') if isinstance(item.get(k), str)), None)
            height = quality_height(item)
            if address and height:
                evidence[address] = height
    variants = [{**v, 'height': evidence[v['url']]} if v.get('url') in evidence else v for v in variants]
    if len(variants) < 2:
        return body, None
    target = None
    if requested and requested != 'origin':
        target = next((v for v in variants if requested in (v.get('name'), v.get('type'))), None)
        requested_height = resolution(requested)
        if target is None and requested_height is not None:
            target = next((v for v in variants if quality_height(v) == requested_height), None)
            # SDK 声明与解析命名可能不同；无同档时保留合法媒体并返回实际画质证据。
    if target is None:
        target = max(variants, key=lambda v: quality_height(v) or 0)
    return json.dumps({'code': 200, 'type': 'multi', 'url': [target]}), quality_height(target)
