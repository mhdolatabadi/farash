import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/main.dart';

void main() {
  testWidgets('shows the app once the server answers', (tester) async {
    await tester.pumpWidget(FarashApp(healthCheck: () async {}));
    await tester.pumpAndSettle();

    expect(find.text('به فراش خوش آمدید'), findsOneWidget);
  });

  testWidgets('offers a retry while the server is unreachable', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      FarashApp(
        healthCheck: () async {
          calls++;
          if (calls == 1) throw Exception('offline');
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('اتصال به سرور برقرار نشد'), findsOneWidget);

    await tester.tap(find.text('تلاش دوباره'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('به فراش خوش آمدید'), findsOneWidget);
  });

  testWidgets('lays the app out right to left', (tester) async {
    await tester.pumpWidget(FarashApp(healthCheck: () async {}));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('به فراش خوش آمدید'));
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
