"""Execute the actual workflow gates, including cancellation and invalid scope."""
import os
import pathlib
import re
import subprocess
import textwrap
import unittest

WORKFLOW = pathlib.Path(__file__).resolve().parents[1] / '.github/workflows/ci.yml'


def script(job):
    section = WORKFLOW.read_text().split(f'\n  {job}:\n', 1)[1]
    section = re.split(r'\n  [a-z][a-z-]*:\n', section, maxsplit=1)[0]
    return textwrap.dedent(section.split('        run: |\n', 1)[1])


class GateTest(unittest.TestCase):
    def check_gate(self, job, env, relevant):
        command = ['bash', '--noprofile', '--norc', '-c', script(job)]
        def accepted(values):
            return subprocess.run(command, env={**os.environ, **values},
                                  capture_output=True).returncode == 0
        self.assertTrue(accepted(env))
        for key in relevant:
            for value in ('failure', 'cancelled', 'skipped', ''):
                if value == env[key]:
                    continue
                with self.subTest(job=job, key=key, value=value):
                    self.assertFalse(accepted({**env, key: value}))

    def test_flutter_gate_rejects_failed_cancelled_and_missing_dependencies(self):
        env = dict(SCOPE='success', APP='true', TESTS='success',
                   WEB='success', ANDROID='success')
        self.check_gate('flutter', env, env.keys())

    def test_unrelated_pr_must_explicitly_skip_all_client_jobs(self):
        env = dict(SCOPE='success', APP='false', TESTS='skipped',
                   WEB='skipped', ANDROID='skipped')
        self.check_gate('flutter', env, env.keys())

    def test_native_gate_requires_build_and_all_capture_groups(self):
        env = dict(SCOPE='success', VISUAL='true', BUILD='success', CAPTURES='success')
        self.check_gate('android-ui-review', env, env.keys())

    def test_native_skip_requires_successful_scope_and_explicit_skip(self):
        env = dict(SCOPE='success', VISUAL='false', BUILD='skipped', CAPTURES='skipped')
        self.check_gate('android-ui-review', env, ('SCOPE', 'VISUAL', 'CAPTURES'))


if __name__ == '__main__':
    unittest.main()
