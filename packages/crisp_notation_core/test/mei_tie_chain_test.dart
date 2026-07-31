import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// MEI ties are a CHAIN, and we only ever wrote its first link.
///
/// `@tie` takes `i` (initial), `m` (medial) and `t` (terminal). The writer put
/// `tie="i"` on every note with `tieToNext` and nothing on the note receiving
/// it, so every tie was left unterminated. Verovio reports
/// "Expected @tie median or terminal" and SKIPS the note outright — the music
/// is simply gone from its rendering.
///
/// Our own reader is lenient about the value, which is exactly why no
/// round-trip could see this. It took asking a third-party renderer.
void main() {
  NoteElement n(Step step, {bool tie = false, required String id}) =>
      NoteElement(
        pitches: [Pitch(step, octave: 4)],
        duration: const NoteDuration(DurationBase.quarter),
        tieToNext: tie,
        id: id,
      );

  List<String> tieValues(String mei) => [
        for (final m in RegExp(r'tie="(\w)"').allMatches(mei)) m[1]!,
      ];

  test('a two-note tie is i then t', () {
    final mei = scoreToMei(Score(clef: Clef.treble, measures: [
      Measure([n(Step.c, tie: true, id: 'a'), n(Step.c, id: 'b')]),
    ]));
    expect(tieValues(mei), ['i', 't']);
  });

  test('a three-note tie is i, m, t', () {
    final mei = scoreToMei(Score(clef: Clef.treble, measures: [
      Measure([
        n(Step.c, tie: true, id: 'a'),
        n(Step.c, tie: true, id: 'b'),
        n(Step.c, id: 'c'),
      ]),
    ]));
    expect(tieValues(mei), ['i', 'm', 't']);
  });

  test('an untied note carries no @tie at all', () {
    final mei = scoreToMei(Score(clef: Clef.treble, measures: [
      Measure([n(Step.c, id: 'a'), n(Step.d, id: 'b')]),
    ]));
    expect(tieValues(mei), isEmpty);
  });

  test('the tie still round-trips through our own reader', () {
    final score = Score(clef: Clef.treble, measures: [
      Measure([
        n(Step.c, tie: true, id: 'a'),
        n(Step.c, tie: true, id: 'b'),
        n(Step.c, id: 'c'),
        n(Step.d, id: 'd'),
      ]),
    ]);
    final back = scoreFromMei(scoreToMei(score));
    expect(
      back.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .map((e) => e.tieToNext),
      [true, true, false, false],
    );
  });
}
