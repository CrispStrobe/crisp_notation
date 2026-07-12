import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void expectPitches(Triad triad, String expected) {
  expect(triad.pitches.join(' '), expected, reason: '$triad');
}

void main() {
  group('root position qualities', () {
    test('major', () {
      expectPitches(const Triad(Pitch(Step.c), ChordQuality.major), 'C4 E4 G4');
      expectPitches(const Triad(Pitch(Step.g), ChordQuality.major), 'G4 B4 D5');
      expectPitches(
        const Triad(Pitch(Step.f, alter: 1), ChordQuality.major),
        'F#4 A#4 C#5',
      );
      expectPitches(
        const Triad(Pitch(Step.e, alter: -1), ChordQuality.major),
        'Eb4 G4 Bb4',
      );
    });

    test('minor', () {
      expectPitches(
        const Triad(Pitch(Step.a), ChordQuality.minor),
        'A4 C5 E5',
      );
      expectPitches(
        const Triad(Pitch(Step.c), ChordQuality.minor),
        'C4 Eb4 G4',
      );
      expectPitches(
        const Triad(Pitch(Step.c, alter: 1), ChordQuality.minor),
        'C#4 E4 G#4',
      );
    });

    test('diminished', () {
      expectPitches(
        const Triad(Pitch(Step.b), ChordQuality.diminished),
        'B4 D5 F5',
      );
      expectPitches(
        const Triad(Pitch(Step.c, alter: 1), ChordQuality.diminished),
        'C#4 E4 G4',
      );
    });

    test('augmented', () {
      expectPitches(
        const Triad(Pitch(Step.c), ChordQuality.augmented),
        'C4 E4 G#4',
      );
      expectPitches(
        const Triad(Pitch(Step.f), ChordQuality.augmented),
        'F4 A4 C#5',
      );
    });
  });

  group('inversions', () {
    test('first inversion puts the third in the bass', () {
      expectPitches(
        const Triad(Pitch(Step.c), ChordQuality.major, inversion: 1),
        'E4 G4 C5',
      );
      expectPitches(
        const Triad(Pitch(Step.a), ChordQuality.minor, inversion: 1),
        'C5 E5 A5',
      );
    });

    test('second inversion puts the fifth in the bass', () {
      expectPitches(
        const Triad(Pitch(Step.c), ChordQuality.major, inversion: 2),
        'G4 C5 E5',
      );
      expectPitches(
        const Triad(Pitch(Step.g), ChordQuality.major, inversion: 2),
        'D5 G5 B5',
      );
    });

    test('inversions keep the same pitch classes', () {
      for (var inversion = 0; inversion <= 2; inversion++) {
        final triad = Triad(const Pitch(Step.d), ChordQuality.minor,
            inversion: inversion);
        expect(
          triad.pitches.map((p) => (p.step, p.alter)).toSet(),
          {(Step.d, 0), (Step.f, 0), (Step.a, 0)},
          reason: 'inversion $inversion',
        );
      }
    });
  });

  test('value semantics', () {
    expect(
      const Triad(Pitch(Step.c), ChordQuality.major),
      const Triad(Pitch(Step.c), ChordQuality.major, inversion: 0),
    );
    expect(
      const Triad(Pitch(Step.c), ChordQuality.major),
      isNot(const Triad(Pitch(Step.c), ChordQuality.major, inversion: 1)),
    );
    expect(
      const Triad(Pitch(Step.c), ChordQuality.major),
      isNot(const Triad(Pitch(Step.c), ChordQuality.minor)),
    );
  });
}
