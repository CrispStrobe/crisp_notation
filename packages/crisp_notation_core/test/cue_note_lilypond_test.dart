import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Cue notes, in every format that draws them.
///
/// ⚠️ This was written off as a LilyPond format limit, and the reason was a
/// wrong assumption about what the model means. `\cueDuring` quotes ANOTHER
/// VOICE, which a flat measure list genuinely cannot produce — but the model
/// defines a cue note as one whose "head, stem, flag and dots" are at a
/// reduced SCALE. That is exactly `\tweak font-size`, the same mechanism the
/// writer already used for noteheads. Read the model before declaring a limit.
///
/// kern and ABC remain real limits: neither has any notion of a small note.
void main() {
  final hops = <String, Score Function(Score)>{
    'musicxml': (x) => scoreFromMusicXml(scoreToMusicXml(x)),
    'mei': (x) => scoreFromMei(scoreToMei(x)),
    'lilypond': (x) => scoreFromLilyPond(scoreToLilyPond(x)),
    'musescore': (x) => scoreFromMscx(scoreToMscx(x)),
  };

  Score scored() => Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure([
            for (var i = 0; i < 4; i++)
              NoteElement(
                id: 'a$i',
                pitches: const [Pitch(Step.c, octave: 4)],
                duration: const NoteDuration(DurationBase.quarter),
              ),
          ])
        ],
        cueNoteIds: const ['a1', 'a2'],
      );

  for (final e in hops.entries) {
    test('${e.key} keeps cue notes, on the right notes', () {
      final back = e.value(scored());
      // By POSITION — every reader regenerates ids.
      final at = {
        for (var i = 0; i < back.measures.single.elements.length; i++)
          back.measures.single.elements[i].id: i
      };
      expect((back.cueNoteIds.map((c) => at[c]).toList()..sort()), [1, 2],
          reason: e.key);
    });

    test('${e.key} marks nothing when there are no cues', () {
      final plain = Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: scored().measures,
      );
      expect(e.value(plain).cueNoteIds, isEmpty, reason: e.key);
    });
  }

  test('a cue is a NEGATIVE font-size, and any reduction counts', () {
    expect(scoreToLilyPond(scored()), contains(r'\tweak font-size #-3'));
    // ⚠️ The lexer splits `font-size` at the hyphen, because `-` is the script
    // marker — `NoteHead.style` survived only because it has none. The reader
    // rejoins the parts, so a different magnitude still reads as a cue.
    final other = scoreFromLilyPond(
        "\\score { \\new Staff { c'4 \\tweak font-size #-2 d'4 } }");
    expect(other.cueNoteIds, hasLength(1));
    final plain = scoreFromLilyPond(
        "\\score { \\new Staff { c'4 \\tweak font-size #2 d'4 } }");
    expect(plain.cueNoteIds, isEmpty, reason: 'an ENLARGED note is not a cue');
  });
}
