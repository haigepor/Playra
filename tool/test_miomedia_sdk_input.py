"""Build-input boundary regression tests without real SDK credentials."""
import base64
import io
import unittest
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


if __name__ == "__main__":
    unittest.main()
