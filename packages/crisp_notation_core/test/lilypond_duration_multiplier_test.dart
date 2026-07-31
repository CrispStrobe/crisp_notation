import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// LilyPond's duration multiplier (`c1*3/4`, `s1*4`).
///
/// `*` and `/` are not symbol prefixes, so the lexer hands `c1*3/4` over as a
/// single word. The note gate is `$`-anchored, so rejecting that word did not
/// mis-read the note — it made the note DISAPPEAR, and in a `\chords` track the
/// leftover `*3/4` was parsed as a slash chord (`f1*3/4` read as `C/C`).
/// Both were silent: the file still "parsed fine", just with less music in it.
void main() {
  Score melody(String body) =>
      scoreFromLilyPond('\\score { \\new Staff { \\time 4/4 $body } }');

  List<Fraction> durations(Score s) => s.measures
      .expand((m) => m.elements.whereType<NoteElement>())
      .map((n) => n.duration.toFraction())
      .toList();

  group('melody', () {
    test('a multiplied note is kept, not dropped', () {
      // The regression: this used to yield ONE note, having lost `c1*3/4`.
      expect(durations(melody(r'c1*3/4 d1')), hasLength(2));
    });

    test('the multiplier scales the note it is attached to', () {
      expect(durations(melody(r'c1*3/4 d1')).first, Fraction(3, 4));
      expect(durations(melody(r'c4*2 d4')).first, Fraction(1, 2));
    });

    test('the multiplier does NOT stick to the following note', () {
      // `d` inherits the BASE duration, not the scaled one.
      expect(durations(melody(r'c1*3/4 d1')).last, Fraction(1, 1));
      expect(durations(melody(r'c4*2 d4')).last, Fraction(1, 4));
    });

    test('an inexpressible scaling keeps the base rather than dropping', () {
      // 1/4 * 2/3 has no base-plus-dots spelling. The note must still exist.
      final d = durations(melody(r'c4*2/3 d4'));
      expect(d, hasLength(2));
      expect(d.first, Fraction(1, 4));
    });

    test('rests take a multiplier too', () {
      final s = melody(r'r1*3/4 c1');
      final rests =
          s.measures.expand((m) => m.elements.whereType<RestElement>());
      expect(rests, hasLength(1));
      expect(rests.first.duration.toFraction(), Fraction(3, 4));
    });

    test('plain durations are unaffected', () {
      expect(durations(melody(r'c1 d1')), [Fraction(1, 1), Fraction(1, 1)]);
      expect(durations(melody(r'c2. d2.')), [Fraction(3, 4), Fraction(3, 4)]);
    });
  });

  group('chord track', () {
    Score charted(String chords) => scoreFromLilyPond(
          'melody = \\relative c\' '
          '{ f4 g a bes c d e f g a bes c d e f g }\n'
          'harmonies = \\chords { $chords }\n'
          '\\score { << \\context ChordNames { \\harmonies } '
          '\\new Staff { \\melody } >> }\n',
        );

    List<String> symbols(Score s) => s.chordSymbols
        .map((c) =>
            c.root.step.name.toUpperCase() +
            (c.quality == ChordSymbolKind.dominantSeventh ? '7' : '') +
            (c.bass != null ? '/${c.bass!.step.name.toUpperCase()}' : ''))
        .toList();

    test('a multiplied chord reads as its root, not a slash chord', () {
      // The regression: `f1*3/4` read as `C/C`.
      expect(symbols(charted(r'f1*3/4 f c:7 f')).first, 'F');
    });

    test('the multiplier shortens the chord, so later chords survive', () {
      // With the multiplier ignored every chord occupied a whole note and the
      // track outran the melody, silently truncating the chart.
      expect(symbols(charted(r'f1*3/4 f c:7 f')), ['F', 'F', 'C7', 'F']);
    });

    test('a real slash chord still reads as one', () {
      expect(symbols(charted(r'f1/c f')).first, 'F/C');
    });
  });
}
