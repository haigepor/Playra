"""导入可验证的私有 Lumina SDK；仅 config/profile 允许宿主环境绑定差异。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re

BASE = Path(__file__).resolve().parent / 'vendor'
DEFAULT_TARGET = BASE / 'lumina'
DEFAULT_MANIFEST = BASE / 'lumina-manifest.json'
PREVIOUS_REQUIRED_FILES = (
    '__init__.py', 'aes_cbc.py', 'auth.py', 'block.py', 'client.py', 'codec.py',
    'config.py', 'envelope.py', 'play.py', 'profile.py', 'rsaio.py',
    '_fuse/__init__.py', '_fuse/assets/fuse_core.dll',
    '_fuse/assets/liblumafuse_android_arm64.so',
    '_fuse/assets/liblumafuse_android_x64.so',
    '_fuse/assets/liblumafuse_linux_arm64.so.gz',
    '_fuse/assets/liblumafuse_linux_x64.so.gz',
    '_fuse/assets/liblumafuse_macos_arm64.dylib.gz',
    '_fuse/assets/fuse_image.bin.gz',
)
REQUIRED_FILES = PREVIOUS_REQUIRED_FILES + (
    '_soloader/__init__.py', '_soloader/assets/libcore.so',
)
ALLOWED_BINDINGS = {'config.py', 'profile.py'}
ANDROID_MACHINES = {
    '_fuse/assets/liblumafuse_android_arm64.so': 183,
    '_fuse/assets/liblumafuse_android_x64.so': 62,
    '_soloader/assets/libcore.so': 183,
}


def _digest(raw):
    return hashlib.sha256(raw).hexdigest()


def verify(*, target=DEFAULT_TARGET, manifest_path=DEFAULT_MANIFEST, allow_previous=False):
    target, manifest_path = Path(target).resolve(), Path(manifest_path).resolve()
    try:
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        files = manifest['files']
        expected = PREVIOUS_REQUIRED_FILES if allow_previous and manifest.get('integrationVersion') == 1 else REQUIRED_FILES
        if manifest.get('schemaVersion') != 1 or not isinstance(files, list) or \
                {row['file'] for row in files} != set(expected) or len(files) != len(expected):
            raise ValueError()
        for row in files:
            path = target / row['file']
            if not path.is_file() or _digest(path.read_bytes()) != row['sha256'] or \
                    (row['file'] not in ALLOWED_BINDINGS and row['upstreamSha256'] != row['sha256']):
                raise ValueError()
    except (OSError, ValueError, KeyError, TypeError):
        raise ValueError('SDK_INTEGRITY_ERROR') from None
    return True


def install(source, *, host=None, target=DEFAULT_TARGET, manifest_path=DEFAULT_MANIFEST):
    source = Path(source).resolve(strict=True)
    target, manifest_path = Path(target).resolve(), Path(manifest_path).resolve()
    if source == target or source in target.parents:
        raise ValueError('SDK_INPUT_PATH_INVALID')
    if host is not None and (not isinstance(host, str) or not re.fullmatch(r'[A-Za-z0-9.\-]{1,253}', host)):
        raise ValueError('SDK_HOST_INVALID')
    if not all((source / name).is_file() for name in REQUIRED_FILES):
        raise ValueError('SDK_INPUT_INCOMPLETE')
    # 先构造并校验全部字节；不会在不完整输入下留下看似可用的 vendor。
    output, files = {}, []
    for name in REQUIRED_FILES:
        raw = (source / name).read_bytes()
        # ABI 以 ELF 头为准，不能把 ARM64 官方库当成 x86_64 库打包。
        if name in ANDROID_MACHINES and (len(raw) < 64 or raw[:6] != b'\x7fELF\x02\x01' or
                                         int.from_bytes(raw[18:20], 'little') != ANDROID_MACHINES[name]):
            raise ValueError('SDK_NATIVE_ABI_INVALID')
        imported = raw
        if name == 'config.py' and host is not None:
            text = raw.decode('utf-8')
            old = "API_HOST = os.environ.get('LUMINA_API_HOST', '<HOST>')"
            if text.count(old) != 1:
                raise ValueError('SDK_CONFIG_BINDING_UNSUPPORTED')
            imported = text.replace(old, "API_HOST = os.environ.get('LUMINA_API_HOST', %r)" % host).encode('utf-8')
        if name not in ALLOWED_BINDINGS and imported != raw:
            raise ValueError('SDK_ALGORITHM_MODIFIED')
        output[name] = imported
        files.append({'file': name, 'upstreamSha256': _digest(raw), 'sha256': _digest(imported),
                      'size': len(imported)})
    if target.exists() and manifest_path.exists():
        # 不覆盖已被修改的私有算法副本；先由维护者查明来源差异。
        verify(target=target, manifest_path=manifest_path, allow_previous=True)
    elif target.exists() and any(target.iterdir()):
        raise ValueError('SDK_UNVERIFIED_TARGET')
    target.mkdir(parents=True, exist_ok=True)
    for name, raw in output.items():
        destination = target / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(destination.name + '.importing')
        temporary.write_bytes(raw)
        os.replace(temporary, destination)
    manifest = {
        'schemaVersion': 1, 'sdk': 'lumina', 'integrationVersion': 2,
        'allowedBindingFiles': sorted(ALLOWED_BINDINGS),
        'runtimeBindings': ['profile.DEVICE_FP'],
        'hostBound': host is not None,
        'platforms': ['windows-x64', 'linux-x64', 'linux-arm64', 'macos-arm64', 'android-arm64', 'android-x64'],
        'optionalBackendsIncluded': False,
        # 随包官方库经 ELF 核对仅有 ARM64；x86_64 继续 SDK 自带引擎。
        'responseDecryption': {'preferred': 'soloader', 'nativeAbis': ['arm64-v8a'],
                               'fallback': 'sdk-default'},
        'files': files,
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8', newline='\n')
    verify(target=target, manifest_path=manifest_path)
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Import the private SDK without changing cryptographic code')
    parser.add_argument('source', type=Path, nargs='?', help='sdk/python/lumina directory')
    parser.add_argument('--host', help='Administrator deployment binding; never accepted from HTTP/Dart')
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    if args.verify:
        verify()
        print('LUMINA SDK INTEGRITY PASS')
    elif args.source:
        result = install(args.source, host=args.host)
        print('LUMINA SDK IMPORT PASS files=%d hostBound=%s' % (len(result['files']), result['hostBound']))
    else:
        parser.error('source is required unless --verify is used')
