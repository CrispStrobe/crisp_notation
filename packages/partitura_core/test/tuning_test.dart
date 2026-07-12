import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.8: string tunings + fret assignment.
void main() {
  final guitar = Tuning.standardGuitar;

  group('standard guitar', () {
    test('has six strings, high E on top', () {
      expect(guitar.stringCount, 6);
      expect(guitar.strings.first, Pitch.parse('e4'));
      expect(guitar.strings.last, Pitch.parse('e2'));
    });

    test('open strings map to fret 0 on their own line', () {
      expect(guitar.fretFor(Pitch.parse('e4')), (0, 0)); // string 1
      expect(guitar.fretFor(Pitch.parse('b3')), (1, 0)); // string 2
      expect(guitar.fretFor(Pitch.parse('g3')), (2, 0)); // string 3
      expect(guitar.fretFor(Pitch.parse('d3')), (3, 0)); // string 4
      expect(guitar.fretFor(Pitch.parse('a2')), (4, 0)); // string 5
      expect(guitar.fretFor(Pitch.parse('e2')), (5, 0)); // string 6
    });

    test('picks the lowest available fret', () {
      // F4 = 1st fret of the high E string.
      expect(guitar.fretFor(Pitch.parse('f4')), (0, 1));
      // C4 = 1st fret of the B string (lower than 5th fret of G).
      expect(guitar.fretFor(Pitch.parse('c4')), (1, 1));
      // G4 = 3rd fret of the high E string.
      expect(guitar.fretFor(Pitch.parse('g4')), (0, 3));
    });

    test('unreachable pitches return null', () {
      expect(guitar.fretFor(Pitch.parse('c1')), isNull); // below low E
      expect(guitar.fretFor(Pitch.parse('c8'), maxFret: 12), isNull);
    });
  });

  group('other tunings', () {
    test('drop D lowers the sixth string', () {
      expect(Tuning.dropDGuitar.strings.last, Pitch.parse('d2'));
      expect(Tuning.dropDGuitar.fretFor(Pitch.parse('d2')), (5, 0));
    });

    test('bass has four strings', () {
      expect(Tuning.standardBass.stringCount, 4);
      expect(Tuning.standardBass.fretFor(Pitch.parse('e1')), (3, 0));
    });

    test('value semantics', () {
      expect(Tuning.standardGuitar, Tuning.standardGuitar);
      expect(Tuning.standardGuitar, isNot(Tuning.dropDGuitar));
    });
  });
}
