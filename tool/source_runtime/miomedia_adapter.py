"""MioMedia SDK 的受限内容操作与本地服务会话；算法由随包 SDK 完成。"""
from copy import deepcopy
from contextlib import contextmanager
import errno
import hmac
import http.client
import ipaddress
import json
import os
from pathlib import Path
import re
import socket
import tempfile
import threading
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit

from adapters import RuntimeContext, RuntimeFailure
from vendor.miomedia import Client, PlaybackClient, STRATEGY_TOKEN
from vendor.miomedia import config
from vendor.miomedia.playback import PARSE_API, PARSE_USER_AGENT

OPERATIONS = {
    'recommend': '/home/recommend', 'banners': '/banner/list',
    'catalog': '/video/categoryList', 'detail': '/video/detail',
    'episodes': '/resolve/episodes', 'qualities': '/resolve/qualities',
    'exchange': '/resolve/exchange',
    'search': '/video/search', 'searchConfig': '/video/searchConfig',
    'hotRank': '/video/modules',
    'play': None,
}
PRIVATE_FIELDS = {'deviceId', 'deviceSecret', 'masterSecret', 'signSecret',
                  'hmacSecret', 'b64tTable', 'fpAlgo', 'adToken', 'nonce'}


def public_data(value):
    if isinstance(value, dict):
        return {k: public_data(v) for k, v in value.items() if k not in PRIVATE_FIELDS}
    if isinstance(value, list):
        return [public_data(v) for v in value]
    return value


def validate_payload(operation, payload):
    if not isinstance(operation, str) or operation not in OPERATIONS:
        raise RuntimeFailure('UNSUPPORTED', 422)
    if not isinstance(payload, dict):
        raise RuntimeFailure('INVALID_ARGUMENT', 400)
    fields = {
        'recommend': set(), 'banners': set(), 'searchConfig': set(),
        'catalog': {'pageIndex', 'pageSize', 'categoryId'}, 'detail': {'videoId'},
        'hotRank': {'categoryId', 'pageIndex', 'pageSize'},
        'search': {'keyword', 'pageIndex', 'pageSize'},
        'play': {'videoId', 'code', 'episodeNum', 'quality', 'caps'},
        'episodes': {'videoId', 'code'},
        'qualities': {'videoId', 'code', 'episodeNum', 'caps'},
        'exchange': {'videoId', 'code', 'episodeNum', 'caps', 'quality', 'exchangeToken'},
    }[operation]
    if set(payload) - fields:
        raise RuntimeFailure('INVALID_ARGUMENT', 400)
    if operation == 'hotRank' and set(payload) != fields:
        raise RuntimeFailure('INVALID_ARGUMENT', 400)
    if operation in ('detail', 'episodes', 'qualities', 'exchange', 'play'):
        if not isinstance(payload.get('videoId'), str) or not re.fullmatch(r'[0-9]{1,64}', payload['videoId']):
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
    for key in ('code', 'quality'):
        if key == 'quality' and operation == 'play' and key not in payload:
            continue
        if key in fields and (not isinstance(payload.get(key), str) or
                              not re.fullmatch(r'[A-Za-z0-9_+.\-]{1,64}', payload[key])):
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
    if 'categoryId' in payload and (not isinstance(payload['categoryId'], str) or
                                    not re.fullmatch(r'[0-9]{1,64}', payload['categoryId'])):
        raise RuntimeFailure('INVALID_ARGUMENT', 400)
    if operation == 'search':
        if not isinstance(payload.get('keyword'), str) or not 1 <= len(payload['keyword'].strip()) <= 300:
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
        payload = {**payload, 'keyword': payload['keyword'].strip()}
    for key, maximum in (('episodeNum', 1000000), ('pageIndex', 1000000), ('pageSize', 100)):
        if key == 'episodeNum' and key in fields and key not in payload:
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
        if key in payload and (type(payload[key]) is not int or not 1 <= payload[key] <= maximum):
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
    # 当前媒体实现尚无 v2ts，不能代替客户端虚报播放能力。
    if 'caps' in fields and payload.get('caps', []) != []:
        raise RuntimeFailure('UNSUPPORTED_CAPABILITY', 422)
    if 'exchangeToken' in fields and (not isinstance(payload.get('exchangeToken'), str) or
                                     not 1 <= len(payload['exchangeToken']) <= 2048):
        raise RuntimeFailure('INVALID_ARGUMENT', 400)
    return {**payload, **({'caps': []} if 'caps' in fields else {})}


class MioMediaSdk:
    def __init__(self, identity_path, *, base_url=None, session_config=None,
                 client_factory=Client, session_ttl=300):
        self.identity_path = Path(identity_path).resolve()
        self.base_url = base_url or config.DEFAULT_BASE_URL
        uri = urlsplit(self.base_url)
        if uri.scheme not in ('http', 'https') or not uri.hostname or uri.username or uri.query or uri.fragment:
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
        self.session_config = deepcopy(session_config or config.FALLBACK_SESSION_CONFIG)
        self.client_factory = client_factory
        self.session_ttl = session_ttl
        self._lock = threading.Lock()
        self._device_id = None
        self._offset = 0
        self._expires = 0
        self._playback_rotations = 0
        self._playback_attempts = 0
        self._playback_ad_required = 0

    def playback_health(self):
        # 只公开计数与策略，不公开身份、凭证或会话材料。
        with self._lock:
            return {'strategy': STRATEGY_TOKEN, 'rotations': self._playback_rotations,
                    'attempts': self._playback_attempts,
                    'adRequired': self._playback_ad_required}

    @staticmethod
    def remaining(context):
        context.check_active()
        return max(0.001, context.timeout_ms / 1000 - (time.monotonic() - context.started))

    def _client(self, context):
        try:
            client = self.client_factory.load_identity(
                self.identity_path, base_url=self.base_url,
                session_config=self.session_config, timeout=min(10, self.remaining(context)))
            if not re.fullmatch(r'[a-f0-9]{64}', client.device_id):
                raise ValueError('invalid identity')
            if self._device_id is not None and self._device_id != client.device_id:
                raise ValueError('identity changed during session')
            client.time_offset_ms = self._offset
            return client
        except RuntimeFailure:
            raise
        except (OSError, ValueError, KeyError, TypeError):
            raise RuntimeFailure('IDENTITY_ERROR', 500) from None

    @contextmanager
    def _identity_creation_lock(self, context):
        # 锁文件长期保留；删除它会让并发实例锁住不同文件。系统会在进程退出时释放锁。
        lock_path = self.identity_path.with_name(self.identity_path.name + '.lock')
        with lock_path.open('a+b') as handle:
            # 锁可以覆盖文件末尾以外的区域；锁前写入标记会与其他实例的锁竞争。
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
                    if error.errno not in (errno.EACCES, errno.EAGAIN):
                        raise
                    context.cancelled.wait(min(0.05, self.remaining(context)))
            try:
                context.check_active()
                yield
            finally:
                release()

    def _create_identity(self, context=None):
        if self.identity_path.exists():
            return
        context = context or RuntimeContext(10000)
        scratch = None
        try:
            self.identity_path.parent.mkdir(parents=True, exist_ok=True)
            with self._identity_creation_lock(context):
                # Android 应用不能创建硬链接；锁内复查后用同目录原子重命名发布。
                if self.identity_path.exists():
                    return
                fd, name = tempfile.mkstemp(prefix='.device-', dir=self.identity_path.parent)
                os.close(fd)
                scratch = Path(name)
                self.client_factory(base_url=self.base_url, session_config=self.session_config).save_identity(scratch)
                with scratch.open('r+b') as handle:
                    os.fsync(handle.fileno())
                context.check_active()
                os.replace(scratch, self.identity_path)
        except (OSError, ValueError, KeyError, TypeError):
            raise RuntimeFailure('IDENTITY_ERROR', 500) from None
        finally:
            if scratch is not None:
                scratch.unlink(missing_ok=True)

    @staticmethod
    def validate_response(status, obj, allow_ad=False):
        if status != 200:
            raise RuntimeFailure('UPSTREAM_NOT_FOUND' if status == 404 else 'UPSTREAM_HTTP_ERROR',
                                 404 if status == 404 else 502)
        if not isinstance(obj, dict):
            raise RuntimeFailure('PARSE_ERROR', 502)
        if allow_ad and obj.get('code') == 4031 and isinstance(obj.get('data'), dict):
            return {**obj['data'], 'adRequired': True}
        if obj.get('success') is not True or type(obj.get('code')) is not int or obj['code'] != 200:
            raise RuntimeFailure('AD_REQUIRED' if obj.get('code') == 4031 else 'BUSINESS_REJECTED', 409)
        data = obj.get('data')
        if not isinstance(data, dict):
            raise RuntimeFailure('PARSE_ERROR', 502)
        if data.get('success') is False:
            raise RuntimeFailure('BUSINESS_REJECTED', 409)
        return data

    def _execute(self, client, context, path=None, payload=None, allow_ad=False):
        for attempt in range(2):
            context.check_active()
            client.timeout = min(10, self.remaining(context))
            try:
                response = client.handshake() if path is None else client.request(path, payload)
                context.check_active()
                return self.validate_response(*response, allow_ad=allow_ad)
            except RuntimeFailure:
                raise
            except FileNotFoundError:
                # SDK 读取随包资源也会抛 OSError，不能当作网络问题重试。
                raise RuntimeFailure('SDK_RESOURCE_MISSING', 500) from None
            except json.JSONDecodeError:
                raise RuntimeFailure('PARSE_ERROR', 502) from None
            except (ValueError, UnicodeError):
                raise RuntimeFailure('DECRYPT_ERROR', 502) from None
            except (http.client.IncompleteRead, urllib.error.URLError, OSError) as error:
                context.check_active()
                # 换取与凭证领取会消费令牌/nonce，响应丢失不能自动重复提交。
                if path not in ('/resolve/exchange', '/ad/claimReward') and attempt == 0 and self.remaining(context) > 0.1:
                    continue
                reason = getattr(error, 'reason', error)
                code = {
                    errno.EACCES: 'UPSTREAM_PERMISSION_DENIED',
                    errno.EPERM: 'UPSTREAM_PERMISSION_DENIED',
                    errno.ENETUNREACH: 'UPSTREAM_NETWORK_UNREACHABLE',
                    errno.EHOSTUNREACH: 'UPSTREAM_NETWORK_UNREACHABLE',
                    errno.ECONNREFUSED: 'UPSTREAM_CONNECTION_REFUSED',
                    errno.ECONNRESET: 'UPSTREAM_CONNECTION_RESET',
                    errno.EPIPE: 'UPSTREAM_CONNECTION_RESET',
                }.get(getattr(reason, 'errno', None), 'UPSTREAM_UNAVAILABLE')
                if isinstance(reason, (TimeoutError, socket.timeout)):
                    code = 'TIMEOUT'
                elif isinstance(reason, socket.gaierror):
                    code = 'UPSTREAM_DNS_ERROR'
                raise RuntimeFailure(code, 504 if code == 'TIMEOUT' else 503) from None

    def _ensure_session(self, context):
        # 等待同一身份的初始化时也遵守取消和总预算。
        while not self._lock.acquire(timeout=min(0.05, self.remaining(context))):
            context.check_active()
        try:
            context.check_active()
            if time.monotonic() < self._expires:
                return
            self._create_identity(context)
            client = self._client(context)
            data = self._execute(client, context)
            secret = data.get('deviceSecret')
            if not isinstance(secret, str) or not re.fullmatch(r'[a-f0-9]{64}', secret) or \
                    not hmac.compare_digest(secret, client.device_secret) or \
                    data.get('deviceId') != client.device_id:
                raise RuntimeFailure('SESSION_MISMATCH', 502)
            if data.get('protocol') != 'v3' or type(data.get('serverTime')) is not int or \
                    data['serverTime'] <= 0 or data.get('keyVersion') != self.session_config.get('keyVersion'):
                raise RuntimeFailure('SESSION_CONFIG_MISMATCH', 502)
            self._device_id = client.device_id
            self._offset = client.time_offset_ms
            self._expires = time.monotonic() + self.session_ttl
        finally:
            self._lock.release()

    def call(self, operation, payload, context):
        payload = validate_payload(operation, payload)
        self._ensure_session(context)
        if operation == 'play':
            return {'data': self._play(payload, context),
                    'meta': {'providerId': 'miomedia', 'operation': operation}}
        data = self._execute(self._client(context), context, OPERATIONS[operation], payload)
        if operation == 'hotRank':
            if not isinstance(data.get('list'), list):
                raise RuntimeFailure('PARSE_ERROR', 502)
            module = next((m for m in data['list'] if isinstance(m, dict)
                           and m.get('id') == 'MOD_818368'), None)
            if module is not None and not isinstance(module.get('items'), list):
                raise RuntimeFailure('PARSE_ERROR', 502)
            # 原始前十按数组顺序投影；累计播放量和评分都不能改变榜单位次。
            data = {'categoryId': payload['categoryId'], 'window': None, 'metric': None,
                    'list': [{**module, 'items': module['items'][:10]}] if module else []}
        return {'data': public_data(data), 'meta': {'providerId': 'miomedia', 'operation': operation}}

    def _parse_get(self, url, context):
        # 解析接入点由原样 SDK 定义；客户端不能传入任意网络目标。
        if not url.startswith(PARSE_API):
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
        request = urllib.request.Request(url, headers={'User-Agent': PARSE_USER_AGENT})
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                raise RuntimeFailure('PLAYBACK_UNAVAILABLE', 502)
        context.check_active()
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=min(10, self.remaining(context))) as response:
            raw = bytearray()
            while True:
                context.check_active()
                chunk = response.read(32768)
                if not chunk: break
                raw.extend(chunk)
                if len(raw) > 2 * 1024 * 1024:
                    raise RuntimeFailure('PAYLOAD_TOO_LARGE', 502)
        context.check_active()
        return raw.decode('utf-8', 'strict')

    def _play(self, payload, context):
        sdk = self
        underlying = self._client(context)
        class PlaybackSession:
            def request(self, path, body):
                if path not in ('/resolve/qualities', '/resolve/exchange', '/resolve/episodes',
                                '/ad/getConfig', '/ad/claimReward'):
                    raise RuntimeFailure('UNSUPPORTED', 422)
                # 凭证端点只允许 SDK 固定槽位与供给任务，不能扩展为任意奖励调用。
                if path in ('/ad/getConfig', '/ad/claimReward'):
                    expected = {'slotCode': 'player_switch_episode'}
                    if path == '/ad/claimReward':
                        expected.update(nonce=body.get('nonce'), taskCode='privilege_supply')
                        if not isinstance(expected['nonce'], str) or not expected['nonce']:
                            raise RuntimeFailure('INVALID_ARGUMENT', 400)
                    if body != expected:
                        raise RuntimeFailure('INVALID_ARGUMENT', 400)
                data = sdk._execute(underlying, context, path, body, allow_ad=True)
                return 200, {'code': 4031 if data.get('adRequired') is True else 200, 'success': True, 'data': data}
            def http_get(self, url):
                return sdk._parse_get(url, context)
        # 应用复用持久设备态，显式 TOKEN；AUTO/ROTATE 留给独立诊断客户端。
        playback = PlaybackClient(PlaybackSession(), strategy=STRATEGY_TOKEN)
        with self._lock:
            self._playback_attempts += 1
        result = playback.play(
            payload['videoId'], payload['code'], payload['episodeNum'],
            quality=payload.get('quality'), caps=[])
        context.check_active()
        status = result.get('status')
        with self._lock:
            self._playback_rotations += playback.rotations
            self._playback_ad_required += int(status == 'ad_required')
        diagnostics = {'strategy': STRATEGY_TOKEN,
                       'rotated': bool(result.get('rotated', False)),
                       'rotations': playback.rotations}
        if status == 'ad_required':
            ad = result.get('ad', {})
            return {**diagnostics, 'status': status, 'ad': {k: ad[k] for k in (
                'adRequired', 'slotCode', 'minWatchSeconds', 'allowEarlyClose',
                'landscapePlacementId', 'portraitPlacementId') if k in ad}}
        if status != 'ready':
            # SDK 错误可能带上游响应片段，统一成稳定公开错误码。
            reason = str(result.get('error', ''))
            codes = (
                ('JSON解析失败', 'CLIENT_PARSE_INVALID_RESPONSE'),
                ('解析请求失败', 'CLIENT_PARSE_NETWORK'),
                ('接口返回为空', 'CLIENT_PARSE_INVALID_RESPONSE'),
                ('接口业务失败', 'CLIENT_PARSE_REJECTED'),
                ('qualities 请求失败', 'QUALITY_UNAVAILABLE'),
                ('未取得 exchangeToken', 'MISSING_EXCHANGE_TOKEN'),
                ('exchange 请求失败', 'EXCHANGE_FAILED'),
                ('source为空', 'EMPTY_SOURCE'),
                ('未知 exchange 响应形态', 'UNKNOWN_PLAYBACK_RESPONSE'),
            )
            code = next((code for prefix, code in codes if reason.startswith(prefix)), 'PLAYBACK_UNAVAILABLE')
            return {**diagnostics, 'status': 'unavailable', 'error': code}
        media = result.get('media')
        if not isinstance(media, dict):
            raise RuntimeFailure('PARSE_ERROR', 502)
        uri = urlsplit(media.get('url', ''))
        if uri.scheme not in ('http', 'https') or not uri.hostname or uri.username or uri.fragment or \
                uri.hostname.lower() in ('localhost', 'localhost.localdomain') or uri.hostname.lower().endswith(('.local', '.localhost')):
            raise RuntimeFailure('INVALID_MEDIA', 502)
        try:
            address = ipaddress.ip_address(uri.hostname)
            if not address.is_global: raise RuntimeFailure('INVALID_MEDIA', 502)
        except ValueError:
            pass
        headers = media.get('headers') or {}
        if not isinstance(headers, dict) or any(not isinstance(v, str) or '\r' in v or '\n' in v for v in headers.values()):
            raise RuntimeFailure('INVALID_MEDIA', 502)
        return {**diagnostics, 'status': 'ready', 'media': {
            'url': media['url'], 'format': str(media.get('format', 'unknown')),
            'name': str(media.get('name', '')),
            'headers': {k: v for k, v in headers.items() if k.lower() in ('user-agent', 'referer', 'origin', 'accept')},
        }, 'selection': {k: payload[k] for k in ('videoId', 'code', 'episodeNum')}}


class MioMediaAdapter:
    adapter_id = 'miomedia'
    capabilities = ('sdk',)

    def __init__(self, sdk=None):
        state_dir = os.environ.get('PLAYRA_MIOMEDIA_STATE_DIR') or \
            str(Path(__file__).resolve().parents[2] / '.dart_tool' / 'miomedia')
        self.sdk = sdk or MioMediaSdk(Path(state_dir) / 'device.json',
                                     base_url=os.environ.get('PLAYRA_MIOMEDIA_BASE_URL'))

    def manifest(self):
        return {'id': self.adapter_id, 'version': '1.0.0', 'domains': ['anime', 'screen'],
                'capabilities': list(self.capabilities), 'operations': list(OPERATIONS),
                'implemented': True, 'identityScope': 'local-service', 'playbackReady': True,
                'playbackHealth': self.sdk.playback_health()}

    def sdk_call(self, operation, payload, context):
        return self.sdk.call(operation, payload, context)
