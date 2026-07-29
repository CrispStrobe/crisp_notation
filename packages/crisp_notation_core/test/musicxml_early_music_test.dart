// Early-music MusicXML handling: unmetered scores and uncompressed `.mxl`.
//
// Both cases came out of a 3,791-score CPDL sweep, where 37 of the 78
// unreadable files failed on exactly these two things.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

String _senzaMisuraScore() => '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>Cantus</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
        <key><fifths>0</fifths></key>
        <time><senza-misura/></time>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      <note><pitch><step>C</step><octave>4</octave></pitch>
        <duration>4</duration><type>whole</type></note>
      <note><pitch><step>D</step><octave>4</octave></pitch>
        <duration>4</duration><type>whole</type></note>
    </measure>
  </part>
</score-partwise>
''';

String _meteredScore() => _senzaMisuraScore().replaceFirst(
      '<time><senza-misura/></time>',
      '<time><beats>3</beats><beat-type>4</beat-type></time>',
    );

void main() {
  group('senza misura', () {
    test('an unmetered score reads with a null time signature, not a throw',
        () {
      // Renaissance polyphony is routinely transcribed without barlines and
      // encoded as <time><senza-misura/></time>. Throwing rejected Byrd,
      // Gibbons, Palestrina and Padilla wholesale.
      final score = scoreFromMusicXml(_senzaMisuraScore());
      expect(score.timeSignature, isNull);
    });

    test('the notes survive — the meter is dropped, not the music', () {
      final mp = multiPartScoreFromMusicXml(_senzaMisuraScore());
      final notes = mp.parts
          .expand((p) => p.measures)
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .length;
      expect(notes, 2);
    });

    test('a metered score is unaffected', () {
      final score = scoreFromMusicXml(_meteredScore());
      expect(score.timeSignature?.beats, 3);
      expect(score.timeSignature?.beatUnit, 4);
    });
  });

  group('uncompressed .mxl', () {
    test('plain MusicXML carrying a .mxl extension is read, not rejected', () {
      // Publishers ship these in the wild; the extension lies but the document
      // is perfectly good.
      final raw = Uint8List.fromList(utf8.encode(_meteredScore()));
      final xml = readMusicXmlFromMxl(raw);
      expect(xml, contains('score-partwise'));
      expect(scoreFromMusicXml(xml).timeSignature?.beats, 3);
    });

    test('a real zipped .mxl still round-trips', () {
      final zipped = writeMusicXmlToMxl(_meteredScore());
      expect(zipped[0], 0x50); // "PK" — still a ZIP
      expect(readMusicXmlFromMxl(zipped), contains('score-partwise'));
    });

    test('genuine garbage still throws rather than being read as XML', () {
      final junk = Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x04]);
      expect(() => readMusicXmlFromMxl(junk), throwsFormatException);
    });
  });
}
