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
}
