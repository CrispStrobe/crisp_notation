part of 'layout_engine.dart';

// Internal value/accumulator types used across the layout passes. Kept in a
// part file so they stay library-private to layout_engine.dart while the main
// file holds the engine itself. No behaviour — pure data.

/// Mutable bounding-box accumulator.
class _Bounds {
  double minX = double.infinity;
  double minY = double.infinity;
  double maxX = double.negativeInfinity;
  double maxY = double.negativeInfinity;

  void expand(double left, double top, double right, double bottom) {
    if (left < minX) minX = left;
    if (top < minY) minY = top;
    if (right > maxX) maxX = right;
    if (bottom > maxY) maxY = bottom;
  }

  bool get isEmpty => minX > maxX;

  Rectangle<double> toRectangle() =>
      Rectangle(minX, minY, maxX - minX, maxY - minY);
}

/// A beamed group: indices into a measure's element list, plus direction.
/// A feathered group carries its (beginBeams, endBeams) fan.
class _BeamGroup {
  final List<int> indices;

  /// Metric onset (from the measure start) of each note in [indices], aligned
  /// index-for-index. Lets the beam layout break secondary beams at metric
  /// subdivisions.
  final List<Fraction> onsets;
  final bool stemsDown;
  final (int, int)? feather;
  final double? forcedSlant;
  _BeamGroup(this.indices,
      {required this.onsets,
      required this.stemsDown,
      this.feather,
      this.forcedSlant});
}

/// Deferred stem/flag data for one beamed note, collected while walking the
/// measure and consumed when the group's beam geometry is computed.
class _BeamedNote {
  final String? elementId;
  final double stemX;

  /// y where the stem meets the notehead (anchor of the outermost notehead
  /// on the stem's far side).
  final double attachY;

  /// y of the outermost notehead on the beam side.
  final double refY;

  /// Beam levels this note needs (1 = eighth … 4 = sixty-fourth).
  final int beamCount;

  _BeamedNote({
    required this.elementId,
    required this.stemX,
    required this.attachY,
    required this.refY,
    required this.beamCount,
  });
}

/// Rendered notehead geometry of one element, kept for the tie pass.
/// Rests participate with an empty head list (a tie cannot cross a rest).
class _TieInfo {
  final NoteElement? note;
  final String? id;
  final bool stemsDown;

  /// Voice this element belongs to (0 or 1); ties never cross voices.
  final int voice;

  /// Horizontal ink extent of the notehead/rest glyphs.
  final double left;
  final double right;

  /// Per pitch: the notehead column's left/right x and its center y.
  final List<(Pitch, double, double, double)> heads;

  _TieInfo({
    required this.note,
    required this.id,
    required this.stemsDown,
    required this.left,
    required this.right,
    required this.heads,
    this.voice = 0,
  });
}
