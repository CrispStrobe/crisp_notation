/// Types for SMuFL font metadata (engraving defaults, glyph metrics).
///
/// `partitura_core` is pure Dart and cannot load assets itself; the consumer
/// (the `partitura` Flutter package, or a test) loads
/// `bravura_metadata.json`, decodes it and hands the map to
/// [SmuflMetadata.fromJson].
library;

import 'dart:math';

/// A glyph bounding box in staff spaces, relative to the glyph origin.
///
/// Follows SMuFL conventions: y grows **upward** (unlike layout
/// coordinates, where y grows downward).
class GlyphBBox {
  /// North-east (right/top) corner, x.
  final double neX;

  /// North-east (right/top) corner, y (up-positive).
  final double neY;

  /// South-west (left/bottom) corner, x.
  final double swX;

  /// South-west (left/bottom) corner, y (up-positive).
  final double swY;

  /// Creates a bounding box from its SMuFL corner coordinates.
  const GlyphBBox({
    required this.neX,
    required this.neY,
    required this.swX,
    required this.swY,
  });

  /// Glyph width in staff spaces.
  double get width => neX - swX;

  /// Glyph height in staff spaces.
  double get height => neY - swY;

  @override
  String toString() => 'GlyphBBox(NE $neX,$neY SW $swX,$swY)';
}

/// Stem attachment anchors of a notehead glyph, in staff spaces relative to
/// the glyph origin, y up-positive (SMuFL convention).
class GlyphAnchors {
  /// Where an upward stem's south-east end meets the notehead.
  final Point<double>? stemUpSE;

  /// Where a downward stem's north-west end meets the notehead.
  final Point<double>? stemDownNW;

  /// Creates an anchor set (either anchor may be absent).
  const GlyphAnchors({this.stemUpSE, this.stemDownNW});
}

/// Parsed SMuFL font metadata: engraving defaults and per-glyph metrics.
///
/// All distances are in staff spaces.
class SmuflMetadata {
  final Map<String, double> _engravingDefaults;
  final Map<String, GlyphBBox> _bBoxes;
  final Map<String, GlyphAnchors> _anchors;

  SmuflMetadata._(this._engravingDefaults, this._bBoxes, this._anchors);

  /// Parses the decoded JSON of a SMuFL font metadata file (e.g.
  /// `bravura_metadata.json`). Unknown keys are ignored; only numeric
  /// engraving defaults, glyph bounding boxes and stem anchors are kept.
  factory SmuflMetadata.fromJson(Map<String, Object?> json) {
    final defaults = <String, double>{};
    final rawDefaults = json['engravingDefaults'];
    if (rawDefaults is Map<String, Object?>) {
      rawDefaults.forEach((key, value) {
        if (value is num) defaults[key] = value.toDouble();
      });
    }

    final bBoxes = <String, GlyphBBox>{};
    final rawBoxes = json['glyphBBoxes'];
    if (rawBoxes is Map<String, Object?>) {
      rawBoxes.forEach((name, value) {
        if (value is! Map<String, Object?>) return;
        final ne = _pointOf(value['bBoxNE']);
        final sw = _pointOf(value['bBoxSW']);
        if (ne == null || sw == null) return;
        bBoxes[name] = GlyphBBox(neX: ne.x, neY: ne.y, swX: sw.x, swY: sw.y);
      });
    }

    final anchors = <String, GlyphAnchors>{};
    final rawAnchors = json['glyphsWithAnchors'];
    if (rawAnchors is Map<String, Object?>) {
      rawAnchors.forEach((name, value) {
        if (value is! Map<String, Object?>) return;
        anchors[name] = GlyphAnchors(
          stemUpSE: _pointOf(value['stemUpSE']),
          stemDownNW: _pointOf(value['stemDownNW']),
        );
      });
    }

    return SmuflMetadata._(defaults, bBoxes, anchors);
  }

  static Point<double>? _pointOf(Object? value) {
    if (value is! List || value.length != 2) return null;
    final x = value[0];
    final y = value[1];
    if (x is! num || y is! num) return null;
    return Point(x.toDouble(), y.toDouble());
  }

  /// The engraving default named [name] (e.g. `stemThickness`), or [orElse]
  /// if the font does not define it.
  double engravingDefault(String name, {required double orElse}) =>
      _engravingDefaults[name] ?? orElse;

  /// The bounding box of [glyphName].
  ///
  /// Throws an [ArgumentError] if the font metadata has no box for it —
  /// that indicates a glyph name typo or a non-SMuFL-compliant font.
  GlyphBBox bBoxOf(String glyphName) {
    final box = _bBoxes[glyphName];
    if (box == null) {
      throw ArgumentError.value(
        glyphName,
        'glyphName',
        'no bounding box in font metadata',
      );
    }
    return box;
  }

  /// The stem anchors of [glyphName]; empty anchors if the font defines
  /// none for it.
  GlyphAnchors anchorsOf(String glyphName) =>
      _anchors[glyphName] ?? const GlyphAnchors();
}
