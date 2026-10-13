"""Build-input boundary regression tests without real SDK credentials."""
import base64
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import miomedia_sdk_input as sdk


class SdkInputTests(unittest.TestCase):
    def bundle(self, extra=None, missing=None):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w") as archive:
            for name in sdk.FILES:
                if name != missing:
                    archive.writestr("miomedia/" + name,
                                     bytes(4168) if name.endswith(".bin") else b"# fixture\n")
            if extra:
                archive.writestr(extra, b"bad")
        encoded = base64.b64encode(stream.getvalue()).decode("ascii")
        return [encoded[:100], encoded[100:]]

    def test_round_trip_keeps_bytes(self):
        files = sdk.decode_bundle(self.bundle())
        self.assertEqual(set(files), sdk.FILES)
        self.assertEqual(files["suite.py"], b"# fixture\n")

    def test_path_traversal_rejected_before_install(self):
        with self.assertRaises(ValueError):
            sdk.decode_bundle(self.bundle(extra="../config.py"))

    def test_incomplete_sdk_rejected(self):
        with self.assertRaises(ValueError):
            sdk.decode_bundle(self.bundle(missing="bf_tables.bin"))

    def test_missing_secret_chunk_rejected(self):
        with self.assertRaises(ValueError):
            sdk.decode_bundle([self.bundle()[0], ""])

    def test_native_bridge_survives_directory_sync(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source'
            source.mkdir()
            for name in sdk.FILES:
                (source / name).write_bytes(bytes(4168) if name.endswith('.bin') else b'# fixture\n')
            (source / 'suite.py').write_bytes(b'from . import _native\n')
            (source / '_native').mkdir()
            bridge = b'# optional native accelerator bridge\n'
            (source / '_native/__init__.py').write_bytes(bridge)
            files = sdk.read_directory(source)
            self.assertEqual(files['_native/__init__.py'], bridge)
            with patch.object(sdk, 'DEST', root / 'installed'):
                sdk.install(files)
                self.assertEqual((sdk.DEST / '_native/__init__.py').read_bytes(), bridge)

    def test_native_bridge_can_be_imported_from_bundle(self):
        files = sdk.decode_bundle(self.bundle(extra='miomedia/_native/__init__.py'))
        self.assertEqual(files['_native/__init__.py'], b'bad')

    def test_suite_referencing_missing_native_bridge_is_rejected(self):
        files = sdk.decode_bundle(self.bundle())
        files['suite.py'] = b'try:\n    from . import _native\nexcept ImportError:\n    import _native\n'
        with self.assertRaises(ValueError):
            sdk.validate(files)


if __name__ == "__main__":
    unittest.main()
