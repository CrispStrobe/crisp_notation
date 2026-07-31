import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Slurs read back out of LilyPond.
///
/// The widest single gap the expression audit found: 73,412 slurs across 3,286
/// of the 4,106 corpus `.ly` files, and the reader had NO handling at all. The
/// writer has always emitted `(`/`)`, the parser has always collected them into
/// `LyNote.scripts`, and `Score.slurs` has always existed — only the reader was
/// missing, so every slur in every LilyPond file we read was dropped.
///
/// The final test is the one that matters: a slur has to survive the OTHER
/// formats too. Anything the neutral model cannot carry across a format
/// boundary is not preserved, it is just a LilyPond round-trip trick.
void main() {
  test('a slur spans the notes it was written over', () {
    final s = scoreFromLilyPond(r"\score { \new Staff { c'4( d'4 e'4) f'4 } }");
    final notes =
        s.measures.expand((m) => m.elements).whereType<NoteElement>().toList();
    expect(s.slurs, hasLength(1));
    expect(s.slurs.single.startId, notes[0].id);
    expect(s.slurs.single.endId, notes[2].id);
  });

  test('a chord can carry one', () {
    final s = scoreFromLilyPond(
      r"\score { \new Staff { <g' b'>4( <a' c''>4) } }",
    );
    expect(s.slurs, hasLength(1));
  });

  test('two slurs in a row are two spans', () {
    final s = scoreFromLilyPond(
      r"\score { \new Staff { c'4( d'4) e'4( f'4) } }",
    );
    expect(s.slurs, hasLength(2));
  });

  test('an unmatched close is dropped, not guessed at', () {
    // Real files carry unbalanced marks — a slur opened in one `\\` branch and
    // closed in another. Inventing a span across that is worse than losing one.
    final s = scoreFromLilyPond(r"\score { \new Staff { c'4 d'4) e'4 } }");
    expect(s.slurs, isEmpty);
  });

  test('it round-trips through our own writer', () {
    final src =
        scoreFromLilyPond(r"\score { \new Staff { c'4( d'4 e'4) f'4 } }");
    expect(scoreFromLilyPond(scoreToLilyPond(src)).slurs, hasLength(1));
  });

  test('it survives EVERY other format — neutral, not LilyPond-only', () {
    final src =
        scoreFromLilyPond(r"\score { \new Staff { c'4( d'4 e'4) f'4 } }");
    for (final (name, back) in [
      ('musicxml', scoreFromMusicXml(scoreToMusicXml(src))),
      ('mei', scoreFromMei(scoreToMei(src))),
      ('kern', scoreFromKern(scoreToKern(src))),
      ('abc', scoreFromAbc(scoreToAbc(src))),
      ('musescore', scoreFromMscx(scoreToMscx(src))),
      ('gp', scoreFromGpif(scoreToGpif(src))),
    ]) {
      expect(back.slurs, hasLength(1), reason: name);
    }
  });
}
