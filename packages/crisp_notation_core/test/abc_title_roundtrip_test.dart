import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// `scoreToAbc` must write the score's OWN title.
///
/// The only source used to be the optional `title` PARAMETER, so the ordinary
/// call `scoreToAbc(score)` emitted no `T:` at all and **every ABC export we
/// produced was untitled**. Composer had the same gap.
///
/// Found by the 10,000-file held ABC control once the harness signature started
/// comparing metadata — the self round trip `abc -> abc` failed on 399 of 400
/// sampled files, having looked perfect while metadata went unchecked.
void main() {
  Score titled() => Score(
        clef: Clef.treble,
        metadata: const ScoreMetadata(
          title: '001 - Antifona',
          composer: 'William Henry Monk',
        ),
        measures: [
          Measure([
            NoteElement(
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.quarter),
              id: 'a',
            ),
          ]),
        ],
      );

  test('the title survives a round trip with no parameter passed', () {
    final back = scoreFromAbc(scoreToAbc(titled()));
    expect(back.metadata.title, '001 - Antifona');
  });

  test('the composer survives too', () {
    expect(scoreFromAbc(scoreToAbc(titled())).metadata.composer,
        'William Henry Monk');
  });

  test('an explicit title parameter still wins', () {
    final abc = scoreToAbc(titled(), title: 'Override');
    expect(scoreFromAbc(abc).metadata.title, 'Override');
  });

  test('a score with no title writes no T: line', () {
    final plain = Score(clef: Clef.treble, measures: [
      Measure([
        NoteElement(
          pitches: const [Pitch(Step.c, octave: 4)],
          duration: const NoteDuration(DurationBase.quarter),
          id: 'a',
        ),
      ]),
    ]);
    expect(scoreToAbc(plain), isNot(contains('T:')));
  });

  test('a BLANK W: line is kept — it separates stanzas', () {
    // Dropping empty verse lines reflows a four-verse hymn into one block; the
    // sample file went 21 -> 16 lines.
    final s = Score(
      clef: Clef.treble,
      metadata: const ScoreMetadata(words: ['verse one', '', 'verse two']),
      measures: [
        Measure([
          NoteElement(
            pitches: const [Pitch(Step.c, octave: 4)],
            duration: const NoteDuration(DurationBase.quarter),
            id: 'a',
          ),
        ]),
      ],
    );
    expect(scoreFromAbc(scoreToAbc(s)).metadata.words,
        ['verse one', '', 'verse two']);
  });
}
