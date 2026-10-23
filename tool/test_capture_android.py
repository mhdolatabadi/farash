"""Host-side regressions for the native capture driver's semantic navigation."""
import importlib.util
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'capture_android', pathlib.Path(__file__).with_name('capture_android.py'))
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


def tree(*nodes):
    return ('<hierarchy>' + ''.join(
        f'<node enabled="{enabled}" clickable="{clickable}" '
        f'content-desc="{label}" bounds="[0,0][100,100]" />'
        for label, enabled, clickable in nodes) + '</hierarchy>').encode()


class CaptureNavigationTest(unittest.TestCase):
    def test_merged_labels_match_complete_lines_and_prefer_action(self):
        xml = tree(('عنوان', 'true', 'false'),
                   ('عنوان&#10;برگه ۲ از ۴', 'true', 'true'),
                   ('عنوان', 'false', 'true'))
        nodes = capture.matching_nodes(xml, 'عنوان')
        self.assertEqual(len(nodes), 2)
        self.assertEqual(nodes[0].get('clickable'), 'true')
        self.assertEqual(capture.matching_nodes(xml, 'عنوا'), [])

    def test_dump_removes_old_snapshot_before_reading(self):
        calls = []
        def adb(*args):
            calls.append(args)
            if args[:2] == ('shell', 'cat'):
                return b'<hierarchy />'
            return b''
        with patch.object(capture, 'adb', side_effect=adb):
            capture.window_xml()
        self.assertEqual(calls[0], ('shell', 'rm', '-f', '/sdcard/window.xml'))
        self.assertEqual(calls[1][1], 'uiautomator')
        self.assertEqual(calls[2][1], 'cat')

    def test_missing_fresh_dump_is_retried_instead_of_using_stale_tree(self):
        reads = 0
        def adb(*args):
            nonlocal reads
            if args[:2] == ('shell', 'cat'):
                reads += 1
                if reads == 1:
                    raise subprocess.CalledProcessError(1, args)
                return b'<hierarchy />'
            return b''
        with patch.object(capture, 'adb', side_effect=adb), \
                patch.object(capture.time, 'sleep'):
            self.assertEqual(capture.window_xml(), b'<hierarchy />')
        self.assertEqual(reads, 2)

    def test_tap_waits_for_confirmed_state_before_returning(self):
        before = tree(('مکث', 'true', 'true'))
        after = tree(('شروع تمرکز', 'true', 'true'))
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(capture, 'OUT', pathlib.Path(directory)), \
                patch.object(capture, 'window_xml', side_effect=[before, after]), \
                patch.object(capture, 'adb') as adb, \
                patch.object(capture.time, 'sleep'):
            capture.tap('مکث', wait_for='شروع تمرکز')
        adb.assert_called_once_with('shell', 'input', 'tap', '50', '50')

    def test_existing_drawer_needs_no_hidden_menu_tap(self):
        with patch.object(capture, 'window_xml', return_value=tree(
                ('حساب و تنظیمات', 'true', 'true'))), \
                patch.object(capture, 'tap') as tap:
            capture.open_drawer()
        tap.assert_not_called()


if __name__ == '__main__':
    unittest.main()
