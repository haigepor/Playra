import io
import plistlib
import struct
import unittest
import zipfile
from cloud_build import plan, runtime_define, verify_ios, macho_arches, flutter_version


def ipa(*, version="2.3.8", signed=False, simulator=False, unsafe=False, executable=None,
        supported_platform="iPhoneOS"):
    value = io.BytesIO()
    info = {"CFBundleExecutable": "Runner", "CFBundleDisplayName": "Playra",
            "CFBundleShortVersionString": version, "CFBundleVersion": "20308",
            "CFBundleIdentifier": "com.example.kazumi", "MinimumOSVersion": "13.0",
            "CFBundleSupportedPlatforms": [supported_platform]}
    with zipfile.ZipFile(value, "w") as archive:
        archive.writestr("Payload/Runner.app/Info.plist", plistlib.dumps(info))
        archive.writestr("Payload/Runner.app/Runner", executable if executable is not None else
                         b"\xcf\xfa\xed\xfe" + struct.pack("<I", 0x01000007 if simulator else 0x0100000C) + bytes(32))
        if signed:
            archive.writestr("Payload/Runner.app/_CodeSignature/CodeResources", b"signature")
        if unsafe:
            archive.writestr("../escaped", b"invalid")
    value.seek(0)
    return value


class CloudBuildTests(unittest.TestCase):
    def test_sdk_pin_is_read_without_platform_yaml_tools(self):
        self.assertEqual(flutter_version("environment:\n  flutter: 3.47.6\n"), "3.47.6")
        with self.assertRaises(ValueError):
            flutter_version("environment:\n  flutter: stable\n")

    def test_cloud_does_not_require_android_signing_and_targets_are_isolated(self):
        targets = plan("cloud")
        self.assertFalse(targets["android"])
        self.assertEqual({t["platform"] for t in targets["matrix"]["include"]},
                         {"ios", "web", "macos", "linux", "windows"})
        self.assertEqual(plan("ios")["matrix"]["include"], [{"platform": "ios", "runner": "macos-15"}])
        self.assertTrue(plan("", "push")["android"])
        with self.assertRaises(ValueError):
            plan("ios; injected-command")

    def test_endpoint_accepts_only_credential_free_https_base(self):
        self.assertEqual(runtime_define(""), [])
        self.assertEqual(runtime_define("https://example.test/v1/"),
                         ["--dart-define=PLAYRA_SOURCE_RUNTIME_URL=https://example.test/v1/"])
        for value in ["http://example.test", "https://user:secret@example.test", "https://example.test/?token=x",
                      "https://example.test/#fragment", "https://example.test/;bad", "https://example.test:99999"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                runtime_define(value)

    def test_unsigned_device_ipa_reports_real_version_and_arm64(self):
        result = verify_ios(ipa(), "2.3.8", "20308")
        self.assertEqual(result["architectures"], ["arm64"])
        self.assertEqual(result["signing"], "unsigned")
        self.assertEqual(result["bundle_id"], "com.example.kazumi")

    def test_rejects_signed_simulator_wrong_version_and_traversal(self):
        for value in [ipa(signed=True), ipa(simulator=True), ipa(supported_platform="iPhoneSimulator"),
                      ipa(version="2.3.7"), ipa(unsafe=True),
                      ipa(executable=b"a placeholder is not a built application")]:
            with self.subTest(), self.assertRaises(ValueError):
                verify_ios(value, "2.3.8", "20308")

    def test_universal_binary_inspection_detects_simulator_arch(self):
        header = b"\xca\xfe\xba\xbe" + struct.pack(">I", 2)
        header += struct.pack(">IIIII", 0x0100000C, 0, 48, 4, 0)
        header += struct.pack(">IIIII", 0x01000007, 0, 52, 4, 0)
        self.assertEqual(macho_arches(header), ["arm64", "x86_64"])
        with self.assertRaises(ValueError):
            macho_arches(b"not executable")


if __name__ == "__main__":
    unittest.main()
