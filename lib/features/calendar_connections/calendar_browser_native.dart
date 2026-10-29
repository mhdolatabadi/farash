import 'package:flutter/services.dart';

const _channel = MethodChannel('ir.mhdolatabadi.farash/calendar');
Future<void> openAuthorization(Uri uri) async {
  await _channel.invokeMethod<void>('authorize', uri.toString());
}
