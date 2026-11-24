import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Menval branding is consistent across installable clients', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final web = File('web/index.html').readAsStringSync();
    final pwa = File('web/manifest.json').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(pubspec, contains('name: menval'));
    expect(pubspec, contains('assets/icon/menval.png'));
    expect(File('assets/icon/menval.png').existsSync(), isTrue);
    expect(manifest, contains('android:label="منوال"'));
    expect(web, contains('<title>منوال</title>'));
    expect(pwa, contains('"name": "منوال"'));
    expect(pwa, contains('"short_name": "منوال"'));
    // A rebrand must remain an in-place update of the existing Android app.
    expect(gradle, contains('applicationId = "ir.mhdolatabadi.farash"'));
  });
}
