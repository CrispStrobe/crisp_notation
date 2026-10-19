// LilyPond: a file of several `\score` blocks holds several pieces, typeset
// one after another and, for each `\midi`, written to a MIDI file of its own.
// `lilyPondScoreCount` counts them and `piece:` reads one alone, as
// `abcTuneCount` and `tune:` do for an ABC tunebook.
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

List<int> _pitches(Score s) => [
      for (final m in s.measures)
        for (final e in m.elements)
          if (e is NoteElement)
            for (final p in e.pitches) p.midiNumber,
    ];

List<List<int>> _partPitches(MultiPartScore mp) =>
    [for (final p in mp.parts) _pitches(p)];

// Two pieces sharing a variable and a staff name, as in Mutopia's
// division-violin-two-27: both print and both play.
const _twoPieces = r'''
\version "2.24.0"
\header { title = "Divisions" composer = "Anon." }
glob = { \time 2/4 }
tune = { \glob c'4 d'4 | e'4 f'4 }
bass = { \glob \clef bass c4 g,4 }
\score {
  \new Staff = "one" \tune
  \layout { }
  \midi { }
}
\score {
  \new Staff = "one" \bass
  \layout { }
  \midi { }
}
''';

void main() {
  group('lilyPondScoreCount', () {
    test('bare music with no \\score is one piece', () {
      expect(lilyPondScoreCount(r"{ c'4 d' e' f' }"), 1);
      expect(lilyPondScoreCount(r"{ c'4 d' e' f' }", playback: true), 1);
    });

    test('one per \\score', () {
      expect(lilyPondScoreCount(_twoPieces), 2);
      expect(lilyPondScoreCount(_twoPieces, playback: true), 2);
    });

    test(
        'a \\midi-only companion is no piece in print, a \\layout-only '
        'score none in playback', () {
      const ly = r'''
mus = { c'4 d' e' f' }
\score { \mus \layout { } }
\score { \unfoldRepeats \mus \midi { } }
\score { { g'1 } \layout { } }
\score { { a'1 } }
''';
      // Printed: the first, third and fourth (no block: a layout by default).
      expect(lilyPondScoreCount(ly), 3);
      // Played: only the one with \midi.
      expect(lilyPondScoreCount(ly, playback: true), 1);
    });

    test('scores inside \\book and \\bookpart count', () {
      const ly = r'''
\book {
  \bookpart { \score { { c'1 } \midi { } \layout { } } }
  \bookpart { \score { { d'1 } \layout { } } }
}
\book { \score { { e'1 } \midi { } } }
''';
      expect(lilyPondScoreCount(ly), 2);
      expect(lilyPondScoreCount(ly, playback: true), 2);
    });
  });

  group('piece:', () {
    test('selects one piece, with the variables the file defines', () {
      expect(
          _pitches(scoreFromLilyPond(_twoPieces, piece: 0)), [60, 62, 64, 65]);
      expect(_pitches(scoreFromLilyPond(_twoPieces, piece: 1)), [48, 43]);
      expect(_partPitches(multiPartFromLilyPond(_twoPieces, piece: 1)), [
        [48, 43]
      ]);
    });

    test('the file\'s \\header and global settings reach each piece', () {
      final s = scoreFromLilyPond(_twoPieces, piece: 1);
      expect(s.metadata.title, 'Divisions');
      expect(s.metadata.composer, 'Anon.');
      expect(s.timeSignature, const TimeSignature(2, 4));
    });

    test('a piece\'s own \\header is its own', () {
      const ly = r'''
\header { composer = "Anon." }
\score { { c'1 } \header { title = "First" } }
\score { { d'1 } \header { title = "Second" } }
''';
      final first = scoreFromLilyPond(ly, piece: 0);
      final second = scoreFromLilyPond(ly, piece: 1);
      expect(first.metadata.title, 'First');
      expect(second.metadata.title, 'Second');
      expect(second.metadata.composer, 'Anon.');
    });

    test('with playback, piece i is the i-th score with \\midi', () {
      const ly = r'''
mus = { c'4 d' e' f' }
\score { \mus \layout { } }
\score { \mus \midi { } }
\score { { g'1 } \layout { } \midi { } }
''';
      expect(_pitches(scoreFromLilyPond(ly, playback: true, piece: 0)),
          [60, 62, 64, 65]);
      expect(_pitches(scoreFromLilyPond(ly, playback: true, piece: 1)), [67]);
      // In print, the \midi-only score is no piece: the second is the g'.
      expect(_pitches(scoreFromLilyPond(ly, piece: 1)), [67]);
    });

    test('a piece inside a \\book, its book\'s \\header with it', () {
      const ly = r'''
\header { composer = "Anon." }
v = { e'1 }
\book {
  \header { title = "Book one" }
  \score { { c'1 } }
}
\book {
  \header { title = "Book two" }
  \bookpart { \score { \v } }
}
''';
      final s = scoreFromLilyPond(ly, piece: 1);
      expect(_pitches(s), [64]);
      expect(s.metadata.title, 'Book two');
      expect(s.metadata.composer, 'Anon.');
      expect(_pitches(scoreFromLilyPond(ly, piece: 0)), [60]);
    });

    test('bare music is piece 0', () {
      expect(_pitches(scoreFromLilyPond(r"{ c'4 d' }", piece: 0)), [60, 62]);
    });

    test('a piece the file does not hold is a RangeError', () {
      expect(() => scoreFromLilyPond(_twoPieces, piece: 2), throwsRangeError);
      expect(
          () => multiPartFromLilyPond(_twoPieces, piece: -1), throwsRangeError);
      expect(() => scoreFromLilyPond(r"{ c'1 }", piece: 1), throwsRangeError);
    });

    test('without piece: the reading is unchanged', () {
      const ly = r'''
\score { \new Staff { c'1 } \layout { } }
\score { \new Staff { d'1 } \layout { } }
''';
      // Two scores, two staves: read together as before.
      expect(multiPartFromLilyPond(ly).parts, hasLength(2));
      expect(multiPartFromLilyPond(ly, piece: 0).parts, hasLength(1));
      // So are two scores sharing a staff name.
      expect(_partPitches(multiPartFromLilyPond(_twoPieces)), [
        [60, 62, 64, 65],
        [48, 43]
      ]);
    });
  });
}
