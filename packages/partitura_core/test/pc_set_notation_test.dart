import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  group('pitch-class set notation', () {
    test('parses braces, brackets and bare, comma or space separated', () {
      expect(parsePitchClassSet('{0,4,7}'), PitchClassSet([0, 4, 7]));
      expect(parsePitchClassSet('[0, 4, 7]'), PitchClassSet([0, 4, 7]));
      expect(parsePitchClassSet('0 4 7'), PitchClassSet([0, 4, 7]));
      expect(parsePitchClassSet('  7,0 , 4 '), PitchClassSet([0, 4, 7]));
    });

    test('accepts T and E for 10 and 11', () {
      expect(parsePitchClassSet('{0, T, E}'), PitchClassSet([0, 10, 11]));
      expect(parsePitchClassSet('0 a b'), PitchClassSet([0, 10, 11]));
    });

    test('reduces out-of-range integers mod 12', () {
      expect(parsePitchClassSet('12 16 19'), PitchClassSet([0, 4, 7]));
    });

    test('the label is members in braces, ascending', () {
      expect(pitchClassSetLabel(PitchClassSet([7, 0, 4])), '{0, 4, 7}');
    });

    test('label round-trips through parse', () {
      for (final members in [
        [0, 4, 7],
        [0, 1, 4, 6],
        [1, 3, 5, 7, 9, 11],
        [0, 10, 11],
      ]) {
        final set = PitchClassSet(members);
        expect(parsePitchClassSet(pitchClassSetLabel(set)), set);
      }
    });

    test('a bad token is a FormatException', () {
      expect(() => parsePitchClassSet('{0, x, 7}'), throwsFormatException);
    });

    test('the analysis line reports normal order, prime form and ICV', () {
      final line = pitchClassSetAnalysis(PitchClassSet([0, 4, 7]));
      expect(line, contains('{0, 4, 7}'));
      expect(line, contains('prime [0, 3, 7]'));
      expect(line, contains('icv [0, 0, 1, 1, 1, 0]'));
    });
  });

  group('tone-row notation', () {
    final row = ToneRow([4, 5, 7, 1, 6, 3, 8, 2, 11, 0, 9, 10]);

    test('the label uses angle brackets with T and E', () {
      expect(toneRowLabel(ToneRow([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])),
          '<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, T, E>');
    });

    test('label round-trips through parse', () {
      expect(parseToneRow(toneRowLabel(row)), row);
    });

    test('parses a bare, space-separated row', () {
      expect(parseToneRow('0 1 2 3 4 5 6 7 8 9 10 11'),
          ToneRow([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]));
    });

    test('an incomplete row is an ArgumentError', () {
      expect(() => parseToneRow('<0, 1, 2>'), throwsArgumentError);
    });
  });
}
