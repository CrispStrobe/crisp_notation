import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Ties through Guitar Pro.
///
/// The GP codec handled bends, slides, harmonics, vibrato, palm-mute, let-ring,
/// tapping, fingering, whammy, brush and barre — and not TIES, in either
/// direction. A tie is not an exotic guitar technique; it is basic notation,
/// and every one in every `.gp` we read or wrote was dropped.
///
/// Syntax read off a real corpus `.gp` rather than guessed:
/// `<Tie origin="true" destination="false"/>`, a NOTE-level sibling of
/// `<Properties>`. `origin` means a tie starts here, `destination` that one
/// ends here.
void main() {
  List<bool> ties(Score s) => s.measures
      .expand((m) => m.elements)
      .whereType<NoteElement>()
      .map((e) => e.tieToNext)
      .toList();

  NoteElement n(Step step, {bool tie = false, required String id}) =>
      NoteElement(
        pitches: [Pitch(step, octave: 4)],
        duration: const NoteDuration(DurationBase.quarter),
        tieToNext: tie,
        id: id,
      );

  test('a tie survives the round trip', () {
    final src = Score(clef: Clef.treble, measures: [
      Measure([
        n(Step.c, tie: true, id: 'a'),
        n(Step.c, id: 'b'),
        n(Step.d, id: 'c'),
      ]),
    ]);
    expect(ties(scoreFromGpif(scoreToGpif(src))), [true, false, false]);
  });

  test('a chain of ties survives', () {
    final src = Score(clef: Clef.treble, measures: [
      Measure([
        n(Step.c, tie: true, id: 'a'),
        n(Step.c, tie: true, id: 'b'),
        n(Step.c, id: 'c'),
      ]),
    ]);
    expect(ties(scoreFromGpif(scoreToGpif(src))), [true, true, false]);
  });

  test('an untied score writes no <Tie> at all', () {
    final gpif = scoreToGpif(Score(clef: Clef.treble, measures: [
      Measure([n(Step.c, id: 'a'), n(Step.d, id: 'b')]),
    ]));
    expect(gpif, isNot(contains('<Tie')));
  });

  test('the destination flag marks the receiving note', () {
    final gpif = scoreToGpif(Score(clef: Clef.treble, measures: [
      Measure([n(Step.c, tie: true, id: 'a'), n(Step.c, id: 'b')]),
    ]));
    expect(gpif, contains('origin="true"'));
    expect(gpif, contains('destination="true"'));
  });

  test('a tied CHORD ties the element', () {
    // GP marks the tie per note, so any tied note in a chord ties it.
    final src = Score(clef: Clef.treble, measures: [
      Measure([
        NoteElement(
          pitches: const [Pitch(Step.c, octave: 4), Pitch(Step.e, octave: 4)],
          duration: const NoteDuration(DurationBase.quarter),
          tieToNext: true,
          id: 'a',
        ),
        NoteElement(
          pitches: const [Pitch(Step.c, octave: 4), Pitch(Step.e, octave: 4)],
          duration: const NoteDuration(DurationBase.quarter),
          id: 'b',
        ),
      ]),
    ]);
    expect(ties(scoreFromGpif(scoreToGpif(src))), [true, false]);
  });
}
