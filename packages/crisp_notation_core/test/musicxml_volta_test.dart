import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A MusicXML `<ending type="start">` covers every bar up to its `stop` (or
/// `discontinue`). Only the bar that opened it used to get the volta, so a
/// two-bar first ending drew its bracket over one bar and its second bar
/// played on BOTH passes.
void main() {
  String bar(int n, {String left = '', String right = ''}) => '''
    <measure number="$n">
      ${n == 1 ? '<attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>' : ''}
      $left
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><type>whole</type></note>
      $right
    </measure>''';

  String xml(List<String> bars) => '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>P</part-name></score-part></part-list>
  <part id="P1">
${bars.join('\n')}
  </part>
</score-partwise>''';

  const start1 =
      '<barline location="left"><ending number="1" type="start"/></barline>';
  const start2 =
      '<barline location="left"><ending number="2" type="start"/></barline>';
  const stopRepeat1 = '<barline location="right"><bar-style>light-heavy'
      '</bar-style><ending number="1" type="stop"/>'
      '<repeat direction="backward"/></barline>';

  List<int?> voltas(Score s) => [for (final m in s.measures) m.volta];

  test('a two-bar first ending marks both bars', () {
    final score = scoreFromMusicXml(xml([
      bar(1),
      bar(2, left: start1),
      bar(3, right: stopRepeat1),
      bar(4,
          left: start2,
          right: '<barline location="right">'
              '<ending number="2" type="stop"/></barline>'),
      bar(5),
    ]));
    expect(voltas(score), [null, 1, 1, 2, null]);
    // The second bar of the first ending is skipped on the second pass.
    expect([for (final n in playbackTimeline(score)) n.measureIndex],
        [0, 1, 2, 0, 3, 4]);
  });

  test('a discontinued ending ends at its bar', () {
    final score = scoreFromMusicXml(xml([
      bar(1, left: start1, right: stopRepeat1),
      bar(2,
          left: start2,
          right: '<barline location="right">'
              '<ending number="2" type="discontinue"/></barline>'),
      bar(3),
    ]));
    expect(voltas(score), [1, 2, null]);
    // It stays open (no closing hook), and the writer says so.
    expect(
        [for (final m in score.measures) m.voltaOpenEnd], [false, true, false]);
    final out = scoreToMusicXml(score);
    expect(out, contains('<ending number="2" type="discontinue"/>'));
    expect(out, contains('<ending number="1" type="stop"/>'));
    expect(scoreFromMusicXml(out).measures[1].voltaOpenEnd, isTrue);
  });

  test('a backward repeat closes an ending whose stop is missing', () {
    final score = scoreFromMusicXml(xml([
      bar(1, left: start1),
      bar(2,
          right: '<barline location="right">'
              '<repeat direction="backward"/></barline>'),
      bar(3),
    ]));
    expect(voltas(score), [1, 1, null]);
  });

  test('a multi-bar ending round-trips with one start and one stop', () {
    final score = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: '!repeat c4:w | !volta=1 d4:w | !volta=1 !endrepeat e4:w | '
          '!volta=2 f4:w | !volta=2 g4:w | a4:w',
    );
    final out = scoreToMusicXml(score);
    expect('type="start"'.allMatches(out), hasLength(2));
    expect('type="stop"'.allMatches(out), hasLength(2));
    expect(voltas(scoreFromMusicXml(out)), [null, 1, 1, 2, 2, null]);
  });

  // `<ending number="1, 2">` lists every pass the ending is taken on; only
  // the first was kept, so the bracket said "1" and the second pass skipped
  // it. The ending's text content is its printed label.
  group('an ending taken on several passes', () {
    String xmlOf() => xml([
          bar(1,
              left: '<barline location="left"><repeat direction="forward"/>'
                  '</barline>'),
          bar(2,
              left: '<barline location="left">'
                  '<ending number="1, 2" type="start"/></barline>',
              right: '<barline location="right"><bar-style>light-heavy'
                  '</bar-style><ending number="1, 2" type="stop"/>'
                  '<repeat direction="backward"/></barline>'),
          bar(3,
              left: '<barline location="left">'
                  '<ending number="3" type="start">3. Fine</ending>'
                  '</barline>',
              right: '<barline location="right">'
                  '<ending number="3" type="stop"/></barline>'),
        ]);

    test('keeps every number and the text', () {
      final score = scoreFromMusicXml(xmlOf());
      expect(score.measures[1].volta, 1);
      expect(score.measures[1].voltaPasses, [1, 2]);
      expect(score.measures[1].voltaLabel, '1., 2.');
      expect(score.measures[2].voltaPasses, [3]);
      expect(score.measures[2].voltaLabel, '3. Fine');
    });

    test('plays on each listed pass', () {
      final score = scoreFromMusicXml(xmlOf());
      expect([for (final n in playbackTimeline(score)) n.measureIndex],
          [0, 1, 0, 1, 0, 2]);
    });

    test('round-trips through the writer', () {
      final out = scoreToMusicXml(scoreFromMusicXml(xmlOf()));
      expect(out, contains('<ending number="1, 2" type="start"/>'));
      expect(out, contains('<ending number="3" type="start">3. Fine</ending>'));
      final back = scoreFromMusicXml(out);
      expect(back.measures[1].voltaPasses, [1, 2]);
      expect(back.measures[2].voltaText, '3. Fine');
    });
  });
}
