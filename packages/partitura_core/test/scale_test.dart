import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Asserts that the scale's pitches spell exactly [expected] (space-separated
/// `Pitch.toString` forms, e.g. 'C4 D4 E4 F4 G4 A4 B4 C5').
void expectScale(Scale scale, String expected) {
  expect(scale.pitches.join(' '), expected, reason: '$scale');
}

void main() {
  group('major scales around the circle of fifths', () {
    test('sharp side', () {
      expectScale(
        const Scale(Pitch(Step.c), ScaleType.major),
        'C4 D4 E4 F4 G4 A4 B4 C5',
      );
      expectScale(
        const Scale(Pitch(Step.g), ScaleType.major),
        'G4 A4 B4 C5 D5 E5 F#5 G5',
      );
      expectScale(
        const Scale(Pitch(Step.d), ScaleType.major),
        'D4 E4 F#4 G4 A4 B4 C#5 D5',
      );
      expectScale(
        const Scale(Pitch(Step.a), ScaleType.major),
        'A4 B4 C#5 D5 E5 F#5 G#5 A5',
      );
      expectScale(
        const Scale(Pitch(Step.e), ScaleType.major),
        'E4 F#4 G#4 A4 B4 C#5 D#5 E5',
      );
      expectScale(
        const Scale(Pitch(Step.b), ScaleType.major),
        'B4 C#5 D#5 E5 F#5 G#5 A#5 B5',
      );
      expectScale(
        const Scale(Pitch(Step.f, alter: 1), ScaleType.major),
        'F#4 G#4 A#4 B4 C#5 D#5 E#5 F#5',
      );
      expectScale(
        const Scale(Pitch(Step.c, alter: 1), ScaleType.major),
        'C#4 D#4 E#4 F#4 G#4 A#4 B#4 C#5',
      );
    });

    test('flat side', () {
      expectScale(
        const Scale(Pitch(Step.f), ScaleType.major),
        'F4 G4 A4 Bb4 C5 D5 E5 F5',
      );
      expectScale(
        const Scale(Pitch(Step.b, alter: -1), ScaleType.major),
        'Bb4 C5 D5 Eb5 F5 G5 A5 Bb5',
      );
      expectScale(
        const Scale(Pitch(Step.e, alter: -1), ScaleType.major),
        'Eb4 F4 G4 Ab4 Bb4 C5 D5 Eb5',
      );
      expectScale(
        const Scale(Pitch(Step.a, alter: -1), ScaleType.major),
        'Ab4 Bb4 C5 Db5 Eb5 F5 G5 Ab5',
      );
      expectScale(
        const Scale(Pitch(Step.d, alter: -1), ScaleType.major),
        'Db4 Eb4 F4 Gb4 Ab4 Bb4 C5 Db5',
      );
      expectScale(
        const Scale(Pitch(Step.g, alter: -1), ScaleType.major),
        'Gb4 Ab4 Bb4 Cb5 Db5 Eb5 F5 Gb5',
      );
      expectScale(
        const Scale(Pitch(Step.c, alter: -1), ScaleType.major),
        'Cb4 Db4 Eb4 Fb4 Gb4 Ab4 Bb4 Cb5',
      );
    });
  });

  group('natural minor scales', () {
    test('common minors', () {
      expectScale(
        const Scale(Pitch(Step.a), ScaleType.naturalMinor),
        'A4 B4 C5 D5 E5 F5 G5 A5',
      );
      expectScale(
        const Scale(Pitch(Step.e), ScaleType.naturalMinor),
        'E4 F#4 G4 A4 B4 C5 D5 E5',
      );
      expectScale(
        const Scale(Pitch(Step.b), ScaleType.naturalMinor),
        'B4 C#5 D5 E5 F#5 G5 A5 B5',
      );
      expectScale(
        const Scale(Pitch(Step.f, alter: 1), ScaleType.naturalMinor),
        'F#4 G#4 A4 B4 C#5 D5 E5 F#5',
      );
      expectScale(
        const Scale(Pitch(Step.c, alter: 1), ScaleType.naturalMinor),
        'C#4 D#4 E4 F#4 G#4 A4 B4 C#5',
      );
      expectScale(
        const Scale(Pitch(Step.d), ScaleType.naturalMinor),
        'D4 E4 F4 G4 A4 Bb4 C5 D5',
      );
      expectScale(
        const Scale(Pitch(Step.g), ScaleType.naturalMinor),
        'G4 A4 Bb4 C5 D5 Eb5 F5 G5',
      );
      expectScale(
        const Scale(Pitch(Step.c), ScaleType.naturalMinor),
        'C4 D4 Eb4 F4 G4 Ab4 Bb4 C5',
      );
      expectScale(
        const Scale(Pitch(Step.f), ScaleType.naturalMinor),
        'F4 G4 Ab4 Bb4 C5 Db5 Eb5 F5',
      );
      expectScale(
        const Scale(Pitch(Step.b, alter: -1), ScaleType.naturalMinor),
        'Bb4 C5 Db5 Eb5 F5 Gb5 Ab5 Bb5',
      );
    });
  });

  group('harmonic minor raises the 7th', () {
    test('classic cases', () {
      expectScale(
        const Scale(Pitch(Step.a), ScaleType.harmonicMinor),
        'A4 B4 C5 D5 E5 F5 G#5 A5',
      );
      expectScale(
        const Scale(Pitch(Step.d), ScaleType.harmonicMinor),
        'D4 E4 F4 G4 A4 Bb4 C#5 D5',
      );
      expectScale(
        const Scale(Pitch(Step.c), ScaleType.harmonicMinor),
        'C4 D4 Eb4 F4 G4 Ab4 B4 C5',
      );
      // The raised 7th of Eb minor is D natural (from Db).
      expectScale(
        const Scale(Pitch(Step.e, alter: -1), ScaleType.harmonicMinor),
        'Eb4 F4 Gb4 Ab4 Bb4 Cb5 D5 Eb5',
      );
      // The raised 7th of G# minor needs a double sharp.
      expectScale(
        const Scale(Pitch(Step.g, alter: 1), ScaleType.harmonicMinor),
        'G#4 A#4 B4 C#5 D#5 E5 F##5 G#5',
      );
    });
  });

  group('melodic minor raises the 6th and 7th (ascending form)', () {
    test('classic cases', () {
      expectScale(
        const Scale(Pitch(Step.a), ScaleType.melodicMinor),
        'A4 B4 C5 D5 E5 F#5 G#5 A5',
      );
      expectScale(
        const Scale(Pitch(Step.c), ScaleType.melodicMinor),
        'C4 D4 Eb4 F4 G4 A4 B4 C5',
      );
      expectScale(
        const Scale(Pitch(Step.g), ScaleType.melodicMinor),
        'G4 A4 Bb4 C5 D5 E5 F#5 G5',
      );
    });
  });

  group('general properties', () {
    test('every scale uses each letter name exactly once before the octave',
        () {
      const tonics = [
        Pitch(Step.c),
        Pitch(Step.g),
        Pitch(Step.d),
        Pitch(Step.b, alter: -1),
        Pitch(Step.f, alter: 1),
        Pitch(Step.a),
        Pitch(Step.e, alter: -1),
      ];
      for (final tonic in tonics) {
        for (final type in ScaleType.values) {
          final pitches = Scale(tonic, type).pitches;
          expect(pitches, hasLength(8));
          expect(pitches.first, tonic);
          expect(
            pitches.last,
            tonic.transposeBy(Interval.perfectOctave),
            reason: 'octave of $tonic ${type.name}',
          );
          final steps = pitches.take(7).map((p) => p.step).toSet();
          expect(steps, hasLength(7), reason: '$tonic ${type.name}');
        }
      }
    });

    test('tonic octave anchors the scale', () {
      final low = const Scale(Pitch(Step.c, octave: 2), ScaleType.major);
      expect(low.pitches.first, const Pitch(Step.c, octave: 2));
      expect(low.pitches.last, const Pitch(Step.c, octave: 3));
    });

    test('value semantics', () {
      expect(
        const Scale(Pitch(Step.c), ScaleType.major),
        const Scale(Pitch(Step.c), ScaleType.major),
      );
      expect(
        const Scale(Pitch(Step.c), ScaleType.major),
        isNot(const Scale(Pitch(Step.c), ScaleType.naturalMinor)),
      );
    });
  });
}
