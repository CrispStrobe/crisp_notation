import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

const _song = r'''
akkorde = \chordmode { \germanChords f4 c:7 f4. c8 g:m7 bes:maj7 c:7/e }
melodie = \relative c' { f4 g a bes c d e f }
\score { << \new ChordNames { \akkorde } \new Staff { \melodie } >> }
''';

void main() {
  group(r'\chordmode chord tracks', () {
    test('chord symbols are read, with quality and slash bass', () {
      final s = scoreFromLilyPond(_song);
      expect(
        s.chordSymbols.map((c) => c.text).toList(),
        ['F', 'C7', 'F', 'C', 'Gm7', 'Bbmaj7', 'C7/E'],
      );
    });

    test('chord-track notes do NOT leak into the melody', () {
      // The property the block-consuming behaviour exists to protect. Losing it
      // would silently inflate note counts across every .ly file with a chord
      // track — 285 in the corpus — and would look like nothing was wrong.
      final s = scoreFromLilyPond(_song);
      final notes =
          s.measures.expand((m) => m.elements).whereType<NoteElement>();
      expect(notes.length, 8);
    });

    test('a denser chord track keeps every chord at its own time', () {
      // Chord tracks are often denser than the melody under them. An earlier
      // version anchored one symbol per note and DISCARDED collisions, and the
      // next pushed them onto later notes. Each chord now stands over the note
      // sounding when it starts, at an offset from that note's onset.
      final s = scoreFromLilyPond(_song);
      expect(s.chordSymbols, hasLength(7));
      final onsetOf = <String, Fraction>{};
      var t = Fraction.zero;
      for (final e in s.measures.expand((m) => m.elements)) {
        onsetOf[e.id!] = t;
        t += e.duration.toFraction();
      }
      expect(
        [for (final c in s.chordSymbols) onsetOf[c.elementId]! + c.offset],
        [
          Fraction.zero,
          Fraction(1, 4),
          Fraction(1, 2),
          Fraction(7, 8),
          Fraction(1, 1),
          Fraction(9, 8),
          Fraction(5, 4),
        ],
      );
      // `c8` falls on the second half of `bes4`; Gm7 and Bbmaj7 share `c4`.
      expect(s.chordSymbols[3].offset, Fraction(1, 8));
      expect(s.chordSymbols[4].elementId, s.chordSymbols[5].elementId);
      expect(s.chordSymbols[5].offset, Fraction(1, 8));
    });

    test('every symbol anchors to a real note element', () {
      final s = scoreFromLilyPond(_song);
      final ids = s.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .map((n) => n.id)
          .toSet();
      for (final c in s.chordSymbols) {
        expect(ids, contains(c.elementId));
      }
    });

    test('a score with no chord track has no chord symbols', () {
      expect(
        scoreFromLilyPond(r"\relative c' { c4 d e f }").chordSymbols,
        isEmpty,
      );
    });

    test('an unreadable quality degrades to major rather than vanishing', () {
      // The root is what a player most needs; dropping a whole chord because its
      // extension is unfamiliar would be the worse failure.
      final s = scoreFromLilyPond(r'''
ch = \chordmode { c:13.11+ }
m = \relative c' { c4 }
\score { << \new ChordNames { \ch } \new Staff { \m } >> }
''');
      expect(s.chordSymbols, hasLength(1));
      expect(s.chordSymbols.single.root.step, Step.c);
    });
    test(r'a \transpose around the chord track moves its chords', () {
      // The chords used to be parsed after the track was read, when the
      // \transpose had ended: they stayed in the key they were written in.
      final s = scoreFromLilyPond(r'''
ch = \transpose g c \chordmode { g2 d:7 }
m = \transpose g c \relative c'' { g2 fis }
\score { << \new ChordNames { \ch } \new Staff { \m } >> }
''');
      expect(s.chordSymbols.map((c) => c.text), ['C', 'G7']);
    });

    test(r'a \transpose around the whole score moves the chord track', () {
      // `\transpose c' bes \context ChoirStaff << \context ChordNames … >>`:
      // the chord track is read apart from the staves, outside the wrapper.
      final mp = multiPartFromLilyPond(r'''
ch = \chordmode { c2 g:7 }
\score {
  \transpose c' bes \new ChoirStaff <<
    \new ChordNames { \ch }
    \new Staff \relative c'' { c2 b }
    \new Staff \relative c' { e2 f }
  >>
}
''');
      expect(mp.parts.first.chordSymbols.map((c) => c.text), ['Bb', 'F7']);
    });
    test('an added bass (/+) is the pitch after the plus', () {
      // `+fis` parsed as no pitch, which came out as C: every added bass a C.
      final s = scoreFromLilyPond(r'''
ch = \chordmode { d2/+fis a2:7/+e }
m = \relative c' { d2 e }
\score { << \new ChordNames { \ch } \new Staff { \m } >> }
''');
      expect(s.chordSymbols.map((c) => c.text), ['D/F#', 'A7/E']);
    });
    test('a staff holding only a chord track gives its chords to the top', () {
      // A hymn's MIDI score: `\context Staff = "b" << \context ChordNames
      // \accomp >>`. The staff has no notes to hang them on; read there,
      // every chord was lost.
      final mp = multiPartFromLilyPond(r'''
accomp = \chordmode { c2 g:7 }
\score {
  <<
    \context Staff = "a" \relative c'' { c2 b }
    \context Staff = "b" << \context ChordNames \accomp >>
  >>
}
''');
      expect(mp.parts.first.chordSymbols.map((c) => c.text), ['C', 'G7']);
    });
    test('a chord track in a variable the score uses is found', () {
      // `music = << \context ChordNames \harm \upper \lower >>` …
      // `\score { \music }`: the track was never looked for inside it.
      final mp = multiPartFromLilyPond(r'''
harm = \chordmode { c2 g:7 }
upper = \context Staff = "upper" \relative c'' { c2 b }
lower = \context Staff = "lower" \relative c { c2 g }
music = << \context ChordNames \harm \upper \lower >>
\score { \music }
''');
      expect(mp.parts, hasLength(2));
      expect(mp.parts.first.chordSymbols.map((c) => c.text), ['C', 'G7']);
    });
    test('skips beside a chord track are not the staff\'s music', () {
      // `\context ChordNames << \global \guitar >>`: \global's skips carry
      // the bar lines. Read as music, the staff's bars came twice.
      final mp = multiPartFromLilyPond(r'''
global = { \time 2/2 s1 s1 }
guitar = \chordmode { c1 g1:7 }
\score {
  <<
    \context ChordNames << \global \guitar >>
    \context Staff = "top" << \global \relative c'' { c1 b } >>
    \context Staff = "bottom" << \global \relative c { c1 g } >>
  >>
}
''');
      final top = mp.parts.first;
      expect(top.measures, hasLength(2));
      expect(top.chordSymbols.map((c) => c.text), ['C', 'G7']);
    });
  });
}
