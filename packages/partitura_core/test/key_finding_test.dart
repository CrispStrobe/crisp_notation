import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

List<Pitch> notes(String s) => s.split(' ').map(Pitch.parse).toList();

void main() {
  group('findKey / keyOf', () {
    test('a C major scale reads as C major', () {
      final key = keyOf(notes('c4 d4 e4 f4 g4 a4 b4 c5'));
      expect(key, Key.major(const Pitch(Step.c)));
    });

    test('a G major scale reads as G major', () {
      final key = keyOf(notes('g4 a4 b4 c5 d5 e5 f#5 g5'));
      expect(key, Key.major(const Pitch(Step.g)));
    });

    test('an F major scale (one flat) reads as F major', () {
      final key = keyOf(notes('f4 g4 a4 bb4 c5 d5 e5 f5'));
      expect(key, Key.major(const Pitch(Step.f)));
    });

    test('an A harmonic-minor melody (raised G#) reads as A minor', () {
      // The G# is foreign to C major, disambiguating the relative pair.
      final key = keyOf(notes('a4 b4 c5 d5 e5 f5 g#5 a5 e5 a4 c5 a4'));
      expect(key, Key.minor(const Pitch(Step.a)));
    });

    test('empty input returns null', () {
      expect(findKey(List.filled(12, 0)), isNull);
      expect(keyOf(const []), isNull);
    });

    test('duration weighting favours the emphasized tonic', () {
      // Same pitches, but D held much longer → D major over its relatives.
      final key = keyOf(
        notes('d4 e4 f#4 g4 a4 b4 c#5'),
        durations: [8, 1, 1, 2, 2, 1, 1],
      );
      expect(key, Key.major(const Pitch(Step.d)));
    });
  });

  group('localKeys', () {
    test('tracks a modulation from C major to G major', () {
      // First half sits in C major, second half in G major (F#s).
      final line = notes('c4 e4 g4 c5 e5 g5 c5 g4 g4 b4 d5 g5 f#5 d5 b4 g4');
      final keys = localKeys(line, window: 8, step: 8);
      expect(keys, hasLength(2));
      expect(keys[0], Key.major(const Pitch(Step.c)));
      expect(keys[1], Key.major(const Pitch(Step.g)));
    });

    test('is empty when there are fewer notes than the window', () {
      expect(localKeys(notes('c4 d4'), window: 8), isEmpty);
    });
  });
}
