import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// kern has TWO writer paths, and the multi-voice one was missing things the
/// single-voice one had.
///
/// ⚠️ That is the shape to look for whenever a codec branches: a feature added
/// to the obvious path and never to the other. Both of these were invisible
/// until a real multi-voice file was compared — and a piano score is ALWAYS
/// multi-voice, so "some scores lose this" really meant "all piano music does".
///
/// Mid-bar clefs and grace notes are structurally different in Humdrum and
/// both need their own ROW: an interpretation must span every spine, and a
/// grace note carries no rhythmic time so it cannot ride the onset merge.
void main() {
  List<MusicElement> ns(String p, DurationBase d) => [
        for (var i = 0; i < 2; i++)
          NoteElement(
            id: '$p$i',
            pitches: const [Pitch(Step.c, octave: 4)],
            duration: NoteDuration(d),
          ),
      ];

  test('a mid-bar clef survives a multi-voice measure', () {
    final back = scoreFromKern(scoreToKern(Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        Measure(
          ns('e', DurationBase.half),
          voice2: ns('g', DurationBase.half),
          inlineClefs: [InlineClefChange(Fraction(1, 2), Clef.bass)],
        ),
      ],
    )));
    final ic = back.measures.first.inlineClefs;
    expect(ic, hasLength(1));
    expect(ic.single.onset, Fraction(1, 2));
    expect(ic.single.clef, Clef.bass);
    expect(back.measures.first.voice2, hasLength(2));
  });

  test('a grace note survives a multi-voice measure', () {
    final back = scoreFromKern(scoreToKern(Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        Measure(
          [
            NoteElement(
              id: 'a0',
              pitches: const [Pitch(Step.c, octave: 5)],
              duration: const NoteDuration(DurationBase.half),
              graceNotes: const [Pitch(Step.b, octave: 4)],
              graceStyle: GraceStyle.appoggiatura,
            ),
            NoteElement(
              id: 'a1',
              pitches: const [Pitch(Step.d, octave: 5)],
              duration: const NoteDuration(DurationBase.half),
            ),
          ],
          voice2: [
            NoteElement(
              id: 'b0',
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.whole),
            )
          ],
        ),
      ],
    )));
    final first = back.measures.single.elements.first as NoteElement;
    expect(first.graceNotes, hasLength(1));
    expect(first.graceStyle, GraceStyle.appoggiatura);
    expect(back.measures.single.voice2, hasLength(1));
    expect(back.measures.single.elements, hasLength(2));
  });

  test('two grace notes on one principal both survive', () {
    final back = scoreFromKern(scoreToKern(Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        Measure(
          [
            NoteElement(
              id: 'a0',
              pitches: const [Pitch(Step.c, octave: 5)],
              duration: const NoteDuration(DurationBase.whole),
              graceNotes: const [
                Pitch(Step.a, octave: 4),
                Pitch(Step.b, octave: 4),
              ],
            )
          ],
          voice2: [
            NoteElement(
              id: 'b0',
              pitches: const [Pitch(Step.e, octave: 4)],
              duration: const NoteDuration(DurationBase.whole),
            )
          ],
        ),
      ],
    )));
    expect((back.measures.single.elements.first as NoteElement).graceNotes,
        hasLength(2));
  });
}
