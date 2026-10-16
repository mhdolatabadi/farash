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


def capture(name):
    time.sleep(2)
    (OUT / f'{name}.png').write_bytes(adb('exec-out', 'screencap', '-p'))


def tap(label):
    for _ in range(12):
        adb('shell', 'uiautomator', 'dump', '/sdcard/window.xml')
        xml = adb('shell', 'cat', '/sdcard/window.xml')
        (OUT / 'last-window.xml').write_bytes(xml)
        for node in ET.fromstring(xml).iter('node'):
            if label in (node.get('text', ''), node.get('content-desc', '')):
                x1, y1, x2, y2 = map(int, re.findall(r'\d+', node.get('bounds')))
                adb('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
                return
        time.sleep(1)
    raise RuntimeError(f'Accessible control not found: {label}')


adb('install', '-r', 'build/app/outputs/flutter-apk/app-debug.apk')
adb('shell', 'am', 'start', '-n', 'ir.mhdolatabadi.farash/.MainActivity')
time.sleep(8)
capture('garden-light')
adb('shell', 'cmd', 'uimode', 'night', 'yes')
capture('garden-dark')
adb('shell', 'settings', 'put', 'system', 'font_scale', '2.0')
capture('garden-large-text')
adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
time.sleep(2)
tap('تمرکز')
capture('focus-dark')
tap('شروع تمرکز')
capture('focus-running')
tap('مکث')
capture('focus-paused')
adb('shell', 'cmd', 'uimode', 'night', 'no')
