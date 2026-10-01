const _digits = '۰۱۲۳۴۵۶۷۸۹';

/// Writes the ASCII digits of [value] as Persian digits.
String persianDigits(Object value) => value.toString().replaceAllMapped(
  RegExp('[0-9]'),
  (m) => _digits[m[0]!.codeUnitAt(0) - 48],
);
