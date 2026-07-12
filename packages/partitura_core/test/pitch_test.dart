import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  group('Pitch.midiNumber', () {
    test('middle C is 60, concert A is 69', () {
      expect(const Pitch(Step.c).midiNumber, 60);
      expect(const Pitch(Step.a).midiNumber, 69);
    });

    test('alterations shift by semitones', () {
      expect(const Pitch(Step.f, alter: 1).midiNumber, 66); // F#4
      expect(const Pitch(Step.b, alter: -1, octave: 3).midiNumber, 58); // Bb3
      expect(const Pitch(Step.g, alter: 2).midiNumber, 69); // G##4
      expect(const Pitch(Step.e, alter: -2).midiNumber, 62); // Ebb4
    });

    test('octaves change at C', () {
      expect(const Pitch(Step.b, octave: 3).midiNumber, 59);
      expect(const Pitch(Step.c, octave: 5).midiNumber, 72);
      expect(const Pitch(Step.a, octave: 0).midiNumber, 21); // piano low A
      expect(const Pitch(Step.c, octave: 8).midiNumber, 108); // piano high C
    });

    test('enharmonic spellings across the octave boundary', () {
      expect(const Pitch(Step.b, alter: 1, octave: 3).midiNumber, 60); // B#3
      expect(const Pitch(Step.c, alter: -1).midiNumber, 59); // Cb4
    });
  });

  group('Pitch.staffPosition', () {
    test('treble: E4 sits on the bottom line, F5 on the top line', () {
      expect(const Pitch(Step.e).staffPosition(Clef.treble), 0);
      expect(const Pitch(Step.f, octave: 5).staffPosition(Clef.treble), 8);
      expect(const Pitch(Step.g).staffPosition(Clef.treble), 2); // clef line
      expect(const Pitch(Step.c).staffPosition(Clef.treble), -2); // ledger
    });

    test('bass: G2 sits on the bottom line, F3 on the clef line', () {
      expect(const Pitch(Step.g, octave: 2).staffPosition(Clef.bass), 0);
      expect(const Pitch(Step.f, octave: 3).staffPosition(Clef.bass), 6);
      expect(const Pitch(Step.a, octave: 3).staffPosition(Clef.bass), 8);
      // Middle C sits on the first ledger line above the bass staff.
      expect(const Pitch(Step.c).staffPosition(Clef.bass), 10);
    });

    test('alteration never moves the staff position', () {
      for (var alter = -2; alter <= 2; alter++) {
        expect(Pitch(Step.b, alter: alter).staffPosition(Clef.treble), 4);
      }
    });

    test('middle line and ledger ranges', () {
      expect(const Pitch(Step.b).staffPosition(Clef.treble), 4); // middle
      expect(const Pitch(Step.d, octave: 3).staffPosition(Clef.bass), 4);
      expect(const Pitch(Step.a, octave: 5).staffPosition(Clef.treble), 10);
      expect(const Pitch(Step.e, octave: 2).staffPosition(Clef.bass), -2);
    });
  });

  group('Pitch.transposeBy', () {
    test('spells diatonically upward', () {
      const c4 = Pitch(Step.c);
      expect(c4.transposeBy(Interval.majorThird), const Pitch(Step.e));
      expect(
        c4.transposeBy(Interval.minorThird),
        const Pitch(Step.e, alter: -1),
      );
      expect(c4.transposeBy(Interval.perfectFifth), const Pitch(Step.g));
      expect(
        c4.transposeBy(Interval.perfectOctave),
        const Pitch(Step.c, octave: 5),
      );
      expect(
        const Pitch(Step.b, octave: 3).transposeBy(Interval.minorSecond),
        const Pitch(Step.c),
      );
      expect(
        const Pitch(Step.f, alter: 1).transposeBy(Interval.perfectFifth),
        const Pitch(Step.c, alter: 1, octave: 5),
      );
      expect(
        const Pitch(Step.e, alter: -1).transposeBy(Interval.majorThird),
        const Pitch(Step.g),
      );
    });

    test('descending', () {
      const c5 = Pitch(Step.c, octave: 5);
      expect(
        c5.transposeBy(Interval.majorThird, descending: true),
        const Pitch(Step.a, alter: -1),
      );
      expect(
        c5.transposeBy(Interval.perfectFifth, descending: true),
        const Pitch(Step.f),
      );
      expect(
        c5.transposeBy(Interval.perfectOctave, descending: true),
        const Pitch(Step.c),
      );
    });

    test('unison and tritone spellings', () {
      const c4 = Pitch(Step.c);
      expect(c4.transposeBy(Interval.perfectUnison), c4);
      expect(
        c4.transposeBy(Interval.augmentedFourth),
        const Pitch(Step.f, alter: 1),
      );
      expect(
        c4.transposeBy(Interval.diminishedFifth),
        const Pitch(Step.g, alter: -1),
      );
    });

    test('throws beyond double alterations', () {
      // Fbb4 down a major third would be D triple-flat.
      expect(
        () => const Pitch(Step.f, alter: -2)
            .transposeBy(Interval.majorThird, descending: true),
        throwsArgumentError,
      );
    });
  });

  group('Pitch.isEnharmonicWith', () {
    test('detects equal-sounding spellings', () {
      expect(
        const Pitch(Step.c, alter: 1)
            .isEnharmonicWith(const Pitch(Step.d, alter: -1)),
        isTrue,
      );
      expect(
        const Pitch(Step.b, alter: 1, octave: 3)
            .isEnharmonicWith(const Pitch(Step.c)),
        isTrue,
      );
      expect(
        const Pitch(Step.c).isEnharmonicWith(const Pitch(Step.c, octave: 5)),
        isFalse,
      );
      expect(const Pitch(Step.c).isEnharmonicWith(const Pitch(Step.c)), isTrue);
    });
  });

  group('Pitch.parse', () {
    test('round-trips common spellings', () {
      expect(Pitch.parse('c4'), const Pitch(Step.c));
      expect(Pitch.parse('C4'), const Pitch(Step.c));
      expect(Pitch.parse('f#3'), const Pitch(Step.f, alter: 1, octave: 3));
      expect(Pitch.parse('bb2'), const Pitch(Step.b, alter: -1, octave: 2));
      expect(Pitch.parse('ebb5'), const Pitch(Step.e, alter: -2, octave: 5));
      expect(Pitch.parse('g##1'), const Pitch(Step.g, alter: 2, octave: 1));
      expect(Pitch.parse('an0'), const Pitch(Step.a, octave: 0));
    });

    test('rejects malformed input', () {
      expect(() => Pitch.parse('h4'), throwsFormatException);
      expect(() => Pitch.parse('c'), throwsFormatException);
      expect(() => Pitch.parse('c#'), throwsFormatException);
      expect(() => Pitch.parse('4c'), throwsFormatException);
      expect(() => Pitch.parse('c###4'), throwsFormatException);
      expect(() => Pitch.parse(''), throwsFormatException);
    });
  });

  group('value semantics', () {
    test('value equality', () {
      expect(const Pitch(Step.c), const Pitch(Step.c, alter: 0, octave: 4));
      expect(const Pitch(Step.c), isNot(const Pitch(Step.c, octave: 5)));
      expect(
        const Pitch(Step.c, alter: 1),
        isNot(const Pitch(Step.d, alter: -1)),
      );
      expect(
        const Pitch(Step.c).hashCode,
        const Pitch(Step.c, alter: 0, octave: 4).hashCode,
      );
    });

    test('toString', () {
      expect(const Pitch(Step.c).toString(), 'C4');
      expect(const Pitch(Step.f, alter: 1, octave: 3).toString(), 'F#3');
      expect(const Pitch(Step.b, alter: -2, octave: 2).toString(), 'Bbb2');
    });
  });

  group('Clef.pitchAt', () {
    test('is the inverse of staffPosition for naturals', () {
      for (final clef in Clef.values) {
        for (var position = -6; position <= 14; position++) {
          final pitch = clef.pitchAt(position);
          expect(pitch.alter, 0);
          expect(
            pitch.staffPosition(clef),
            position,
            reason: '$clef position $position gave $pitch',
          );
        }
      }
    });

    test('known anchors', () {
      expect(Clef.treble.pitchAt(0), const Pitch(Step.e));
      expect(Clef.treble.pitchAt(4), const Pitch(Step.b)); // middle line
      expect(Clef.treble.pitchAt(-2), const Pitch(Step.c)); // middle C
      expect(Clef.bass.pitchAt(0), const Pitch(Step.g, octave: 2));
      expect(Clef.bass.pitchAt(10), const Pitch(Step.c)); // middle C
    });
  });
}
