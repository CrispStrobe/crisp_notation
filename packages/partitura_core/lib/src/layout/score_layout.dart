/// The layout engine's output: a flat display list plus hit information.
///
/// **Coordinate system** (binding, see docs/DESIGN.md): distances in staff
/// spaces; origin at the intersection of the staff's **top line** with its
/// left edge; y grows **downward**. The five staff lines lie at y = 0, 1,
/// 2, 3, 4; a staff position `p` (0 = bottom line) maps to
/// `y = (8 - p) / 2`. Ink above the staff has negative y.
library;

import 'dart:math';

/// One drawable item of a laid-out score.
///
/// Primitives tagged with an [elementId] belong to that score element
/// (notehead, stem, its accidentals, …); untagged primitives are staff
/// furniture (staff lines, clef, signatures, barlines).
sealed class LayoutPrimitive {
  /// The id of the score element this primitive belongs to, if any.
  final String? elementId;

  /// Creates a primitive, optionally owned by element [elementId].
  const LayoutPrimitive({this.elementId});
}

/// A SMuFL glyph drawn with its origin (text baseline) at [position].
final class GlyphPrimitive extends LayoutPrimitive {
  /// SMuFL glyph name (see [SmuflGlyph]).
  final String smuflName;

  /// Glyph origin in staff spaces.
  final Point<double> position;

  /// Size multiplier: 1.0 = normal; grace notes use a reduced scale.
  final double scale;

  /// Creates a glyph primitive.
  const GlyphPrimitive(
    this.smuflName,
    this.position, {
    this.scale = 1.0,
    super.elementId,
  });

  @override
  String toString() => 'Glyph($smuflName @ ${position.x},${position.y}'
      '${scale == 1.0 ? '' : ' x$scale'}'
      '${elementId == null ? '' : ', $elementId'})';
}

/// A straight line: staff lines, stems, ledger lines, barlines.
///
/// The line's [thickness] is centered on the segment from [from] to [to].
final class LinePrimitive extends LayoutPrimitive {
  /// Start point in staff spaces.
  final Point<double> from;

  /// End point in staff spaces.
  final Point<double> to;

  /// Line thickness in staff spaces.
  final double thickness;

  /// Round the stroke ends (so a zero-length line renders as a filled dot,
  /// e.g. a chord-diagram fingering). Default false = butt caps.
  final bool round;

  /// Creates a line primitive.
  const LinePrimitive(
    this.from,
    this.to, {
    required this.thickness,
    this.round = false,
    super.elementId,
  });

  @override
  String toString() => 'Line(${from.x},${from.y} -> ${to.x},${to.y} x$thickness'
      '${round ? ' round' : ''}${elementId == null ? '' : ', $elementId'})';
}

/// A run of text (lyrics; later annotations/chord symbols), anchored by
/// its **horizontal center** at `position.x` with the alphabetic
/// baseline at `position.y`. Renderers pick the font; [size] is the em
/// size in staff spaces. Core cannot measure text — hit regions use an
/// estimated width, painters center the real text on the anchor.
final class TextPrimitive extends LayoutPrimitive {
  /// The text to draw.
  final String text;

  /// Center-baseline anchor in staff spaces.
  final Point<double> position;

  /// Em size (font size) in staff spaces.
  final double size;

  /// Creates a text primitive.
  const TextPrimitive(
    this.text,
    this.position, {
    required this.size,
    super.elementId,
  });

  @override
  String toString() => 'Text("$text" @ ${position.x},${position.y} x$size'
      '${elementId == null ? '' : ', $elementId'})';
}

/// A beam: a filled parallelogram with vertical end edges.
///
/// [start] and [end] are the **midpoints** of the beam's left and right
/// edges; the beam extends [thickness] / 2 above and below the line
/// through them.
final class BeamPrimitive extends LayoutPrimitive {
  /// Midpoint of the left edge, in staff spaces.
  final Point<double> start;

  /// Midpoint of the right edge, in staff spaces.
  final Point<double> end;

  /// Vertical thickness of the beam in staff spaces.
  final double thickness;

  /// Creates a beam primitive.
  const BeamPrimitive(
    this.start,
    this.end, {
    required this.thickness,
    super.elementId,
  });

  @override
  String toString() =>
      'Beam(${start.x},${start.y} -> ${end.x},${end.y} x$thickness'
      '${elementId == null ? '' : ', $elementId'})';
}

/// A cubic Bézier curve: ties (and, from v0.3.2, slurs).
///
/// Drawn from [start] to [end] with control points [control1] and
/// [control2]; stroked with [thickness]. Like beams, curves are shared
/// note ink and carry no element id.
final class CurvePrimitive extends LayoutPrimitive {
  /// Curve start point in staff spaces.
  final Point<double> start;

  /// First control point.
  final Point<double> control1;

  /// Second control point.
  final Point<double> control2;

  /// Curve end point in staff spaces.
  final Point<double> end;

  /// Stroke thickness in staff spaces.
  final double thickness;

  /// Creates a curve primitive.
  const CurvePrimitive(
    this.start,
    this.control1,
    this.control2,
    this.end, {
    required this.thickness,
  });

  @override
  String toString() =>
      'Curve(${start.x},${start.y} ~ ${control1.x},${control1.y} ~ '
      '${control2.x},${control2.y} ~ ${end.x},${end.y} x$thickness)';
}

/// The hit box of one score element, tagged with its id.
class ElementRegion {
  /// The element's id (elements without an id get no region).
  final String elementId;

  /// Bounding box of the element's ink in staff spaces (noteheads,
  /// accidentals, stem, flag, dots — beams are shared and excluded).
  final Rectangle<double> bounds;

  /// Creates a region.
  const ElementRegion(this.elementId, this.bounds);

  @override
  String toString() => 'ElementRegion($elementId, $bounds)';
}

/// The horizontal extent of one measure (for mapping taps to measures).
class MeasureRegion {
  /// Index of the measure in `Score.measures`.
  final int index;

  /// Left edge in staff spaces (after the preceding barline/signatures).
  final double startX;

  /// Right edge in staff spaces (before the following barline).
  final double endX;

  /// Creates a measure region.
  const MeasureRegion(this.index, {required this.startX, required this.endX});

  @override
  String toString() => 'MeasureRegion($index, $startX..$endX)';
}

/// A laid-out score: flat display list plus hit information.
///
/// Produced by `LayoutEngine.layout`; deterministic for identical inputs.
class ScoreLayout {
  /// Total width in staff spaces, from x = 0 to the end of the final
  /// barline plus padding.
  final double width;

  /// Total height of the bounding box in staff spaces.
  final double height;

  /// y of the bounding box's top edge. Usually negative: ink (clef
  /// overshoot, notes above the staff) extends above the top staff line,
  /// which is y = 0.
  final double top;

  /// Drawables in painting order (staff furniture first, then elements).
  final List<LayoutPrimitive> primitives;

  /// Hit boxes for all elements that carry an id.
  final List<ElementRegion> regions;

  /// Horizontal extents of the measures, in order.
  final List<MeasureRegion> measureRegions;

  /// Creates a layout (treat the lists as immutable).
  const ScoreLayout({
    required this.width,
    required this.height,
    required this.top,
    required this.primitives,
    required this.regions,
    required this.measureRegions,
  });

  /// The bounding box: x from 0 to [width], y from [top] to
  /// [top] + [height].
  Rectangle<double> get bounds => Rectangle(0, top, width, height);

  @override
  String toString() =>
      'ScoreLayout(${width}x$height, ${primitives.length} primitives, '
      '${regions.length} regions)';
}
