import 'package:flutter_timezone/flutter_timezone.dart';

/// Tests set this instead of asking the platform.
String? debugTimeZoneOverride;

/// The device's IANA time zone, such as "Asia/Tehran", sent with a timed
/// due so the server knows its local day. Falls back to Tehran, the
/// product's home zone, when the platform cannot say.
Future<String> deviceTimeZone() async {
  final override = debugTimeZoneOverride;
  if (override != null) return override;
  try {
    final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
    return zone.isEmpty ? 'Asia/Tehran' : zone;
  } catch (_) {
    return 'Asia/Tehran';
  }
}
