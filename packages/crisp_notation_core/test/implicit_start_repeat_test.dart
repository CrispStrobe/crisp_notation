// An end repeat with no start repeat before it — GitHub issue #1.
//
// Engraving convention leaves the opening `|:` off a piece (or a section that
// follows another repeat): a lone `:|` means "repeat from the start", or from
// the end of the previous repeated section. `playbackTimeline` used to ignore
// such a barline entirely, so the passage played once.

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

List<String> orderOf(String notes) => playbackTimeline(Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: notes,
    )).map((n) => n.elementId).toList();

void main() {
  test('a lone end repeat repeats from the first measure', () {
    // a | b :| c   →  a b a b c
    expect(orderOf('a4:w | b4:w !endrepeat | c4:w'),
        ['e0', 'e1', 'e0', 'e1', 'e2']);
  });

  test('a lone end repeat on the very first measure repeats it', () {
    expect(orderOf('a4:w !endrepeat | b4:w'), ['e0', 'e0', 'e1']);
  });

  test('a second lone end repeat repeats from just past the first', () {
    // a :| b | c :| d   →  a a b c b c d
    expect(orderOf('a4:w !endrepeat | b4:w | c4:w !endrepeat | d4:w'),
        ['e0', 'e0', 'e1', 'e2', 'e1', 'e2', 'e3']);
  });

  test('a lone end repeat after an explicit repeat starts past it', () {
    // |: a :| b :|   →  a a b b
    expect(orderOf('!repeat a4:w !endrepeat | b4:w !endrepeat'),
        ['e0', 'e0', 'e1', 'e1']);
  });

  test('voltas work under an implied start repeat', () {
    // a | [1. b :| [2. c | d  →  a b a c d
    expect(orderOf('a4:w | !volta=1 b4:w !endrepeat | !volta=2 c4:w | d4:w'),
        ['e0', 'e1', 'e0', 'e2', 'e3']);
  });

  test('after a volta repeat, a lone end repeat starts past the last ending',
      () {
    // |: a [1. b :| [2. c | d :|  →  a b a c d d
    expect(
        orderOf('!repeat a4:w | !volta=1 b4:w !endrepeat | !volta=2 c4:w | '
            'd4:w !endrepeat'),
        ['e0', 'e1', 'e0', 'e2', 'e3', 'e3']);
  });

  test('a finished volta repeat does not pick the voltas of the next one', () {
    // |: a [1. b :| [2. c | d [1. e :| [2. f
    //   → a b a c | d e d f — the second section's first ending must play on
    //   ITS first pass, not be skipped as "pass 2" of the finished repeat.
    expect(
        orderOf('!repeat a4:w | !volta=1 b4:w !endrepeat | !volta=2 c4:w | '
            'd4:w | !volta=1 e4:w !endrepeat | !volta=2 f4:w'),
        ['e0', 'e1', 'e0', 'e2', 'e3', 'e4', 'e3', 'e5']);
  });

  test('an inner explicit repeat inside an implied outer section', () {
    // a |: b :| c :|  →  the inner b repeats; the final :| repeats c alone,
    // because the closed inner repeat ended the previous section.
    expect(orderOf('a4:w | !repeat b4:w !endrepeat | c4:w !endrepeat'),
        ['e0', 'e1', 'e1', 'e2', 'e2']);
  });

  test('D.C. after a lone end repeat plays straight through on return', () {
    final score = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'a4:w !endrepeat | b4:w',
    );
    final measures = [...score.measures];
    measures[1] = measures[1].copyWith(navigation: NavigationMark.daCapo);
    final order = playbackTimeline(score.copyWith(measures: measures))
        .map((n) => n.elementId);
    expect(order, ['e0', 'e0', 'e1', 'e0', 'e1']);
  });

  test('expandRepeats: false still ignores the lone end repeat', () {
    final timeline = playbackTimeline(
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'a4:w | b4:w !endrepeat | c4:w',
      ),
      expandRepeats: false,
    );
    expect(timeline.map((n) => n.elementId), ['e0', 'e1', 'e2']);
  });

  test('the issue as filed: a MusicXML backward repeat with no forward one',
      () {
    // The reporter's shape — the opening section closes with a backward
    // repeat barline and nothing opens it.
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Music</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>1</divisions><time><beats>2</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef></attributes>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration><type>half</type></note>
    </measure>
    <measure number="2">
      <note><pitch><step>D</step><octave>5</octave></pitch><duration>2</duration><type>half</type></note>
      <barline location="right"><bar-style>light-heavy</bar-style><repeat direction="backward"/></barline>
    </measure>
    <measure number="3">
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>2</duration><type>half</type></note>
    </measure>
  </part>
</score-partwise>''';
    final score = scoreFromMusicXml(xml);
    expect(score.measures[1].endRepeat, isTrue);
    expect(score.measures.first.startRepeat, isFalse);
    expect(playbackTimeline(score).map((n) => n.measureIndex), [0, 1, 0, 1, 2]);
  });
}
