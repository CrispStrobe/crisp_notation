import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// What a slur or tie may treat as an obstacle. Each case was found by the
/// live corpus sweep's curve checks on real files (Für Elise, a Mutopia
/// guitar duo, Horetzky, a hymn, Bach's Contrapunctus V).
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<CurvePrimitive> curvesOf(ScoreLayout l, {required double thickness}) => [
      for (final c in l.primitives.whereType<CurvePrimitive>())
        if ((c.thickness - thickness).abs() < 1e-9) c
    ];

List<CurvePrimitive> slursOf(ScoreLayout l) => curvesOf(l, thickness: 0.2);
List<CurvePrimitive> tiesOf(ScoreLayout l) => curvesOf(l, thickness: 0.18);

/// The drawn curve's vertical extent (its control points overshoot it).
(double, double) extentOf(CurvePrimitive c) {
  final ys = [
    for (var k = 0; k <= 20; k++)
      () {
        final t = k / 20, u = 1 - t;
        return u * u * u * c.start.y +
            3 * u * u * t * c.control1.y +
            3 * u * t * t * c.control2.y +
            t * t * t * c.end.y;
      }()
  ];
  return (ys.reduce(min), ys.reduce(max));
}

NoteElement note(Pitch p, NoteDuration d, String id, {bool tie = false}) =>
    NoteElement(pitches: [p], duration: d, id: id, tieToNext: tie);

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    settings = LayoutSettings(
        metadata:
            SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>));
  });

  test('a slur hugs its notes and a hairpin under them goes below it', () {
    // Für Elise: dynamics were laid out BEFORE slurs, so a slur treated the
    // decrescendo under its two notes as an obstacle and dove beneath it.
    final score =
        Score.simple(notes: 'd4:e d5 c5 b4 a4 g4 f4 e4').copyWith(slurs: const [
      Slur('e0', 'e1')
    ], hairpins: const [
      Hairpin('e0', 'e7', HairpinType.diminuendo),
    ]);
    final layout = layoutOf(score);
    final (_, slurBottom) = extentOf(slursOf(layout).single);
    final hairpinTop = layout.primitives
        .whereType<LinePrimitive>()
        .where((l) =>
            l.elementId == null && l.from.y != l.to.y && l.from.x != l.to.x)
        .map((l) => min(l.from.y, l.to.y))
        .reduce(min);
    expect(slurBottom, lessThan(hairpinTop), reason: 'hairpin below the slur');
    expect(slurBottom, lessThan(6.5), reason: 'the slur stays near its notes');
  });

  test('a slur crossing a barline does not arch over the staff', () {
    // A guitar duo: a slur from the last note of one bar to the first of the
    // next, low on the staff, arched over the TOP staff line to clear the
    // barline between them.
    final score = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:h. c5:q | d5:w',
    ).copyWith(slurs: const [Slur('e1', 'e2')]);
    final (top, _) = extentOf(slursOf(layoutOf(score)).single);
    // C5 -> D5, stems down: the slur sits just above the noteheads (its top
    // near y -0.4). Clearing the barline's top (y 0) pushed it to ~-0.85.
    expect(top, greaterThan(-0.7));
  });

  test('a lower voice of rests still makes the upper slur take the top', () {
    // Horetzky: voice 2 only rests under a slurred upper voice; counting
    // only notes as "another voice" put the slur below, under the rests.
    final score = Score(clef: Clef.treble, measures: [
      Measure([
        note(const Pitch(Step.c, octave: 5), NoteDuration.quarter, 'u0'),
        note(const Pitch(Step.b), NoteDuration.quarter, 'u1'),
        note(const Pitch(Step.a), NoteDuration.half, 'u2'),
      ], voice2: [
        const RestElement(NoteDuration.quarter, id: 'r0'),
        const RestElement(NoteDuration.quarter, id: 'r1'),
        const RestElement(NoteDuration.half, id: 'r2'),
      ]),
    ], slurs: const [
      Slur('u0', 'u1')
    ]);
    final slur = slursOf(layoutOf(score)).single;
    expect(slur.control1.y, lessThan(slur.start.y), reason: 'bulges upward');
  });

  test('a tie across a clef change runs head to head', () {
    // alas.ly: G2 tied over a clef change sits at two different heights;
    // the tie was drawn flat at the first, ending in empty space.
    final score = Score(clef: Clef.bass, measures: [
      Measure([
        note(const Pitch(Step.g, octave: 2), NoteDuration.whole, 'a',
            tie: true),
      ]),
      Measure([note(const Pitch(Step.g, octave: 2), NoteDuration.whole, 'b')],
          clefChange: Clef.treble8vb),
    ]);
    final layout = layoutOf(score);
    double headY(String id) => layout.primitives
        .whereType<GlyphPrimitive>()
        .firstWhere(
            (g) => g.elementId == id && g.smuflName.startsWith('notehead'))
        .position
        .y;
    final tie = tiesOf(layout).single;
    expect(headY('a'), isNot(headY('b')), reason: 'the clef moves the head');
    expect((tie.start.y - headY('a')).abs(), closeTo(0.6, 1e-9));
    expect((tie.end.y - headY('b')).abs(), closeTo(0.6, 1e-9));
  });

  test('crossing voices: a tie flips rather than run through a notehead', () {
    // Contrapunctus V: the LOWER voice briefly sits above the upper one, so
    // its stem-side (downward) tie ran through the upper voice's notehead.
    final score = Score(clef: Clef.treble, measures: [
      // The upper voice's off-beat F4 sits between the lower voice's tied
      // A4s, right under a downward (stem-side) tie.
      Measure([
        note(const Pitch(Step.f, octave: 4), NoteDuration.eighth, 'u0'),
        note(const Pitch(Step.f, octave: 4), NoteDuration.eighth, 'u1'),
        note(const Pitch(Step.f, octave: 4), NoteDuration.quarter, 'u2'),
        note(const Pitch(Step.f, octave: 4), NoteDuration.half, 'u3'),
      ], voice2: [
        note(const Pitch(Step.a, octave: 4), NoteDuration.quarter, 'l0',
            tie: true),
        note(const Pitch(Step.a, octave: 4), NoteDuration.quarter, 'l1'),
        note(const Pitch(Step.e, octave: 4), NoteDuration.half, 'l2'),
      ]),
    ]);
    final layout = layoutOf(score);
    final heads = [
      for (final g in layout.primitives.whereType<GlyphPrimitive>())
        if (g.elementId != null && g.smuflName.startsWith('notehead')) g
    ];
    for (final tie in tiesOf(layout)) {
      final (top, bottom) = extentOf(tie);
      final x0 = min(tie.start.x, tie.end.x), x1 = max(tie.start.x, tie.end.x);
      for (final h in heads) {
        final cx = h.position.x + 0.59;
        expect(
            cx > x0 && cx < x1 && h.position.y > top && h.position.y < bottom,
            isFalse,
            reason: 'tie runs through ${h.elementId}');
      }
    }
  });
}
