import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/tasks/data/checklist.dart';

void main() {
  const description =
      'یادداشت سفر\n- [ ] بلیت\n- [x] چمدان\n* [X] پاسپورت\n-[ ] not an item';

  test('finds checklist lines and their state', () {
    final items = parseChecklist(description);
    expect([for (final i in items) i.text], ['بلیت', 'چمدان', 'پاسپورت']);
    expect([for (final i in items) i.done], [false, true, true]);
    expect([for (final i in items) i.line], [1, 2, 3]);
  });

  test('ticking rewrites only that line', () {
    final ticked = setChecklistItem(description, 1, true);
    expect(ticked.split('\n')[1], '- [x] بلیت');
    expect(setChecklistItem(ticked, 1, false), description);
    // Out-of-range or non-item lines leave the text alone.
    expect(setChecklistItem(description, 0, true), description);
    expect(setChecklistItem(description, 99, true), description);
  });

  test('adding appends an open item', () {
    expect(addChecklistItem('', ' نان '), '- [ ] نان');
    expect(addChecklistItem('خرید', 'شیر'), 'خرید\n- [ ] شیر');
    expect(addChecklistItem('خرید\n', 'شیر'), 'خرید\n- [ ] شیر');
  });

  test('the preview skips checklist lines', () {
    expect(descriptionPreview(description), 'یادداشت سفر');
    expect(descriptionPreview('- [ ] فقط چک‌لیست'), '');
  });

  test('digits read in Persian', () {
    expect(persianDigits('2/15'), '۲/۱۵');
  });
}
