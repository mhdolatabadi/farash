/// Jalali (Solar Hijri) dates, converted with the 33-year break table of
/// the jalaali-js algorithm (valid for Jalali years -61 to 3177).
class JalaliDate {
  const JalaliDate(this.year, this.month, this.day);

  factory JalaliDate.fromGregorian(DateTime date) =>
      _fromDayNumber(_gregorianToDayNumber(date.year, date.month, date.day));

  final int year;

  /// 1 is Farvardin, 12 is Esfand.
  final int month;
  final int day;

  /// The same day in the Gregorian calendar, at local midnight.
  DateTime toGregorian() {
    final r = _jalCal(year);
    final dayNumber =
        _gregorianToDayNumber(r.gregorianYear, 3, r.march) +
        (month - 1) * 31 -
        _div(month, 7) * (month - 7) +
        day -
        1;
    final (y, m, d) = _dayNumberToGregorian(dayNumber);
    return DateTime(y, m, d);
  }

  static bool isLeapYear(int year) => _jalCal(year).leap == 0;

  static int monthLength(int year, int month) {
    if (month <= 6) return 31;
    if (month <= 11) return 30;
    return isLeapYear(year) ? 30 : 29;
  }

  @override
  bool operator ==(Object other) =>
      other is JalaliDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '$year/$month/$day';
}

const _breaks = [
  -61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181, 1210, //
  1635, 2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178,
];

// Truncating division and remainder, as in the reference algorithm.
int _div(int a, int b) => a ~/ b;
int _mod(int a, int b) => a - (a ~/ b) * b;

({int leap, int gregorianYear, int march}) _jalCal(int jy) {
  if (jy < _breaks.first || jy >= _breaks.last) {
    throw RangeError.range(jy, _breaks.first, _breaks.last - 1, 'year');
  }
  final gy = jy + 621;
  var leapJ = -14;
  var jp = _breaks.first;
  var jump = 0;
  for (var i = 1; i < _breaks.length; i++) {
    final jm = _breaks[i];
    jump = jm - jp;
    if (jy < jm) break;
    leapJ += _div(jump, 33) * 8 + _div(_mod(jump, 33), 4);
    jp = jm;
  }
  var n = jy - jp;
  leapJ += _div(n, 33) * 8 + _div(_mod(n, 33) + 3, 4);
  if (_mod(jump, 33) == 4 && jump - n == 4) leapJ += 1;
  final leapG = _div(gy, 4) - _div((_div(gy, 100) + 1) * 3, 4) - 150;
  final march = 20 + leapJ - leapG;
  if (jump - n < 6) n = n - jump + _div(jump + 4, 33) * 33;
  var leap = _mod(_mod(n + 1, 33) - 1, 4);
  if (leap == -1) leap = 4;
  return (leap: leap, gregorianYear: gy, march: march);
}

int _gregorianToDayNumber(int gy, int gm, int gd) {
  var d =
      _div((gy + _div(gm - 8, 6) + 100100) * 1461, 4) +
      _div(153 * _mod(gm + 9, 12) + 2, 5) +
      gd -
      34840408;
  d = d - _div(_div(gy + 100100 + _div(gm - 8, 6), 100) * 3, 4) + 752;
  return d;
}

(int, int, int) _dayNumberToGregorian(int dayNumber) {
  var j = 4 * dayNumber + 139361631;
  j = j + _div(_div(4 * dayNumber + 183187720, 146097) * 3, 4) * 4 - 3908;
  final i = _div(_mod(j, 1461), 4) * 5 + 308;
  final gd = _div(_mod(i, 153), 5) + 1;
  final gm = _mod(_div(i, 153), 12) + 1;
  final gy = _div(j, 1461) - 100100 + _div(8 - gm, 6);
  return (gy, gm, gd);
}

JalaliDate _fromDayNumber(int dayNumber) {
  final (gy, _, _) = _dayNumberToGregorian(dayNumber);
  var jy = gy - 621;
  final r = _jalCal(jy);
  var k = dayNumber - _gregorianToDayNumber(gy, 3, r.march);
  if (k >= 0) {
    if (k <= 185) return JalaliDate(jy, 1 + _div(k, 31), _mod(k, 31) + 1);
    k -= 186;
  } else {
    jy -= 1;
    k += 179;
    if (r.leap == 1) k += 1;
  }
  return JalaliDate(jy, 7 + _div(k, 30), _mod(k, 30) + 1);
}
