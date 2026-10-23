import base64
from pathlib import Path
import tempfile
import unittest

from prepare_android_signing import escape_property, prepare


class SigningPreparationTest(unittest.TestCase):
    def test_unicode_and_properties_delimiters_roundtrip_representation(self):
        self.assertEqual(escape_property(' x=ی\\\n'), '\\ x\\=\\u06cc\\\\\\n')
        self.assertEqual(escape_property('😀'), '\\ud83d\\ude00')

    def test_missing_or_malformed_secret_writes_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'android').mkdir()
            env = {'RUNNER_TEMP': directory, 'KEYSTORE_BASE64': '!!!',
                   'STORE_PASSWORD': 'private', 'KEY_PASSWORD': 'private', 'KEY_ALIAS': 'key'}
            with self.assertRaises(ValueError):
                prepare(env, root)
            self.assertFalse((root / 'farash-release.jks').exists())
            env['KEYSTORE_BASE64'] = base64.b64encode(b'fixture').decode()
            del env['KEY_PASSWORD']
            with self.assertRaises(ValueError):
                prepare(env, root)
            self.assertFalse((root / 'android/key.properties').exists())

    def test_private_files_and_exact_key_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'android').mkdir()
            env = {'RUNNER_TEMP': directory, 'KEYSTORE_BASE64': base64.b64encode(b'fixture').decode(),
                   'STORE_PASSWORD': 'ی=private', 'KEY_PASSWORD': ' key', 'KEY_ALIAS': 'main'}
            prepare(env, root)
            self.assertEqual((root / 'farash-release.jks').read_bytes(), b'fixture')
            for path in [root / 'farash-release.jks', root / 'android/key.properties']:
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertIn('storePassword=\\u06cc\\=private\n', (root / 'android/key.properties').read_text())


if __name__ == '__main__':
    unittest.main()
