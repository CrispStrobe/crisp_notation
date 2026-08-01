import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Melismas through MuseScore.
///
/// `Lyric.extender` has existed all along and MusicXML, MEI and LilyPond all
/// use it — MuseScore read and wrote none, dropping the melisma in **895 of
/// 1,500 sampled `.mscx` (60%)**. That made it the largest single gap left
/// after the spanner work, and it needed no model change at all.
///
/// ⚠️ MuseScore stores a melisma as `<ticks>` — the DURATION it spans — while
/// the model records only the FACT of one, as MusicXML's `<extend/>` and
/// LilyPond's `__` do. The length is derivable on the way out: a melisma runs
/// from its own note to the next note carrying a syllable in the SAME verse.
void main() {
  Score sung({required bool extender}) => Score(
        clef: Clef.treble,
        lyrics: [
          Lyric('a', 'ex', extender: extender),
          const Lyric('c', 'pa'),
        ],
        measures: [
          Measure([
            for (final (i, midi) in [60, 62, 64, 65].indexed)
              NoteElement(
                pitches: [Pitch.fromMidi(midi)],
                duration: const NoteDuration(DurationBase.quarter),
                id: ['a', 'b', 'c', 'd'][i],
              ),
          ]),
        ],
      );

  test('a melisma round-trips', () {
    final back = scoreFromMscx(scoreToMscx(sung(extender: true)));
    expect(back.lyrics.firstWhere((l) => l.text == 'ex').extender, isTrue);
  });

  test('a syllable with no melisma stays plain', () {
    final back = scoreFromMscx(scoreToMscx(sung(extender: false)));
    expect(back.lyrics.every((l) => !l.extender), isTrue);
    expect(scoreToMscx(sung(extender: false)), isNot(contains('<ticks>')));
  });

  test('the span is measured to the NEXT syllable in the same verse', () {
    // 'ex' is on note a; the next syllable is on note c, two quarters later.
    // MuseScore ticks are 480 per quarter, so 2 quarters is 960.
    expect(scoreToMscx(sung(extender: true)), contains('<ticks>960</ticks>'));
  });

  test('a melisma with no following syllable runs to the end', () {
    final s = Score(
      clef: Clef.treble,
      lyrics: const [Lyric('a', 'ah', extender: true)],
      measures: [
        Measure([
          NoteElement(
            pitches: const [Pitch(Step.c, octave: 4)],
            duration: const NoteDuration(DurationBase.quarter),
            id: 'a',
          ),
          NoteElement(
            pitches: const [Pitch(Step.d, octave: 4)],
            duration: const NoteDuration(DurationBase.quarter),
            id: 'b',
          ),
        ]),
      ],
    );
    // One quarter of melody follows the syllable's own note: 2 quarters total.
    expect(scoreToMscx(s), contains('<ticks>960</ticks>'));
    expect(scoreFromMscx(scoreToMscx(s)).lyrics.single.extender, isTrue);
  });

  test('it reaches the other formats — the concept is NEUTRAL', () {
    final src = sung(extender: true);
    for (final (name, back) in [
      ('musicxml', scoreFromMusicXml(scoreToMusicXml(src))),
      ('mei', scoreFromMei(scoreToMei(src))),
      ('lilypond', scoreFromLilyPond(scoreToLilyPond(src))),
    ]) {
      expect(back.lyrics.any((l) => l.extender), isTrue, reason: name);
    }
  });
}
