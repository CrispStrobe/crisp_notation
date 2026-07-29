// A meter the model cannot hold must not cost the whole score.
//
// TimeSignature caps beatUnit at 16 (layout keys compound-meter beaming off
// 8/16), so `3/32` and `16/32` — legal notation, present in the corpus — used
// to throw and take every note with them.
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

String _score(String time) => '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>M</part-name></score-part></part-list>
  <part id="P1"><measure number="1">
    <attributes><divisions>1</divisions><key><fifths>0</fifths></key>
      $time<clef><sign>G</sign><line>2</line></clef></attributes>
    <note><pitch><step>C</step><octave>4</octave></pitch>
      <duration>1</duration><type>quarter</type></note>
    <note><pitch><step>D</step><octave>4</octave></pitch>
      <duration>1</duration><type>quarter</type></note>
  </measure></part>
</score-partwise>
''';

void main() {
  test('an out-of-range beat-type reads UNMETERED, keeping the notes', () {
    final s = scoreFromMusicXml(
        _score('<time><beats>3</beats><beat-type>32</beat-type></time>'));
    expect(s.timeSignature, isNull, reason: 'meter is dropped…');
    expect(
      s.measures.expand((m) => m.elements).whereType<NoteElement>().length,
      2,
      reason: '…but the music survives',
    );
  });

  test('a representable meter is unaffected', () {
    final s = scoreFromMusicXml(
        _score('<time><beats>3</beats><beat-type>4</beat-type></time>'));
    expect(s.timeSignature?.beats, 3);
    expect(s.timeSignature?.beatUnit, 4);
  });
}
