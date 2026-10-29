import 'calendar_browser_native.dart'
    if (dart.library.js_interop) 'calendar_browser_web.dart'
    as browser;

Future<void> openCalendarAuthorization(Uri uri) =>
    browser.openAuthorization(uri);
