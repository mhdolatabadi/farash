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
            # A failed UIAutomator dump can exit zero and leave an old file.
            # Never navigate from that stale accessibility snapshot.
            adb('shell', 'rm', '-f', '/sdcard/window.xml')
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


def matching_nodes(xml, label):
    # Material may merge a navigation/header label into a multi-line semantic
    # description (including badges). Match the complete line, not substrings.
    matches = [
        node for node in ET.fromstring(xml).iter('node')
        if node.get('enabled') == 'true'
        and any(label in value.splitlines() for value in
                (node.get('text', ''), node.get('content-desc', '')))
    ]
    return sorted(matches, key=lambda n: n.get('clickable') != 'true')


def tap(label, *, wait_for=None):
    for _ in range(12):
        xml = window_xml()
        (OUT / 'last-window.xml').write_bytes(xml)
        if clear_launcher_anr(xml):
            continue
        if wait_for is not None and matching_nodes(xml, wait_for):
            return
        nodes = matching_nodes(xml, label)
        if nodes:
            node = nodes[0]
            x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
            adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
            if wait_for is None:
                return
        time.sleep(1)
    visible = [
        value
        for node in ET.fromstring(xml).iter('node')
        for value in (node.get('text', ''), node.get('content-desc', ''))
        if value
    ]
    raise RuntimeError(
        f'Accessible action did not reach expected state: {label} -> {wait_for}; '
        f'visible: {visible}')


def open_drawer():
    # Closing account/export routes can reveal the already-open drawer.
    # Tapping the hidden menu button again would fail despite a valid screen.
    if matching_nodes(window_xml(), 'حساب و تنظیمات'):
        return
    tap('باز کردن منو پیمایش', wait_for='حساب و تنظیمات')



def scroll_to(label, *, upward=True):
    size = re.search(r'(\d+)x(\d+)', adb('shell', 'wm', 'size').decode())
    width, height = map(int, size.groups())
    start, end = (0.78, 0.30) if upward else (0.30, 0.78)
    for _ in range(8):
        if matching_nodes(window_xml(), label):
            return
        adb('shell', 'input', 'swipe', str(width//2), str(int(height*start)),
            str(width//2), str(int(height*end)), '350')
        time.sleep(1)
    raise RuntimeError(f'Calendar review could not reveal: {label}')


def main():
    adb('install', '-r', 'build/app/outputs/flutter-apk/app-debug.apk')
    adb('shell', 'am', 'start', '-n', 'ir.mhdolatabadi.farash/.MainActivity')
    time.sleep(8)
    capture('weaving-light')
    adb('shell', 'cmd', 'uimode', 'night', 'yes')
    capture('weaving-dark')
    adb('shell', 'settings', 'put', 'system', 'font_scale', '1.3')
    capture('today-font-1_3-dark')
    adb('shell', 'settings', 'put', 'system', 'font_scale', '2.0')
    capture('weaving-large-text')
    adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
    time.sleep(2)
    tap('تمرکز')
    capture('focus-dark')
    tap('شروع تمرکز')
    capture('focus-running')
    tap('مکث', wait_for='شروع تمرکز')
    capture('focus-paused')
    tap('کارها', wait_for='مطالعهٔ فصل اول کتاب')
    capture('tasks-dark')
    tap('مطالعهٔ فصل اول کتاب')
    capture('editor-dark')
    adb('shell', 'input', 'keyevent', '4')
    time.sleep(2)
    open_drawer()
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
    open_drawer()
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
    tap('برد اسپرینت')
    capture('scrum-board-wide')
    adb('shell', 'wm', 'size', 'reset')
    adb('shell', 'wm', 'density', 'reset')
    time.sleep(3)
    tap('گزارش و مرور')
    capture('scrum-report-dark')
    adb('shell', 'settings', 'put', 'system', 'font_scale', '2.0')
    capture('scrum-report-large-text')
    adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
    time.sleep(2)
    open_drawer()
    tap('حساب و تنظیمات')
    tap('تنظیمات تقویم')
    capture('appearance-phone-dark')
    adb('shell', 'settings', 'put', 'system', 'font_scale', '2.0')
    capture('appearance-phone-large-text')
    tap('بستن')
    adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
    time.sleep(2)
    # Explicit synthetic export payload; OS document-provider choice is real.
    tap('حساب و تنظیمات')
    tap('خروجی داده‌های من')
    capture('export-initial-dark')
    tap('آماده‌سازی خروجی')
    capture('export-ready-dark')
    tap('ذخیرهٔ فایل')
    capture('export-android-picker')
    adb('shell', 'input', 'keyevent', '4')
    time.sleep(2)
    adb('shell', 'settings', 'put', 'system', 'font_scale', '2.0')
    capture('export-large-text')
    adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
    adb('shell', 'wm', 'size', '1920x1200')
    adb('shell', 'wm', 'density', '160')
    time.sleep(3)
    capture('export-wide-dark')

    # Search and recurrence use only the explicit synthetic fixture account above.
    tap('بستن')
    adb('shell', 'wm', 'size', 'reset')
    adb('shell', 'wm', 'density', 'reset')
    time.sleep(3)
    open_drawer()
    tap('حساب و تنظیمات')
    tap('اتصال تقویم‌ها', wait_for='حساب Google متصل است.')
    adb('shell', 'cmd', 'uimode', 'night', 'no')
    capture('calendar-phone-light')
    scroll_to('جلسهٔ مطالعه')
    capture('calendar-events-phone-light')
    scroll_to('Google Calendar', upward=False)
    adb('shell', 'cmd', 'uimode', 'night', 'yes')
    capture('calendar-phone-dark')
    adb('shell', 'settings', 'put', 'system', 'font_scale', '1.3')
    capture('calendar-phone-font-1_3-dark')
    adb('shell', 'settings', 'put', 'system', 'font_scale', '2.0')
    capture('calendar-phone-large-text-dark')
    adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
    adb('shell', 'wm', 'size', '1920x1200')
    adb('shell', 'wm', 'density', '160')
    time.sleep(3)
    capture('calendar-wide-dark')
    adb('shell', 'wm', 'size', 'reset')
    adb('shell', 'wm', 'density', 'reset')
    adb('shell', 'input', 'keyevent', '4')
    time.sleep(3)
    open_drawer()
    tap('جست‌وجو و فیلترها')
    capture('search-phone-ime-dark')
    # Dismiss only the IME; the saved chip fills the real Persian query field.
    adb('shell', 'input', 'keyevent', '4')
    time.sleep(2)
    tap('مطالعه')
    capture('search-phone-dark')
    adb('shell', 'cmd', 'uimode', 'night', 'no')
    capture('search-phone-light')
    adb('shell', 'settings', 'put', 'system', 'font_scale', '2.0')
    capture('search-phone-large-text')
    adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
    adb('shell', 'wm', 'size', '1920x1200')
    adb('shell', 'wm', 'density', '160')
    time.sleep(3)
    capture('search-wide-light')
    adb('shell', 'wm', 'size', 'reset')
    adb('shell', 'wm', 'density', 'reset')
    time.sleep(3)
    tap('مطالعهٔ فصل اول کتاب')
    tap('تکرار کار')
    tap('تنظیم تکرار')
    capture('recurrence-editor-phone-light')
    adb('shell', 'settings', 'put', 'system', 'font_scale', '2.0')
    capture('recurrence-editor-large-text')


if __name__ == '__main__':
    main()
