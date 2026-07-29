import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// UTF-16 MusicXML. The spec permits `encoding="UTF-16"` and Finale emitted it
/// by default for years, so an entire publisher's output can arrive that way —
/// the Project Gutenberg Beethoven string quartets are UTF-16LE throughout.
///
/// Decoded byte-wise, such a document becomes NUL-interleaved mojibake that
/// matches none of the reader's "does this look like XML?" sniffs, so it used
/// to be reported as "not a MusicXML document" instead of failing loudly. This
/// is reader-only syntax — our writer always emits UTF-8 — which is exactly the
/// class of bug a round-trip test is structurally blind to.
Uint8List utf16le(String s, {bool bom = true}) {
  final out = <int>[if (bom) 0xFF, if (bom) 0xFE];
  for (final unit in s.codeUnits) {
    out.add(unit & 0xFF);
    out.add(unit >> 8);
  }
  return Uint8List.fromList(out);
}

Uint8List utf16be(String s) {
  final out = <int>[0xFE, 0xFF];
  for (final unit in s.codeUnits) {
    out.add(unit >> 8);
    out.add(unit & 0xFF);
  }
  return Uint8List.fromList(out);
}

void main() {
  final source = Score.simple(
    keySignature: const KeySignature(-1),
    timeSignature: TimeSignature.threeFour,
    notes: 'c4:q d4 e4 | f4:h. | g4:q a4 b4',
  );
  final xml = scoreToMusicXml(source);

  List<String> pitches(Score s) => s.measures
      .expand((m) => m.elements)
      .whereType<NoteElement>()
      .expand((n) => n.pitches)
      .map((p) => p.toString())
      .toList();

  test('bare UTF-16LE MusicXML under a .mxl extension reads', () {
    final back = scoreFromMusicXml(readMusicXmlFromMxl(utf16le(xml)));
    expect(pitches(back), pitches(source));
    expect(back.timeSignature, source.timeSignature);
    expect(back.keySignature, source.keySignature);
  });

  test('bare UTF-16BE MusicXML reads too', () {
    final back = scoreFromMusicXml(readMusicXmlFromMxl(utf16be(xml)));
    expect(pitches(back), pitches(source));
  });

  test('a real .mxl whose score entry is UTF-16 reads', () {
    final archive = zipArchive([
      (
        'META-INF/container.xml',
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<container><rootfiles>'
          '<rootfile full-path="score.xml"/>'
          '</rootfiles></container>',
        )
      ),
      ('score.xml', utf16le(xml)),
    ]);
    final back = scoreFromMusicXml(readMusicXmlFromMxl(archive));
    expect(pitches(back), pitches(source));
  });

  test('non-ASCII survives the UTF-16 round trip', () {
    final titled = xml.replaceFirst(
      '<score-partwise',
      '<!-- Streichquartett — Fauré, œuvre № 5 -->\n<score-partwise',
    );
    expect(readMusicXmlFromMxl(utf16le(titled)), contains('Fauré, œuvre № 5'));
  });

  test('UTF-8 is unaffected — no BOM, and with one', () {
    expect(
        pitches(scoreFromMusicXml(
            readMusicXmlFromMxl(Uint8List.fromList(utf8.encode(xml))))),
        pitches(source));
    final withBom = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(xml)]);
    expect(pitches(scoreFromMusicXml(readMusicXmlFromMxl(withBom))),
        pitches(source));
  });

  test('a two-byte non-BOM payload is still rejected, not decoded', () {
    // 0xFF 0xFE is the ONLY thing that makes this UTF-16; arbitrary binary
    // must keep failing loudly rather than being mistaken for a score.
    expect(
        () => readMusicXmlFromMxl(Uint8List.fromList([0x1F, 0x8B, 0x08, 0x00])),
        throwsA(isA<FormatException>()));
  });

  test('a BOM with no document after it does not crash', () {
    expect(() => readMusicXmlFromMxl(Uint8List.fromList([0xFF, 0xFE])),
        throwsA(isA<FormatException>()));
  });
}
