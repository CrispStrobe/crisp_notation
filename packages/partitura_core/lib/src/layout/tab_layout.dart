/// Tablature layout: renders a [Score]'s pitches as fret numbers on an
/// N-line string staff, using a [Tuning]. Produces the same [ScoreLayout]
/// primitives as the notation engine, so the Flutter renderer and the
/// interaction layer work unchanged.
///
/// This is a parallel notation mode: each note's pitch is assigned to the
/// lowest-fret (string, fret) on the tuning, drawn as a digit centered on its
/// string line (the line is broken behind the digit). Rhythm is shown with
/// stems, flags and beams **below** the staff (half and quarter both draw a
/// plain stem — the tab convention leaves them distinguished by context).
library;

import 'dart:math';

import '../model/element.dart';
import '../model/score.dart';
import '../smufl/glyph_names.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/tuning.dart';
import 'layout_settings.dart';
import 'score_layout.dart';

/// One rhythmic column below the staff: its x, duration and measure onset.
class _Col {
  final double x;
  final NoteDuration duration;
  final Fraction onset;
  final bool isRest;
  _Col(this.x, this.duration, this.onset, this.isRest);
}

/// Lays out a [Score] as tablature for a [Tuning].
class TabLayoutEngine {
  /// Creates a tab layout engine.
  const TabLayoutEngine();

  /// Vertical distance between adjacent string lines, in staff spaces.
  static const double lineGap = 1.5;

  /// Em size of a fret digit, in staff spaces.
  static const double fretSize = 1.4;

  /// Lays [score] out as tablature for [tuning].
  ScoreLayout layout(Score score, Tuning tuning, LayoutSettings settings) {
    final n = tuning.stringCount;
    final s = settings;
    final meta = s.metadata;
    final primitives = <LayoutPrimitive>[];
    final regions = <ElementRegion>[];
    final measureRegions = <MeasureRegion>[];
    final breaks = List.generate(n, (_) => <(double, double)>[]);
    final measureCols = <List<_Col>>[];
    // note id -> (x, y) of its (first) fret digit, for slide/legato spans.
    final anchor = <String, (double, double)>{};

    double yOfString(int i) => i * lineGap;
    final bottomY = (n - 1) * lineGap;

    final clefGlyph =
        n <= 4 ? SmuflGlyph.fourStringTabClef : SmuflGlyph.sixStringTabClef;
    final clefBox = meta.bBoxOf(clefGlyph);
    var x = 0.5;
    final clefBaseline = bottomY / 2 + (clefBox.neY + clefBox.swY) / 2;
    primitives.add(GlyphPrimitive(clefGlyph, Point(x, clefBaseline)));
    x += clefBox.width + 1.2;

    for (var m = 0; m < score.measures.length; m++) {
      final measure = score.measures[m];
      final startX = x;
      final cols = <_Col>[];
      var onset = Fraction.zero;
      for (var i = 0; i < measure.elements.length; i++) {
        final element = measure.elements[i];
        final dur = measure.effectiveDurationAt(i);
        if (element is! NoteElement) {
          cols.add(_Col(x, element.duration, onset, true));
          x += _advance(element.duration, s);
          onset += dur;
          continue;
        }
        cols.add(_Col(x, element.duration, onset, false));
        var left = double.infinity;
        var right = -double.infinity;
        for (final pitch in element.pitches) {
          final place = tuning.fretFor(pitch);
          if (place == null) continue;
          final (stringIndex, fret) = place;
          final text = '$fret';
          final halfW = 0.28 * fretSize * text.length;
          final y = yOfString(stringIndex);
          primitives.add(TextPrimitive(
            text,
            Point(x, y + 0.32 * fretSize),
            size: fretSize,
            elementId: element.id,
          ));
          breaks[stringIndex].add((x - halfW - 0.1, x + halfW + 0.1));
          left = min(left, x - halfW);
          right = max(right, x + halfW);
          if (element.id != null) {
            anchor.putIfAbsent(element.id!, () => (x, y));
          }
        }
        if (element.id != null && left.isFinite) {
          regions.add(ElementRegion(
            element.id!,
            Rectangle(left, -0.3, right - left, bottomY + 3.6),
          ));
        }
        x += _advance(element.duration, s);
        onset += dur;
      }
      measureCols.add(cols);
      x = max(x, startX + 2.0);
      measureRegions.add(MeasureRegion(m, startX: startX, endX: x));
      final barX = x;
      primitives.add(LinePrimitive(
        Point(barX, 0),
        Point(barX, bottomY),
        thickness: s.thinBarlineThickness,
      ));
      x = barX + s.barlineGap;
    }

    final width = x;

    // Rhythm: stems, flags and beams below the staff.
    final beatUnit = score.timeSignature?.beatUnit ?? 4;
    final beatFrac = Fraction(1, beatUnit).toDouble();
    final stemTop = bottomY + 0.4;
    final stemBottom = stemTop + 2.4;
    for (final cols in measureCols) {
      _layoutRhythm(primitives, cols, stemTop, stemBottom, beatFrac, s);
    }

    // Slides (reuse `Score.glissandos`): a diagonal line between the two frets.
    for (final gliss in score.glissandos) {
      final a = anchor[gliss.startId];
      final b = anchor[gliss.endId];
      if (a == null || b == null) continue;
      primitives.add(LinePrimitive(
        Point(a.$1 + 0.5, a.$2 + 0.1),
        Point(b.$1 - 0.5, b.$2 - 0.1),
        thickness: 0.16,
      ));
    }

    // String bends: an upward arrow from the fret with the amount label.
    for (final bend in score.bends) {
      final at = anchor[bend.noteId];
      if (at == null) continue;
      final (bx, by) = at;
      final rise = 1.4 + bend.steps.clamp(0.25, 3.0) * 0.7;
      final tipX = bx + 1.3;
      final tipY = by - 0.5 - rise;
      // Curved rise from the fret up to the arrow tip.
      primitives.add(CurvePrimitive(
        Point(bx + 0.45, by - 0.4),
        Point(tipX, by - 0.4),
        Point(tipX, by - 0.4),
        Point(tipX, tipY + 0.35),
        thickness: 0.13,
      ));
      // Arrowhead.
      primitives.add(LinePrimitive(
          Point(tipX, tipY), Point(tipX - 0.28, tipY + 0.5),
          thickness: 0.13));
      primitives.add(LinePrimitive(
          Point(tipX, tipY), Point(tipX + 0.28, tipY + 0.5),
          thickness: 0.13));
      // Amount label above the tip.
      primitives.add(TextPrimitive(
        _bendLabel(bend.steps),
        Point(tipX, tipY - 0.25),
        size: 1.1,
      ));
    }

    // Hammer-on / pull-off (reuse `Score.slurs`): a small arc above the frets.
    for (final slur in score.slurs) {
      final a = anchor[slur.startId];
      final b = anchor[slur.endId];
      if (a == null || b == null) continue;
      final topY = min(a.$2, b.$2) - 1.1;
      primitives.add(CurvePrimitive(
        Point(a.$1 + 0.3, a.$2 - 0.6),
        Point(a.$1 + 0.3, topY),
        Point(b.$1 - 0.3, topY),
        Point(b.$1 - 0.3, b.$2 - 0.6),
        thickness: 0.12,
      ));
    }

    // String lines, broken behind any digits.
    for (var i = 0; i < n; i++) {
      final y = yOfString(i);
      final ranges = [...breaks[i]]..sort((a, b) => a.$1.compareTo(b.$1));
      var cursor = 0.0;
      for (final (bl, br) in ranges) {
        if (bl > cursor) {
          primitives.insert(
              0,
              LinePrimitive(Point(cursor, y), Point(bl, y),
                  thickness: s.staffLineThickness));
        }
        cursor = max(cursor, br);
      }
      if (cursor < width) {
        primitives.insert(
            0,
            LinePrimitive(Point(cursor, y), Point(width, y),
                thickness: s.staffLineThickness));
      }
    }

    return ScoreLayout(
      width: width,
      height: stemBottom + 0.4,
      top: -0.3,
      primitives: List.unmodifiable(primitives),
      regions: List.unmodifiable(regions),
      measureRegions: List.unmodifiable(measureRegions),
    );
  }

  void _layoutRhythm(
    List<LayoutPrimitive> primitives,
    List<_Col> cols,
    double stemTop,
    double stemBottom,
    double beatFrac,
    LayoutSettings s,
  ) {
    // Stems for every stemmed (half-or-shorter) note.
    for (final col in cols) {
      if (col.isRest || !_hasStem(col.duration.base)) continue;
      primitives.add(LinePrimitive(
        Point(col.x, stemTop),
        Point(col.x, stemBottom),
        thickness: s.stemThickness,
      ));
    }

    // Beam runs: consecutive beamable notes within the same beat.
    var i = 0;
    while (i < cols.length) {
      final col = cols[i];
      if (col.isRest || _beamCount(col.duration.base) < 1) {
        i++;
        continue;
      }
      final beat = (col.onset.toDouble() / beatFrac).floor();
      var j = i;
      while (j + 1 < cols.length &&
          !cols[j + 1].isRest &&
          _beamCount(cols[j + 1].duration.base) >= 1 &&
          (cols[j + 1].onset.toDouble() / beatFrac).floor() == beat) {
        j++;
      }
      if (j > i) {
        _drawBeams(primitives, cols.sublist(i, j + 1), stemBottom, s);
      } else {
        _drawFlag(primitives, col, stemBottom, s);
      }
      i = j + 1;
    }
  }

  void _drawBeams(List<LayoutPrimitive> primitives, List<_Col> run,
      double stemBottom, LayoutSettings s) {
    final maxLevel = run.map((c) => _beamCount(c.duration.base)).reduce(max);
    for (var level = 1; level <= maxLevel; level++) {
      final offset = (s.beamThickness + s.beamSpacing) * (level - 1);
      final y = stemBottom - offset; // stack upward from the stem ends
      var k = 0;
      while (k < run.length) {
        if (_beamCount(run[k].duration.base) < level) {
          k++;
          continue;
        }
        var l = k;
        while (l + 1 < run.length &&
            _beamCount(run[l + 1].duration.base) >= level) {
          l++;
        }
        if (l > k) {
          primitives.add(BeamPrimitive(Point(run[k].x, y), Point(run[l].x, y),
              thickness: s.beamThickness));
        } else {
          final stubX = k == 0 ? run[k].x + 0.9 : run[k].x - 0.9;
          primitives.add(BeamPrimitive(
              Point(min(run[k].x, stubX), y), Point(max(run[k].x, stubX), y),
              thickness: s.beamThickness));
        }
        k = l + 1;
      }
    }
  }

  void _drawFlag(List<LayoutPrimitive> primitives, _Col col, double stemBottom,
      LayoutSettings s) {
    final glyph = switch (col.duration.base) {
      DurationBase.eighth => SmuflGlyph.flag8thDown,
      DurationBase.sixteenth => SmuflGlyph.flag16thDown,
      DurationBase.thirtySecond => SmuflGlyph.flag32ndDown,
      DurationBase.sixtyFourth => SmuflGlyph.flag64thDown,
      _ => null,
    };
    if (glyph == null) return;
    primitives.add(
        GlyphPrimitive(glyph, Point(col.x - s.stemThickness / 2, stemBottom)));
  }

  /// The conventional label for a bend of [steps] whole steps.
  static String _bendLabel(double steps) => switch (steps) {
        0.25 => '¼',
        0.5 => '½',
        0.75 => '¾',
        1.0 => 'full',
        1.5 => '1½',
        2.0 => '2',
        _ => steps == steps.roundToDouble() ? '${steps.toInt()}' : '$steps',
      };

  static bool _hasStem(DurationBase base) =>
      base != DurationBase.whole && base != DurationBase.breve;

  static int _beamCount(DurationBase base) =>
      (base.index >= 3 && base.index <= 6) ? base.index - 2 : 0;

  double _advance(NoteDuration duration, LayoutSettings s) {
    final baseLog2 = duration.base == DurationBase.breve
        ? 1.0
        : -duration.base.index.toDouble();
    final dotLog2 = [0.0, log(1.5) / ln2, log(1.75) / ln2][duration.dots];
    return max(
        2.0, s.spacingBase + s.spacingPerLog2 * (4 + baseLog2 + dotLog2));
  }
}
