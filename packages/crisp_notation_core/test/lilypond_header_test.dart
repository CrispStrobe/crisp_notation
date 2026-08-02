import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// `\header` was WRITE-ONLY on the single-staff path.
///
/// `multiPartFromLilyPond` read it; `scoreFromLilyPond` — which is what every
/// round trip and most callers use — did not, so every LilyPond export came
/// back untitled while the file on disk carried the title all along.
///
/// Systematic rather than an edge case: it failed on 400 of 400 corpus ABC
/// files put through LilyPond, and the plain note comparison could not see it.
void main() {
  Score titled(ScoreMetadata m) => Score(
        clef: Clef.treble,
        metadata: m,
        measures: [
          Measure(<MusicElement>[
            NoteElement(
              id: 'e0',
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.quarter),
            ),
          ]),
        ],
      );

  test('title and composer survive the round trip', () {
    final back = scoreFromLilyPond(scoreToLilyPond(titled(
        const ScoreMetadata(title: "Charlotte's Jig", composer: 'Pete Mac'))));
    expect(back.metadata.title, "Charlotte's Jig");
    expect(back.metadata.composer, 'Pete Mac');
  });

  test('a lyricist survives too', () {
    final back = scoreFromLilyPond(
        scoreToLilyPond(titled(const ScoreMetadata(lyricist: 'W. Cowper'))));
    expect(back.metadata.lyricist, 'W. Cowper');
  });

  test('an apostrophe in the title is not an octave mark', () {
    // The title rides in a quoted string, but `'` is the octave mark in music,
    // so a naive lexer would take it as one.
    final back = scoreFromLilyPond(
        scoreToLilyPond(titled(const ScoreMetadata(title: "A' B' C'"))));
    expect(back.metadata.title, "A' B' C'");
  });

  test('no header means no invented metadata', () {
    final back =
        scoreFromLilyPond(scoreToLilyPond(titled(const ScoreMetadata())));
    expect(back.metadata.title, isNull);
    expect(back.metadata.composer, isNull);
  });

  test('the notes are unaffected', () {
    final back = scoreFromLilyPond(
        scoreToLilyPond(titled(const ScoreMetadata(title: 'x'))));
    expect(back.measures.single.elements, hasLength(1));
  });
}
