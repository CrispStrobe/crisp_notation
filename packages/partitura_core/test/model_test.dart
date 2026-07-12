import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  group('Score.simple DSL', () {
    test('parses pitches and durations', () {
      final score = Score.simple(notes: 'c4:q d4:q e4:h');
      expect(score.measures, hasLength(1));
      final elements = score.measures.first.elements;
      expect(elements, hasLength(3));
      expect(
        elements[0],
        const NoteElement(
          pitches: [Pitch(Step.c)],
          duration: NoteDuration.quarter,
          id: 'e0',
        ),
      );
      expect(
        (elements[2] as NoteElement).duration,
        NoteDuration.half,
      );
    });

    test('durations are sticky and default to quarter', () {
      final score = Score.simple(notes: 'c4 d4:e e4 f4:h g4');
      final durations =
          score.measures.first.elements.map((e) => e.duration).toList();
      expect(durations, [
        NoteDuration.quarter,
        NoteDuration.eighth,
        NoteDuration.eighth,
        NoteDuration.half,
        NoteDuration.half,
      ]);
    });

    test('dotted durations', () {
      final score = Score.simple(notes: 'c4:q. d4:h..');
      expect(
        score.measures.first.elements[0].duration,
        const NoteDuration(DurationBase.quarter, dots: 1),
      );
      expect(
        score.measures.first.elements[1].duration,
        const NoteDuration(DurationBase.half, dots: 2),
      );
    });

    test('rests', () {
      final score = Score.simple(notes: 'c4:q r r:h');
      final elements = score.measures.first.elements;
      expect(elements[1], const RestElement(NoteDuration.quarter, id: 'e1'));
      expect(elements[2], const RestElement(NoteDuration.half, id: 'e2'));
    });

    test('chords via +', () {
      final score = Score.simple(notes: 'c4+e4+g4:h');
      final chord = score.measures.first.elements.single as NoteElement;
      expect(chord.pitches, const [
        Pitch(Step.c),
        Pitch(Step.e),
        Pitch(Step.g),
      ]);
      expect(chord.duration, NoteDuration.half);
    });

    test('measures split on |', () {
      final score = Score.simple(
        timeSignature: TimeSignature.threeFour,
        notes: 'c4:q d4 e4 | f4 g4 a4 | b4:h.',
      );
      expect(score.measures, hasLength(3));
      for (final measure in score.measures) {
        expect(measure.totalDuration, Fraction(3, 4), reason: '$measure');
      }
    });

    test('accidentals incl. forced naturals', () {
      final score = Score.simple(notes: 'f#4:q bb3 cn5');
      final elements = score.measures.first.elements.cast<NoteElement>();
      expect(elements[0].pitches.single, const Pitch(Step.f, alter: 1));
      expect(elements[0].showAccidental, isNull);
      expect(
        elements[1].pitches.single,
        const Pitch(Step.b, alter: -1, octave: 3),
      );
      expect(elements[2].pitches.single, const Pitch(Step.c, octave: 5));
      expect(elements[2].showAccidental, isTrue);
    });

    test('ids are assigned in reading order across measures', () {
      final score = Score.simple(notes: 'c4:q d4 | r e4');
      final ids = [
        for (final measure in score.measures)
          for (final element in measure.elements) element.id,
      ];
      expect(ids, ['e0', 'e1', 'e2', 'e3']);
    });

    test('carries clef and signatures', () {
      final score = Score.simple(
        clef: Clef.bass,
        keySignature: const KeySignature(-2),
        timeSignature: TimeSignature.fourFour,
        notes: 'c3:w',
      );
      expect(score.clef, Clef.bass);
      expect(score.keySignature, const KeySignature(-2));
      expect(score.timeSignature, TimeSignature.fourFour);
    });

    test('rejects malformed input', () {
      expect(() => Score.simple(notes: 'h4:q'), throwsFormatException);
      expect(() => Score.simple(notes: 'c4:z'), throwsFormatException);
      expect(() => Score.simple(notes: 'c4:q:q'), throwsFormatException);
      expect(() => Score.simple(notes: 'c4:q...'), throwsFormatException);
      expect(() => Score.simple(notes: 'c+4'), throwsFormatException);
    });
  });

  group('Measure.totalDuration', () {
    test('sums exactly', () {
      final measure = Measure([
        NoteElement.note(const Pitch(Step.c), NoteDuration.quarter),
        const RestElement(NoteDuration.eighth),
        NoteElement.note(
          const Pitch(Step.d),
          const NoteDuration(DurationBase.eighth, dots: 1),
        ),
      ]);
      // 1/4 + 1/8 + 3/16 = 9/16.
      expect(measure.totalDuration, Fraction(9, 16));
      expect(const Measure([]).totalDuration, Fraction.zero);
    });
  });

  group('value semantics', () {
    test('elements', () {
      expect(
        NoteElement.note(const Pitch(Step.c), NoteDuration.quarter),
        NoteElement.note(const Pitch(Step.c), NoteDuration.quarter),
      );
      expect(
        NoteElement.note(const Pitch(Step.c), NoteDuration.quarter),
        isNot(NoteElement.note(const Pitch(Step.d), NoteDuration.quarter)),
      );
      expect(
        NoteElement.note(const Pitch(Step.c), NoteDuration.quarter, id: 'a'),
        isNot(NoteElement.note(const Pitch(Step.c), NoteDuration.quarter)),
      );
      expect(
        const RestElement(NoteDuration.quarter),
        const RestElement(NoteDuration.quarter),
      );
      expect(
        const RestElement(NoteDuration.quarter),
        isNot(const RestElement(NoteDuration.half)),
      );
    });

    test('scores parsed from the same string are equal', () {
      expect(
        Score.simple(notes: 'c4:q d4 | e4:h'),
        Score.simple(notes: 'c4:q d4 | e4:h'),
      );
      expect(
        Score.simple(notes: 'c4:q'),
        isNot(Score.simple(notes: 'c4:h')),
      );
      expect(
        Score.simple(notes: 'c4:q'),
        isNot(Score.simple(notes: 'c4:q', clef: Clef.bass)),
      );
    });
  });
}
