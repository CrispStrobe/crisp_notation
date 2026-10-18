import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Full ending data through LilyPond: the passes an ending is taken on, its
/// printed label, and whether its bracket ends open.
///
/// ⚠️ LilyPond states passes two ways. `\repeat volta N` with fewer
/// alternatives than passes takes the FIRST alternative for the spare ones
/// (`\repeat volta 3` with two alternatives prints "1., 2." and "3."), and
/// `\set Score.repeatCommands` gives only a printed label, from which the
/// passes are read back. It states no open end: it draws the closing hook
/// only at a repeat sign or the final barline.
void main() {
  /// The bars in the order playback plays them (one whole note per bar).
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
    test(r'\repeat volta 3 with two alternatives: "1., 2." then "3."', () {
      final s = scoreFromLilyPond(
          r"{ \repeat volta 3 { c'1 } \alternative { { d'1 } { e'1 } } f'1 }");
      expect(s.measures[1].voltaPasses, [1, 2]);
      expect(s.measures[1].voltaLabel, '1., 2.');
      expect(s.measures[2].voltaPasses, [3]);
      // The first ending stops at its `:|` (hooked); the last runs on, open.
      expect(s.measures[1].voltaOpenEnd, isFalse);
      expect(s.measures[2].voltaOpenEnd, isTrue);
      expect(playOrder(s), [0, 1, 0, 1, 0, 2, 3]);
    });

    test(r'\repeat volta 4 with two alternatives: "1.-3." passes', () {
      final s = scoreFromLilyPond(
          r"{ \repeat volta 4 { c'1 } \alternative { { d'1 } { e'1 } } }");
      expect(s.measures[1].voltaPasses, [1, 2, 3]);
      expect(s.measures[2].voltaPasses, [4]);
      expect(playOrder(s), [0, 1, 0, 1, 0, 1, 0, 2]);
    });

    test(r'\volta 1,2 states an alternative' "'s passes", () {
      final s = scoreFromLilyPond(r"{ \repeat volta 3 { c'1 } "
          r"\alternative { \volta 1,2 { d'1 } \volta 3 { e'1 } } }");
      expect(s.measures[1].voltaPasses, [1, 2]);
      expect(s.measures[2].voltaPasses, [3]);
    });

    test('a last alternative ending at the final barline is closed', () {
      final s = scoreFromLilyPond(r"{ \repeat volta 2 { c'1 } "
          r"""\alternative { { d'1 } { e'1 \bar "|." } } }""");
      expect(s.measures[2].voltaOpenEnd, isFalse);
    });

    test('repeatCommands: multi-pass label, span, text and #f', () {
      final s = scoreFromLilyPond(r"""{
  \bar ".|:" c'1
  \set Score.repeatCommands = #'((volta "1.2.3.")) d'1 e'1 \bar ":|."
  \set Score.repeatCommands = #'((volta #f) (volta "Fine")) f'1
  \set Score.repeatCommands = #'((volta #f)) g'1
}""");
      expect(s.measures.map((m) => m.volta), [null, 1, 1, 4, null]);
      // The bracket covers every bar until `#f`, not just the first.
      expect(s.measures[1].voltaPasses, [1, 2, 3]);
      expect(s.measures[2].voltaPasses, [1, 2, 3]);
      expect(s.measures[1].voltaText, isNull);
      // A label naming no pass is taken on the pass after the ones before.
      expect(s.measures[3].voltaText, 'Fine');
      expect(s.measures[3].voltaPasses, [4]);
      expect(s.measures[3].voltaOpenEnd, isTrue);
      expect(s.measures[2].voltaOpenEnd, isFalse);
      expect(playOrder(s), [0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 3, 4]);
    });

    test('repeatCommands end-repeat closes the bar before', () {
      final s = scoreFromLilyPond(r"""{
  \bar ".|:" c'1
  \set Score.repeatCommands = #'((volta "1.2.3.")) d'1
  \set Score.repeatCommands = #'((volta #f)end-repeat(volta "4.")) e'1
  \set Score.repeatCommands = #'((volta #f)) \bar "|."
}""");
      expect(s.measures[1].endRepeat, isTrue);
      expect(s.measures[2].voltaPasses, [4]);
      expect(playOrder(s), [0, 1, 0, 1, 0, 1, 0, 2]);
    });

    // The shape of Schubert's "Trost in Thränen" (Mutopia): the ending opens
    // after a full bar no note has closed, on a mid-piece `\partial`, and
    // closes before a final barline written after the `#f`.
    test(r'a directive after a full bar belongs to the next one', () {
      final s = scoreFromLilyPond(r"""{ \time 3/4
  c'2.
  \set Score.repeatCommands = #'((volta "1.2.3."))
  \partial 4 r4
  \set Score.repeatCommands = #'((volta #f)end-repeat(volta "4."))
  d'2.
  \set Score.repeatCommands = #'((volta #f))
  \bar "|."
}""");
      expect(s.measures.map((m) => m.volta), [null, 1, 4]);
      expect(s.measures[1].voltaPasses, [1, 2, 3]);
      expect(s.measures[1].endRepeat, isTrue);
      expect(s.measures[2].barline, BarlineStyle.finalBar);
      expect(s.measures[2].voltaOpenEnd, isFalse);
    });

    test('an edge-height override states the end', () {
      final s = scoreFromLilyPond(r"""{
  \bar ".|:" c'1
  \once \override Score.VoltaBracket.edge-height = #'(2 . 0)
  \set Score.repeatCommands = #'((volta "1.")) d'1 \bar ":|."
  \once \override Score.VoltaBracket.edge-height = #'(2 . 2)
  \set Score.repeatCommands = #'((volta #f) (volta "2.")) e'1
  \set Score.repeatCommands = #'((volta #f)) f'1
}""");
      expect(s.measures[1].voltaOpenEnd, isTrue);
      expect(s.measures[2].voltaOpenEnd, isFalse);
    });
  });

  group('write', () {
    test('labels name every pass, or carry the text', () {
      final ly = scoreToLilyPond(Score(clef: Clef.treble, measures: [
        bar('a').copyWith(startRepeat: true),
        bar('b', volta: 1, numbers: [1, 2]).copyWith(endRepeat: true),
        bar('c', volta: 3).copyWith(voltaText: 'last time', voltaOpenEnd: true),
        bar('d'),
      ]));
      expect(ly, contains(r'''#'((volta "1., 2."))'''));
      expect(ly, contains(r'''#'((volta #f) (volta "last time"))'''));
      // LilyPond leaves this one open on its own: no override needed.
      expect(ly, isNot(contains('edge-height')));
    });

    test('an end LilyPond would not draw is stated', () {
      final ly = scoreToLilyPond(Score(clef: Clef.treble, measures: [
        bar('a').copyWith(startRepeat: true),
        bar('b', volta: 1).copyWith(endRepeat: true, voltaOpenEnd: true),
        bar('c', volta: 2),
        bar('d'),
      ]));
      expect(ly, contains("edge-height = #'(2 . 0)"));
      expect(ly, contains("edge-height = #'(2 . 2)"));
    });
  });

  group('round trip', () {
    for (final (name, measures) in [
      (
        'multi-pass, text and open ends',
        [
          bar('a').copyWith(startRepeat: true),
          bar('b', volta: 1, numbers: [1, 2]),
          bar('c', volta: 1, numbers: [1, 2]).copyWith(endRepeat: true),
          bar('d', volta: 3).copyWith(voltaText: 'Fine', voltaOpenEnd: true),
          bar('e'),
        ]
      ),
      (
        'ends against LilyPond default',
        [
          bar('a').copyWith(startRepeat: true),
          bar('b', volta: 1).copyWith(endRepeat: true, voltaOpenEnd: true),
          bar('c', volta: 2).copyWith(voltaText: '2nd time'),
          bar('d'),
        ]
      ),
      (
        'a range label',
        [
          bar('a').copyWith(startRepeat: true),
          bar('b', volta: 1, numbers: [1, 2, 3])
              .copyWith(voltaText: '1.-3.', endRepeat: true),
          bar('c', volta: 4).copyWith(voltaOpenEnd: true),
        ]
      ),
    ]) {
      test(name, () {
        final source = Score(clef: Clef.treble, measures: measures);
        final back = scoreFromLilyPond(scoreToLilyPond(source));
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
