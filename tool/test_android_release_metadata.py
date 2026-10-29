import unittest

from android_release_metadata import resolve, verify_apk


class AndroidReleaseMetadataTest(unittest.TestCase):
    def env(self, **values):
        return {'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF': 'refs/tags/v1.2.3',
                'GITHUB_RUN_NUMBER': '21', **values}

    def test_tag_and_manual_version_resolve(self):
        self.assertEqual(resolve(self.env()), ('1.2.3', 100021))
        self.assertEqual(resolve(self.env(GITHUB_EVENT_NAME='workflow_dispatch',
                                         GITHUB_REF='refs/heads/main', INPUT_VERSION='2.0.0')), ('2.0.0', 100021))

    def test_main_merge_uses_pubspec_version(self):
        self.assertEqual(resolve(self.env(GITHUB_EVENT_NAME='workflow_run', GITHUB_REF='refs/heads/main',
                                         PUBSPEC_VERSION='0.1.0+1')), ('0.1.0', 100021))
        with self.assertRaises(ValueError):
            resolve(self.env(GITHUB_EVENT_NAME='workflow_run', PUBSPEC_VERSION='0.1'))

    def test_manual_tag_cannot_publish_a_different_version(self):
        with self.assertRaises(ValueError):
            resolve(self.env(GITHUB_EVENT_NAME='workflow_dispatch', INPUT_VERSION='9.9.9'))

    def test_invalid_event_version_and_build_number_fail(self):
        cases = [dict(GITHUB_EVENT_NAME='pull_request'), dict(GITHUB_REF='refs/heads/main'),
                 dict(GITHUB_REF='refs/tags/v01.2.3'), dict(GITHUB_REF='refs/tags/v1.2.3-rc1'),
                 dict(GITHUB_RUN_NUMBER='0'), dict(GITHUB_RUN_NUMBER='-1'),
                 dict(GITHUB_RUN_NUMBER='2100000000')]
        for values in cases:
            with self.subTest(values=values), self.assertRaises(ValueError):
                resolve(self.env(**values))

    def test_apk_matches_exact_expected_identity_and_version(self):
        verify_apk("package: name='ir.mhdolatabadi.farash' versionCode='100021' versionName='1.2.3'\n", '1.2.3', '100021')

    def test_wrong_missing_or_debug_apk_is_rejected(self):
        good = "package: name='ir.mhdolatabadi.farash' versionCode='100021' versionName='1.2.3'\n"
        for bad in [good.replace('farash', 'other'), good.replace('100021', '1'),
                    good.replace('1.2.3', '0.1.0'), good + 'application-debuggable\n', '']:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                verify_apk(bad, '1.2.3', '100021')


if __name__ == '__main__':
    unittest.main()
