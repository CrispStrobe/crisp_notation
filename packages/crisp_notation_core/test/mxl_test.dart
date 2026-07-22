import 'dart:convert';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// `.mxl` (compressed MusicXML) — a ZIP wrapping the MusicXML the existing
/// codec already round-trips, so a Score → `.mxl` → Score keeps the shared
/// data, the archive is a real (deflated) ZIP, and the reader follows the
/// `META-INF/container.xml` rootfile the way other tools write it.
List<String> pitches(Score s) => s.measures
    .expand((m) => m.elements)
    .whereType<NoteElement>()
    .expand((n) => n.pitches)
    .map((p) => p.toString())
    .toList();

void main() {
  final source = Score.simple(
    keySignature: const KeySignature(-1),
    timeSignature: TimeSignature.threeFour,
    notes: 'c4:q d4 e4 | f4:h. | g4:q a4 b4',
  );

  test('Score → .mxl → Score preserves pitches and rhythm', () {
    final mxl = writeMusicXmlToMxl(scoreToMusicXml(source));
    final back = scoreFromMusicXml(readMusicXmlFromMxl(mxl));
    expect(pitches(back), pitches(source));
    expect(back.timeSignature, source.timeSignature);
    expect(back.keySignature, source.keySignature);
  });

  test('writes a real ZIP (PK header) that reads back to the same MusicXML',
      () {
    final mxl = writeMusicXmlToMxl(scoreToMusicXml(source));
    expect(mxl.sublist(0, 2), [0x50, 0x4B]); // "PK"
    expect(readMusicXmlFromMxl(mxl), scoreToMusicXml(source));
  });

  test('follows the container.xml rootfile to an oddly-named entry', () {
    // A hand-built .mxl whose score entry is not "score.xml".
    final musicXml = scoreToMusicXml(source);
    final mxl = zipArchive([
      (
        'META-INF/container.xml',
        utf8.encode('<container><rootfiles>'
            '<rootfile full-path="parts/flute.musicxml"/>'
            '</rootfiles></container>')
      ),
      ('parts/flute.musicxml', utf8.encode(musicXml)),
    ]);
    expect(readMusicXmlFromMxl(mxl), musicXml);
  });

  test('falls back to the first non-META-INF xml when no container', () {
    final musicXml = scoreToMusicXml(source);
    final mxl = zipArchive([('anything.xml', utf8.encode(musicXml))]);
    expect(readMusicXmlFromMxl(mxl), musicXml);
  });

  test('throws when there is no MusicXML entry', () {
    final mxl = zipArchive([('readme.txt', utf8.encode('not a score'))]);
    expect(() => readMusicXmlFromMxl(mxl), throwsFormatException);
  });

  test('falls back past a malformed container.xml to the score entry', () {
    // A real MuseScore export bug: an apostrophe in the title makes the
    // single-quoted `full-path` invalid XML ("Dixie's Land"). The container is
    // unparseable but the score entry is fine — read it anyway.
    final score = scoreToMusicXml(source);
    final mxl = zipArchive([
      (
        'META-INF/container.xml',
        utf8.encode("<?xml version='1.0'?><container><rootfiles>"
            "<rootfile full-path='Dixie's Land.xml'/>"
            '</rootfiles></container>')
      ),
      ("Dixie's Land.xml", utf8.encode(score)),
    ]);
    expect(readMusicXmlFromMxl(mxl), contains('<score-partwise'));
    expect(() => scoreFromMusicXml(readMusicXmlFromMxl(mxl)), returnsNormally);
  });

  test('the shared ZIP round-trips arbitrary entries', () {
    final zip = zipArchive([
      ('a.txt', utf8.encode('alpha' * 100)),
      ('dir/b.bin', List<int>.generate(500, (i) => i & 0xff)),
    ]);
    expect(utf8.decode(readZipEntry(zip, (n) => n == 'a.txt')!), 'alpha' * 100);
    expect(readZipEntry(zip, (n) => n == 'dir/b.bin'),
        List<int>.generate(500, (i) => i & 0xff));
    expect(readZipEntry(zip, (n) => n == 'missing'), isNull);
  });

  test('the extracted entry is a parseable score-partwise document', () {
    final xml =
        readMusicXmlFromMxl(writeMusicXmlToMxl(scoreToMusicXml(source)));
    expect(xml, contains('<score-partwise'));
    expect(() => scoreFromMusicXml(xml), returnsNormally);
  });
}
