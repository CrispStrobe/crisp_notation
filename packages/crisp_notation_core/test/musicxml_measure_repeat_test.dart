import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// `Measure.measureRepeat` — the simile `%` — was a channel NOTHING could put
/// on paper: no codec wrote it, so anything the app produced there was lost on
/// every save. Its sibling `<multiple-rest>` has been written all along.
void main() {
  List<MusicElement> ns() => [
        for (var i = 0; i < 4; i++)
          NoteElement(
            id: 'e$i',
            pitches: const [Pitch(Step.c, octave: 4)],
            duration: const NoteDuration(DurationBase.quarter),
          ),
      ];

  Score scored(int? repeat) => Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(ns()),
          Measure(const [], measureRepeat: repeat),
        ],
      );

  for (final n in [1, 2, 4]) {
    test('a $n-bar repeat survives MusicXML', () {
      final back = scoreFromMusicXml(scoreToMusicXml(scored(n)));
      expect(back.measures[1].measureRepeat, n);
      expect(back.measures.first.measureRepeat, isNull);
    });
  }

  test('a score without one writes no <measure-repeat>', () {
    expect(scoreToMusicXml(scored(null)), isNot(contains('measure-repeat')));
  });

  test('a type="stop" mark does not start one', () {
    // The stop element closes a repeat rather than opening it; reading it as a
    // start would put a simile on the bar AFTER the group.
    final xml =
        scoreToMusicXml(scored(2)).replaceAll('type="start"', 'type="stop"');
    expect(scoreFromMusicXml(xml).measures[1].measureRepeat, isNull);
  });

  test('an out-of-range count from a third-party file is dropped, not thrown',
      () {
    // The model asserts 1, 2 or 4. A file naming 3 must not crash the import.
    final xml =
        scoreToMusicXml(scored(2)).replaceAll('slashes="2"', 'slashes="3"');
    expect(() => scoreFromMusicXml(xml), returnsNormally);
    expect(scoreFromMusicXml(xml).measures[1].measureRepeat, isNull);
  });
}
