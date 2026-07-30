// A meter the model cannot hold must not cost the whole score.
//
// ⚠️ The example CHANGED, and the change is good news. This file was written
// when `TimeSignature` capped `beatUnit` at 16, which made `3/32` — legal
// notation, present in the corpus — unrepresentable. The cap is now
// `maxBeatUnit` (1024), so `3/32` reads as itself and the old case no longer
// tests anything: the assertion "the meter is dropped" became false because the
// model got better, not because the reader broke.
//
// So the case is restated with a meter that is still out of range, keeping the
// property the file exists for — an unrepresentable meter costs the meter, never
// the notes — and `3/32` is now asserted to WORK, which is what it should have
// done all along.
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
    // Past `maxBeatUnit`, so genuinely unholdable rather than merely unusual.
    final s = scoreFromMusicXml(
        _score('<time><beats>3</beats><beat-type>2048</beat-type></time>'));
    expect(s.timeSignature, isNull, reason: 'meter is dropped…');
    expect(
      s.measures.expand((m) => m.elements).whereType<NoteElement>().length,
      2,
      reason: '…but the music survives',
    );
  });

  test('3/32 is representable NOW, and reads as itself', () {
    // The case this file used to treat as impossible.
    final s = scoreFromMusicXml(
        _score('<time><beats>3</beats><beat-type>32</beat-type></time>'));
    expect(s.timeSignature?.beats, 3);
    expect(s.timeSignature?.beatUnit, 32);
    expect(
      s.measures.expand((m) => m.elements).whereType<NoteElement>().length,
      2,
    );
  });

  test('a representable meter is unaffected', () {
    final s = scoreFromMusicXml(
        _score('<time><beats>3</beats><beat-type>4</beat-type></time>'));
    expect(s.timeSignature?.beats, 3);
    expect(s.timeSignature?.beatUnit, 4);
  });
}
