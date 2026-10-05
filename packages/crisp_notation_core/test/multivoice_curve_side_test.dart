import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Which side ties and slurs curve on in chords and multi-voice bars —
/// GitHub issue #2 ("lower note ties do not render properly … when one of
/// the tied notes is a double stop").
///
/// Before the fix every tie of a chord took the same side (opposite the
/// stem), so in a double stop the inner tie ran into the other notehead; in a
/// two-voice bar the upper voice's tie curved down and the lower voice's up,
/// crossing; and a slur in the upper voice counted the lower voice's notes as
/// obstacles and dove under its stems.
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<CurvePrimitive> curvesOf(ScoreLayout layout) =>
    layout.primitives.whereType<CurvePrimitive>().toList();

/// The y of [id]'s notehead glyphs, top to bottom.
List<double> headYs(ScoreLayout layout, String id) => [
      for (final g in layout.primitives.whereType<GlyphPrimitive>())
        if (g.elementId == id && g.smuflName.startsWith('notehead'))
          g.position.y,
    ]..sort();

NoteElement note(List<Pitch> pitches, NoteDuration d, String id,
        {bool tie = false}) =>
    NoteElement(pitches: pitches, duration: d, id: id, tieToNext: tie);

/// Whether a curve bulges upward (control points above its endpoints).
bool bulgesUp(CurvePrimitive c) => c.control1.y < c.start.y;

const f4 = Pitch(Step.f),
    b4 = Pitch(Step.b, alter: -1),
    c5 = Pitch(Step.c, octave: 5);

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    settings = LayoutSettings(
        metadata:
            SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>));
  });

  group('chord ties split', () {
    for (final (name, pitches) in [
      ('stems up (low double stop)', [f4, b4]),
      (
        'stems down (high double stop)',
        [
          const Pitch(Step.d, octave: 5),
          const Pitch(Step.a, octave: 5),
        ]
      ),
    ]) {
      test('$name: the upper tie curves up, the lower tie down', () {
        final layout = layoutOf(Score(clef: Clef.treble, measures: [
          Measure([
            note(pitches, NoteDuration.half, 'a', tie: true),
            note(pitches, NoteDuration.half, 'b'),
          ]),
        ]));
        final ties = curvesOf(layout)
          ..sort((p, q) => p.start.y.compareTo(q.start.y));
        expect(ties, hasLength(2));
        final [top, bottom] = headYs(layout, 'a');
        expect(bulgesUp(ties.first), isTrue, reason: 'upper tie goes up');
        expect(ties.first.start.y, lessThan(top));
        expect(bulgesUp(ties.last), isFalse, reason: 'lower tie goes down');
        expect(ties.last.start.y, greaterThan(bottom));
      });
    }

    test('only the lower note of a double stop tied: it curves down', () {
      // The reported shape: a stems-down double stop whose LOWER note is tied
      // on into a single note. Opposite-the-stem sent it up into the upper
      // notehead.
      const lower = Pitch(Step.d, octave: 5), upper = Pitch(Step.a, octave: 5);
      final layout = layoutOf(Score(clef: Clef.treble, measures: [
        Measure([
          note([lower, upper], NoteDuration.half, 'a', tie: true),
          note([lower], NoteDuration.half, 'b'),
        ]),
      ]));
      final tie = curvesOf(layout).single;
      expect(bulgesUp(tie), isFalse);
      expect(tie.start.y, greaterThan(headYs(layout, 'a').last));
    });

    test('a three-note chord: middle tie goes away from the stem', () {
      const pitches = [Pitch(Step.e), Pitch(Step.g), Pitch(Step.b)];
      final layout = layoutOf(Score(clef: Clef.treble, measures: [
        Measure([
          note(pitches, NoteDuration.half, 'a', tie: true),
          note(pitches, NoteDuration.half, 'b'),
        ]),
      ]));
      final ties = curvesOf(layout)
        ..sort((p, q) => p.start.y.compareTo(q.start.y));
      expect(ties.map(bulgesUp), [true, false, false],
          reason: 'stems up: top up, middle and bottom down');
    });

    test('a single note still ties opposite the stem (no regression)', () {
      final below = curvesOf(layoutOf(Score.simple(notes: 'a4:q~ a4'))).single;
      expect(bulgesUp(below), isFalse);
      final above = curvesOf(layoutOf(Score.simple(notes: 'c5:q~ c5'))).single;
      expect(bulgesUp(above), isTrue);
    });
  });

  group('two voices', () {
    test('each voice ties on its stem side, so the ties never cross', () {
      final layout = layoutOf(Score(clef: Clef.treble, measures: [
        Measure([
          note([c5], NoteDuration.half, 'u0', tie: true),
          note([c5], NoteDuration.half, 'u1'),
        ], voice2: [
          note([f4], NoteDuration.half, 'l0', tie: true),
          note([f4], NoteDuration.half, 'l1'),
        ]),
      ]));
      final ties = curvesOf(layout)
        ..sort((p, q) => p.start.y.compareTo(q.start.y));
      expect(ties, hasLength(2));
      expect(bulgesUp(ties.first), isTrue, reason: 'voice 1 up');
      expect(bulgesUp(ties.last), isFalse, reason: 'voice 2 down');
      expect(ties.first.control1.y, lessThan(ties.last.control1.y));
    });

    test(
        'the reported bar: an upper-voice slur stays above, not under the '
        'lower voice', () {
      final layout = layoutOf(Score(
        clef: Clef.treble,
        keySignature: const KeySignature(-3),
        timeSignature: const TimeSignature(3, 4),
        measures: [
          Measure([
            note([b4], NoteDuration.half, 'u0'),
            note([const Pitch(Step.a, alter: -1)], NoteDuration.quarter, 'u1'),
          ], voice2: [
            note([f4], const NoteDuration(DurationBase.half, dots: 1), 'l0'),
          ]),
        ],
        slurs: const [Slur('u0', 'u1')],
      ));
      final slur = curvesOf(layout).single;
      expect(bulgesUp(slur), isTrue);
      // Entirely above the upper voice's noteheads — nowhere near the lower
      // voice's stem below the staff (the bug put it at y ≈ 8).
      final top = headYs(layout, 'u0').first;
      for (final y in [
        slur.start.y,
        slur.control1.y,
        slur.control2.y,
        slur.end.y
      ]) {
        expect(y, lessThan(top));
      }
    });

    test('a lower-voice slur stays below', () {
      final layout = layoutOf(Score(clef: Clef.treble, measures: [
        Measure([
          note([c5], NoteDuration.whole, 'u0'),
        ], voice2: [
          note([f4], NoteDuration.half, 'l0'),
          note([const Pitch(Step.e)], NoteDuration.half, 'l1'),
        ]),
      ], slurs: const [
        Slur('l0', 'l1')
      ]));
      final slur = curvesOf(layout).single;
      expect(bulgesUp(slur), isFalse);
      expect(slur.start.y, greaterThan(headYs(layout, 'l0').single));
    });

    test('a single-voice slur is unchanged (still opposite the stems)', () {
      final layout = layoutOf(Score.simple(
        notes: 'a4:q b4 a4 g4',
      ).copyWith(slurs: const [Slur('e0', 'e3')]));
      expect(bulgesUp(curvesOf(layout).single), isFalse);
    });
  });
}
