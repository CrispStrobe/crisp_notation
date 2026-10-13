import '../model/measure.dart';
import 'layout_settings.dart';

/// Draws barlines and repeat signs on a staff of any height, for every engine
/// that draws a staff (notation, tab), so a barline has one definition.
///
/// Each method draws at `x` — the measure's right edge, where the barline
/// starts — and returns the x after it plus the barline gap. Lines go out
/// through [line]; repeat dots through [dots], which draws them with their
/// left edge at its argument and returns their width.
class BarlinePen {
  /// The spacing and thickness settings.
  final LayoutSettings s;

  /// The staff's top and bottom line, in the engine's units.
  final double top, bottom;

  /// Draws one vertical stroke.
  final void Function(double x, double y0, double y1, double thickness,
      {bool round}) line;

  /// Draws a pair of repeat dots with their left edge at `x`; returns their
  /// width.
  final double Function(double x) dots;

  /// A pen for a staff from [top] to [bottom].
  const BarlinePen(this.s,
      {required this.top,
      required this.bottom,
      required this.line,
      required this.dots});

  double get _thin => s.thinBarlineThickness;
  double get _thick => s.thickBarlineThickness;

  /// `|:` — thick line, thin line, dots.
  double startRepeat(double x) {
    final thickX = x + _thick / 2;
    line(thickX, top, bottom, _thick);
    final thinX = thickX + _thick / 2 + s.barlineSeparation;
    line(thinX, top, bottom, _thin);
    final dotsX = thinX + _thin / 2 + 0.3;
    return dotsX + dots(dotsX) + s.barlineGap;
  }

  /// `:|` — dots, thin line, thick line.
  double endRepeat(double x) {
    final thinX = x + dots(x) + 0.3;
    line(thinX, top, bottom, _thin);
    final thickX = thinX + _thin / 2 + s.barlineSeparation;
    line(thickX, top, bottom, _thick);
    return thickX + _thick / 2 + s.barlineGap;
  }

  /// The outer (right) edge of [endRepeat] drawn at `x`, for [dotsWidth].
  double endRepeatRight(double x, double dotsWidth) =>
      x + dotsWidth + 0.3 + _thin / 2 + s.barlineSeparation + _thick / 2;

  /// A barline in [style].
  double barline(BarlineStyle style, double x) {
    final sep = s.barlineSeparation;
    switch (style) {
      case BarlineStyle.normal:
        line(x, top, bottom, _thin);
        return x + _thin + s.barlineGap;
      case BarlineStyle.doubleBar:
        line(x, top, bottom, _thin);
        final x2 = x + _thin + sep;
        line(x2, top, bottom, _thin);
        return x2 + _thin + s.barlineGap;
      case BarlineStyle.finalBar:
        line(x, top, bottom, _thin);
        final xt = x + _thin / 2 + sep + _thick / 2;
        line(xt, top, bottom, _thick);
        return xt + _thick / 2 + s.barlineGap;
      case BarlineStyle.heavy:
        final xt = x + _thick / 2;
        line(xt, top, bottom, _thick);
        return xt + _thick / 2 + s.barlineGap;
      case BarlineStyle.dashed:
        return _segmented(x, dash: 0.5, gap: 0.4, round: false);
      case BarlineStyle.dotted:
        return _segmented(x, dash: 0.02, gap: 0.32, round: true);
      case BarlineStyle.tick:
        // A short stroke crossing only the top staff line.
        line(x, top - 0.75, top + 0.75, _thin);
        return x + _thin + s.barlineGap;
      case BarlineStyle.short:
        // A short stroke over the middle half of the staff.
        final quarter = (bottom - top) / 4;
        line(x, top + quarter, bottom - quarter, _thin);
        return x + _thin + s.barlineGap;
      case BarlineStyle.reverseFinal:
        // Thick + thin — the mirror of a final barline.
        final xt = x + _thick / 2;
        line(xt, top, bottom, _thick);
        final xthin = xt + _thick / 2 + sep + _thin / 2;
        line(xthin, top, bottom, _thin);
        return xthin + _thin / 2 + s.barlineGap;
      case BarlineStyle.none:
        return x + s.barlineGap;
    }
  }

  /// Where [barline]`(style, x)` inks, relative to `x`: the left edge
  /// offset and the width.
  (double, double) ink(BarlineStyle style) {
    final sep = s.barlineSeparation;
    return switch (style) {
      BarlineStyle.normal ||
      BarlineStyle.dashed ||
      BarlineStyle.dotted ||
      BarlineStyle.tick ||
      BarlineStyle.short =>
        (-_thin / 2, _thin),
      BarlineStyle.doubleBar => (-_thin / 2, 2 * _thin + sep),
      BarlineStyle.finalBar => (-_thin / 2, _thin + sep + _thick),
      BarlineStyle.heavy => (0, _thick),
      BarlineStyle.reverseFinal => (0, _thick + sep + _thin),
      BarlineStyle.none => (0, 0),
    };
  }

  /// A vertical barline drawn as short segments (dashed or, with [round],
  /// dotted), spanning the staff.
  double _segmented(double x,
      {required double dash, required double gap, required bool round}) {
    var y = top;
    while (y <= bottom + 1e-9) {
      line(x, y, y + dash < bottom ? y + dash : bottom, _thin, round: round);
      y += dash + gap;
    }
    return x + _thin + s.barlineGap;
  }
}
