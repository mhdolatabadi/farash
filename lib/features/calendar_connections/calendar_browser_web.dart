import 'package:web/web.dart' as web;

Future<void> openAuthorization(Uri uri) async {
  web.window.open(uri.toString(), '_blank', 'noopener,noreferrer');
}
