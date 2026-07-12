import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

Pitch _p(Step s, int octave, [int alter = 0]) =>
    Pitch(s, alter: alter, octave: octave);

void main() {
  group('identifyChord', () {
    test('triad qualities', () {
      expect(
          chordSymbolFor([_p(Step.c, 4), _p(Step.e, 4), _p(Step.g, 4)]), 'C');
      expect(chordSymbolFor([_p(Step.c, 4), _p(Step.e, 4, -1), _p(Step.g, 4)]),
          'Cm');
      expect(
          chordSymbolFor([_p(Step.c, 4), _p(Step.e, 4, -1), _p(Step.g, 4, -1)]),
          'Cdim');
      expect(chordSymbolFor([_p(Step.c, 4), _p(Step.e, 4), _p(Step.g, 4, 1)]),
          'Caug');
    });

    test('sevenths', () {
      expect(
          chordSymbolFor(
              [_p(Step.g, 3), _p(Step.b, 3), _p(Step.d, 4), _p(Step.f, 4)]),
          'G7');
      expect(
          chordSymbolFor(
              [_p(Step.c, 4), _p(Step.e, 4), _p(Step.g, 4), _p(Step.b, 4)]),
          'Cmaj7');
      expect(
          chordSymbolFor(
              [_p(Step.a, 3), _p(Step.c, 4), _p(Step.e, 4), _p(Step.g, 4)]),
          'Am7');
      expect(
          chordSymbolFor(
              [_p(Step.b, 3), _p(Step.d, 4), _p(Step.f, 4), _p(Step.a, 4)]),
          'Bm7b5');
    });

    test('sus chords', () {
      expect(chordSymbolFor([_p(Step.c, 4), _p(Step.f, 4), _p(Step.g, 4)]),
          'Csus4');
      expect(chordSymbolFor([_p(Step.c, 4), _p(Step.d, 4), _p(Step.g, 4)]),
          'Csus2');
    });

    test('inversions become slash chords', () {
      // C major, third in the bass.
      final firstInv =
          identifyChord([_p(Step.e, 4), _p(Step.g, 4), _p(Step.c, 5)])!;
      expect(firstInv.symbol, 'C/E');
      expect(firstInv.inversion, 1);
      expect(firstInv.root, _p(Step.c, 5));
      // C major, fifth in the bass.
      expect(
          identifyChord([_p(Step.g, 3), _p(Step.c, 4), _p(Step.e, 4)])!.symbol,
          'C/G');
    });

    test('the bass disambiguates C6 vs Am7', () {
      expect(
          chordSymbolFor(
              [_p(Step.c, 4), _p(Step.e, 4), _p(Step.g, 4), _p(Step.a, 4)]),
          'C6');
      expect(
          chordSymbolFor(
              [_p(Step.a, 3), _p(Step.c, 4), _p(Step.e, 4), _p(Step.g, 4)]),
          'Am7');
    });

    test('spelling follows the input pitches', () {
      expect(
          chordSymbolFor(
              [_p(Step.f, 4, 1), _p(Step.a, 4, 1), _p(Step.c, 5, 1)]),
          'F#'); // F# A# C#
      expect(chordSymbolFor([_p(Step.b, 3, -1), _p(Step.d, 4), _p(Step.f, 4)]),
          'Bb'); // Bb major
    });

    test('octave doubling and note order do not matter', () {
      expect(
          chordSymbolFor([
            _p(Step.g, 5),
            _p(Step.c, 4),
            _p(Step.e, 4),
            _p(Step.c, 3),
          ]),
          'C'); // still a C major triad
    });

    test('non-chords return null', () {
      expect(chordSymbolFor([_p(Step.c, 4), _p(Step.g, 4)]), isNull); // dyad
      expect(chordSymbolFor([_p(Step.c, 4)]), isNull); // single note
      expect(chordSymbolFor([_p(Step.c, 4), _p(Step.d, 4, 1), _p(Step.d, 4)]),
          isNull); // C C# D — a chromatic cluster, no template
    });
  });
}
