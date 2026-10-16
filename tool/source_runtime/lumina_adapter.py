"""Lumina 受限内容适配；协议算法保留在私有 SDK，不向客户端返回信封材料。"""
from contextlib import contextmanager
import errno
import html
import http.client
import importlib
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import socket
import ssl
import tempfile
import threading
import time
from urllib.parse import urlsplit

from adapters import RuntimeFailure

OPERATIONS = ('config', 'channels', 'banners', 'catalog', 'search', 'detail', 'play')
MAX_RESPONSE = 2 * 1024 * 1024
_BIND_LOCK = threading.RLock()
_PROFILE_BINDING = None


def remaining(context):
    context.check_active()
    return max(.001, context.timeout_ms / 1000 - (time.monotonic() - context.started))


def validate_payload(operation, payload):
    if operation not in OPERATIONS or not isinstance(operation, str):
        raise RuntimeFailure('UNSUPPORTED', 422)
    if not isinstance(payload, dict):
        raise RuntimeFailure('INVALID_ARGUMENT', 400)
    allowed = {
        'config': set(), 'channels': set(), 'banners': {'channelId'},
        'catalog': {'channelId', 'pageIndex', 'pageSize', 'sort'},
        'search': {'keyword', 'pageIndex', 'pageSize'},
        'detail': {'videoId'}, 'play': {'videoId', 'playFormat', 'part'},
    }[operation]
    if set(payload) - allowed:
        raise RuntimeFailure('INVALID_ARGUMENT', 400)
    value = dict(payload)
    for key in ('videoId', 'channelId'):
        if key in allowed and (not isinstance(value.get(key), str) or
                               not re.fullmatch(r'[0-9]{1,64}', value[key])):
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
    if operation == 'search':
        if not isinstance(value.get('keyword'), str) or not 1 <= len(value['keyword'].strip()) <= 300:
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
        value['keyword'] = value['keyword'].strip()
    for key, limit in (('pageIndex', 1000000), ('pageSize', 100)):
        if key in value and (type(value[key]) is not int or not 1 <= value[key] <= limit):
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
    if operation in ('catalog', 'search'):
        value.setdefault('pageIndex', 1)
        value.setdefault('pageSize', 24 if operation == 'catalog' else 12)
    if operation == 'catalog':
        value.setdefault('sort', 'weight')
        if not isinstance(value['sort'], str) or not re.fullmatch(r'[\w\-\u4e00-\u9fff]{1,80}', value['sort']):
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
    if operation == 'play':
        if not isinstance(value.get('playFormat'), str) or not re.fullmatch(r'[A-Za-z0-9_+.\-]{1,64}', value['playFormat']):
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
        # 集名是源站身份，不能重排、trim 或根据展示序号重新构造。
        if not isinstance(value.get('part'), str) or not value['part'].strip() or len(value['part']) > 512 or any(ord(c) < 32 for c in value['part']):
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
    return value


def _public_url(url, code='INVALID_MEDIA'):
    try:
        value = urlsplit(url)
        port = value.port
        if value.scheme not in ('http', 'https') or not value.hostname or value.username or value.password or value.fragment or \
                (port is not None and not 1 <= port <= 65535) or len(url) > 16384 or any(ord(c) < 32 for c in url):
            raise ValueError()
        host = value.hostname.lower().rstrip('.')
        if host in ('localhost', 'localhost.localdomain') or host.endswith(('.local', '.localhost', '.internal')):
            raise ValueError()
        try:
            address = ipaddress.ip_address(host)
        except ValueError:
            address = None
        if address is not None and not address.is_global:
            raise ValueError()
        return value
    except (TypeError, ValueError):
        raise RuntimeFailure(code, 502) from None


def bounded_request(method, url, headers, body, context):
    """仅网络层接管：固定 SDK 仍负责认证、信封与解析器签名/解密。"""
    context.check_active()
    value = _public_url(url, 'UPSTREAM_HOST_REJECTED')
    addresses = socket.getaddrinfo(value.hostname, value.port or (443 if value.scheme == 'https' else 80), type=socket.SOCK_STREAM)
    context.check_active()
    if not addresses or any(not ipaddress.ip_address(item[4][0]).is_global for item in addresses):
        raise RuntimeFailure('UPSTREAM_HOST_REJECTED', 502)
    family, kind, proto, _, address = addresses[0]
    connection = http.client.HTTPConnection(value.hostname, value.port or (443 if value.scheme == 'https' else 80), timeout=min(8, remaining(context)))
    sock = socket.socket(family, kind, proto)
    try:
        sock.settimeout(min(8, remaining(context)))
        sock.connect(address)
        context.check_active()
        sock.settimeout(min(8, remaining(context)))
        if value.scheme == 'https':
            sock = ssl.create_default_context().wrap_socket(sock, server_hostname=value.hostname)
        connection.sock = sock
        # HTTPConnection 不按大小写合并字典键；SDK 的小写 host 必须先移除，
        # 否则同时发送 host/Host 会被接入点按错误报文拒绝。
        hop = {'host', 'connection', 'proxy-connection', 'keep-alive',
               'transfer-encoding', 'te', 'trailer', 'upgrade',
               'proxy-authorization', 'proxy-authenticate', 'content-length'}
        for key, item in headers.items():
            if key.lower() == 'connection':
                hop.update(token.strip().lower() for token in item.split(','))
        folded = {key.lower(): (key, item) for key, item in headers.items() if key.lower() not in hop}
        outgoing = dict(folded.values())
        outgoing['Host'] = value.netloc
        context.check_active()
        sock.settimeout(min(8, remaining(context)))
        connection.request(method, value.path + ('?' + value.query if value.query else '') or '/', body=body, headers=outgoing)
        context.check_active()
        sock.settimeout(min(8, remaining(context)))
        response = connection.getresponse()
        declared = response.getheader('Content-Length')
        if declared is not None and (not declared.isdigit() or int(declared) > MAX_RESPONSE):
            raise RuntimeFailure('RESPONSE_TOO_LARGE', 502)
        raw = bytearray()
        while len(raw) <= MAX_RESPONSE:
            context.check_active()
            sock.settimeout(min(3, remaining(context)))
            chunk = response.read1(min(16384, MAX_RESPONSE + 1 - len(raw)))
            if not chunk:
                break
            raw.extend(chunk)
        if len(raw) > MAX_RESPONSE:
            raise RuntimeFailure('RESPONSE_TOO_LARGE', 502)
        if response.length not in (None, 0):
            raise RuntimeFailure('UPSTREAM_TRUNCATED', 502)
        context.check_active()
        return response.status, bytes(raw)
    finally:
        connection.close()
        sock.close()


def _text(value, maximum=1000):
    return str(value)[:maximum] if isinstance(value, (str, int, float)) and not isinstance(value, bool) else ''


def _number(value):
    try:
        number = int(value)
        return number if 0 <= number <= 10000000 else None
    except (ValueError, TypeError, OverflowError):
        return None


def _id(value):
    value = str(value) if type(value) is int else value
    return value if isinstance(value, str) and re.fullmatch(r'[0-9]{1,64}', value) else ''


def _cover(value):
    value = _text(value, 8192)
    if not value:
        return ''
    try:
        _public_url(value)
        return value
    except RuntimeFailure:
        return ''


def _video(row):
    if not isinstance(row, dict) or not _id(row.get('id')):
        raise RuntimeFailure('PARSE_ERROR', 502)
    name = _text(row.get('name'))
    result = {
        'id': _id(row['id']), 'title': _text(row.get('title')) or name,
        'name': name, 'cover': _cover(row.get('pic') or row.get('cover')),
        'summary': html.unescape(re.sub(r'<[^>]*>', '', _text(row.get('content'), 100000))),
        'year': _text(row.get('year'), 40), 'area': _text(row.get('area'), 200),
        'categoryId': _id(row.get('cid')), 'isEnd': row.get('isend') in (1, '1', True),
    }
    for source, target in (('continu', 'updatedTo'), ('total', 'totalEpisodes')):
        value = _number(row.get(source))
        if value is not None:
            result[target] = value
    return result


def _media(row):
    if not isinstance(row, dict) or not isinstance(row.get('url'), str):
        raise RuntimeFailure('INVALID_MEDIA', 502)
    value = _public_url(row['url'])
    headers = row.get('headers', {})
    allowed = {'user-agent', 'referer', 'origin', 'accept', 'accept-language'}
    if not isinstance(headers, dict) or len(headers) > 8 or any(
            not isinstance(key, str) or key.lower() not in allowed or
            not isinstance(item, str) or len(item) > 16384 or '\r' in item or '\n' in item
            for key, item in headers.items()):
        raise RuntimeFailure('INVALID_MEDIA', 502)
    fmt = _text(row.get('format'), 40).lower()
    if fmt not in ('mp4', 'm3u8', 'hls'):
        fmt = 'hls' if value.path.lower().endswith('.m3u8') else 'auto'
    return {'url': row['url'], 'headers': dict(headers), 'format': fmt,
            'name': _text(row.get('name'), 200),
            **({'vcodec': _text(row['vcodec'], 40)} if row.get('vcodec') else {})}


class LuminaSdk:
    def __init__(self, identity_path, *, host=None, port=None, cache_directory=None,
                 engine_directory=None, client_factory=None, play_module=None,
                 engine_available=None, transport=bounded_request):
        self.identity_path = Path(identity_path).resolve()
        self.cache_directory = Path(cache_directory or self.identity_path.parent / 'runtime-cache').resolve()
        self.engine_directory = Path(engine_directory).resolve() if engine_directory else None
        self.host, self.port = host, port
        self.client_factory, self.play_module = client_factory, play_module
        self.engine_available = engine_available
        self.transport = transport
        self._local = threading.local()
        self._startup = threading.Lock()
        self._ready = False
        self._fingerprint = None

    @contextmanager
    def _identity_lock(self, context):
        self.identity_path.parent.mkdir(parents=True, exist_ok=True)
        with self.identity_path.with_suffix('.lock').open('a+b') as handle:
            if os.name == 'nt':
                import msvcrt
                def acquire():
                    handle.seek(0)
                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                def release():
                    handle.seek(0)
                    msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl
                def acquire():
                    fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                def release():
                    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
            while True:
                context.check_active()
                try:
                    acquire()
                    break
                except OSError as error:
                    if error.errno not in (errno.EAGAIN, errno.EACCES):
                        raise
                    context.cancelled.wait(min(.05, remaining(context)))
            try:
                yield
            finally:
                release()

    def _identity(self, context):
        scratch = None
        try:
            with self._identity_lock(context):
                if self.identity_path.exists():
                    if self.identity_path.stat().st_size > 4096:
                        raise ValueError()
                    value = json.loads(self.identity_path.read_text(encoding='utf-8'))
                    fingerprint = value.get('deviceFingerprint')
                    if not isinstance(fingerprint, str) or not re.fullmatch(r'[a-f0-9]{32}', fingerprint):
                        raise ValueError()
                    return fingerprint
                fingerprint = secrets.token_hex(16)
                fd, name = tempfile.mkstemp(prefix='.device-', dir=self.identity_path.parent)
                scratch = Path(name)
                with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as stream:
                    json.dump({'deviceFingerprint': fingerprint}, stream)
                    stream.flush()
                    os.fsync(stream.fileno())
                context.check_active()
                os.replace(scratch, self.identity_path)
                return fingerprint
        except RuntimeFailure:
            raise
        except (OSError, ValueError, TypeError, AttributeError):
            raise RuntimeFailure('IDENTITY_ERROR', 500) from None
        finally:
            if scratch is not None:
                scratch.unlink(missing_ok=True)

    def _initialize(self, context):
        if self._ready:
            return
        while not self._startup.acquire(timeout=min(.05, remaining(context))):
            context.check_active()
        try:
            if self._ready:
                return
            if self.client_factory is None:
                self._load_sdk(context)
            if self.engine_available is None or not self.engine_available():
                raise RuntimeFailure('ENGINE_UNAVAILABLE', 503)
            self._fingerprint = self._identity(context)
            if self.client_factory is not None and hasattr(self, '_profile'):
                global _PROFILE_BINDING
                with _BIND_LOCK:
                    binding = (str(self.identity_path), self._fingerprint)
                    if _PROFILE_BINDING is not None and _PROFILE_BINDING != binding:
                        raise RuntimeFailure('IDENTITY_CONFLICT', 500)
                    # 仅绑定 profile 的宿主设备值；不更改认证或密码实现。
                    self._profile.DEVICE_FP = self._fingerprint
                    _PROFILE_BINDING = binding
            self._ready = True
        finally:
            self._startup.release()

    def _load_sdk(self, context):
        try:
            with _BIND_LOCK:
                self.cache_directory.mkdir(parents=True, exist_ok=True)
                os.environ['LUMINA_RT_CACHE'] = str(self.cache_directory)
                if self.engine_directory:
                    os.environ['LUMINA_ENGINE_PATH'] = str(self.engine_directory / 'liblumafuse.so')
                config = importlib.import_module('vendor.lumina.config')
                self._profile = importlib.import_module('vendor.lumina.profile')
                sdk_client = importlib.import_module('vendor.lumina.client')
                self.play_module = importlib.import_module('vendor.lumina.play')
                fuse = importlib.import_module('vendor.lumina._fuse')
                self.engine_available = fuse.available
                self.host = self.host or os.environ.get('LUMINA_API_HOST') or config.API_HOST
                self.port = self.port or os.environ.get('LUMINA_API_PORT') or config.API_PORT
                if not self.host or str(self.host).startswith('<'):
                    raise RuntimeFailure('SDK_NOT_CONFIGURED', 503)
                if not re.fullmatch(r'[A-Za-z0-9.\-]{1,253}', str(self.host)) or not 1 <= int(self.port) <= 65535:
                    raise RuntimeFailure('SDK_NOT_CONFIGURED', 503)
                transport = self.transport
                class BoundedClient(sdk_client.Client):
                    def _round(client, method, path, body, headers):
                        # POST 凭证请求不盲目重发；总预算由同一 context 贯穿。
                        status, raw = transport(method, 'http://%s:%d%s' % (client.host, client.port, path),
                                                headers, body, client._playra_context)
                        return status, raw, None
                self.client_factory = BoundedClient
                context.check_active()
        except RuntimeFailure:
            raise
        except (ImportError, OSError):
            raise RuntimeFailure('SDK_RESOURCE_MISSING', 503) from None
        except (ValueError, TypeError):
            raise RuntimeFailure('SDK_NOT_CONFIGURED', 503) from None

    def _client(self, context):
        self._initialize(context)
        client = getattr(self._local, 'client', None)
        if client is None:
            client = self.client_factory(host=self.host, port=self.port, timeout=min(8, remaining(context)))
            self._local.client = client
        client.timeout = min(8, remaining(context))
        client._playra_context = context
        return client

    @staticmethod
    def _data(response):
        if not isinstance(response, dict) or response.get('http') != 200:
            raise RuntimeFailure('UPSTREAM_HTTP_ERROR', 502)
        value = response.get('json')
        if not isinstance(value, dict):
            raise RuntimeFailure('DECRYPT_ERROR' if response.get('error') else 'PARSE_ERROR', 502)
        if type(value.get('code')) is not int or value['code'] != 20000:
            raise RuntimeFailure('BUSINESS_REJECTED', 409)
        return value.get('data')

    def _play(self, client, payload, context):
        # resolve=False 仍取播放凭证；只把外链网络交给有预算/大小限制的宿主传输。
        response = client.play(payload['videoId'], play_fmt=payload['playFormat'], part=payload['part'], resolve=False)
        entries = self._data(response)
        if isinstance(entries, dict):
            entries = entries.get('data')
        if not isinstance(entries, list) or not entries:
            return {'status': 'unavailable', 'error': 'NO_PLAYBACK_SOURCE'}
        entry = entries[0]
        if not isinstance(entry, dict) or not isinstance(entry.get('url'), str) or not entry['url'] or len(entry['url']) > 16384:
            return {'status': 'unavailable', 'error': 'NO_PLAYBACK_SOURCE'}
        context.check_active()
        params = self.play_module.lua_params(entry.get('parse') or '')
        ts = int(time.time() * 1000)
        sign1, sign2 = self.play_module.sign_resolver(entry['url'], ts, params['salt'])
        parser_url = params['parser'] + entry['url'] + '&t=' + str(ts)
        status, raw = self.transport('GET', parser_url, {
            'x-time': str(ts), 'x-form': getattr(getattr(self, '_profile', None), 'PARSER_PLATFORM', 'Android'),
            'x-sign1': sign1, 'x-sign2': sign2,
            'user-agent': getattr(getattr(self, '_profile', None), 'USER_AGENT', 'Dart/3.6 (dart:io)'),
        }, None, context)
        if status != 200:
            raise RuntimeFailure('RESOLVER_HTTP_ERROR', 502)
        parsed = self.play_module.parse_resolver(raw.decode('utf-8', 'replace'), params['aes_key'], params['aes_iv'])
        links = self.play_module.play_direct_links(response['json'], params, parsed)
        context.check_active()
        if not isinstance(links, list) or not links:
            return {'status': 'unavailable', 'error': 'NO_DIRECT_LINK'}
        if len(links) > 20:
            raise RuntimeFailure('RESPONSE_TOO_LARGE', 502)
        media = [_media(row) for row in links]
        return {'status': 'ready', 'media': media[0], 'medias': media}

    def call(self, operation, payload, context):
        payload = validate_payload(operation, payload)
        context.check_active()
        try:
            client = self._client(context)
            if operation == 'play':
                data = self._play(client, payload, context)
            else:
                if operation == 'config':
                    response = client.config()
                elif operation == 'channels':
                    response = client.channel_top()
                elif operation == 'banners':
                    response = client.banners(payload['channelId'])
                elif operation == 'catalog':
                    response = client.video_list(payload['channelId'], limit=payload['pageSize'], page=payload['pageIndex'], sort=payload['sort'])
                elif operation == 'search':
                    response = client.get('/app/video/search', params={'key': payload['keyword'], 'limit': payload['pageSize'], 'page': payload['pageIndex']})
                else:
                    response = client.video_detail(payload['videoId'])
                context.check_active()
                data = self._normalize(operation, self._data(response), payload)
            context.check_active()
            if len(json.dumps(data, ensure_ascii=False, allow_nan=False).encode('utf-8')) > MAX_RESPONSE:
                raise RuntimeFailure('RESPONSE_TOO_LARGE', 502)
            return {'data': data, 'meta': {'providerId': 'lumina', 'operation': operation}}
        except RuntimeFailure:
            raise
        except (TimeoutError, socket.timeout):
            context.check_active()
            raise RuntimeFailure('TIMEOUT', 504) from None
        except (OSError, http.client.HTTPException):
            context.check_active()
            raise RuntimeFailure('UPSTREAM_UNAVAILABLE', 503) from None
        except RuntimeError:
            raise RuntimeFailure('ENGINE_UNAVAILABLE', 503) from None
        except (ValueError, TypeError, KeyError, AttributeError, UnicodeError):
            # SDK 异常可能包含解密样本、脚本和 URL，不透传原消息。
            raise RuntimeFailure('PARSE_ERROR', 502) from None

    @staticmethod
    def _normalize(operation, data, payload):
        if operation == 'config':
            return {'available': True}
        if operation in ('catalog', 'search'):
            if not isinstance(data, dict) or not isinstance(data.get('items'), list):
                raise RuntimeFailure('PARSE_ERROR', 502)
            if len(data['items']) > 100:
                raise RuntimeFailure('RESPONSE_TOO_LARGE', 502)
            return {'videos': [_video(row) for row in data['items']], 'pageInfo': {
                'pageIndex': payload['pageIndex'], 'pageSize': payload['pageSize'],
                'total': _number(data.get('total')) or 0}}
        if operation == 'detail':
            video = _video(data)
            parts = data.get('parts') or []
            if not isinstance(parts, list) or len(parts) > 100:
                raise RuntimeFailure('PARSE_ERROR', 502)
            roads = []
            for part in parts:
                if not isinstance(part, dict) or not isinstance(part.get('part'), list) or not isinstance(part.get('play'), str):
                    raise RuntimeFailure('PARSE_ERROR', 502)
                if len(part['part']) > 10000 or not re.fullmatch(r'[A-Za-z0-9_+.\-]{1,64}', part['play']):
                    raise RuntimeFailure('RESPONSE_TOO_LARGE', 502)
                episodes = []
                for index, name in enumerate(part['part'], 1):
                    if not isinstance(name, str) or not name.strip() or len(name) > 512 or any(ord(c) < 32 for c in name):
                        raise RuntimeFailure('PARSE_ERROR', 502)
                    episodes.append({'part': name, 'name': name, 'index': index})
                roads.append({'play': part['play'], 'name': _text(part.get('play_zh')) or part['play'],
                              'oid': _text(part.get('oid'), 64), 'episodes': episodes})
            return {'video': video, 'parts': roads}
        if not isinstance(data, list) or len(data) > 200:
            raise RuntimeFailure('PARSE_ERROR', 502)
        if operation == 'channels':
            return {'channels': [{'id': _id(row.get('id')), 'name': _text(row.get('name')),
                                  'types': [_text(t, 80) for t in (row.get('types') or [])[:100] if isinstance(t, str)]}
                                 for row in data if isinstance(row, dict) and _id(row.get('id'))]}
        return {'banners': [{'id': _id(row.get('id')), 'videoId': _id(row.get('vid') or row.get('video_id') or row.get('videoId')),
                             # 轮播实际使用 vname，缺失映射会把真实作品渲染成SDK占位文案。
                             'title': _text(row.get('title') or row.get('name') or row.get('vname')),
                             'cover': _cover(row.get('pic') or row.get('image') or row.get('img') or row.get('cover'))}
                            for row in data if isinstance(row, dict)]}


class LuminaAdapter:
    adapter_id = 'lumina'
    capabilities = ('sdk',)

    def __init__(self, sdk=None):
        directory = Path(os.environ.get('PLAYRA_LUMINA_STATE_DIR') or Path(__file__).resolve().parents[2] / '.dart_tool' / 'lumina')
        self.sdk = sdk or LuminaSdk(directory / 'device.json')

    def manifest(self):
        return {'id': self.adapter_id, 'version': '1.0.0', 'domains': ['anime'],
                'capabilities': list(self.capabilities), 'operations': list(OPERATIONS),
                'implemented': True, 'identityScope': 'local-install', 'preparePlayback': True}

    def sdk_call(self, operation, payload, context):
        return self.sdk.call(operation, payload, context)
