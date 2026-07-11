/// Chord (fretboard) diagrams: the small string×fret grid that shows a chord
/// shape, with a standalone layout so it renders through the usual pipeline
/// (SVG / PNG) and can later be placed above a staff.
library;

import 'dart:math';

import '../layout/layout_settings.dart';
import '../layout/score_layout.dart';

/// A chord fretboard diagram.
///
/// [frets] gives the fret for each string in **tuning order** — index 0 is the
/// top tab line (the highest-sounding string), matching `Tuning`. A value of
/// `0` is an open string, `-1` a muted (x) string, and `n > 0` the fretted
/// number. The diagram draws the lowest string on the left. [baseFret] is the
/// fret of the top row (1 draws the nut); [fretSpan] the number of rows shown.
/// Optional [name] labels it, [fingers] annotates finger numbers per string
/// (parallel to [frets]; a null entry draws none), and [barreFret] draws a
/// barre across all strings at that fret.
class ChordDiagram {
  /// Fret per string in tuning order (0 = open, -1 = muted, n = fretted).
  final List<int> frets;

  /// Chord name drawn above the grid, or null.
  final String? name;

  /// Finger numbers per string (parallel to [frets]; null entry = none).
  final List<int?>? fingers;

  /// Fret of the top row (1 = at the nut).
  final int baseFret;

  /// Number of fret rows drawn.
  final int fretSpan;

  /// Fret of a barre across all strings, or null.
  final int? barreFret;

  /// Creates a chord diagram.
  const ChordDiagram(
    this.frets, {
    this.name,
    this.fingers,
    this.baseFret = 1,
    this.fretSpan = 4,
    this.barreFret,
  });

  @override
  bool operator ==(Object other) =>
      other is ChordDiagram &&
      _intListEq(other.frets, frets) &&
      other.name == name &&
      _nIntListEq(other.fingers, fingers) &&
      other.baseFret == baseFret &&
      other.fretSpan == fretSpan &&
      other.barreFret == barreFret;

  @override
  int get hashCode => Object.hash(
      Object.hashAll(frets),
      name,
      fingers == null ? null : Object.hashAll(fingers!),
      baseFret,
      fretSpan,
      barreFret);

  @override
  String toString() => 'ChordDiagram(${name ?? '?'}: $frets'
      '${baseFret == 1 ? '' : ' @$baseFret'})';

  static bool _intListEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _nIntListEq(List<int?>? a, List<int?>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Horizontal distance between adjacent strings, in staff spaces.
const double _stringGap = 0.9;

/// Vertical distance between adjacent frets, in staff spaces.
const double _fretGap = 1.1;

/// Lays a [diagram] out as a standalone [ScoreLayout] (in staff spaces).
ScoreLayout layoutChordDiagram(ChordDiagram diagram, LayoutSettings settings) {
  final n = diagram.frets.length;
  final s = settings;
  final gridW = (n - 1) * _stringGap;
  final gridH = diagram.fretSpan * _fretGap;
  const ox = 0.5; // left margin so no ink sits at negative x
  final primitives = <LayoutPrimitive>[];

  // The lowest string draws on the left; string i is tuning index i.
  double xOf(int i) => ox + (n - 1 - i) * _stringGap;

  // Vertical string lines.
  for (var i = 0; i < n; i++) {
    final x = ox + i * _stringGap;
    primitives.add(LinePrimitive(Point(x, 0), Point(x, gridH),
        thickness: s.staffLineThickness));
  }
  // Horizontal fret lines; the top line is thick when it is the nut.
  for (var r = 0; r <= diagram.fretSpan; r++) {
    final y = r * _fretGap;
    final thick = r == 0 && diagram.baseFret == 1;
    primitives.add(LinePrimitive(Point(ox, y), Point(ox + gridW, y),
        thickness: thick ? s.staffLineThickness * 3 : s.staffLineThickness));
  }

  // A base-fret label to the right of the top row when not at the nut.
  if (diagram.baseFret > 1) {
    primitives.add(TextPrimitive(
      '${diagram.baseFret}fr',
      Point(ox + gridW + 0.55, _fretGap * 0.7),
      size: 1.0,
    ));
  }

  const markY = -0.5; // the open/muted marker row, above the grid

  // A barre (drawn instead of the individual dots on that fret).
  final barreRow =
      diagram.barreFret == null ? -1 : diagram.barreFret! - diagram.baseFret;
  if (barreRow >= 0 && barreRow < diagram.fretSpan) {
    final y = (barreRow + 0.5) * _fretGap;
    primitives.add(LinePrimitive(Point(ox, y), Point(ox + gridW, y),
        thickness: 0.55, round: true));
  }

  for (var i = 0; i < n; i++) {
    final fret = diagram.frets[i];
    final x = xOf(i);
    if (fret < 0) {
      primitives.add(TextPrimitive('x', Point(x, markY + 0.3), size: 0.9));
      continue;
    }
    if (fret == 0) {
      primitives.add(TextPrimitive('o', Point(x, markY + 0.3), size: 0.9));
      continue;
    }
    final row = fret - diagram.baseFret;
    if (row < 0 || row >= diagram.fretSpan) continue;
    if (row == barreRow) continue; // covered by the barre
    final y = (row + 0.5) * _fretGap;
    // A round-capped zero-length line renders as a filled fingering dot.
    primitives.add(
        LinePrimitive(Point(x, y), Point(x, y), thickness: 0.6, round: true));
  }

  // Finger numbers below the grid.
  var bottom = gridH;
  if (diagram.fingers != null) {
    final fingers = diagram.fingers!;
    for (var i = 0; i < n && i < fingers.length; i++) {
      final f = fingers[i];
      if (f == null) continue;
      primitives
          .add(TextPrimitive('$f', Point(xOf(i), gridH + 0.85), size: 0.9));
    }
    bottom = gridH + 1.0;
  }

  // Chord name above everything.
  var topEdge = markY - 0.6;
  if (diagram.name != null) {
    final nameY = markY - 1.0;
    primitives.add(
        TextPrimitive(diagram.name!, Point(ox + gridW / 2, nameY), size: 1.3));
    topEdge = nameY - 1.1;
  }

  const pad = 0.3;
  final right = ox + gridW + (diagram.baseFret > 1 ? 1.6 : 0.5);
  return ScoreLayout(
    width: right + pad,
    height: bottom - topEdge + 2 * pad,
    top: topEdge - pad,
    primitives: List.unmodifiable(primitives),
    regions: const [],
    measureRegions: const [],
  );
}
