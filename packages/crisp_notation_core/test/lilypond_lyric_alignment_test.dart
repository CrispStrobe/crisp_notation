import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A lyric line must start on the note it is sung on.
///
/// ⚠️ Two directives were being read as SUNG SYLLABLES, and each one shifted
/// every syllable after it onto the next note. That is a silent misalignment of
/// a whole verse, not a stray word — and it looked like a trailing-space
/// difference in the corpus report, which is how it stayed hidden.
///
/// - `\lyricsto "Melodie" \Text` names the VOICE in its first argument. It is
///   the standard spelling as soon as a context has a name, so this affected
///   ordinary vocal scores, not an edge case.
/// - `\set stanza = #"1. "` configures the context. The parser does not keep it
///   together: `\set` arrives with NO arguments, the `stanza = #` assignment as
///   its sibling and the Scheme string as a sibling of THAT, so a blind walk
///   sang the verse number.
void main() {
  const src = r'''
Melody = \relative c'' { c4 d4 e4 f4 }
Text = \lyricmode { \set stanza = #"1. " Kling, Glöck chen, klin }
\score {
  <<
    \new Voice = "Melodie" { \Melody }
    \new Lyrics = Strophe \lyricsto Melodie \Text
  >>
}
''';

  test('the voice name of \\lyricsto is not sung', () {
    final score = scoreFromLilyPond(src);
    expect(score.lyrics.map((l) => l.text), isNot(contains('Melodie')));
  });

  test('a \\set stanza marker is not sung', () {
    final score = scoreFromLilyPond(src);
    expect(score.lyrics.map((l) => l.text), isNot(contains('1. ')));
  });

  test('every syllable lands on its own note', () {
    final score = scoreFromLilyPond(src);
    final ids = [for (final e in score.measures.first.elements) e.id];
    expect(ids, hasLength(4));
    expect(
      [for (final l in score.lyrics) '${l.elementId}=${l.text}'],
      [
        '${ids[0]}=Kling,',
        '${ids[1]}=Glöck',
        '${ids[2]}=chen,',
        '${ids[3]}=klin'
      ],
    );
  });

  test('a plain \\addlyrics is unaffected', () {
    final score = scoreFromLilyPond(
        r"\score { \new Staff { c'4 d'4 } \addlyrics { one two } }");
    expect([for (final l in score.lyrics) l.text], ['one', 'two']);
  });
}
