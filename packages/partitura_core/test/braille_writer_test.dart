import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Phase 7.5: Braille music export. Expected cells are written as dot-number
/// lists (1–6) so they read against a braille chart.
String cell(List<int> dots) {
  var bits = 0;
  for (final d in dots) {
    bits |= 1 << (d - 1);
  }
  return String.fromCharCode(0x2800 + bits);
}

String cells(List<List<int>> each) => each.map(cell).join();

void main() {
  group('scoreToBraille', () {
    test('a single quarter middle-C = octave-4 mark + C-quarter sign', () {
      // Octave 4 = dots 5; quarter C = name C (1,4,5) + value dot 3.
      expect(scoreToBraille(Score.simple(notes: 'c4:q')),
          cells([[5], [1, 3, 4, 5]]));
    });

    test('the four note values on middle C', () {
      String only(String notes) =>
          scoreToBraille(Score.simple(notes: notes)).substring(1); // drop 8ve
      expect(only('c4:w'), cell([1, 3, 4, 5, 6])); // whole  ⠽
      expect(only('c4:h'), cell([1, 4, 5, 6])); //     half   ⠹
      expect(only('c4:q'), cell([1, 3, 4, 5])); //     quarter⠝
      expect(only('c4:e'), cell([1, 4, 5])); //        eighth ⠙
    });

    test('the seven note names (eighth signs = letters d–j)', () {
      String note(String n) =>
          scoreToBraille(Score.simple(notes: '$n:e')).substring(1);
      expect(note('c4'), cell([1, 4, 5])); // d
      expect(note('d4'), cell([1, 5])); // e
      expect(note('e4'), cell([1, 2, 4])); // f
      expect(note('f4'), cell([1, 2, 4, 5])); // g
      expect(note('g4'), cell([1, 2, 5])); // h
      expect(note('a4'), cell([2, 4])); // i
      expect(note('b4'), cell([2, 4, 5])); // j
    });

    test('a C-major scale marks only the first octave', () {
      final braille = scoreToBraille(
          Score.simple(notes: 'c4:q d4 e4 f4 g4 a4 b4 c5'));
      // Octave marks are the seven cells {4},{45},{456},{5},{46},{56},{6}.
      const marks = [
        [4], [4, 5], [4, 5, 6], [5], [4, 6], [5, 6], [6] //
      ];
      final markChars = {for (final m in marks) cell(m)};
      final count =
          braille.split('').where((c) => markChars.contains(c)).length;
      expect(count, 1, reason: 'stepwise motion needs no further octave marks');
    });

    test('octave marks follow the interval rule', () {
      String brl(String notes) => scoreToBraille(Score.simple(notes: notes));
      final o4 = cell([5]);
      final o5 = cell([4, 6]);
      // A 4th within the same octave: no mark on the second note.
      expect(brl('c4:q f4').contains(o4 + cell([5])), isFalse);
      expect(brl('c4:q f4'), startsWith(o4)); // only the first
      // A 4th that changes octave (g4 → c5): the second note IS marked.
      expect(brl('g4:q c5').endsWith(o5 + cell([1, 3, 4, 5])), isTrue);
      // A 6th or more (c4 → c5, an octave): marked.
      expect(brl('c4:q c5').endsWith(o5 + cell([1, 3, 4, 5])), isTrue);
    });

    test('accidentals show only when not implied by the key', () {
      final sharp = cell([1, 4, 6]);
      // The music sits after any signature header (split off the leading space).
      String music(String b) => b.split(' ').last;
      // F# in C major prints a sharp (no header).
      expect(music(scoreToBraille(Score.simple(notes: 'f#4:q'))).contains(sharp),
          isTrue);
      // F# in G major (F already sharp) prints none on the note.
      expect(
          music(scoreToBraille(Score.simple(
                  notes: 'f#4:q', keySignature: const KeySignature(1))))
              .contains(sharp),
          isFalse);
      // A natural cancelling the key prints a natural sign.
      expect(
          music(scoreToBraille(Score.simple(
                  notes: 'f4:q', keySignature: const KeySignature(1))))
              .contains(cell([1, 6])),
          isTrue);
    });

    test('dotted notes add an augmentation-dot cell', () {
      // c4:q. → octave + quarter C + one aug dot (dot 3).
      expect(scoreToBraille(Score.simple(notes: 'c4:q.')),
          cells([[5], [1, 3, 4, 5], [3]]));
    });

    test('rests use the value rest signs', () {
      expect(scoreToBraille(Score.simple(notes: 'r:q')), cell([1, 2, 3, 6]));
      expect(scoreToBraille(Score.simple(notes: 'r:h')), cell([1, 3, 6]));
      expect(scoreToBraille(Score.simple(notes: 'r:w')), cell([1, 3, 4]));
      expect(scoreToBraille(Score.simple(notes: 'r:e')), cell([1, 3, 4, 6]));
    });

    test('a key signature prints as a leading header', () {
      // G major = one sharp, then a space, then the music.
      final b = scoreToBraille(
          Score.simple(notes: 'c4:q', keySignature: const KeySignature(1)));
      expect(b, startsWith('${cell([1, 4, 6])} ')); // ♯ + space
      // Two flats repeat the flat sign.
      final bf = scoreToBraille(
          Score.simple(notes: 'c4:q', keySignature: const KeySignature(-2)));
      expect(bf, startsWith(cells([[1, 2, 6], [1, 2, 6]])));
    });

    test('a time signature prints as number sign + upper/lower digits', () {
      final b = scoreToBraille(Score.simple(
          notes: 'c4:w', timeSignature: TimeSignature.fourFour));
      // ⠼ (number) + upper-4 + lower-4, then a space.
      expect(b, startsWith(cells([[3, 4, 5, 6], [1, 4, 5], [2, 5, 6]])));
    });

    test('a chord is the top note plus downward interval signs', () {
      // C-E-G → reference G (top), a 3rd and a 5th below it.
      expect(
          scoreToBraille(Score.simple(notes: 'c4+e4+g4:q')),
          cells([
            [5], // octave-4 mark on the reference
            [1, 2, 3, 5], // G quarter (reference)
            [3, 4, 6], // 3rd (down to E)
            [3, 5], // 5th (down to C)
          ]));
    });

    test('an octave chord uses the octave interval sign', () {
      // C4 + C5 → reference C5, one octave below it.
      expect(
          scoreToBraille(Score.simple(notes: 'c4+c5:q')),
          cells([
            [4, 6], // octave-5 mark on the reference
            [1, 3, 4, 5], // C5 quarter (reference)
            [1, 2, 3, 4, 5, 6], // octave interval down to C4
          ]));
    });

    test('measures are separated by a braille space', () {
      final braille = scoreToBraille(Score.simple(notes: 'c4:q d4 | e4:q f4'));
      final parts = braille.split(' ');
      expect(parts, hasLength(2));
      // The first note of measure 2 (E, after D) is a 2nd → no octave mark;
      // both are quarters (name dots + value dot 3).
      expect(parts[1], cells([[1, 2, 3, 4], [1, 2, 3, 4, 5]]));
    });
  });
}
