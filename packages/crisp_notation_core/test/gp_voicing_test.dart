// The GP readers must PRESERVE the file's human fingering (per-note string
// choice), not just its pitches — [TabDocument.fromScore] and any tab importer
// rely on [Score.tabVoicings], and a corpus extractor mines them. Regression lock
// for that: a note voiced on a NON-default string must survive a GPIF round-trip
// on the recovered string, not be silently re-derived to the lowest position.
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

void main() {
  test('GPIF read preserves a non-default string choice (tabVoicings)', () {
    final t = Tuning.standardGuitar; // idx 0 = high e(64) … 5 = low E(40)
    // E4 (64): default is open high-e (string 0, fret 0). Voice it deliberately
    // on string 1 (b3=59) fret 5 — a real fingering choice a human might make.
    final score = Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement(
            pitches: [Pitch.fromMidi(64)],
            duration: NoteDuration.quarter,
            id: 'n0',
          ),
        ]),
      ],
      tabVoicings: [
        const TabVoicing('n0', [1])
      ],
    );

    final back = scoreFromGpif(
        readGpifFromGp(writeGpFromGpif(scoreToGpif(score, tuning: t))));

    final voiced = {for (final v in back.tabVoicings) v.noteId: v.strings};
    expect(voiced, isNotEmpty, reason: 'fingering must survive the round-trip');
    final note =
        back.measures.expand((m) => m.elements).whereType<NoteElement>().single;
    final strings = voiced[note.id]!;
    expect(strings, [1],
        reason: 'must recover string 1, not re-derive string 0');
    // And the string+fret must reproduce the sounding pitch under the tuning.
    final fret =
        note.pitches.single.midiNumber - t.strings[strings.single].midiNumber;
    expect(fret, 5);
  });
}
