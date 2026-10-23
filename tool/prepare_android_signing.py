"""Build a private Java properties file without logging signing values."""
import base64
import os
from pathlib import Path


def escape_property(value):
    value = (value.replace('\\', '\\\\').replace('\n', '\\n')
             .replace('\r', '\\r').replace('\t', '\\t')
             .replace('=', '\\=').replace(':', '\\:').replace(' ', '\\ '))
    raw = value.encode('utf-16-be')
    units = [int.from_bytes(raw[i:i + 2], 'big') for i in range(0, len(raw), 2)]
    return ''.join(chr(unit) if unit < 128 else '\\u%04x' % unit for unit in units)


def prepare(environment, root):
    names = ['KEYSTORE_BASE64', 'STORE_PASSWORD', 'KEY_PASSWORD', 'KEY_ALIAS']
    if any(not environment.get(name) for name in names):
        raise ValueError('All Android signing secrets are required.')
    # Decode before writing either file, so malformed input leaves no partial key.
    key = base64.b64decode(environment['KEYSTORE_BASE64'], validate=True)
    if not key:
        raise ValueError('The Android keystore is empty.')
    key_path = Path(environment['RUNNER_TEMP']) / 'farash-release.jks'
    properties_path = Path(root) / 'android/key.properties'
    key_path.write_bytes(key)
    key_path.chmod(0o600)
    values = {'storeFile': str(key_path), 'storePassword': environment['STORE_PASSWORD'],
              'keyPassword': environment['KEY_PASSWORD'], 'keyAlias': environment['KEY_ALIAS']}
    properties_path.write_text(''.join(k + '=' + escape_property(v) + '\n'
                                       for k, v in values.items()), encoding='ascii')
    properties_path.chmod(0o600)


if __name__ == '__main__':
    os.umask(0o077)
    prepare(os.environ, Path.cwd())
