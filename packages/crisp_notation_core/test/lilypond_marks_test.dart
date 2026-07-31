import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Ties, articulations and ornaments survive a LilyPond round trip.
///
/// The writer has always emitted all three and the PARSER has always collected
/// them — `LyNote.scripts` held `~`, `-.`, `->` and the rest, and `\trill` /
/// `\fermata` arrived as sibling commands. The READER simply dropped them on
/// the floor, so every one was lost on the way back in.
///
/// Nothing could see it while the sweep compared only pitch and rhythm: the
/// notes were all present, at the right lengths, stripped of their marks.
void main() {
  NoteElement first(Score s) =>
      s.measures.expand((m) => m.elements).whereType<NoteElement>().first;

  List<NoteElement> notes(Score s) =>
      s.measures.expand((m) => m.elements).whereType<NoteElement>().toList();

  group('read directly from source', () {
    test('a tie', () {
      final s = scoreFromLilyPond(r"\score { \new Staff { c'4~ c'4 } }");
      expect(notes(s).map((e) => e.tieToNext), [true, false]);
    });

    test('the shorthand scripts', () {
      for (final (script, artic) in [
        ('-.', Articulation.staccato),
        ('--', Articulation.tenuto),
        ('->', Articulation.accent),
        ('-^', Articulation.marcato),
      ]) {
        final s = scoreFromLilyPond("\\score { \\new Staff { c'4$script } }");
        expect(first(s).articulations, {artic}, reason: script);
      }
    });

    test('post-note commands attach to the note BEFORE them', () {
      for (final (cmd, orn) in [
        ('trill', Ornament.trill),
        ('prall', Ornament.shortTrill),
        ('mordent', Ornament.mordent),
        ('turn', Ornament.turn),
        ('reverseturn', Ornament.invertedTurn),
      ]) {
        final s = scoreFromLilyPond("\\score { \\new Staff { c'4\\$cmd } }");
        expect(first(s).ornament, orn, reason: cmd);
      }
      for (final (cmd, artic) in [
        ('fermata', Articulation.fermata),
        ('upbow', Articulation.upBow),
        ('downbow', Articulation.downBow),
      ]) {
        final s = scoreFromLilyPond("\\score { \\new Staff { c'4\\$cmd } }");
        expect(first(s).articulations, contains(artic), reason: cmd);
      }
    });

    test('a script and a command on the same note', () {
      final s = scoreFromLilyPond(r"\score { \new Staff { c'4->\trill } }");
      expect(first(s).articulations, {Articulation.accent});
      expect(first(s).ornament, Ornament.trill);
    });
  });

  test('they survive our own round trip', () {
    final score = Score(clef: Clef.treble, measures: [
      Measure([
        NoteElement(
          pitches: const [Pitch(Step.c, octave: 4)],
          duration: const NoteDuration(DurationBase.quarter),
          tieToNext: true,
          id: 'a',
        ),
        NoteElement(
          pitches: const [Pitch(Step.c, octave: 4)],
          duration: const NoteDuration(DurationBase.quarter),
          articulations: const {Articulation.staccato},
          id: 'b',
        ),
        NoteElement(
          pitches: const [Pitch(Step.d, octave: 4)],
          duration: const NoteDuration(DurationBase.quarter),
          articulations: const {Articulation.fermata},
          ornament: Ornament.trill,
          id: 'c',
        ),
      ]),
    ]);
    final back = scoreFromLilyPond(scoreToLilyPond(score));
    final got = notes(back);
    expect(got[0].tieToNext, isTrue);
    expect(got[1].articulations, contains(Articulation.staccato));
    expect(got[2].articulations, contains(Articulation.fermata));
    expect(got[2].ornament, Ornament.trill);
  });
}
