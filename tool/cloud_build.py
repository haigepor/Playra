"""Build and verify Playra cloud artifacts without handling signing credentials."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import struct
import subprocess
import tarfile
from urllib.parse import urlsplit
import zipfile

TARGETS = {
    "ios": "macos-15",
    "web": "ubuntu-latest",
    "macos": "macos-15",
    "linux": "ubuntu-24.04",
    "windows": "windows-2022",
}


def plan(target, event="workflow_dispatch"):
    if event == "push" or target == "android":
        return {"matrix": {"include": []}, "cloud": False, "android": True}
    if target == "cloud":
        selected = list(TARGETS)
    elif target in TARGETS:
        selected = [target]
    else:
        raise ValueError("Unsupported build target")
    return {"matrix": {"include": [
        {"platform": name, "runner": TARGETS[name]} for name in selected
    ]}, "cloud": True, "android": False}


def version(root):
    match = re.search(r"^version: (\d+\.\d+\.\d+)\+(\d+)\s*$",
                      (root / "pubspec.yaml").read_text(encoding="utf-8"), re.M)
    if not match:
        raise ValueError("Expected a stable application version and build number")
    return match.groups()


def runtime_define(value):
    if not value:
        return []
    parsed = urlsplit(value)
    # Do not print this value: the configured service endpoint can be private.
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or
            parsed.password or parsed.query or parsed.fragment or
            not re.fullmatch(r"https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?(?:/[A-Za-z0-9._~%/-]*)?", value)):
        raise ValueError("Runtime endpoint must be an HTTPS base URL without credentials")
    if parsed.port is not None and not 1 <= parsed.port <= 65535:
        raise ValueError("Invalid runtime endpoint port")
    return ["--dart-define=PLAYRA_SOURCE_RUNTIME_URL=" + value]


def macho_arches(data):
    if len(data) < 8:
        raise ValueError("Missing Mach-O executable header")
    names = {0x0100000C: "arm64", 0x01000007: "x86_64"}
    if data[:4] in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe"):
        return [names.get(struct.unpack_from("<I", data, 4)[0], "unknown")]
    if data[:4] in (b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce"):
        return [names.get(struct.unpack_from(">I", data, 4)[0], "unknown")]
    if data[:4] in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        count = struct.unpack_from(">I", data, 4)[0]
        width = 32 if data[:4] == b"\xca\xfe\xba\xbf" else 20
        if not 1 <= count <= 16 or len(data) < 8 + count * width:
            raise ValueError("Invalid universal Mach-O header")
        return [names.get(struct.unpack_from(">I", data, 8 + i * width)[0], "unknown")
                for i in range(count)]
    raise ValueError("Expected a Mach-O executable")


def verify_ios(archive, expected_version=None, expected_build=None):
    with zipfile.ZipFile(archive) as package:
        if package.testzip() is not None:
            raise ValueError("IPA CRC verification failed")
        paths = package.namelist()
        for name in paths:
            parts = PurePosixPath(name).parts
            if name.startswith("/") or ".." in parts or "\\" in name or ":" in name:
                raise ValueError("Unsafe IPA archive path")
        roots = {"/".join(PurePosixPath(name).parts[:2]) for name in paths
                 if name.startswith("Payload/") and len(PurePosixPath(name).parts) > 2
                 and PurePosixPath(name).parts[1].endswith(".app")}
        if len(roots) != 1:
            raise ValueError("IPA must contain exactly one Payload application")
        app = roots.pop()
        if any(name.startswith(app + "/_CodeSignature/") or
               name == app + "/embedded.mobileprovision" for name in paths):
            raise ValueError("Expected an unsigned application without provisioning")
        info = plistlib.loads(package.read(app + "/Info.plist"))
        if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
            raise ValueError("Expected an iPhoneOS device application")
        executable = info["CFBundleExecutable"]
        if PurePosixPath(executable).name != executable or not executable:
            raise ValueError("Invalid executable name")
        if info.get("CFBundleDisplayName", info.get("CFBundleName")) != "Playra":
            raise ValueError("Unexpected application display name")
        app_version, build = str(info["CFBundleShortVersionString"]), str(info["CFBundleVersion"])
        if expected_version is not None and app_version != expected_version:
            raise ValueError("IPA version mismatch")
        if expected_build is not None and build != str(expected_build):
            raise ValueError("IPA build number mismatch")
        arches = macho_arches(package.read(app + "/" + executable)[:1024])
        if "arm64" not in arches or "x86_64" in arches:
            raise ValueError("Expected an arm64 device application, not a simulator")
        return {"version": app_version, "build_number": build, "bundle_id": info["CFBundleIdentifier"],
                "architectures": arches, "minimum_os": info.get("MinimumOSVersion"),
                "signing": "unsigned", "zip_crc": "pass"}


def zip_tree(target, source, prefix=""):
    # Preserve framework symlinks and executable permissions in Apple packages.
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(source.rglob("*")):
            name = (PurePosixPath(prefix) / path.relative_to(source).as_posix()).as_posix()
            if path.is_symlink():
                item = zipfile.ZipInfo(name)
                item.create_system = 3
                item.external_attr = path.lstat().st_mode << 16
                archive.writestr(item, os.readlink(path))
            else:
                archive.write(path, name)


def unique_app(directory):
    values = list(directory.glob("*.app"))
    if len(values) != 1:
        raise ValueError("Expected exactly one built application")
    return values[0]


def package(root, platform):
    app_version, build_number = version(root)
    sha = os.environ.get("GITHUB_SHA") or subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    if not re.fullmatch(r"[0-9a-fA-F]{40}", sha):
        raise ValueError("Expected a complete source commit SHA")
    output = root / "build/playra-artifacts"
    output.mkdir(parents=True, exist_ok=True)
    stem = f"Playra-{app_version}-{build_number}-{platform}"
    details = {}
    if platform == "ios":
        app = unique_app(root / "build/ios/iphoneos")
        target = output / f"{stem}-unsigned-{sha[:8]}.ipa"
        zip_tree(target, app, "Payload/" + app.name)
        details = verify_ios(target, app_version, build_number)
        signature = subprocess.run(["codesign", "-dv", str(app)], capture_output=True)
        if signature.returncode == 0:
            raise ValueError("The device application unexpectedly has a code signature")
    elif platform == "windows":
        source = root / "build/windows/x64/runner/Release"
        for required in ["Playra.exe", "flutter_windows.dll", "data/flutter_assets"]:
            if not (source / required).exists():
                raise ValueError("Missing Windows application component")
        target = output / f"{stem}-{sha[:8]}.zip"
        zip_tree(target, source)
        with zipfile.ZipFile(target) as archive:
            if archive.testzip() is not None:
                raise ValueError("Windows ZIP CRC verification failed")
    elif platform in ("web", "linux", "macos"):
        if platform == "macos":
            source = unique_app(root / "build/macos/Build/Products/Release")
            info = plistlib.loads((source / "Contents/Info.plist").read_bytes())
            details = {"architectures": macho_arches((source / "Contents/MacOS" / info["CFBundleExecutable"]).read_bytes()[:1024]),
                       "signing": "not-notarized"}
            archive_name = source.name
        else:
            source = root / ("build/web" if platform == "web" else "build/linux/x64/release/bundle")
            required = ["index.html", "main.dart.js"] if platform == "web" else ["Playra", "lib", "data"]
            if any(not (source / name).exists() for name in required):
                raise ValueError("Missing application bundle components")
            archive_name = "."
        target = output / f"{stem}-{sha[:8]}.tar.gz"
        with tarfile.open(target, "w:gz") as archive:
            archive.add(source, arcname=archive_name)
        with tarfile.open(target) as archive:
            if not archive.getmembers():
                raise ValueError("Empty application archive")
    else:
        raise ValueError("Unsupported package platform")
    flutter = shutil.which("flutter")
    raw = subprocess.check_output([flutter, "--version", "--machine"], text=True)
    sdk = json.loads(raw[raw.index("{"):raw.rindex("}") + 1])
    receipt = {"platform": platform, "source_sha": sha, "version": app_version,
               "build_number": build_number, "artifact": target.name,
               "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
               "size_bytes": target.stat().st_size, "flutter_version": sdk["frameworkVersion"],
               "dart_version": sdk["dartSdkVersion"], "run_id": os.environ.get("GITHUB_RUN_ID"),
               "runtime_configured": bool(os.environ.get("PLAYRA_SOURCE_RUNTIME_URL")), **details}
    if platform in ("ios", "macos"):
        receipt["xcode"] = subprocess.check_output(["xcodebuild", "-version"], text=True).strip()
    target.with_suffix(target.suffix + ".json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    (output / "SHA256SUMS").write_text(receipt["sha256"] + "  " + target.name + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2))
    return target


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=["plan", "build", "package", "verify-ios"])
    parser.add_argument("archive", nargs="?")
    args = parser.parse_args()
    root = Path.cwd()
    if args.operation == "plan":
        values = plan(os.environ.get("PLAYRA_BUILD_TARGET", ""), os.environ.get("PLAYRA_BUILD_EVENT", "workflow_dispatch"))
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            for name, value in values.items():
                output.write(name + "=" + json.dumps(value, separators=(",", ":")) + "\n")
    elif args.operation == "verify-ios":
        print(json.dumps(verify_ios(args.archive), indent=2))
    else:
        platform = os.environ.get("PLAYRA_BUILD_PLATFORM", "")
        if platform not in TARGETS:
            raise ValueError("Unsupported build platform")
        if args.operation == "package":
            package(root, platform)
            return
        command = [shutil.which("flutter"), "build", platform, "--release", "--no-pub",
                   "--dart-define=PLAYRA_DIAGNOSTICS=false"]
        if platform == "ios":
            command.append("--no-codesign")
        if platform == "web":
            command.append("--no-wasm-dry-run")
        command.extend(runtime_define(os.environ.get("PLAYRA_SOURCE_RUNTIME_URL", "")))
        subprocess.run(command, check=True)


if __name__ == "__main__":
    main()
