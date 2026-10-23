import 'dart:typed_data';

import 'export_saver_native.dart'
    if (dart.library.js_interop) 'export_saver_web.dart'
    as platform;

enum ExportSaveResult { saved, downloadStarted, cancelled }

typedef ExportSaver = Future<ExportSaveResult> Function(Uint8List bytes);

Future<ExportSaveResult> saveAccountExport(Uint8List bytes) =>
    platform.save(bytes);
