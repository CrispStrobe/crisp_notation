import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  List<num> weights(List<int> pcsPresent) {
    final w = List<num>.filled(12, 0);
    for (final pc in pcsPresent) {
      w[pc % 12] += 1;
    }
    return w;
  }

  group('major keys', () {
    test('the C major scale is found as C major', () {
      final est = estimateKey(weights([0, 2, 4, 5, 7, 9, 11]));
      expect(est.key, Key.major(Pitch.parse('c4')));
      expect(est.correlation, greaterThan(0.7));
    });

    test('transposition: the G major scale is found as G major', () {
      final est = estimateKey(weights([7, 9, 11, 0, 2, 4, 6]));
      expect(est.key.isMajor, isTrue);
      expect(est.key.tonic.midiNumber % 12, 7); // G
    });

    test('the E-flat major scale is found as E-flat major', () {
      final est = estimateKey(weights([3, 5, 7, 8, 10, 0, 2]));
      expect(est.key.isMajor, isTrue);
      expect(est.key.tonic.midiNumber % 12, 3);
      expect(est.key.signature.fifths, -3); // three flats
    });
  });

  group('minor keys', () {
    test('the A harmonic-minor scale is found as A minor', () {
      // A B C D E F G# — the leading tone disambiguates from C major.
      final est = estimateKey(weights([9, 11, 0, 2, 4, 5, 8]));
      expect(est.key.isMajor, isFalse);
      expect(est.key.tonic.midiNumber % 12, 9); // A
    });

    test('the D harmonic-minor scale is found as D minor', () {
      // D E F G A Bb C#.
      final est = estimateKey(weights([2, 4, 5, 7, 9, 10, 1]));
      expect(est.key.isMajor, isFalse);
      expect(est.key.tonic.midiNumber % 12, 2); // D
    });
  });

  group('ranking', () {
    test('rankKeys returns all 24 keys, best first', () {
      final ranked = rankKeys(weights([0, 2, 4, 5, 7, 9, 11]));
      expect(ranked, hasLength(24));
      for (var i = 1; i < ranked.length; i++) {
        expect(ranked[i - 1].correlation,
            greaterThanOrEqualTo(ranked[i].correlation));
      }
      expect(ranked.first.key, Key.major(Pitch.parse('c4')));
      // The relative minor (A minor) is a strong runner-up.
      final aMinorRank = ranked
          .indexWhere((e) => !e.key.isMajor && e.key.tonic.step == Step.a);
      expect(aMinorRank, lessThan(3));
    });
  });

  group('input handling', () {
    test('from a list of pitches', () {
      final est = estimateKeyFromPitches([
        for (final n in ['c4', 'e4', 'g4', 'c5', 'g4', 'e4']) Pitch.parse(n),
      ]);
      expect(est.key, Key.major(Pitch.parse('c4')));
    });

    test('rejects the wrong length', () {
      expect(() => estimateKey([1, 2, 3]), throwsArgumentError);
    });

    test('rejects an all-zero distribution', () {
      expect(() => estimateKey(List<num>.filled(12, 0)), throwsArgumentError);
      expect(() => estimateKeyFromPitches(const []), throwsArgumentError);
    });
  });
}
