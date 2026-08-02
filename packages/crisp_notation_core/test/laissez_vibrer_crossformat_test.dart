import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Let-ring (laissez vibrer) reached only MusicXML.
///
/// LilyPond spells it `\laissezVibrer` on the note; MEI makes it an ATTRIBUTE
/// (`@lv`) on the `<note>`/`<chord>` rather than a control event, which is why
/// it rides with the note writer instead of with the spans.
void main() {
  Score scored(List<LaissezVibrer> lv) => Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(<MusicElement>[
            NoteElement(
              id: 'e0',
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.quarter),
            ),
            NoteElement(
              id: 'e1',
              pitches: const [
                Pitch(Step.d, octave: 4),
                Pitch(Step.f, octave: 4),
              ],
              duration: const NoteDuration(DurationBase.quarter),
            ),
          ]),
        ],
        laissezVibrer: lv,
      );

  final hops = <String, Score Function(Score)>{
    'musicxml': (x) => scoreFromMusicXml(scoreToMusicXml(x)),
    'mei': (x) => scoreFromMei(scoreToMei(x)),
    'lilypond': (x) => scoreFromLilyPond(scoreToLilyPond(x)),
  };

  for (final e in hops.entries) {
    test('${e.key} carries a let-ring on a note', () {
      final back = e.value(scored(const [LaissezVibrer('e0')]));
      expect(back.laissezVibrer, hasLength(1), reason: e.key);
      final ids = back.measures.single.elements
          .whereType<NoteElement>()
          .map((n) => n.id)
          .toList();
      expect(back.laissezVibrer.single.noteId, ids.first, reason: e.key);
    });

    test('${e.key} carries one on a CHORD', () {
      // MEI puts `@lv` on `<chord>`, not on each `<note>` inside it.
      final back = e.value(scored(const [LaissezVibrer('e1')]));
      expect(back.laissezVibrer, hasLength(1), reason: e.key);
      final ids = back.measures.single.elements
          .whereType<NoteElement>()
          .map((n) => n.id)
          .toList();
      expect(back.laissezVibrer.single.noteId, ids[1], reason: e.key);
    });

    test('${e.key} invents none when there are none', () {
      expect(e.value(scored(const [])).laissezVibrer, isEmpty, reason: e.key);
    });
  }
}
