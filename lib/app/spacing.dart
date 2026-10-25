/// One spacing scale on a 4-point grid, and the two keylines every list
/// lines up on: the gutter, where the check circle, section labels and
/// header icons start, and the content keyline, where row titles start.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// The page edge on every screen.
  static const gutter = 16.0;

  /// Where row titles start: the gutter, a 24 control, and 16 of air.
  static const keyline = 56.0;

  /// Above a section label; more than below it, so the label belongs to
  /// the rows it names.
  static const sectionTop = 24.0;
  static const sectionBottom = 4.0;
}
