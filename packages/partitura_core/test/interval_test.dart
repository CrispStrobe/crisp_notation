import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  group('Interval.semitones', () {
    test('all named constants', () {
      expect(Interval.perfectUnison.semitones, 0);
      expect(Interval.minorSecond.semitones, 1);
      expect(Interval.majorSecond.semitones, 2);
      expect(Interval.minorThird.semitones, 3);
      expect(Interval.majorThird.semitones, 4);
      expect(Interval.perfectFourth.semitones, 5);
      expect(Interval.augmentedFourth.semitones, 6);
      expect(Interval.diminishedFifth.semitones, 6);
      expect(Interval.perfectFifth.semitones, 7);
      expect(Interval.augmentedFifth.semitones, 8);
      expect(Interval.minorSixth.semitones, 8);
      expect(Interval.majorSixth.semitones, 9);
      expect(Interval.minorSeventh.semitones, 10);
      expect(Interval.majorSeventh.semitones, 11);
      expect(Interval.perfectOctave.semitones, 12);
    });

    test('diminished and augmented of both classes', () {
      expect(const Interval(IntervalQuality.diminished, 4).semitones, 4);
      expect(const Interval(IntervalQuality.augmented, 1).semitones, 1);
      expect(const Interval(IntervalQuality.diminished, 7).semitones, 9);
      expect(const Interval(IntervalQuality.augmented, 6).semitones, 10);
      expect(const Interval(IntervalQuality.diminished, 8).semitones, 11);
    });
  });

  group('Interval.between', () {
    test('recovers quality from spelling', () {
      expect(
        Interval.between(const Pitch(Step.c), const Pitch(Step.e)),
        Interval.majorThird,
      );
      expect(
        Interval.between(const Pitch(Step.c), const Pitch(Step.e, alter: -1)),
        Interval.minorThird,
      );
      expect(
        Interval.between(const Pitch(Step.c), const Pitch(Step.g)),
        Interval.perfectFifth,
      );
      expect(
        Interval.between(const Pitch(Step.c), const Pitch(Step.c, octave: 5)),
        Interval.perfectOctave,
      );
      expect(
        Interval.between(const Pitch(Step.c), const Pitch(Step.c)),
        Interval.perfectUnison,
      );
    });

    test('distinguishes enharmonic spellings (A4 vs d5)', () {
      expect(
        Interval.between(const Pitch(Step.c), const Pitch(Step.f, alter: 1)),
        Interval.augmentedFourth,
      );
      expect(
        Interval.between(const Pitch(Step.c), const Pitch(Step.g, alter: -1)),
        Interval.diminishedFifth,
      );
    });

    test('is order-insensitive', () {
      expect(
        Interval.between(const Pitch(Step.e), const Pitch(Step.c)),
        Interval.majorThird,
      );
      // B3 up to G4 spans B C D E F G: a minor sixth.
      expect(
        Interval.between(const Pitch(Step.g), const Pitch(Step.b, octave: 3)),
        Interval.minorSixth,
      );
    });

    test('crosses octave boundaries', () {
      expect(
        Interval.between(
          const Pitch(Step.b, octave: 3),
          const Pitch(Step.f, octave: 4),
        ),
        Interval.diminishedFifth,
      );
      expect(
        Interval.between(
          const Pitch(Step.a, octave: 3),
          const Pitch(Step.c, octave: 4),
        ),
        Interval.minorThird,
      );
    });

    test('rejects spans wider than an octave or unnameable intervals', () {
      expect(
        () => Interval.between(
          const Pitch(Step.c),
          const Pitch(Step.d, octave: 5),
        ),
        throwsArgumentError,
      );
      // C4 to G##4 would be a doubly augmented fifth.
      expect(
        () => Interval.between(
          const Pitch(Step.c),
          const Pitch(Step.g, alter: 2),
        ),
        throwsArgumentError,
      );
    });
  });

  group('value semantics', () {
    test('equality and toString', () {
      expect(
        const Interval(IntervalQuality.major, 3),
        Interval.majorThird,
      );
      expect(
        const Interval(IntervalQuality.major, 3).hashCode,
        Interval.majorThird.hashCode,
      );
      expect(Interval.majorThird, isNot(Interval.minorThird));
      expect(Interval.majorThird.toString(), 'M3');
      expect(Interval.perfectFifth.toString(), 'P5');
      expect(Interval.diminishedFifth.toString(), 'd5');
      expect(Interval.minorSeventh.toString(), 'm7');
      expect(Interval.augmentedFourth.toString(), 'A4');
    });
  });
}
