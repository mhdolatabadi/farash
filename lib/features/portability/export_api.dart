import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

abstract interface class ExportApi {
  Future<Uint8List> exportAccount(String token);
}

class ExportException implements Exception {
  const ExportException(this.message);
  final String message;

  @override
  String toString() => message;
}

const exportByteLimit = 32 * 1024 * 1024;

/// A bounded read keeps a malformed or outdated server from exhausting memory.
Future<Uint8List> downloadAccountExport(
  http.Client client,
  Uri uri,
  String token,
) async {
  try {
    return await (() async {
      final request = http.Request('GET', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'application/json';
      final response = await client.send(request);
      if ((response.contentLength ?? 0) > exportByteLimit) {
        throw const ExportException('حجم خروجی بیش از حد مجاز است.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > exportByteLimit) {
          throw const ExportException('حجم خروجی بیش از حد مجاز است.');
        }
        bytes.add(chunk);
      }
      if (response.statusCode != 200) {
        throw ExportException(switch (response.statusCode) {
          401 => 'نشست شما منقضی شده است. دوباره وارد شوید.',
          413 => 'حجم خروجی بیش از حد مجاز است.',
          429 => 'درخواست‌ها زیاد است. یک دقیقه بعد دوباره امتحان کنید.',
          _ => 'دریافت خروجی انجام نشد. دوباره امتحان کنید.',
        });
      }
      final result = bytes.takeBytes();
      final document = jsonDecode(utf8.decode(result));
      if (document is! Map<String, dynamic> ||
          document['format'] != 'farash-export' ||
          document['version'] != 1 ||
          document['records'] is! Map<String, dynamic> ||
          document['preferences'] is! Map<String, dynamic> ||
          document['exported_at'] is! String) {
        throw const ExportException('قالب خروجی شناخته‌شده نیست.');
      }
      return result;
    })().timeout(const Duration(seconds: 30));
  } on ExportException {
    rethrow;
  } on FormatException {
    throw const ExportException('قالب خروجی شناخته‌شده نیست.');
  } on Exception {
    throw const ExportException('اتصال برقرار نشد. دوباره امتحان کنید.');
  }
}
