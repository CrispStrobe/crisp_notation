import 'dart:math';

import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Engraving rules a finished [ScoreLayout] must keep, whatever produced it.
///
/// The unit tests and the live corpus sweep both run every layout through
/// [lintLayout]. The rules describe the printed page, not the code that drew
/// it, so a bug like #19 (two closing barlines) fails here even when a test
/// written against the code's own output would have agreed with it.
///
/// Rule ids:
/// - `duplicate`: the same element's primitive drawn twice at the same place.
/// - `barline-group`: lines closer than a barline gap form one barline as the
///   eye reads it; the group is not one of the barlines engravers draw (a
///   plain barline left in front of a start repeat, a thin+thick behind an
///   end repeat).
/// - `repeat-dots`: repeat dots with no repeat barline beside them.
/// - `collision`: a notehead drawn over a clef, key or time signature or a
///   barline.
/// - `closing`: the staff does not end on its closing barline, or the piece
///   closes with something other than a closing barline.
class LayoutIssue {
  /// The rule broken (see [lintLayout]).
  final String rule;

  /// What is wrong, in engraving terms.
  final String message;

  /// Where (staff spaces from the layout's left edge).
  final double x;

  const LayoutIssue(this.rule, this.message, this.x);

  @override
  String toString() => '$rule @x=${x.toStringAsFixed(2)}: $message';
}

/// A vertical barline stroke: `|` thin, `I` thick, `:` repeat dots.
typedef _Stroke = ({double left, double right, String token});

/// The barline groups of [layout], left to right, as token strings with their
/// extents: `|` thin, `I` thick, `:` repeat dots (`|I` final, `:|I` end
/// repeat, `I|:` start repeat).
List<({double left, double right, String tokens})> barlineGroups(
    ScoreLayout layout, LayoutSettings settings) {
  final strokes = <_Stroke>[];
  final dotsWidth = settings.metadata.bBoxOf(SmuflGlyph.repeatDots).width;
  final dotWidth = settings.metadata.bBoxOf(SmuflGlyph.repeatDot).width;
  final dotXs = <double>{};
  for (final p in layout.primitives) {
    switch (p) {
      case LinePrimitive(:final from, :final to, :final thickness)
          when p.elementId == null &&
              from.x == to.x &&
              (to.y - from.y).abs() >= 2 &&
              from.y <= 0 &&
              to.y >= 0:
        final token = (thickness - settings.thickBarlineThickness).abs() <
                (thickness - settings.thinBarlineThickness).abs()
            ? 'I'
            : '|';
        strokes.add((
          left: from.x - thickness / 2,
          right: from.x + thickness / 2,
          token: token
        ));
      case GlyphPrimitive(:final smuflName, :final position)
          when smuflName == SmuflGlyph.repeatDots && p.elementId == null:
        strokes.add((
          left: position.x,
          right: position.x + dotsWidth,
          token: ':',
        ));
      // A tab staff draws its pair of dots one at a time: one `:` per x.
      case GlyphPrimitive(:final smuflName, :final position)
          when smuflName == SmuflGlyph.repeatDot &&
              p.elementId == null &&
              dotXs.add(position.x):
        strokes.add((
          left: position.x,
          right: position.x + dotWidth,
          token: ':',
        ));
      default:
    }
  }
  strokes.sort((a, b) => a.left.compareTo(b.left));
  final groups = <({double left, double right, String tokens})>[];
  for (final s in strokes) {
    final last = groups.isEmpty ? null : groups.last;
    // Strokes closer than a barline gap and a half read as one barline (a
    // bar with notes in it is always wider).
    if (last != null && s.left - last.right < 1.5 * settings.barlineGap) {
      groups[groups.length - 1] = (
        left: last.left,
        right: max(last.right, s.right),
        tokens: last.tokens + s.token,
      );
    } else {
      groups.add((left: s.left, right: s.right, tokens: s.token));
    }
  }
  return groups;
}

/// The barlines engravers draw, as [barlineGroups] tokens.
const legalBarlineGroups = {
  '|', // plain
  '||', // double
  '|I', // final
  'I', // heavy
  'I|', // reverse final
  'I|:', // start repeat
  ':|I', // end repeat
  ':|I|:', // end + start repeat, shared thick line
  ':|II|:', // end + start repeat, thick + thick
};

/// Checks [layout] against the engraving rules (see [LayoutIssue]).
///
/// [closes] says the layout ends the piece (its last system); a continuation
/// system may end on any barline. [lastMeasure], the layout's last measure
/// when given, lets the closing rule honour its explicit barline style.
List<LayoutIssue> lintLayout(
  ScoreLayout layout,
  LayoutSettings settings, {
  bool closes = true,
  Measure? lastMeasure,
}) {
  final issues = <LayoutIssue>[];

  // duplicate: identical primitives at the same place.
  final seen = <String>{};
  String f(double v) => v.toStringAsFixed(4);
  String p(Point<double> pt) => '${f(pt.x)},${f(pt.y)}';
  for (final prim in layout.primitives) {
    final key = switch (prim) {
      GlyphPrimitive(:final smuflName, :final position, :final scale) =>
        'G $smuflName ${p(position)} ${f(scale)}',
      LinePrimitive(:final from, :final to, :final thickness) =>
        'L ${p(from)} ${p(to)} ${f(thickness)}',
      TextPrimitive(:final text, :final position, :final size) =>
        'T $text ${p(position)} ${f(size)}',
      BeamPrimitive(:final start, :final end, :final thickness) =>
        'B ${p(start)} ${p(end)} ${f(thickness)}',
      CurvePrimitive(
        :final start,
        :final control1,
        :final control2,
        :final end
      ) =>
        'C ${p(start)} ${p(control1)} ${p(control2)} ${p(end)}',
    };
    // Two voices sharing a unison each draw their head (and dots, ledger
    // lines) under their own element id, which a player highlights; only
    // the same element drawn twice is a fault.
    if (!seen.add('$key ${prim.elementId}')) {
      final x = switch (prim) {
        GlyphPrimitive(:final position) => position.x,
        LinePrimitive(:final from) => from.x,
        TextPrimitive(:final position) => position.x,
        BeamPrimitive(:final start) => start.x,
        CurvePrimitive(:final start) => start.x,
      };
      issues.add(LayoutIssue('duplicate', 'drawn twice: $key', x));
    }
  }

  final groups = barlineGroups(layout, settings);
  for (final g in groups) {
    if (!legalBarlineGroups.contains(g.tokens)) {
      issues.add(LayoutIssue('barline-group',
          'strokes "${g.tokens}" read as one barline', g.left));
    }
    if (g.tokens.contains(':') && !g.tokens.contains('I')) {
      issues.add(LayoutIssue('repeat-dots',
          'dots "${g.tokens}" without a repeat barline', g.left));
    }
  }

  // collision: a notehead over the staff's furniture (clef, key and time
  // signature, barlines) — found as a stem-down second's left head on the
  // time signature.
  final meta = settings.metadata;
  Rectangle<double> boxOf(GlyphPrimitive g) {
    final b = meta.bBoxOf(g.smuflName);
    return Rectangle(g.position.x + b.swX * g.scale,
        g.position.y - b.neY * g.scale, b.width * g.scale, b.height * g.scale);
  }

  final furniture = <(String, Rectangle<double>)>[
    for (final g in layout.primitives.whereType<GlyphPrimitive>())
      if (g.elementId == null &&
          (g.smuflName.endsWith('Clef') ||
              g.smuflName.startsWith('timeSig') ||
              g.smuflName.startsWith('accidental')))
        (g.smuflName, boxOf(g)),
    for (final g in groups)
      (
        'barline "${g.tokens}"',
        Rectangle(g.left, 0, g.right - g.left, 4),
      ),
  ];
  for (final g in layout.primitives.whereType<GlyphPrimitive>()) {
    if (g.elementId == null || !g.smuflName.startsWith('notehead')) continue;
    final head = boxOf(g);
    for (final (name, box) in furniture) {
      final overlap = head.intersection(box);
      if (overlap != null && overlap.width > 0.05 && overlap.height > 0.05) {
        issues.add(LayoutIssue('collision',
            '${g.smuflName} (${g.elementId}) on $name', g.position.x));
      }
    }
  }

  // closing: the staff ends on its last barline's outer edge, and a piece
  // ends on a closing barline unless its last measure asks for another style.
  // A continuation system may end on any barline.
  final last = lastMeasure;
  final explicitStyle =
      last != null && !last.endRepeat && last.barline != BarlineStyle.normal;
  final unbarred = explicitStyle &&
      const {
        BarlineStyle.none,
        BarlineStyle.dashed,
        BarlineStyle.dotted,
        BarlineStyle.tick,
        BarlineStyle.short,
      }.contains(last.barline);
  // An unbarred ending (an invisible kern `=-`, `none`) ends where its music
  // does, on any line.
  if (groups.isNotEmpty && !unbarred) {
    final end = groups.last;
    if ((end.right - layout.width).abs() > 1e-6) {
      issues.add(LayoutIssue(
          'closing',
          'staff ends at ${f(layout.width)}, '
              'its last barline at ${f(end.right)}',
          end.left));
    }
    if (closes && !explicitStyle && !{'|I', ':|I'}.contains(end.tokens)) {
      issues.add(LayoutIssue(
          'closing', 'piece closes with "${end.tokens}"', end.left));
    }
  }
  return issues;
}

/// The barline [barlineGroups] tokens a measure boundary should draw: after
/// [measure] (null before the first), before [next] (null after the last).
/// Null when the style draws no full-height stroke (dashed, dotted, tick,
/// short, none), which [barlineMismatches] skips.
///
/// [changeDrawn] says a clef, key or time change is drawn between the
/// boundary and [next]'s start repeat (then the barline stays, and the repeat
/// follows the new signature — not checked here).
String? expectedBarline(Measure? measure, Measure? next,
    {bool closes = true, bool changeDrawn = false}) {
  if (measure == null) return next!.startRepeat ? 'I|:' : null;
  final end = measure.endRepeat ? ':|I' : null;
  // A clef, key or time change draws between the barline and a start repeat,
  // which then follows the new signature (not checked here).
  final start = next != null && next.startRepeat && !changeDrawn ? 'I|:' : null;
  if (end != null && start != null) return ':|II|:';
  if (end != null || start != null) return end ?? start;
  final style = measure.barline;
  if (next == null && style == BarlineStyle.normal) return closes ? '|I' : '|';
  return switch (style) {
    BarlineStyle.normal => '|',
    BarlineStyle.doubleBar => '||',
    BarlineStyle.finalBar => '|I',
    BarlineStyle.heavy => 'I',
    BarlineStyle.reverseFinal => 'I|',
    BarlineStyle.dashed ||
    BarlineStyle.dotted ||
    BarlineStyle.tick ||
    BarlineStyle.short ||
    BarlineStyle.none =>
      null,
  };
}

/// Where [layout]'s drawn barlines differ from what [score]'s measures ask
/// for, one message per measure boundary: a barline lost, doubled, or of the
/// wrong kind. [closes] as for [lintLayout].
List<String> barlineMismatches(
    ScoreLayout layout, Score score, LayoutSettings settings,
    {bool closes = true, bool signatures = true}) {
  final groups = barlineGroups(layout, settings);
  final regions = layout.measureRegions;
  final out = <String>[];
  // The clef, key and time in force, to tell a drawn change from a restated
  // one. [signatures]: the staff draws them (a tab staff does not, so its
  // start repeat always replaces the barline).
  var clef = score.clef;
  var key = score.keySignature;
  var time = score.timeSignature;
  for (var i = 0; i <= regions.length; i++) {
    final measure = i == 0 ? null : score.measures[regions[i - 1].index];
    final next = i == regions.length ? null : score.measures[regions[i].index];
    final changeDrawn = signatures &&
        next != null &&
        ((next.clefChange ?? clef) != clef ||
            (next.keyChange ?? key) != key ||
            (next.timeChange ?? time) != time);
    if (next != null) {
      clef = next.clefChange ?? clef;
      key = next.keyChange ?? key;
      time = next.timeChange ?? time;
    }
    final want = expectedBarline(measure, next,
        closes: closes, changeDrawn: changeDrawn);
    // The boundary's barline starts where the measure before ends, or (a
    // start repeat on the first bar) just before the bar's content.
    final at = i == 0 ? regions[0].startX : regions[i - 1].endX;
    final found = [
      for (final g in groups)
        if (i == 0
            ? (g.right <= at + 1e-6 && g.right > at - 3)
            : (g.left > at - 0.6 && g.left < at + 0.6))
          g.tokens,
    ];
    if (want == null) continue;
    if (found.length != 1 || found.single != want) {
      final drawn =
          found.isEmpty ? 'nothing' : found.map((t) => '"$t"').join(' ');
      final bar = i == 0 ? 'start' : '${regions[i - 1].index + 1}';
      out.add('bar $bar: wanted "$want", drawn $drawn');
    }
  }
  return out;
}
