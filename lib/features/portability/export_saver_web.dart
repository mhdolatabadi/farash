import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'export_saver.dart';

Future<ExportSaveResult> save(Uint8List bytes) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = 'farash-export-v1.json';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Keep the URL alive long enough for the browser to consume the download.
  Future<void>.delayed(
    const Duration(minutes: 1),
    () => web.URL.revokeObjectURL(url),
  );
  return ExportSaveResult.downloadStarted;
}
