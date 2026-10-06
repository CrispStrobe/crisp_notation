/// Physical sizes: the layout works in staff spaces, and these map a staff
/// space to millimetres so a page can be set on real paper at a real staff
/// size.
library;

import 'page_layout.dart';

/// The physical size of one staff space: the distance between two adjacent
/// staff lines, a quarter of the staff height.
class Spatium {
  /// One staff space, in millimetres.
  final double millimetres;

  /// A staff space of [millimetres].
  const Spatium(this.millimetres)
      : assert(millimetres > 0, 'a staff space must be positive');

  /// The staff space of a staff [height] millimetres tall (bottom line to top
  /// line, four spaces).
  factory Spatium.staffHeight(double height) => Spatium(height / 4);

  /// A traditional rastral size, 0 (largest) to 8 (smallest), by its staff
  /// height: 9.2, 7.9, 7.4, 7.0, 6.5, 6.0, 5.5, 4.8 and 3.7 mm. Sizes 2–3 are
  /// usual for solo parts, 5–6 for scores, 7–8 for cues, ossias and pocket
  /// scores.
  factory Spatium.rastral(int size) {
    const heights = [9.2, 7.9, 7.4, 7.0, 6.5, 6.0, 5.5, 4.8, 3.7];
    if (size < 0 || size >= heights.length) {
      throw RangeError.range(size, 0, heights.length - 1, 'size');
    }
    return Spatium.staffHeight(heights[size]);
  }

  /// The staff height (four spaces), in millimetres.
  double get staffHeight => millimetres * 4;

  /// [mm] millimetres in staff spaces.
  double toSpaces(double mm) => mm / millimetres;

  /// [spaces] staff spaces in millimetres.
  double toMillimetres(double spaces) => spaces * millimetres;

  /// Device pixels per staff space at [dpi] dots per inch — the
  /// `staffSpace` to render at for true size on that device.
  double pixelsPerSpace(double dpi) => millimetres / 25.4 * dpi;

  @override
  bool operator ==(Object other) =>
      other is Spatium && other.millimetres == millimetres;

  @override
  int get hashCode => millimetres.hashCode;

  @override
  String toString() => 'Spatium(${millimetres}mm)';
}

/// A sheet of paper, in millimetres (portrait).
class PaperSize {
  /// Width in millimetres.
  final double width;

  /// Height in millimetres.
  final double height;

  /// A sheet [width] × [height] millimetres.
  const PaperSize(this.width, this.height)
      : assert(width > 0 && height > 0, 'paper must be positive');

  /// ISO A3, 297 × 420 mm.
  static const a3 = PaperSize(297, 420);

  /// ISO A4, 210 × 297 mm.
  static const a4 = PaperSize(210, 297);

  /// ISO A5, 148 × 210 mm.
  static const a5 = PaperSize(148, 210);

  /// ISO B4, 250 × 353 mm — a common size for orchestral parts.
  static const b4 = PaperSize(250, 353);

  /// US Letter, 8.5 × 11 in.
  static const letter = PaperSize(215.9, 279.4);

  /// US Legal, 8.5 × 14 in.
  static const legal = PaperSize(215.9, 355.6);

  /// US Tabloid, 11 × 17 in.
  static const tabloid = PaperSize(279.4, 431.8);

  /// "Concert" or part size, 9 × 12 in.
  static const concert = PaperSize(228.6, 304.8);

  /// The same sheet turned sideways.
  PaperSize get landscape => PaperSize(height, width);

  @override
  bool operator ==(Object other) =>
      other is PaperSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'PaperSize(${width}mm × ${height}mm)';
}

/// [PageMetrics] for [paper] at staff size [spatium], with margins in
/// millimetres (15 mm, a usual engraving margin, unless given).
PageMetrics pageMetricsFor(
  PaperSize paper,
  Spatium spatium, {
  double marginTop = 15,
  double marginBottom = 15,
  double marginLeft = 15,
  double marginRight = 15,
}) =>
    PageMetrics(
      width: spatium.toSpaces(paper.width),
      height: spatium.toSpaces(paper.height),
      marginTop: spatium.toSpaces(marginTop),
      marginBottom: spatium.toSpaces(marginBottom),
      marginLeft: spatium.toSpaces(marginLeft),
      marginRight: spatium.toSpaces(marginRight),
    );
