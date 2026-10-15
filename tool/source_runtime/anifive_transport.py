"""AniFive 元数据传输：校验证书、公网目标、每请求预算和响应上限。"""
import gzip
import http.client
import http.cookiejar
import ipaddress
import json
import socket
import ssl
import time
import urllib.request
from urllib.parse import urlsplit, urljoin

from adapters import RuntimeFailure


def remaining(context):
    context.check_active()
    return max(.001, context.timeout_ms / 1000 - (time.monotonic() - context.started))


def public_addresses(url):
    try:
        value = urlsplit(url)
        port = value.port
    except ValueError:
        raise RuntimeFailure('INVALID_ARGUMENT', 400) from None
    if value.scheme not in ('https', 'http') or not value.hostname or value.username or value.password or value.fragment or (port is not None and not 1 <= port <= 65535):
        raise RuntimeFailure('INVALID_ARGUMENT', 400)
    addresses = socket.getaddrinfo(value.hostname, value.port or (443 if value.scheme == 'https' else 80), type=socket.SOCK_STREAM)
    if not addresses or any(not ipaddress.ip_address(a[4][0]).is_global for a in addresses):
        raise RuntimeFailure('INVALID_ARGUMENT', 400)
    return value, addresses


class Response:
    def __init__(self, status, body, headers, url):
        self.status, self.body, self.headers, self.url = status, body, headers, url

    def text(self):
        return self.body.decode('utf-8', 'replace')


class BoundedTransport:
    def __init__(self, context, hosts, cookies=None, limit=2 * 1024 * 1024):
        self.context, self.hosts, self.limit = context, hosts, limit
        self.cookies = cookies if cookies is not None else http.cookiejar.CookieJar()

    def request(self, method, url, headers=None, body=None, *, probe=False):
        from vendor.anifive import profile, transport
        headers = {'User-Agent': profile.USER_AGENT, 'Accept-Language': profile.ACCEPT_LANGUAGE, **(headers or {})}
        if body is not None and not isinstance(body, bytes):
            body = json.dumps(body, ensure_ascii=False).encode('utf-8')
            headers.setdefault('Content-Type', 'application/json')
        for _ in range(6):
            self.context.check_active()
            url = transport.ascii_url(url)
            host = urlsplit(url).hostname
            if not probe and host not in self.hosts:
                raise RuntimeFailure('UPSTREAM_HOST_REJECTED', 502)
            value, addresses = public_addresses(url)
            # 连接已校验的地址，TLS SNI/证书仍使用原主机，避免二次 DNS 解析。
            connection = http.client.HTTPConnection(value.hostname, value.port or (443 if value.scheme == 'https' else 80), timeout=min(8, remaining(self.context)))
            sock = None
            try:
                family, kind, proto, _, address = addresses[0]
                sock = socket.socket(family, kind, proto)
                sock.settimeout(min(8, remaining(self.context)))
                sock.connect(address)
                if value.scheme == 'https':
                    sock = ssl.create_default_context().wrap_socket(sock, server_hostname=value.hostname)
                connection.sock = sock
                request = urllib.request.Request(url, headers=headers)
                if not probe:
                    self.cookies.add_cookie_header(request)
                outgoing = dict(request.header_items())
                outgoing['Host'] = value.netloc
                connection.request(method, value.path + ('?' + value.query if value.query else '') or '/', body=body, headers=outgoing)
                response = connection.getresponse()
                self.context.check_active()
                if not probe:
                    self.cookies.extract_cookies(response, request)
                if response.status in (301, 302, 303, 307, 308) and response.getheader('Location'):
                    target = urljoin(url, response.getheader('Location'))
                    if urlsplit(target).netloc != value.netloc:
                        headers = {k: v for k, v in headers.items() if k.lower() not in ('cookie', 'authorization', 'apikey', 'referer', 'origin')}
                    if response.status == 303 or (response.status in (301, 302) and method == 'POST'):
                        method, body = 'GET', None
                    url = target
                    continue
                limit = 4096 if probe else self.limit
                raw = bytearray()
                while len(raw) <= limit:
                    self.context.check_active()
                    sock.settimeout(min(3, remaining(self.context)))
                    chunk = response.read1(min(16384, limit + (0 if probe else 1) - len(raw)))
                    if not chunk:
                        break
                    raw.extend(chunk)
                    if probe and len(raw) >= limit:
                        break
                if len(raw) > limit:
                    raise RuntimeFailure('RESPONSE_TOO_LARGE', 502)
                if not probe and response.length not in (None, 0):
                    raise RuntimeFailure('UPSTREAM_TRUNCATED', 502)
                if response.getheader('Content-Encoding') == 'gzip':
                    import io
                    with gzip.GzipFile(fileobj=io.BytesIO(raw)) as decoded:
                        raw = decoded.read(limit + 1)
                    if len(raw) > limit:
                        raise RuntimeFailure('RESPONSE_TOO_LARGE', 502)
                self.context.check_active()
                return Response(response.status, bytes(raw), dict(response.getheaders()), url)
            except RuntimeFailure:
                raise
            except (OSError, http.client.HTTPException) as error:
                self.context.check_active()
                raise RuntimeFailure('TIMEOUT' if isinstance(error, TimeoutError) else 'UPSTREAM_UNAVAILABLE', 502) from None
            finally:
                connection.close()
                if sock is not None:
                    sock.close()
        raise RuntimeFailure('UPSTREAM_REDIRECT_LIMIT', 502)
