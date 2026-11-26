import unittest

from ci_scope import scope


class ScopeTest(unittest.TestCase):
    def test_docs_and_server_changes_avoid_android_but_unknown_paths_do_not(self):
        self.assertEqual(scope(['README.md', 'docs/setup.md', 'server/main.go'],
                               'pull_request'), (False, False))
        for path in ('lib/app.dart', 'assets/font.ttf', 'pubspec.lock',
                     'android/app/build.gradle.kts', 'web/index.html',
                     '.github/workflows/ci.yml', 'tool/capture_android.py',
                     'deploy/Dockerfile.web', 'new-build-system/config'):
            with self.subTest(path=path):
                self.assertEqual(scope([path], 'pull_request'), (True, True))

    def test_test_only_changes_keep_full_tests_and_builds(self):
        self.assertEqual(scope(['test/home_screen_test.dart'], 'pull_request'),
                         (True, False))
        self.assertEqual(scope(['test/home_screen_test.dart', 'lib/main.dart'],
                               'pull_request'), (True, True))

    def test_main_manual_and_empty_diffs_never_skip(self):
        for event in ('push', 'workflow_dispatch', 'unknown'):
            self.assertEqual(scope(['README.md'], event), (True, True))
        self.assertEqual(scope([], 'pull_request'), (True, True))


if __name__ == '__main__':
    unittest.main()
