/// Tablature layout: renders a [Score]'s pitches as fret numbers on an
/// N-line string staff, using a [Tuning]. Produces the same [ScoreLayout]
/// primitives as the notation engine, so the Flutter renderer and the
/// interaction layer work unchanged.
///
/// This is a parallel notation mode: each note's pitch is assigned to a
/// (string, fret) on the tuning — a chord's tones to distinct strings, so two
/// never collide on one line — drawn as a digit centered on its string line
/// (the line is broken behind the digit). Rhythm is shown with
/// stems, flags and beams **below** the staff (half and quarter both draw a
/// plain stem — the tab convention leaves them distinguished by context).
library;

import 'dart:math';

import '../model/element.dart';
import '../model/score.dart';
import '../smufl/glyph_names.dart';
import '../tablature/chord_diagram.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/pitch.dart';
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
  ///
  /// [capo] (default 0) clamps the nut up that many frets: the shown numbers
  /// become relative to the capo and a "capo N" label is drawn. [showTuning]
  /// draws each open string's note letter in a gutter on the left.
  ScoreLayout layout(
    Score score,
    Tuning tuning,
    LayoutSettings settings, {
    int capo = 0,
    bool showTuning = false,
  }) {
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
    // Per-note fret-digit overrides: dead notes show "x", ghost notes "(n)".
    final noteStyle = {for (final m in score.tabNoteMarks) m.noteId: m.style};
    // Per-note string pinning (overrides lowest-fret placement).
    final voicing = {for (final v in score.tabVoicings) v.noteId: v.strings};
    // A capo shifts every open string up, so frets read relative to it.
    final effTuning = capo <= 0
        ? tuning
        : Tuning([
            for (final p in tuning.strings) _shiftPitch(p, capo),
          ], name: tuning.name);

    double yOfString(int i) => i * lineGap;
    final bottomY = (n - 1) * lineGap;

    // A left gutter for the per-string note letters, when requested.
    final gutter = showTuning ? 1.3 : 0.0;
    if (showTuning) {
      for (var i = 0; i < n; i++) {
        primitives.add(TextPrimitive(
          _noteLetter(tuning.strings[i]),
          Point(gutter * 0.45, yOfString(i) + 0.32 * fretSize),
          size: fretSize,
        ));
      }
    }
    if (capo > 0) {
      primitives.add(TextPrimitive(
        'capo $capo',
        Point(gutter + 1.0, -1.2),
        size: 1.1,
      ));
    }

    final clefGlyph =
        n <= 4 ? SmuflGlyph.fourStringTabClef : SmuflGlyph.sixStringTabClef;
    final clefBox = meta.bBoxOf(clefGlyph);
    var x = 0.5 + gutter;
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
        // Assign every chord tone to a distinct string (a pinned voicing wins;
        // otherwise auto-assign so two notes never collide on one line).
        final placement =
            _placeChord(element.pitches, effTuning, voicing[element.id]);
        for (var pi = 0; pi < element.pitches.length; pi++) {
          final place = placement[pi];
          if (place == null) continue;
          final (stringIndex, fret) = place;
          final text = switch (noteStyle[element.id]) {
            TabNoteStyle.dead => 'x',
            TabNoteStyle.ghost => '($fret)',
            TabNoteStyle.harmonic ||
            TabNoteStyle.artificialHarmonic ||
            TabNoteStyle.pinchHarmonic =>
              '<$fret>',
            null => '$fret',
          };
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
        // Artificial / pinch harmonics keep the angle-bracketed fret but add a
        // small "A.H." / "P.H." label above the staff over the column.
        final hLabel = switch (noteStyle[element.id]) {
          TabNoteStyle.artificialHarmonic => 'A.H.',
          TabNoteStyle.pinchHarmonic => 'P.H.',
          _ => null,
        };
        if (hLabel != null && left.isFinite) {
          primitives.add(TextPrimitive(
            hLabel,
            Point(x, -0.6),
            size: 1.0,
            elementId: element.id,
          ));
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

    // Vibrato: a horizontal wavy line above the fret.
    for (final vibrato in score.vibratos) {
      final at = anchor[vibrato.noteId];
      if (at == null) continue;
      _layoutVibrato(primitives, at.$1, at.$2, vibrato.wide);
    }

    // Tapping: a "T" above the fret.
    for (final tap in score.taps) {
      final at = anchor[tap.noteId];
      if (at == null) continue;
      primitives.add(TextPrimitive('T', Point(at.$1, at.$2 - 1.0), size: 1.1));
    }

    // Tremolo bar (whammy): a V above the fret with the dip amount.
    for (final tb in score.tremoloBars) {
      final at = anchor[tb.noteId];
      if (at == null) continue;
      _layoutTremoloBar(primitives, at.$1, at.$2, tb.steps);
    }

    // Chord diagrams placed above the staff over their note.
    for (final placed in score.chordDiagrams) {
      final at = anchor[placed.elementId];
      if (at == null) continue;
      final (prims, _, _, _, _) = placeChordDiagram(placed.diagram, s,
          centerX: at.$1, bottomY: -1.6, scale: placed.scale);
      primitives.addAll(prims);
    }

    // Palm mute / let ring: a labelled dashed bracket above the staff.
    for (final pm in score.palmMutes) {
      final a = anchor[pm.startId];
      final b = anchor[pm.endId];
      if (a == null || b == null) continue;
      _layoutTextBracket(primitives, 'P.M.', a.$1, b.$1, s);
    }
    for (final lr in score.letRings) {
      final a = anchor[lr.startId];
      final b = anchor[lr.endId];
      if (a == null || b == null) continue;
      _layoutTextBracket(primitives, 'let ring', a.$1, b.$1, s);
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

    // String lines, broken behind any digits (starting after the gutter).
    for (var i = 0; i < n; i++) {
      final y = yOfString(i);
      final ranges = [...breaks[i]]..sort((a, b) => a.$1.compareTo(b.$1));
      var cursor = gutter;
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

    // Vertical ink bounds. Technique marks (bends, vibrato, palm-mute / let-
    // ring labels) extend above the staff and rhythm below it, so derive
    // top/height from the actual primitives — a fixed constant would clip
    // them and break the ScoreLayout `top`/`bounds` contract.
    var minY = 0.0; // the top string line
    var maxY = bottomY;
    void span(double a, double b) {
      minY = min(minY, min(a, b));
      maxY = max(maxY, max(a, b));
    }

    for (final p in primitives) {
      switch (p) {
        case GlyphPrimitive(:final smuflName, :final position, :final scale):
          final box = meta.bBoxOf(smuflName);
          span(position.y - box.neY * scale, position.y - box.swY * scale);
        case LinePrimitive(:final from, :final to):
          span(from.y, to.y);
        case CurvePrimitive(
            :final start,
            :final control1,
            :final control2,
            :final end
          ):
          span(min(min(start.y, control1.y), min(control2.y, end.y)),
              max(max(start.y, control1.y), max(control2.y, end.y)));
        case BeamPrimitive(:final start, :final end, :final thickness):
          span(min(start.y, end.y) - thickness / 2,
              max(start.y, end.y) + thickness / 2);
        case TextPrimitive(:final position, :final size):
          // Center-baseline text: ascenders rise ~0.8 em, descenders ~0.25.
          span(position.y - 0.8 * size, position.y + 0.25 * size);
      }
    }
    const pad = 0.3;

    return ScoreLayout(
      width: width,
      height: maxY - minY + 2 * pad,
      top: minY - pad,
      primitives: List.unmodifiable(primitives),
      regions: List.unmodifiable(regions),
      measureRegions: List.unmodifiable(measureRegions),
    );
  }

  /// Draws a horizontal wavy vibrato line above the fret at ([bx], [by]).
  void _layoutVibrato(
      List<LayoutPrimitive> primitives, double bx, double by, bool wide) {
    final amp = wide ? 0.5 : 0.28;
    const half = 0.5; // horizontal length of each half-wave
    const count = 4; // number of half-waves
    final baseY = by - 1.0;
    var px = bx - 0.4;
    for (var k = 0; k < count; k++) {
      final dir = k.isEven ? -1.0 : 1.0;
      final peakY = baseY + dir * amp;
      primitives.add(CurvePrimitive(
        Point(px, baseY),
        Point(px + half * 0.4, peakY),
        Point(px + half * 0.6, peakY),
        Point(px + half, baseY),
        thickness: wide ? 0.16 : 0.13,
      ));
      px += half;
    }
  }

  /// Draws a tremolo-bar V above the fret at ([bx], [by]) with the [steps]
  /// dip amount labelled at the bottom of the V.
  void _layoutTremoloBar(
      List<LayoutPrimitive> primitives, double bx, double by, double steps) {
    final topY = by - 1.4;
    final lowY = topY + 0.65;
    primitives.add(LinePrimitive(Point(bx - 0.1, topY), Point(bx + 0.35, lowY),
        thickness: 0.13));
    primitives.add(LinePrimitive(Point(bx + 0.35, lowY), Point(bx + 0.8, topY),
        thickness: 0.13));
    primitives.add(TextPrimitive(
      _tremoloBarLabel(steps),
      Point(bx + 0.35, lowY + 0.55),
      size: 1.0,
    ));
  }

  /// The conventional label for a tremolo-bar dip of [steps] whole tones.
  static String _tremoloBarLabel(double steps) {
    final mag = steps.abs();
    final magLabel = switch (mag) {
      0.25 => '¼',
      0.5 => '½',
      0.75 => '¾',
      1.5 => '1½',
      _ => mag == mag.roundToDouble() ? '${mag.toInt()}' : '$mag',
    };
    return '${steps < 0 ? '-' : ''}$magLabel';
  }

  /// Draws a [label] followed by a dashed bracket line above the staff, from
  /// [startX] to [endX], with a downward end tick. Used for palm mute and let
  /// ring. A single-note span (start ≈ end) draws just the label and the tick.
  void _layoutTextBracket(List<LayoutPrimitive> primitives, String label,
      double startX, double endX, LayoutSettings s) {
    const size = 1.1;
    const y = -1.4; // above the top string line (y = 0)
    // Center-baseline text: shift right so the label's left edge sits at startX.
    final labelHalf = 0.25 * size * label.length;
    primitives.add(TextPrimitive(
      label,
      Point(startX + labelHalf, y + 0.35),
      size: size,
    ));
    final lineStart = startX + 2 * labelHalf + 0.3;
    if (endX > lineStart + 0.3) {
      // Dashed line from after the label to the end.
      const dash = 0.4;
      const gap = 0.28;
      var px = lineStart;
      while (px < endX) {
        primitives.add(LinePrimitive(
          Point(px, y),
          Point(min(px + dash, endX), y),
          thickness: s.staffLineThickness,
        ));
        px += dash + gap;
      }
    }
    // Downward end tick.
    primitives.add(LinePrimitive(
      Point(endX, y),
      Point(endX, y + 0.5),
      thickness: s.staffLineThickness,
    ));
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

  /// Per-pitch (string, fret) for a note/chord. A pinned voicing ([pins]) is
  /// honored where playable; otherwise every tone is assigned a **distinct**
  /// string via [_assignChord] so two notes never land on the same line.
  static List<(int, int)?> _placeChord(
      List<Pitch> pitches, Tuning tuning, List<int>? pins) {
    if (pins == null) return _assignChord(pitches, tuning);
    return [
      for (var pi = 0; pi < pitches.length; pi++)
        () {
          if (pi < pins.length) {
            final s = pins[pi];
            if (s >= 0 && s < tuning.stringCount) {
              final f = pitches[pi].midiNumber - tuning.strings[s].midiNumber;
              if (f >= 0 && f <= 24) return (s, f);
            }
          }
          return tuning.fretFor(pitches[pi]);
        }(),
    ];
  }

  /// Assigns each pitch to a distinct string, greedily placing higher pitches
  /// on higher strings (lowest fret first) — the natural chord voicing. A
  /// pitch that can't be placed on a free string is dropped (null).
  static List<(int, int)?> _assignChord(List<Pitch> pitches, Tuning tuning) {
    final n = tuning.stringCount;
    final used = List<bool>.filled(n, false);
    final result = List<(int, int)?>.filled(pitches.length, null);
    // Strings from highest open pitch to lowest.
    final strings = List.generate(n, (i) => i)
      ..sort((a, b) =>
          tuning.strings[b].midiNumber.compareTo(tuning.strings[a].midiNumber));
    // Pitches high to low, so the top voice claims the top string first.
    final order = List.generate(pitches.length, (i) => i)
      ..sort((a, b) => pitches[b].midiNumber.compareTo(pitches[a].midiNumber));
    for (final pi in order) {
      final midi = pitches[pi].midiNumber;
      for (final si in strings) {
        if (used[si]) continue;
        final fret = midi - tuning.strings[si].midiNumber;
        if (fret < 0 || fret > 24) continue;
        used[si] = true;
        result[pi] = (si, fret);
        break;
      }
    }
    return result;
  }

  /// The open string's note letter (with accidental) for a tuning label.
  static String _noteLetter(Pitch pitch) {
    const acc = {-2: 'bb', -1: 'b', 0: '', 1: '#', 2: '##'};
    return '${pitch.step.name.toUpperCase()}${acc[pitch.alter] ?? ''}';
  }

  /// A pitch [semitones] higher (by MIDI number, sharps spelling) — used to
  /// shift open strings up for a capo.
  static Pitch _shiftPitch(Pitch pitch, int semitones) {
    const table = [
      (Step.c, 0), (Step.c, 1), (Step.d, 0), (Step.d, 1), //
      (Step.e, 0), (Step.f, 0), (Step.f, 1), (Step.g, 0),
      (Step.g, 1), (Step.a, 0), (Step.a, 1), (Step.b, 0),
    ];
    final midi = pitch.midiNumber + semitones;
    final (step, alter) = table[midi % 12];
    return Pitch(step, alter: alter, octave: midi ~/ 12 - 1);
  }

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
