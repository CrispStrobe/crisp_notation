import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Constructor validation: invalid arguments must fail loudly (asserts in
/// debug mode) instead of producing silently wrong theory.
void main() {
  group('Interval validation', () {
    test('perfect-class numbers reject major/minor qualities', () {
      for (final number in [1, 4, 5, 8]) {
        expect(() => Interval(IntervalQuality.major, number),
            throwsA(isA<AssertionError>()),
            reason: 'major $number');
        expect(() => Interval(IntervalQuality.minor, number),
            throwsA(isA<AssertionError>()),
            reason: 'minor $number');
      }
    });

    test('imperfect numbers reject the perfect quality', () {
      for (final number in [2, 3, 6, 7]) {
        expect(() => Interval(IntervalQuality.perfect, number),
            throwsA(isA<AssertionError>()),
            reason: 'perfect $number');
      }
    });

    test('numbers outside 1..8 are rejected', () {
      expect(() => Interval(IntervalQuality.major, 0),
          throwsA(isA<AssertionError>()));
      expect(() => Interval(IntervalQuality.major, 9),
          throwsA(isA<AssertionError>()));
      expect(() => Interval(IntervalQuality.perfect, -1),
          throwsA(isA<AssertionError>()));
    });

    test('all valid combinations construct', () {
      for (var number = 1; number <= 8; number++) {
        final perfectClass = {1, 4, 5, 8}.contains(number);
        final valid = perfectClass
            ? [
                IntervalQuality.diminished,
                IntervalQuality.perfect,
                IntervalQuality.augmented,
              ]
            : [
                IntervalQuality.diminished,
                IntervalQuality.minor,
                IntervalQuality.major,
                IntervalQuality.augmented,
              ];
        for (final quality in valid) {
          expect(Interval(quality, number).semitones, isA<int>(),
              reason: '$quality $number');
        }
      }
    });
  });

  group('other constructor guards', () {
    test('Pitch rejects alterations beyond double sharp/flat', () {
      expect(() => Pitch(Step.c, alter: 3), throwsA(isA<AssertionError>()));
      expect(() => Pitch(Step.c, alter: -3), throwsA(isA<AssertionError>()));
    });

    test('NoteDuration rejects more than two dots', () {
      expect(() => NoteDuration(DurationBase.quarter, dots: 3),
          throwsA(isA<AssertionError>()));
      expect(() => NoteDuration(DurationBase.quarter, dots: -1),
          throwsA(isA<AssertionError>()));
    });

    test('TimeSignature rejects invalid beats and beat units', () {
      expect(() => TimeSignature(0, 4), throwsA(isA<AssertionError>()));
      expect(() => TimeSignature(4, 3), throwsA(isA<AssertionError>()));
      expect(() => TimeSignature(4, 32), throwsA(isA<AssertionError>()));
      expect(() => TimeSignature(4, 0), throwsA(isA<AssertionError>()));
      // Valid power-of-two units all construct.
      for (final unit in [1, 2, 4, 8, 16]) {
        expect(TimeSignature(3, unit).beatUnit, unit);
      }
    });

    test('Triad rejects inversions outside 0..2', () {
      expect(() => Triad(const Pitch(Step.c), ChordQuality.major, inversion: 3),
          throwsA(isA<AssertionError>()));
      expect(
          () => Triad(const Pitch(Step.c), ChordQuality.major, inversion: -1),
          throwsA(isA<AssertionError>()));
    });

    test('KeySignature rejects more than seven accidentals', () {
      expect(() => KeySignature(8), throwsA(isA<AssertionError>()));
      expect(() => KeySignature(-8), throwsA(isA<AssertionError>()));
    });
  });

  group('value-type contracts', () {
    test('Key equality and parallel-key signature relation', () {
      expect(const Key.major(Pitch(Step.g)), const Key.major(Pitch(Step.g)));
      expect(
        const Key.major(Pitch(Step.g)),
        isNot(const Key.minor(Pitch(Step.g))),
      );
      expect(
        const Key.major(Pitch(Step.g)).hashCode,
        const Key.major(Pitch(Step.g)).hashCode,
      );
      // A parallel minor always sits three fifths flatward.
      for (final source in ['c4', 'g4', 'd4', 'f4', 'bb4', 'e4']) {
        final tonic = Pitch.parse(source);
        expect(
          Key.major(tonic).signature.fifths - Key.minor(tonic).signature.fifths,
          3,
          reason: source,
        );
      }
    });

    test('Score equality distinguishes null and set time signatures', () {
      final unmetered = Score.simple(notes: 'c4:q');
      final metered = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q',
      );
      expect(unmetered, isNot(metered));
      expect(unmetered, Score.simple(notes: 'c4:q'));
    });

    test('equal scores hash equally', () {
      final a = Score.simple(
        keySignature: const KeySignature(2),
        timeSignature: TimeSignature.threeFour,
        notes: 'f#4:q g4+b4 a4 | d5:h.',
      );
      final b = Score.simple(
        keySignature: const KeySignature(2),
        timeSignature: TimeSignature.threeFour,
        notes: 'f#4:q g4+b4 a4 | d5:h.',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('GhostNote-free core types have stable toStrings', () {
      expect(const Pitch(Step.f, alter: 1, octave: 3).toString(), 'F#3');
      expect(Interval.minorSixth.toString(), 'm6');
      expect(const KeySignature(-3).toString(), 'KeySignature(-3)');
      expect(TimeSignature.sixEight.toString(), '6/8');
      expect(
        const Scale(Pitch(Step.d), ScaleType.melodicMinor).toString(),
        'Scale(D4 melodicMinor)',
      );
      expect(
        const Triad(Pitch(Step.e), ChordQuality.diminished, inversion: 2)
            .toString(),
        'Triad(E4 diminished, inv 2)',
      );
      expect(const Key.minor(Pitch(Step.b)).toString(), 'Key(B4 minor)');
    });
  });

  group('fraction algebra extras', () {
    test('multiplication distributes over addition (sampled)', () {
      final samples = [
        for (var n = -3; n <= 3; n++)
          for (final d in [1, 2, 3, 8]) Fraction(n, d),
      ];
      for (final a in samples) {
        for (final b in samples) {
          for (final c in [Fraction(1, 2), Fraction(-2, 3), Fraction(3, 16)]) {
            expect(c * (a + b), c * a + c * b, reason: '$c * ($a + $b)');
          }
        }
      }
    });

    test('compareTo is transitive over a sorted sample', () {
      final samples = [
        for (var n = -6; n <= 6; n++)
          for (final d in [1, 2, 3, 4, 5, 8, 16]) Fraction(n, d),
      ]..sort();
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i - 1].compareTo(samples[i]), lessThanOrEqualTo(0),
            reason: '${samples[i - 1]} <= ${samples[i]}');
      }
    });
  });
}
