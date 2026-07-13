import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Humdrum `**kern` — a single-spine subset codec. A subset-only score writes
/// and reads back exactly; documented losses are asserted separately.
void main() {
  test('exact round-trip: clef, key, meter, chords, rests, dots', () {
    final source = Score.simple(
      clef: Clef.bass,
      keySignature: const KeySignature(-3),
      timeSignature: TimeSignature.fourFour,
      notes: 'c3+e3+g3:h. r:q | e2:q f2 g2:q. a2:e',
    );
    expect(scoreFromKern(scoreToKern(source)), source);
  });

  test('exact round-trip: ties across a barline', () {
    final source = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:h~ c4:h~ | c4:w',
    );
    expect(scoreFromKern(scoreToKern(source)), source);
  });

  test('exact round-trip: mid-score clef / key / time changes', () {
    final source = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | !clef=bass !key=3 !time=3/4 c3:q d3 e3',
    );
    expect(scoreFromKern(scoreToKern(source)), source);
  });

  test('exact round-trip: common time keeps its symbol', () {
    final source = Score.simple(
      timeSignature: TimeSignature.commonTime,
      notes: 'c4:w',
    );
    final back = scoreFromKern(scoreToKern(source));
    expect(back.timeSignature, TimeSignature.commonTime);
    expect(back, source);
  });

  test('exact round-trip: additive meter', () {
    final source = Score.simple(
      timeSignature: TimeSignature.additive([3, 2], 8),
      notes: 'c4:e d4 e4 f4 g4',
    );
    expect(scoreFromKern(scoreToKern(source)).timeSignature,
        TimeSignature.additive([3, 2], 8));
  });

  test('exact round-trip: pickup detected from a short first bar', () {
    final source = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q | c5:q d5 e5 f5 | g5:w',
    );
    expect(source.measures.first.pickup, isTrue);
    final back = scoreFromKern(scoreToKern(source));
    expect(back.measures.first.pickup, isTrue);
    expect(back, source);
  });

  test('enharmonic spelling survives (C# stays C#, not Db)', () {
    final source = Score.simple(notes: 'c#4:q db4:q');
    final names = scoreFromKern(scoreToKern(source))
        .measures
        .single
        .elements
        .whereType<NoteElement>()
        .map((n) => n.pitches.single.toString())
        .toList();
    expect(names, ['C#4', 'Db4']);
  });

  test('octave letters: case + repetition', () {
    // C4 = "c", C5 = "cc", C3 = "C", C2 = "CC".
    final kern = scoreToKern(Score.simple(notes: 'c4:q c5 c3 c2'));
    expect(kern, contains('4c\n'));
    expect(kern, contains('4cc\n'));
    expect(kern, contains('4C\n'));
    expect(kern, contains('4CC\n'));
  });

  test('reads a hand-written kern document', () {
    const kern = '''
**kern
*clefG2
*k[f#]
*M3/4
4c
4r
8.f#
4g 4b
=
2cc
4dd
==
*-
''';
    final score = scoreFromKern(kern);
    expect(score.clef, Clef.treble);
    expect(score.keySignature.fifths, 1);
    expect(score.timeSignature, TimeSignature.threeFour);
    expect(score.measures, hasLength(2));
    final first = score.measures.first.elements;
    expect(first, hasLength(4));
    expect((first[0] as NoteElement).pitches.single, const Pitch(Step.c));
    expect(first[1], isA<RestElement>());
    expect((first[2] as NoteElement).pitches.single,
        const Pitch(Step.f, alter: 1));
    expect(first[2].duration, const NoteDuration(DurationBase.eighth, dots: 1));
    expect((first[3] as NoteElement).pitches, hasLength(2)); // chord
  });

  test('rejects a non-kern document', () {
    expect(() => scoreFromKern('<score-partwise/>'), throwsFormatException);
  });

  group('tuplets', () {
    test('reads a triplet reciprocal as a TupletSpan of written notes', () {
      final score = scoreFromKern('**kern\n*clefG2\n6cc\n6dd\n6ee\n*-');
      final measure = score.measures.single;
      expect(measure.tuplets, [const TupletSpan(0, 2, actual: 3, normal: 2)]);
      // Written value is a quarter (recip 4); the ratio scales the sounding time.
      for (final e in measure.elements) {
        expect((e as NoteElement).duration.base, DurationBase.quarter);
      }
    });

    test('eighth-triplet reciprocal 12 also reads as 3:2', () {
      final m = scoreFromKern('**kern\n*clefG2\n12cc\n12dd\n12ee\n*-')
          .measures
          .single;
      expect(m.tuplets, [const TupletSpan(0, 2, actual: 3, normal: 2)]);
      expect((m.elements.first as NoteElement).duration.base,
          DurationBase.eighth);
    });

    test('round-trips a slur through kern (( and ))', () {
      final source = Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(
                pitches: [const Pitch(Step.c, octave: 4)],
                duration: NoteDuration.quarter,
                id: 'a'),
            NoteElement(
                pitches: [const Pitch(Step.d, octave: 4)],
                duration: NoteDuration.quarter,
                id: 'b'),
            NoteElement(
                pitches: [const Pitch(Step.e, octave: 4)],
                duration: NoteDuration.quarter,
                id: 'c'),
          ]),
        ],
        slurs: const [Slur('a', 'c')],
      );
      final kern = scoreToKern(source);
      expect(kern, contains('(4c'));
      expect(kern, contains('4e)'));
      final back = scoreFromKern(kern);
      expect(back.slurs.length, 1);
      final ids =
          back.measures.single.elements.map((e) => e.id).toList();
      expect(back.slurs.single.startId, ids.first);
      expect(back.slurs.single.endId, ids.last);
    });

    test('round-trips a triplet through kern (recip 6 out and back)', () {
      final source = Score(
        clef: Clef.treble,
        measures: [
          Measure(
            [
              NoteElement(
                  pitches: [const Pitch(Step.c, octave: 5)],
                  duration: NoteDuration.quarter,
                  id: 'a'),
              NoteElement(
                  pitches: [const Pitch(Step.d, octave: 5)],
                  duration: NoteDuration.quarter,
                  id: 'b'),
              NoteElement(
                  pitches: [const Pitch(Step.e, octave: 5)],
                  duration: NoteDuration.quarter,
                  id: 'c'),
            ],
            tuplets: const [TupletSpan(0, 2, actual: 3, normal: 2)],
          ),
        ],
      );
      final kern = scoreToKern(source);
      expect(kern, contains('6cc'));
      final measure = scoreFromKern(kern).measures.single;
      expect(measure.tuplets, source.measures.single.tuplets);
      expect(measure.elements.length, 3);
    });
  });
}
