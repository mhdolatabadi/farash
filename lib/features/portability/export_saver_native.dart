import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'export_saver.dart';

Future<ExportSaveResult> save(Uint8List bytes) async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    throw UnsupportedError('Export saving is available on Android and Web.');
  }
  final saved = await const MethodChannel(
    'ir.mhdolatabadi.farash/export',
  ).invokeMethod<bool>('saveJson', bytes);
  return saved == true ? ExportSaveResult.saved : ExportSaveResult.cancelled;
}
