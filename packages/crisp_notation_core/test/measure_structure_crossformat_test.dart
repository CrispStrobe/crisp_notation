import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Volta brackets and mid-score key changes, in every format that spells them.
///
/// LilyPond carried neither. Its writer emitted `\key` for a change and its
/// reader only ever updated the RUNNING key with it, so the change itself was
/// dropped — the same write-only asymmetry as `\tempo` and `\header`. Voltas it
/// wrote nothing for at all.
///
/// ⚠️ The volta spelling was taken from the corpus, not invented: 442 `.ly`
/// files write `\repeat volta { … } \alternative { … }` (which the reader's
/// unfolding path handles) and 4 write the explicit
/// `\set Score.repeatCommands = #'((volta "1"))`. Only the second can be
/// produced from a FLAT measure list, since folding arbitrary repeat marks back
/// into a `\repeat` block is not always possible.
void main() {
  List<MusicElement> ns(String p) => [
        for (var i = 0; i < 4; i++)
          NoteElement(
            id: '$p$i',
            pitches: const [Pitch(Step.c, octave: 4)],
            duration: const NoteDuration(DurationBase.quarter),
          ),
      ];

  final hops = <String, Score Function(Score)>{
    'musicxml': (x) => scoreFromMusicXml(scoreToMusicXml(x)),
    'mei': (x) => scoreFromMei(scoreToMei(x)),
    'kern': (x) => scoreFromKern(scoreToKern(x)),
    'abc': (x) => scoreFromAbc(scoreToAbc(x)),
    'lilypond': (x) => scoreFromLilyPond(scoreToLilyPond(x)),
    'musescore': (x) => scoreFromMscx(scoreToMscx(x)),
  };

  Score scored() => Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(ns('a'), startRepeat: true),
          Measure(ns('b'), endRepeat: true, volta: 1),
          Measure(ns('c'), volta: 2, keyChange: const KeySignature(-2)),
          Measure(ns('d')),
        ],
      );

  for (final e in hops.entries) {
    test('${e.key} keeps a mid-score KEY change', () {
      final back = e.value(scored());
      expect(back.measures[2].keyChange?.fifths, -2, reason: e.key);
      expect(back.keySignature.fifths, 0, reason: '${e.key}: score key intact');
    });

    test('${e.key} keeps VOLTA brackets', () {
      final back = e.value(scored());
      expect(back.measures[1].volta, 1, reason: e.key);
      // ⚠️ The second bracket both closes the first and opens itself, so
      // LilyPond writes `#'((volta #f) (volta "2"))` — reading the FIRST
      // directive of that list yields null, and the LAST is the answer.
      expect(back.measures[2].volta, 2, reason: e.key);
      expect(back.measures[0].volta, isNull, reason: e.key);
      expect(back.measures[3].volta, isNull, reason: e.key);
    });

    test('${e.key} keeps the repeat marks that carry them', () {
      final back = e.value(scored());
      expect(back.measures[0].startRepeat, isTrue, reason: e.key);
      expect(back.measures[1].endRepeat, isTrue, reason: e.key);
    });
  }
}
