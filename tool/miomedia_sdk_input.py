"""Private SDK build input. Standard library only; never prints input contents."""
import argparse
import ast
import base64
import io
import os
from pathlib import Path
import zipfile

FILES = frozenset(("__init__.py", "block.py", "client.py", "config.py",
                   "device.py", "playback.py", "profile.py", "selftest.py",
                   "signature.py", "suite.py", "transport.py", "bf_tables.bin"))
OPTIONAL_FILES = frozenset(("_native/__init__.py",))
ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "tool/source_runtime/vendor/miomedia"


def validate(files):
    if not FILES <= set(files) or set(files) - (FILES | OPTIONAL_FILES):
        raise ValueError("SDK input must contain all fixed modules and bf_tables.bin")
    if sum(map(len, files.values())) > 2_000_000:
        raise ValueError("SDK input is too large")
    if len(files["bf_tables.bin"]) != 4168:
        raise ValueError("SDK table resource is incomplete")
    for name, data in files.items():
        if name.endswith(".py"):
            compile(data, name, "exec")
    # 加速动态库可以缺省，suite 导入的 Python 桥本身必须随包提供。
    tree = ast.parse(files["suite.py"], filename="suite.py")
    uses_native = any(isinstance(node, (ast.Import, ast.ImportFrom)) and
                      any(alias.name == "_native" for alias in node.names)
                      for node in ast.walk(tree))
    if uses_native and "_native/__init__.py" not in files:
        raise ValueError("SDK optional accelerator bridge is missing")
    return files


def read_directory(path):
    names = FILES | {name for name in OPTIONAL_FILES if (path / name).is_file()}
    return validate({name: (path / name).read_bytes() for name in names})


def decode_bundle(parts):
    if not all(parts) or len("".join(parts)) > 200_000:
        raise ValueError("Both MIOMEDIA_SDK_BUNDLE_1 and _2 are required")
    raw = base64.b64decode("".join(parts), validate=True)
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        infos = archive.infolist()
        expected = {"miomedia/" + name for name in FILES}
        allowed = expected | {"miomedia/" + name for name in OPTIONAL_FILES}
        names = {i.filename for i in infos}
        if len(infos) != len(names) or not expected <= names or names - allowed:
            raise ValueError("Unexpected SDK archive paths")
        if sum(i.file_size for i in infos) > 2_000_000:
            raise ValueError("SDK archive is too large")
        return validate({name.removeprefix("miomedia/"): archive.read(name) for name in names})


def install(files):
    files = validate(files)
    DEST.mkdir(parents=True, exist_ok=True)
    for name, data in files.items():
        # Fixed destination and atomic writes; algorithm sources remain unchanged.
        temporary = DEST / (name + ".input-tmp")
        temporary.parent.mkdir(parents=True, exist_ok=True)
        temporary.write_bytes(data)
        temporary.replace(DEST / name)
    (DEST.parent / "__init__.py").touch(exist_ok=True)


def export(files):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name in sorted(FILES):
            z.writestr("miomedia/" + name, files[name])
    encoded = base64.b64encode(buffer.getvalue()).decode("ascii")
    midpoint = (len(encoded) + 1) // 2
    parts = (encoded[:midpoint], encoded[midpoint:])
    if max(map(len, parts)) > 48_000:
        raise ValueError("SDK secret chunks exceed supported size")
    out = ROOT / ".dart_tool/private-sdk-input"
    out.mkdir(parents=True, exist_ok=True)
    for index, part in enumerate(parts, 1):
        (out / ("MIOMEDIA_SDK_BUNDLE_%d.txt" % index)).write_text(part, encoding="ascii")
    print("Private SDK input saved under ignored .dart_tool/private-sdk-input")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("sync", "check", "export", "import-env"))
    parser.add_argument("--sdk-directory", type=Path)
    args = parser.parse_args()
    try:
        if args.mode == "import-env":
            install(decode_bundle([os.environ.get("MIOMEDIA_SDK_BUNDLE_%d" % i, "")
                                   for i in (1, 2)]))
        else:
            files = read_directory(args.sdk_directory or DEST)
            if args.mode == "sync":
                if args.sdk_directory is None:
                    raise ValueError("sync requires --sdk-directory")
                install(files)
            elif args.mode == "export":
                export(files)
        print("SDK input OK (%d files; no source contents printed)" % len(files))
    except (OSError, ValueError, SyntaxError, zipfile.BadZipFile) as error:
        # No exception text: malformed sources may embed credentials.
        parser.exit(1, "SDK input unavailable or invalid. See docs/release/build-inputs.zh.md\n")


if __name__ == "__main__":
    main()
