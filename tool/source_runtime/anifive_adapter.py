"""四个动漫来源共享 SDK 契约；保留原站详情/集链接，兼容旧历史。"""
from collections import OrderedDict
from contextlib import contextmanager
from copy import deepcopy
from html import unescape
import http.cookiejar
import re
import threading
import time
from urllib.parse import urlsplit, urljoin

from adapters import RuntimeFailure
from anifive_transport import BoundedTransport, remaining

SOURCES = {
    'a': ('DM84', 'dmbus.cc'),
    'b': ('MXdm', 'www.dcc3.com'),
    'c': ('akianime', 'www.akianime.cc'),
    'd': ('moonci', 'www.moonci.com'),
}


class AniFiveAdapter:
    capabilities = ('search', 'episodes', 'resolve')
    version = '1.0.0'
    domains = ('anime',)

    def __init__(self, source, sdk=None, transport_factory=BoundedTransport):
        self.source = source.lower()
        self.name, self.host = SOURCES[self.source]
        self.adapter_id = 'anifive-' + self.source
        self.base = 'https://' + self.host
        self.sdk = sdk
        self.transport_factory = transport_factory
        self._lock = threading.Lock()
        self._cookies = http.cookiejar.CookieJar()
        self._last_page = 0
        self._cache = OrderedDict()
        self._covers = {}

    def collect_covers(self, html):
        from vendor.anifive import selector
        root = selector.parse_html(html)
        images = selector.find_all(root, '//img') + [a for a in selector.find_all(root, '//a') if a.attrs.get('data-bg')]
        for img in images:
            raw = next((img.attrs.get(k) for k in ('data-bg', 'data-original', 'data-src', 'data-url', 'src') if img.attrs.get(k)), '')
            if not raw.strip():
                continue
            try:
                cover = urljoin(self.base + '/', unescape(raw))
                uri = urlsplit(cover)
                if uri.scheme not in ('https', 'http') or not uri.hostname or uri.username or uri.password or uri.port not in (None, 80, 443):
                    continue
            except ValueError:
                continue
            node = img if img.tag == 'a' else img.parent
            # 只关联最近的单作品容器，不把列表首图填给其他作品。
            for _ in range(5):
                if node is None or node.tag in ('#root', 'body', 'main', 'footer', 'header', 'nav'):
                    break
                anchors = ([node] if node.tag == 'a' else []) + selector.find_relative(node, '//a')
                paths = set()
                for anchor in anchors:
                    href = unescape(anchor.attrs.get('href', ''))
                    if not href:
                        continue
                    try:
                        path = self.path(href)
                        if self.source == 'a':
                            match = re.match(r'/(?:v|p)/(\d+)(?:\.html|-)', path)
                            path = '/v/' + match[1] + '.html' if match else ''
                        elif self.source == 'c':
                            match = re.match(r'/bgm(?:detail|play)/([A-Za-z0-9]+)(?:\.html|-)', path)
                            path = '/bgmdetail/' + match[1] + '.html' if match else ''
                        elif self.source == 'd':
                            match = re.match(r'/(?:anime|voddetail)/(\d+)(?:\.html|/play/)', path)
                            path = '/anime/' + match[1] + '.html' if match else ''
                        if path and path != '/': paths.add(path)
                    except RuntimeFailure:
                        pass
                if len(paths) == 1:
                    self._covers[self.base + paths.pop()] = cover
                    break
                if len(paths) > 1:
                    break
                node = node.parent
        while len(self._covers) > 1000:
            self._covers.pop(next(iter(self._covers)))

    def manifest(self):
        return {'id': self.adapter_id, 'name': self.name, 'version': self.version,
                'domains': list(self.domains), 'capabilities': list(self.capabilities), 'implemented': True}

    @contextmanager
    def session(self, context):
        from vendor.anifive import Client, profile, transport
        while not self._lock.acquire(timeout=min(.05, remaining(context))):
            context.check_active()
        try:
            context.check_active()
            if self.sdk is None:
                self.sdk = Client(source=self.source.upper(), host=self.host)
            hosts = {self.host, self.host.removeprefix('www.'), 'www.' + self.host.removeprefix('www.'), profile.PARSE_HOST, profile.EDGE_SIGN_HOST}
            network = self.transport_factory(context, hosts, self._cookies)
            # 覆盖页面等待方法，解析算法保持 SDK 原实现；锁覆盖同源整个操作。
            def get_page(path, referer=None):
                # MXdm搜索页要求3秒间隔；别名回退也必须遵守，详情/播放仍按原间隔。
                slow_search = self.source == 'b' and urlsplit(path).path.startswith('/search/')
                delay = (3 if self.source in ('a', 'd') or slow_search else 1) - (time.monotonic() - self._last_page)
                if delay > 0:
                    context.cancelled.wait(min(delay, remaining(context)))
                context.check_active()
                try:
                    response = network.request('GET', urljoin(self.base, path), headers={'Referer': referer} if referer else {})
                    if response.status != 200:
                        raise RuntimeFailure('RATE_LIMITED' if response.status == 403 else 'UPSTREAM_HTTP_ERROR', 502)
                    html = response.text()
                    # 原站限频页使用HTTP200，不能让SDK解析为空列表后缓存“无作品”。
                    if self.source == 'b' and '请不要频繁操作' in html and '搜索时间间隔' in html:
                        raise RuntimeFailure('RATE_LIMITED', 502)
                    self.collect_covers(html)
                    return html
                finally:
                    self._last_page = time.monotonic()
            if hasattr(self.sdk, 'impl'):
                self.sdk.impl._get_page = get_page
            with transport.use_transport(network):
                yield self.sdk, network
            context.check_active()
        except RuntimeFailure:
            raise
        except (ValueError, KeyError, IndexError, TypeError, RuntimeError):
            raise RuntimeFailure('PARSE_ERROR', 502) from None
        finally:
            self._lock.release()

    def path(self, value):
        if not isinstance(value, str) or len(value) > 4096:
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
        try:
            uri = urlsplit(urljoin(self.base + '/', value))
            port = uri.port
        except ValueError:
            raise RuntimeFailure('INVALID_ARGUMENT', 400) from None
        if uri.scheme != 'https' or uri.hostname not in (self.host, self.host.removeprefix('www.')) or port not in (None, 443) or uri.username or uri.password or uri.query or uri.fragment or '..' in uri.path or '\\' in uri.path:
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
        if not re.fullmatch(r'/[A-Za-z0-9_./%~\-]+', uri.path):
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
        return uri.path

    def detail_url(self, ref):
        if self.source == 'b':
            return self.base + self.path(ref)
        if not re.fullmatch(r'[A-Za-z0-9]{1,80}' if self.source == 'c' else r'\d{1,64}', str(ref)):
            raise RuntimeFailure('PARSE_ERROR', 502)
        return self.base + {'a': '/v/', 'c': '/bgmdetail/', 'd': '/anime/'}[self.source] + str(ref) + '.html'

    def detail_ref(self, value):
        path = self.path(value)
        if self.source == 'b':
            return path
        pattern = {'a': r'/v/(\d+)\.html', 'c': r'/bgmdetail/([A-Za-z0-9]+)\.html', 'd': r'/(?:anime|voddetail)/(\d+)\.html'}[self.source]
        match = re.fullmatch(pattern, path)
        if not match:
            raise RuntimeFailure('INVALID_ARGUMENT', 400)
        return match[1]

    def cached(self, key, operation):
        entry = self._cache.get(key)
        if entry and time.monotonic() - entry[0] < 120:
            return deepcopy(entry[1])
        value = operation()
        self._cache[key] = (time.monotonic(), deepcopy(value))
        self._cache.move_to_end(key)
        while len(self._cache) > 32:
            self._cache.popitem(last=False)
        return value

    def search(self, keyword, page, page_size, context):
        with self.session(context) as (sdk, _):
            hits = self.cached(('search', keyword), lambda: sdk.search(self.source.upper(), keyword))
            result = [{'name': title, 'url': self.detail_url(ref), 'cover': self._covers.get(self.detail_url(ref), '')} for ref, title in hits if isinstance(title, str) and title.strip()]
            start = (page - 1) * page_size
            # 上游只有第一页；分页仅切分已缓存的这批结果，不伪造下一页请求。
            return {'data': result[start:start + page_size], 'total': len(result), 'hasMore': start + page_size < len(result), 'paginationMode': 'local'}

    def episodes(self, source, context):
        ref = self.detail_ref(source)
        with self.session(context) as (sdk, _):
            detail = self.cached(('detail', ref), lambda: sdk.detail(self.source.upper(), ref))
            roads = OrderedDict()
            for index, road in enumerate(detail.get('roads') or []):
                for episode in road:
                    if self.source == 'b':
                        path, label, _ = episode
                        number = index + 1
                        url = self.base + self.path(path)
                    else:
                        identity, number, episode_id, label = episode
                        if str(identity) != ref or type(number) is not int or type(episode_id) is not int or number < 1 or episode_id < 1:
                            raise RuntimeFailure('PARSE_ERROR', 502)
                        if self.source == 'c' and number != 2:
                            continue
                        path = {'a': f'/p/{ref}-{number}-{episode_id}.html', 'c': f'/bgmplay/{ref}-{number}-{episode_id}.html', 'd': f'/anime/{ref}/play/{number}-{episode_id}.html'}[self.source]
                        url = self.base + path
                    entries = roads.setdefault(number, OrderedDict())
                    entries[url] = {'name': str(label), 'url': url}
            return {'data': {'roads': [{'id': str(number), 'name': f'线路 {number}', 'episodes': list(entries.values())} for number, entries in roads.items() if entries]}}

    def resolve(self, episode_url, context):
        path = self.path(episode_url)
        if self.source == 'b':
            arguments = (path,)
        else:
            pattern = {'a': r'/p/(\d+)-(\d+)-(\d+)\.html', 'c': r'/bgmplay/([A-Za-z0-9]+)-(2)-(\d+)\.html', 'd': r'/anime/(\d+)/play/(\d+)-(\d+)\.html'}[self.source]
            match = re.fullmatch(pattern, path)
            if not match or min(int(match[2]), int(match[3])) < 1:
                raise RuntimeFailure('INVALID_ARGUMENT', 400)
            arguments = (match[1], int(match[2]), int(match[3]))
        with self.session(context) as (sdk, network):
            result = sdk.play(self.source.upper(), *arguments)
            url = result.get('direct_url')
            if not isinstance(url, str):
                raise RuntimeFailure('PLAYBACK_UNAVAILABLE', 502)
            from vendor.anifive import transport
            bare = transport.needs_bare_request(url)
            headers = {k: v for k, v in (result.get('headers') or {}).items() if k.lower() in ('user-agent', 'referer', 'origin', 'accept') and isinstance(v, str)}
            if bare:
                headers = {k: v for k, v in headers.items() if k.lower() not in ('referer', 'origin')}
            response = network.request('GET', url, headers={**headers, 'Range': 'bytes=0-4095'}, probe=True)
            if response.status not in (200, 206):
                raise RuntimeFailure('PLAYBACK_UNAVAILABLE', 502)
            sample = response.body.lstrip()
            # MP4 的 ftyp 必须位于 box 类型字段，避免把错误页面中的文字当作媒体。
            binary = response.body
            is_mp4 = len(binary) >= 12 and binary[4:8] == b'ftyp' and int.from_bytes(binary[:4], 'big') >= 12
            kind = 'hls' if sample.startswith(b'#EXTM3U') else 'auto' if is_mp4 or binary.startswith(b'\x1aE\xdf\xa3') else None
            if kind is None:
                raise RuntimeFailure('NOT_MEDIA', 502)
            # expires_at 是 SDK 的建议刷新点，不冒充硬过期。播放失败重新解析。
            return {'data': {'url': response.url, 'headers': headers, 'headerPolicy': 'replace', 'format': kind}}


def registered_anifive():
    return {a.adapter_id: a for a in (AniFiveAdapter(source) for source in SOURCES)}
