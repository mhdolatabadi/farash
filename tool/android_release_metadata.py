"""Resolve bounded release identifiers and verify the built APK metadata."""
import os
from pathlib import Path
import re
import sys

VERSION = re.compile(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z')


def resolve(env):
    event = env.get('GITHUB_EVENT_NAME', '')
    ref = env.get('GITHUB_REF', '')
    selected = env.get('INPUT_VERSION', '')
    if event == 'push' and ref.startswith('refs/tags/v'):
        version = ref.removeprefix('refs/tags/v')
    elif event == 'workflow_dispatch':
        version = selected
        if ref.startswith('refs/tags/') and ref != f'refs/tags/v{version}':
            raise ValueError('Selected version must match the checked-out tag.')
    elif event == 'workflow_run':
        # Builds after each merge to main take the version name from pubspec.yaml.
        version = env.get('PUBSPEC_VERSION', '').split('+', 1)[0]
    else:
        raise ValueError('Release requires a version tag or manual dispatch.')
    if not VERSION.fullmatch(version):
        raise ValueError('Expected major.minor.patch without leading zeroes.')
    run = env.get('GITHUB_RUN_NUMBER', '')
    if not re.fullmatch(r'[1-9][0-9]*', run):
        raise ValueError('Workflow run number must be positive.')
    code = 100000 + int(run)
    if code > 2_100_000_000:
        raise ValueError('Android version code budget exhausted.')
    return version, code


def pubspec_version(root):
    text = (Path(root) / 'pubspec.yaml').read_text()
    match = re.search(r'^version:\s*(\S+)\s*$', text, re.MULTILINE)
    return match.group(1) if match else ''


def verify_apk(text, version, code):
    package = next((line for line in text.splitlines() if line.startswith('package: ')), '')
    fields = dict(re.findall(r"([A-Za-z]+)='([^']*)'", package))
    if fields.get('name') != 'ir.mhdolatabadi.farash':
        raise ValueError('Unexpected APK application ID.')
    if fields.get('versionName') != version or fields.get('versionCode') != str(code):
        raise ValueError('APK version does not match the selected release.')
    if any(line.startswith('application-debuggable') for line in text.splitlines()):
        raise ValueError('Debuggable APK rejected.')


def main():
    if sys.argv[1:] == ['resolve']:
        version, code = resolve({**os.environ, 'PUBSPEC_VERSION': pubspec_version(Path.cwd())})
        with Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
            output.write(f'name={version}\ncode={code}\n')
    elif len(sys.argv) == 3 and sys.argv[1] == 'verify-apk':
        verify_apk(Path(sys.argv[2]).read_text(), os.environ['VERSION_NAME'], os.environ['VERSION_CODE'])
    else:
        raise ValueError('Expected resolve or verify-apk <aapt-output>.')


if __name__ == '__main__':
    try:
        main()
    except (KeyError, ValueError) as error:
        sys.exit(str(error))
