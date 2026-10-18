import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Endings through Humdrum `**kern`: section labels and the expansion list.
///
/// ⚠️ Humdrum has no ending token. An ending is a SECTION whose label ends in
/// a number (`*>B1`, `*>B2`, as the NIFC corpus writes them), and a section
/// runs until the next label — so an ending covers every bar up to it, not
/// just the first. The passes it is taken on come from the expansion list
/// (`*>[A,B,B1,B,B2,C]`): each time the list plays the ending, the count of
/// times its section `B` has been played so far. Humdrum states no label
/// text and no open end; ends follow the engraving rule (hooked only at a
/// repeat sign or the final barline).
void main() {
  List<int> playOrder(Score s) => [
        for (final n in playbackTimeline(s)) n.measureIndex,
      ];

  Measure m(String id, {int? volta, List<int> numbers = const []}) => Measure([
        NoteElement(
          id: id,
          pitches: const [Pitch(Step.c, octave: 4)],
          duration: const NoteDuration(DurationBase.whole),
        ),
      ], volta: volta, voltaNumbers: numbers);

  group('read', () {
    test('section labels span to the next label; passes from the list', () {
      final s = scoreFromKern('''**kern
*M4/4
*>[A,B,B1,B,B1,B,B2,C]
*>A
=1
1c
=2!|:
*>B
1d
=3
*>B1
1e
=4
1f
=5:|!
*>B2
1g
=6
*>C
1a
==
*-
''');
      // B2 is taken on the third pass, so it is the "3." ending.
      expect(s.measures.map((x) => x.volta), [null, null, 1, 1, 3, null]);
      expect(s.measures[2].voltaPasses, [1, 2]);
      expect(s.measures[3].voltaPasses, [1, 2]);
      expect(s.measures[2].voltaContinuesInto(s.measures[3]), isTrue);
      expect(s.measures[3].voltaOpenEnd, isFalse);
      expect(s.measures[4].voltaPasses, [3]);
      expect(s.measures[4].voltaOpenEnd, isTrue);
      expect(playOrder(s), [0, 1, 2, 3, 1, 2, 3, 1, 4, 5]);
    });

    // Shapes from the NIFC corpus: a da capo replaying `A,A1,A,A2` adds no
    // passes, and two endings played straight through keep their numbers.
    for (final (list, passes) in [
      ('[A,A1,A,A2,B,A,A1,A,A2]', [1, 2]),
      ('[A,A1,A2,B]', [1, 2]),
    ]) {
      test('expansion $list', () {
        final s = scoreFromKern('''**kern
*M4/4
*>$list
=1!|:
*>A
1c
=2
*>A1
1d
=3:|!
*>A2
1e
=4
*>B
1f
==
*-
''');
        expect([
          s.measures[1].voltaPasses,
          s.measures[2].voltaPasses
        ], [
          for (final p in passes) [p]
        ]);
      });
    }

    test('without an expansion list the number is the pass', () {
      final s = scoreFromKern('''**kern
*M4/4
=1!|:
*>A
1c
=2
*>A1
1d
=3:|!
*>A2
1e
==
*-
''');
      expect(s.measures.map((x) => x.volta), [null, 1, 2]);
      // The last ending stops at the final barline: closed.
      expect(s.measures[2].voltaOpenEnd, isFalse);
    });
  });

  group('write', () {
    test('sections, ending labels and the expansion list', () {
      final kern = scoreToKern(Score(clef: Clef.treble, measures: [
        m('a'),
        m('b').copyWith(startRepeat: true),
        m('c', volta: 1, numbers: [1, 2]),
        m('d', volta: 1, numbers: [1, 2]).copyWith(endRepeat: true),
        m('e', volta: 3),
        m('f'),
      ]));
      expect(kern, contains('*>[A,B,B1,B,B1,B,B3,C]'));
      for (final label in ['*>A', '*>B', '*>B1', '*>B3', '*>C']) {
        expect(kern.split('\n'), contains(label));
      }
      // Stated once at the ending's start, not on every bar.
      expect('*>B1\n'.allMatches(kern), hasLength(1));
    });
  });

  group('round trip', () {
    final source = Score(clef: Clef.treble, measures: [
      m('a').copyWith(startRepeat: true),
      m('b', volta: 1, numbers: [1, 3]),
      m('c', volta: 1, numbers: [1, 3]).copyWith(endRepeat: true),
      m('d', volta: 2).copyWith(endRepeat: true),
      m('e', volta: 4).copyWith(voltaOpenEnd: true),
      m('f'),
    ]);

    for (final (name, hop) in [
      ('single spine', (Score s) => scoreFromKern(scoreToKern(s))),
      (
        'with a lyric spine',
        (Score s) => scoreFromKern(scoreToKern(Score(
            clef: s.clef,
            measures: s.measures,
            lyrics: const [Lyric('a', 'la')]))),
      ),
      (
        'multi-part',
        (Score s) =>
            multiPartScoreFromKern(multiPartToKern(MultiPartScore([s, s])))
                .parts
                .first,
      ),
    ]) {
      test(name, () {
        final back = hop(source);
        expect(back.measures, hasLength(source.measures.length));
        for (var i = 0; i < source.measures.length; i++) {
          final a = source.measures[i];
          final b = back.measures[i];
          expect(b.voltaPasses, a.voltaPasses, reason: 'bar $i passes');
          expect(b.voltaLabel, a.voltaLabel, reason: 'bar $i label');
          expect(b.voltaOpenEnd, a.voltaOpenEnd, reason: 'bar $i open end');
        }
        expect(playOrder(back), playOrder(source));
      });
    }
  });
}
