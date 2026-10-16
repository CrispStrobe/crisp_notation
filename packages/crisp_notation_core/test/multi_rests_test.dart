import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// `withMultiRests`: a part's runs of silent bars print as multi-bar rests,
/// broken where a player must see something.
void main() {
  Measure rest(String id) => Measure([RestElement(NoteDuration.whole, id: id)]);
  Measure note(String id) => Measure([
        NoteElement.note(const Pitch(Step.c, octave: 5), NoteDuration.whole,
            id: id),
      ]);
  Score part(List<Measure> bars, {List<Annotation> annotations = const []}) =>
      Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: bars,
        annotations: annotations,
      );
  List<int?> shape(Score s) => [for (final m in s.measures) m.multiRest];

  test('a run of silent bars becomes one multi-bar rest', () {
    final s = part([note('a'), rest('r1'), rest('r2'), rest('r3'), note('b')])
        .withMultiRests();
    expect(shape(s), [null, 3, null]);
    expect((s.measures[1].elements.single as RestElement).id, 'r1');
    // The part still lasts as long: 1 + 3 + 1 bars of 4/4.
    final last = playbackTimeline(s, expandRepeats: false).last;
    expect(last.start, Fraction(4, 1));
  });

  test('a single silent bar stays a bar', () {
    expect(shape(part([note('a'), rest('r'), note('b')]).withMultiRests()),
        [null, null, null]);
  });

  test('a change a player must see starts a new rest', () {
    final s = part([
      rest('r1'),
      rest('r2'),
      rest('r3').copyWith(keyChange: KeySignature.fromFifths(2)),
      rest('r4'),
    ]).withMultiRests();
    expect(shape(s), [2, 2]);
    expect(s.measures[1].keyChange, KeySignature.fromFifths(2));
  });

  test('an end repeat closes the run, keeping its barline', () {
    final s = part([
      rest('r1'),
      rest('r2').copyWith(endRepeat: true),
      rest('r3'),
      rest('r4'),
    ]).withMultiRests();
    expect(shape(s), [2, 2]);
    expect(s.measures.first.endRepeat, isTrue);
  });

  test('a rest carrying text is not swallowed', () {
    final s = part([rest('r1'), rest('r2'), rest('r3')],
        annotations: [const Annotation('r2', 'Solo')]).withMultiRests();
    expect(shape(s), [null, null, null]);
  });
}
