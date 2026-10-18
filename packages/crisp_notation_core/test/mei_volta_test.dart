import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Full ending data through MEI: `<ending n="1-3" label="…" lendsym="none">`.
///
/// `@n` names the passes (real files write "1", "2" and "1-3"), `@label` the
/// printed label, and `@lendsym="none"` an ending left open. One `<ending>`
/// wraps every bar of the ending — written bar by bar, a two-bar first ending
/// read as two brackets.
void main() {
  String mei(String section) => '''<?xml version="1.0" encoding="UTF-8"?>
<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="5.0">
<music><body><mdiv><score>
<scoreDef keysig="0" meter.count="4" meter.unit="4">
<staffGrp><staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp>
</scoreDef>
<section>$section</section>
</score></mdiv></body></music></mei>''';

  String bar(int n, String step, {String attrs = ''}) =>
      '<measure n="$n"$attrs><staff n="1"><layer n="1">'
      '<note pname="$step" oct="4" dur="1"/></layer></staff></measure>';

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
    test('@n ranges, @label text and @lendsym', () {
      final s = scoreFromMei(mei('${bar(1, 'c', attrs: ' left="rptstart"')}'
          '<ending n="1-3">${bar(2, 'd')}'
          '${bar(3, 'e', attrs: ' right="rptend"')}</ending>'
          '<ending n="4" label="last time" lendsym="none">${bar(4, 'f')}'
          '</ending>${bar(5, 'g')}'));
      expect(s.measures[1].voltaPasses, [1, 2, 3]);
      expect(s.measures[2].voltaPasses, [1, 2, 3]);
      expect(s.measures[1].voltaLabel, '1., 2., 3.');
      expect(s.measures[1].voltaContinuesInto(s.measures[2]), isTrue);
      expect(s.measures[2].voltaOpenEnd, isFalse);
      expect(s.measures[3].voltaPasses, [4]);
      expect(s.measures[3].voltaText, 'last time');
      expect(s.measures[3].voltaOpenEnd, isTrue);
      expect(playOrder(s), [0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 3, 4]);
    });

    test('a label restating the numbers is not kept as text', () {
      final s = scoreFromMei(mei('${bar(1, 'c', attrs: ' left="rptstart"')}'
          '<ending n="1" label="1.">'
          '${bar(2, 'd', attrs: ' right="rptend"')}</ending>'
          '<ending label="2.">${bar(3, 'e')}</ending>'));
      expect(s.measures[1].voltaText, isNull);
      // No @n: the label's numbers stand in.
      expect(s.measures[2].voltaPasses, [2]);
    });
  });

  group('write', () {
    test('one <ending> per ending, with its passes, label and end', () {
      final out = scoreToMei(Score(clef: Clef.treble, measures: [
        m('a').copyWith(startRepeat: true),
        m('b', volta: 1, numbers: [1, 2]),
        m('c', volta: 1, numbers: [1, 2]).copyWith(endRepeat: true),
        m('d', volta: 3).copyWith(voltaText: 'Fine', voltaOpenEnd: true),
      ]));
      expect('<ending '.allMatches(out), hasLength(2));
      expect(out, contains('<ending n="1-2" label="1., 2.">'));
      expect(out, contains('<ending n="3" label="Fine" lendsym="none">'));
    });
  });

  group('round trip', () {
    final source = Score(clef: Clef.treble, measures: [
      m('a').copyWith(startRepeat: true),
      m('b', volta: 1, numbers: [1, 3]),
      m('c', volta: 1, numbers: [1, 3]).copyWith(endRepeat: true),
      m('d', volta: 2).copyWith(endRepeat: true, voltaOpenEnd: true),
      m('e', volta: 4).copyWith(voltaText: 'last time', voltaOpenEnd: true),
      m('f'),
    ]);

    for (final (name, hop) in [
      ('single staff', (Score s) => scoreFromMei(scoreToMei(s))),
      (
        'multi-part',
        (Score s) =>
            multiPartScoreFromMei(multiPartToMei(MultiPartScore([s, s])))
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
