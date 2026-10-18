import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Full ending data through ABC: `[1,2` / `[1-3` / `|1` / `:|2` number lists,
/// `["text"` labels, endings over several bars, and open ends.
///
/// ⚠️ ABC states no open end, so ends follow how it is engraved: a closing
/// hook only where the ending stops at a repeat sign or the final bar line.
/// An ending runs on over plain `|` bar lines up to the `:|` that closes it,
/// so a two-bar first ending is skipped on the last pass as a whole.
void main() {
  String tune(String body) => 'X:1\nM:4/4\nL:1/4\nK:C\n$body\n';

  /// The bars in the order playback plays them (whole-bar notes).
  List<int> playOrder(Score s) => [
        for (final n in playbackTimeline(s)) n.measureIndex,
      ];

  Measure bar(String id, {int? volta, List<int> numbers = const []}) =>
      Measure([
        NoteElement(
          id: id,
          pitches: const [Pitch(Step.c, octave: 4)],
          duration: const NoteDuration(DurationBase.whole),
        ),
      ], volta: volta, voltaNumbers: numbers);

  group('read', () {
    test('[1,2 and [3 name every pass', () {
      final s = scoreFromAbc(tune('|:C4|[1,2D4:|[3E4|F4|]'));
      expect(s.measures[1].voltaPasses, [1, 2]);
      expect(s.measures[1].voltaLabel, '1., 2.');
      expect(s.measures[2].voltaPasses, [3]);
      expect(playOrder(s), [0, 1, 0, 1, 0, 2, 3]);
    });

    test('[1-3 is a range, and :|4 a bar-attached ending', () {
      final s = scoreFromAbc(tune('|:C4|[1-3D4:|4E4|]'));
      expect(s.measures[1].voltaPasses, [1, 2, 3]);
      expect(s.measures[2].voltaPasses, [4]);
    });

    test('a first ending runs on to the :| that closes it', () {
      final s = scoreFromAbc(tune('|:C4|1D4|E4:|2F4|G4|]'));
      expect(s.measures.map((m) => m.volta), [null, 1, 1, 2, null]);
      // One bracket over both bars, hooked at its `:|`.
      expect(s.measures[1].voltaContinuesInto(s.measures[2]), isTrue);
      expect(s.measures[2].voltaOpenEnd, isFalse);
      // The last ending runs on into plain bars: left open.
      expect(s.measures[3].voltaOpenEnd, isTrue);
      expect(playOrder(s), [0, 1, 2, 0, 3, 4]);
    });

    test('a last ending at the final bar line is closed', () {
      final s = scoreFromAbc(tune('|:C4|[1D4:|[2E4|]'));
      expect(s.measures[2].voltaOpenEnd, isFalse);
    });

    test('["text" endings', () {
      final s = scoreFromAbc(tune('|:C4|[1D4:|["last time"E4|F4|]'));
      expect(s.measures[2].voltaText, 'last time');
      expect(s.measures[2].voltaLabel, 'last time');
      // A label naming no pass is taken on the pass after the ones before.
      expect(s.measures[2].voltaPasses, [2]);
      expect(playOrder(s), [0, 1, 0, 2, 3]);
    });

    test('a ["text" restated on the next bar keeps its passes', () {
      final s = scoreFromAbc(tune('|:C4|[1D4:|["Fine"E4|["Fine"F4|G4|]'));
      expect(s.measures[2].voltaPasses, [2]);
      expect(s.measures[3].voltaPasses, [2]);
      expect(s.measures[2].voltaContinuesInto(s.measures[3]), isTrue);
    });
  });

  group('write', () {
    test('number lists and text labels', () {
      final abc = scoreToAbc(Score(clef: Clef.treble, measures: [
        bar('a').copyWith(startRepeat: true),
        bar('b', volta: 1, numbers: [1, 2]).copyWith(endRepeat: true),
        bar('c', volta: 3).copyWith(voltaText: 'last time'),
        bar('d'),
      ]));
      expect(abc, contains('[1,2'));
      expect(abc, contains('["last time"'));
    });

    test('a first ending closed by :| is stated once', () {
      final abc = scoreToAbc(Score(clef: Clef.treble, measures: [
        bar('a').copyWith(startRepeat: true),
        bar('b', volta: 1),
        bar('c', volta: 1).copyWith(endRepeat: true),
        bar('d', volta: 2),
        bar('e', volta: 2),
      ]));
      expect('[1'.allMatches(abc), hasLength(1));
      // A last ending over plain bars is restated on each.
      expect('[2'.allMatches(abc), hasLength(2));
    });
  });

  group('round trip', () {
    for (final (name, measures) in [
      (
        'multi-pass, multi-bar, text, open end',
        [
          bar('a').copyWith(startRepeat: true),
          bar('b', volta: 1, numbers: [1, 2]),
          bar('c', volta: 1, numbers: [1, 2]).copyWith(endRepeat: true),
          bar('d', volta: 3).copyWith(voltaText: 'Fine'),
          bar('e', volta: 3).copyWith(voltaText: 'Fine', voltaOpenEnd: true),
          bar('f'),
        ]
      ),
      (
        'a range label and a closed last ending',
        [
          bar('a').copyWith(startRepeat: true),
          bar('b', volta: 1, numbers: [1, 2, 3])
              .copyWith(voltaText: '1.-3.', endRepeat: true),
          bar('c', volta: 4).copyWith(barline: BarlineStyle.finalBar),
        ]
      ),
    ]) {
      test(name, () {
        final source = Score(clef: Clef.treble, measures: measures);
        final back = scoreFromAbc(scoreToAbc(source));
        expect(back.measures, hasLength(measures.length));
        for (var i = 0; i < measures.length; i++) {
          final m = measures[i];
          final b = back.measures[i];
          expect(b.voltaPasses, m.voltaPasses, reason: 'bar $i passes');
          expect(b.voltaLabel, m.voltaLabel, reason: 'bar $i label');
          expect(b.voltaOpenEnd, m.voltaOpenEnd, reason: 'bar $i open end');
        }
        expect(playOrder(back), playOrder(source));
      });
    }
  });
}
