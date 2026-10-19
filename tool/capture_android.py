"""Capture the offline fixture on an ephemeral CI emulator, including OS insets."""
import pathlib
import re
import subprocess
import time
import xml.etree.ElementTree as ET

OUT = pathlib.Path('.impeccable/android-review')
OUT.mkdir(parents=True, exist_ok=True)


def adb(*args):
    return subprocess.check_output(['adb', *args])


def window_xml():
    for _ in range(10):
        try:
            adb('shell', 'uiautomator', 'dump', '/sdcard/window.xml')
            xml = adb('shell', 'cat', '/sdcard/window.xml')
            ET.fromstring(xml)
            return xml
        except (subprocess.CalledProcessError, ET.ParseError):
            time.sleep(2)
    raise RuntimeError('Emulator accessibility tree did not become available')


def capture(name):
    time.sleep(2)
    clear_launcher_anr()
    (OUT / f'{name}.png').write_bytes(adb('exec-out', 'screencap', '-p'))


def clear_launcher_anr(xml=None):
    # API 35's launcher may ANR during font/density changes on hosted runners.
    # Only handle this known system launcher dialog; never hide a Farash ANR.
    if xml is None:
        xml = window_xml()
    root = ET.fromstring(xml)
    if not any(n.get('text') == "Quickstep isn't responding" for n in root.iter('node')):
        return False
    for node in root.iter('node'):
        if node.get('resource-id') == 'android:id/aerr_wait':
            x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
            adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
            time.sleep(2)
            return True
    return False


def tap(label):
    for _ in range(12):
        xml = window_xml()
        (OUT / 'last-window.xml').write_bytes(xml)
        if clear_launcher_anr(xml):
            continue
        for node in ET.fromstring(xml).iter('node'):
            if any(value.split('\n')[0] == label for value in (node.get('text', ''), node.get('content-desc', ''))):
                x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
                adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
                return
        time.sleep(1)
    raise RuntimeError(f'Accessible control not found: {label}')


adb('install', '-r', 'build/app/outputs/flutter-apk/app-debug.apk')
adb('shell', 'am', 'start', '-n', 'ir.mhdolatabadi.farash/.MainActivity')
time.sleep(8)
capture('weaving-light')
adb('shell', 'cmd', 'uimode', 'night', 'yes')
capture('weaving-dark')
adb('shell', 'settings', 'put', 'system', 'font_scale', '2.0')
capture('weaving-large-text')
adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
time.sleep(2)
tap('تمرکز')
capture('focus-dark')
tap('شروع تمرکز')
capture('focus-running')
tap('مکث')
capture('focus-paused')
tap('کارها')
capture('tasks-dark')
tap('مطالعهٔ فصل اول کتاب')
capture('editor-dark')
adb('shell', 'input', 'keyevent', '4')
time.sleep(2)
tap('باز کردن منو پیمایش')
capture('drawer-dark')
adb('shell', 'input', 'keyevent', '4')
time.sleep(2)
tap('زمان‌ها')
capture('times-dark')
adb('shell', 'settings', 'put', 'system', 'font_scale', '2.0')
capture('times-large-text')
adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
time.sleep(2)
tap('شروع برای یک کار')
time.sleep(2)
tap('مطالعهٔ فصل اول کتاب')
capture('tracker-active')
adb('shell', 'settings', 'put', 'system', 'font_scale', '2.0')
capture('tracker-active-large-text')
adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
time.sleep(2)
tap('توقف ثبت زمان')
capture('tracker-stopped')
tap('افزودن بازهٔ دستی')
time.sleep(2)
tap('مطالعهٔ فصل اول کتاب')
capture('time-manual-dark')
adb('shell', 'settings', 'put', 'system', 'font_scale', '2.0')
capture('time-manual-large-text')
adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
time.sleep(2)
tap('انصراف')
adb('shell', 'cmd', 'uimode', 'night', 'no')
capture('times-light')
adb('shell', 'wm', 'size', '1920x1200')
adb('shell', 'wm', 'density', '160')
time.sleep(3)
capture('times-wide-light')
adb('shell', 'wm', 'size', 'reset')
adb('shell', 'wm', 'density', 'reset')

time.sleep(3)
tap('باز کردن منو پیمایش')
tap('پروژهٔ شخصی')
capture('scrum-backlog-light')
adb('shell', 'cmd', 'uimode', 'night', 'yes')
capture('scrum-backlog-dark')
adb('shell', 'settings', 'put', 'system', 'font_scale', '2.0')
capture('scrum-backlog-large-text')
tap('اسپرینت تازه')
capture('scrum-sprint-editor-large-text')
tap('انصراف')
adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
time.sleep(2)
tap('شروع اسپرینت')
tap('شروع')
tap('برد اسپرینت')
capture('scrum-board-dark')
adb('shell', 'wm', 'size', '1920x1200')
adb('shell', 'wm', 'density', '160')
time.sleep(3)
capture('scrum-board-wide')
adb('shell', 'wm', 'size', 'reset')
adb('shell', 'wm', 'density', 'reset')
time.sleep(3)
tap('گزارش و مرور')
capture('scrum-report-dark')
adb('shell', 'settings', 'put', 'system', 'font_scale', '2.0')
capture('scrum-report-large-text')
