// LilyPond: hairpin escapes, and contexts written `\new Staff = "name" << … >>`.
//
// Both found by parse-sweeping 3,791 CPDL editions, where 17 of 59 LilyPond
// scores read as completely empty and many more were silently truncated.
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

int _notes(MultiPartScore mp) => mp.parts
    .expand((p) => p.measures)
    .expand((m) => m.elements)
    .whereType<NoteElement>()
    .length;

void main() {
  group('hairpin escapes', () {
    test(r'\< does not open a chord and swallow the rest of the part', () {
      // The lexer used to emit a bare `\` and advance ONE char, leaving `<` to
      // be read as the chord-opener — the chord never closed and ate the music.
      final mp = multiPartFromLilyPond(r'''
Mus = \relative c' { c4\< d e\! f g }
\score { << \new Staff { \Mus } >> }
''');
      expect(_notes(mp), 5);
    });

    test(r'\> behaves the same (it always did — which is why \< hid so long)',
        () {
      final mp = multiPartFromLilyPond(r'''
Mus = \relative c' { c4\> d e\! f g }
\score { << \new Staff { \Mus } >> }
''');
      expect(_notes(mp), 5);
    });

    test('a hairpin attached to a beamed note still reads', () {
      final mp = multiPartFromLilyPond(r'''
Mus = \relative c' { c8\<[ d] e\![ f] }
\score { << \new Staff { \Mus } >> }
''');
      expect(_notes(mp), 4);
    });
  });

  group('named contexts', () {
    test(r'\new Staff = "name" << … >> is recognised as a staff', () {
      // `= "name"` parses the type+name as an ASSIGNMENT, so the context type
      // is not a bare word. Missing it meant no staves were collected and the
      // document fell back to the single-staff path, which reads `{ … }` but
      // returns nothing for `<< … >>`.
      final mp = multiPartFromLilyPond(r'''
Mus = \relative c' { c4 d e }
Low = \relative c { g4 a b }
\score { <<
  \new Staff = "upper" << \new Voice = "v1" { \Mus } >>
  \new Staff = "lower" << \new Voice = "v2" { \Low } >>
>> }
''');
      expect(mp.parts.length, 2);
      expect(_notes(mp), 6);
    });

    test(r'\context Voice = "name" { … } contributes its music', () {
      // `\context` had no case at all, so it fell through and was dropped.
      final mp = multiPartFromLilyPond(r'''
Mus = \relative c' { c4 d e }
\score { << \new Staff = "s" <<
  \set Staff.instrumentName = "T"
  \context Voice = "one" { \Mus }
>> >> }
''');
      expect(_notes(mp), 3);
    });

    test('the plain unnamed forms still work', () {
      final mp = multiPartFromLilyPond(r'''
Mus = \relative c' { c4 d e }
\score { << \new Staff { \Mus } >> }
''');
      expect(_notes(mp), 3);
    });
  });
}
