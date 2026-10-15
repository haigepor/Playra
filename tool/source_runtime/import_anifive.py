"""导入固定版本的私有 SDK；保留上游目录，兼容修改仅应用于项目副本。"""
import argparse
import hashlib
import json
from pathlib import Path


def install(source):
    target = Path(__file__).parent / 'vendor' / 'anifive'
    target.mkdir(parents=True, exist_ok=True)
    files = []
    for path in sorted(source.glob('*.py')):
        raw = path.read_bytes()
        text = raw.decode('utf-8-sig').replace('\r\n', '\n')
        if path.name == 'transport.py':
            # 请求级注入避免并行 SDK 共用全局 Cookie/timeout，且不调用系统 curl。
            text = text.replace('import http.client\n', 'import http.client\nfrom contextvars import ContextVar\nfrom contextlib import contextmanager\n\n_bound = ContextVar("anifive_transport", default=None)\n\n@contextmanager\ndef use_transport(value):\n    token = _bound.set(value)\n    try:\n        yield\n    finally:\n        _bound.reset(token)\n\n')
            text = text.replace('    h = host_of(url)\n', '    if _bound.get() is not None:\n        return False\n    h = host_of(url)\n', 1)
            text = text.replace('    global _default\n    if _default is None:', '    if _bound.get() is not None:\n        return _bound.get()\n    global _default\n    if _default is None:')
            text = text.replace('    return _default\n', '    _default.timeout = timeout\n    return _default\n')
            start = text.index('            # 读取到多少算多少')
            end = text.index('\n\n\ndef selftest', start)
            text = text[:start] + '            # 截断不是成功；下一轮重新请求，不返回伪造的 200。\n' + text[end:]
            text = text.replace('["curl", "-sk",', '["curl", "-sS",')
        elif path.name == '__init__.py':
            text = text.replace('    "Client": "client",', '    "Client": "client",\n    "build_request_headers": "client",')
            text = text.replace('if name == "Client" else mod', 'if name in ("Client", "build_request_headers") else mod')
        elif path.name == 'source_d.py':
            text = text.replace('except ImportError:  # 目录直跑\n    import config', 'except ImportError:  # 目录直跑\n    import codec\n    import config')
        (target / path.name).write_text(text, encoding='utf-8', newline='\n')
        files.append({'file': path.name, 'upstreamSha256': hashlib.sha256(raw).hexdigest(),
                      'sha256': hashlib.sha256(text.encode()).hexdigest()})
    required = {'__init__.py', 'client.py', 'transport.py', 'profile.py', 'source_a.py', 'source_b.py', 'source_c.py', 'source_d.py', 'selector.py', 'codec.py', 'config.py', 'clarity.py'}
    if not required.issubset({f['file'] for f in files}):
        raise ValueError('Incomplete AniFive SDK input')
    (target.parent / 'anifive-manifest.json').write_text(json.dumps(
        {'upstreamCommit': 'dc13fdb', 'integrationVersion': 1, 'files': files}, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path, help='SDK sdk/python/anifive directory')
    install(parser.parse_args().source.resolve(strict=True))
