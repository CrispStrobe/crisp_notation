import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  group('Key.signature', () {
    test('all fifteen major keys', () {
      const cases = {
        'cb4': -7, 'gb4': -6, 'db4': -5, 'ab4': -4, 'eb4': -3, 'bb4': -2,
        'f4': -1, 'c4': 0, 'g4': 1, 'd4': 2, 'a4': 3, 'e4': 4, 'b4': 5,
        'f#4': 6, 'c#4': 7, //
      };
      cases.forEach((tonic, fifths) {
        expect(
          Key.major(Pitch.parse(tonic)).signature,
          KeySignature(fifths),
          reason: '$tonic major',
        );
      });
    });

    test('all fifteen minor keys', () {
      const cases = {
        'ab4': -7, 'eb4': -6, 'bb4': -5, 'f4': -4, 'c4': -3, 'g4': -2,
        'd4': -1, 'a4': 0, 'e4': 1, 'b4': 2, 'f#4': 3, 'c#4': 4, 'g#4': 5,
        'd#4': 6, 'a#4': 7, //
      };
      cases.forEach((tonic, fifths) {
        expect(
          Key.minor(Pitch.parse(tonic)).signature,
          KeySignature(fifths),
          reason: '$tonic minor',
        );
      });
    });

    test('relative keys share a signature', () {
      expect(
        const Key.major(Pitch(Step.c)).signature,
        const Key.minor(Pitch(Step.a)).signature,
      );
      expect(
        const Key.major(Pitch(Step.e, alter: -1)).signature,
        const Key.minor(Pitch(Step.c)).signature,
      );
    });

    test('keys beyond seven accidentals throw', () {
      expect(
        () => const Key.major(Pitch(Step.g, alter: 1)).signature,
        throwsArgumentError, // G# major = 8 sharps
      );
      expect(
        () => const Key.major(Pitch(Step.f, alter: -1)).signature,
        throwsArgumentError, // Fb major = 8 flats
      );
    });
  });

  group('Key.triadFor', () {
    test('C major: T = C, S = F, D = G (all major)', () {
      const key = Key.major(Pitch(Step.c));
      expect(
        key.triadFor(HarmonicFunction.tonic),
        const Triad(Pitch(Step.c), ChordQuality.major),
      );
      expect(
        key.triadFor(HarmonicFunction.subdominant),
        const Triad(Pitch(Step.f), ChordQuality.major),
      );
      expect(
        key.triadFor(HarmonicFunction.dominant),
        const Triad(Pitch(Step.g), ChordQuality.major),
      );
    });

    test('D major transposes the functions', () {
      const key = Key.major(Pitch(Step.d));
      expect(
        key.triadFor(HarmonicFunction.subdominant).root,
        const Pitch(Step.g),
      );
      expect(
        key.triadFor(HarmonicFunction.dominant).root,
        const Pitch(Step.a),
      );
    });

    test('A minor: t = Am, s = Dm, D = E major (harmonic-minor dominant)', () {
      const key = Key.minor(Pitch(Step.a));
      expect(
        key.triadFor(HarmonicFunction.tonic),
        const Triad(Pitch(Step.a), ChordQuality.minor),
      );
      expect(
        key.triadFor(HarmonicFunction.subdominant),
        const Triad(Pitch(Step.d, octave: 5), ChordQuality.minor),
      );
      expect(
        key.triadFor(HarmonicFunction.dominant),
        const Triad(Pitch(Step.e, octave: 5), ChordQuality.major),
      );
    });

    test('functions land on scale degrees 1, 4 and 5', () {
      for (final tonicSource in ['c4', 'g4', 'f4', 'bb3', 'e4']) {
        final tonic = Pitch.parse(tonicSource);
        final key = Key.major(tonic);
        expect(key.triadFor(HarmonicFunction.tonic).root, tonic);
        expect(
          key.triadFor(HarmonicFunction.subdominant).root,
          tonic.transposeBy(Interval.perfectFourth),
        );
        expect(
          key.triadFor(HarmonicFunction.dominant).root,
          tonic.transposeBy(Interval.perfectFifth),
        );
      }
    });
  });

  test('value semantics', () {
    expect(const Key.major(Pitch(Step.c)), const Key.major(Pitch(Step.c)));
    expect(
      const Key.major(Pitch(Step.c)),
      isNot(const Key.minor(Pitch(Step.c))),
    );
    expect(const Key.major(Pitch(Step.c)).toString(), 'Key(C4 major)');
  });
}
