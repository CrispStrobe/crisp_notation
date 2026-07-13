import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Score-model lacuna implemented: grace notes can now be an **appoggiatura**
/// (unslashed) as well as the default **acciaccatura** (slashed), via
/// `NoteElement.graceStyle`. Round-trips through MusicXML (`<grace slash>`); the
/// layout draws the stem slash only for acciaccatura.
void main() {
  test('MusicXML round-trips the grace style', () {
    final source = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          NoteElement.note(
            const Pitch(Step.c),
            NoteDuration.quarter,
            graceNotes: const [Pitch(Step.b, octave: 3)],
            id: 'e0', // acciaccatura (default)
          ),
          NoteElement.note(
            const Pitch(Step.d),
            NoteDuration.quarter,
            graceNotes: const [Pitch(Step.c)],
            graceStyle: GraceStyle.appoggiatura,
            id: 'e1',
          ),
          NoteElement.note(const Pitch(Step.e), NoteDuration.quarter, id: 'e2'),
          NoteElement.note(const Pitch(Step.f), NoteDuration.quarter, id: 'e3'),
        ]),
      ],
    );
    final back = scoreFromMusicXml(scoreToMusicXml(source));
    expect(back, source);
    final notes = back.measures.single.elements.cast<NoteElement>();
    expect(notes[0].graceStyle, GraceStyle.acciaccatura);
    expect(notes[1].graceStyle, GraceStyle.appoggiatura);
  });

  test('the DSL grace group defaults to acciaccatura', () {
    final score = Score.simple(notes: '{g4}a4:q');
    final note = score.measures.single.elements.single as NoteElement;
    expect(note.graceStyle, GraceStyle.acciaccatura);
  });

  test('grace style survives transposition', () {
    final note = NoteElement.note(
      const Pitch(Step.c),
      NoteDuration.quarter,
      graceNotes: const [Pitch(Step.b, octave: 3)],
      graceStyle: GraceStyle.appoggiatura,
      id: 'e0',
    );
    final score = Score(clef: Clef.treble, measures: [
      Measure([note])
    ]);
    final up = score.transposedBy(const Interval(IntervalQuality.major, 2));
    expect((up.measures.single.elements.single as NoteElement).graceStyle,
        GraceStyle.appoggiatura);
  });
}
