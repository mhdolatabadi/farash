"""Verify image preparation failures stop before any rollout is possible."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]


class TransferImagesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.log = self.root / "commands.jsonl"
        stub = '''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['TRANSFER_TEST_LOG'], 'a') as f:
    f.write(json.dumps([name, args]) + '\\n')
if name == 'ssh':
    if 'docker version' in args[-1]:
        print(os.environ.get('TEST_PLATFORM', 'linux/amd64'))
    else:
        sys.stdin.buffer.read()
        sys.exit(int(os.environ.get('FAIL_LOAD', '0')))
elif args[:1] == ['pull']:
    if os.environ.get('FAIL_PULL', '__no_failure__') in args[-1]:
        sys.exit(8)
elif args[:2] == ['image', 'save']:
    sys.stdout.buffer.write(b'test-image-stream')
    sys.exit(int(os.environ.get('FAIL_SAVE', '0')))
'''
        for name in ['docker', 'ssh']:
            path = self.root / name
            path.write_text(stub)
            path.chmod(0o755)
        self.env = {
            **os.environ, 'PATH': f"{self.root}:{os.environ['PATH']}",
            'TRANSFER_TEST_LOG': str(self.log), 'DEPLOY_HOST': 'test.invalid',
            'DEPLOY_USER': 'deploy', 'DEPLOY_SHA': 'a' * 40,
            'DEPLOY_IDENTITY_FILE': '/key with spaces', 'DEPLOY_PORT': '2222',
            'FARASH_IMAGE_REPO': 'ghcr.io/example/menval',
        }

    def run_transfer(self, **env):
        return subprocess.run(
            ['bash', str(SOURCE / 'tool/transfer_deploy_images.sh')],
            env={**self.env, **env}, capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_transfers_both_exact_images_for_destination_platform(self):
        result = self.run_transfer(TEST_PLATFORM='linux/arm64')
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        pulls = [args for command, args in calls if command == 'docker' and args[0] == 'pull']
        images = [f"ghcr.io/example/menval/{service}:{'a' * 40}" for service in ['api', 'web']]
        self.assertEqual(pulls, [['pull', '--platform', 'linux/arm64', image] for image in images])
        saves = [args for command, args in calls if command == 'docker' and args[0] == 'image']
        self.assertEqual(saves, [['image', 'save', *images]])
        ssh = [args for command, args in calls if command == 'ssh']
        self.assertEqual(len(ssh), 2)
        for args in ssh:
            self.assertIn('StrictHostKeyChecking=yes', args)
            self.assertIn('/key with spaces', args)
            self.assertIn('2222', args)
        self.assertIn('pipefail', ssh[-1][-1])
        self.assertIn('docker image load', ssh[-1][-1])

    def test_failed_second_pull_never_transfers_partial_pair(self):
        self.assertNotEqual(self.run_transfer(FAIL_PULL='/web:').returncode, 0)
        self.assertEqual(sum(command == 'ssh' for command, _ in self.calls()), 1)
        self.assertFalse(any(args[:2] == ['image', 'save'] for _, args in self.calls()))

    def test_save_and_remote_load_failures_are_not_masked_by_pipeline(self):
        for failure in ['FAIL_SAVE', 'FAIL_LOAD']:
            with self.subTest(failure=failure):
                self.assertNotEqual(self.run_transfer(**{failure: '7'}).returncode, 0)

    def test_invalid_revision_or_platform_stops_before_pulls(self):
        self.assertNotEqual(self.run_transfer(DEPLOY_SHA='main').returncode, 0)
        self.assertFalse(self.log.exists())
        self.assertNotEqual(self.run_transfer(TEST_PLATFORM='unexpected').returncode, 0)
        self.assertFalse(any(command == 'docker' for command, _ in self.calls()))


if __name__ == '__main__':
    unittest.main()
