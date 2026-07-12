/// Compressed MusicXML (`.mxl`) container handling — a ZIP holding the
/// MusicXML score alongside `META-INF/container.xml` (which names the score
/// entry). `.mxl` is the interchange format every major notation editor
/// (Sibelius, Finale, Dorico, MuseScore) reads and writes, so this pairs the
/// existing MusicXML codec with a web-safe ZIP. Pure Dart.
///
/// Read: [readMusicXmlFromMxl] → the score XML, which `scoreFromMusicXml`
/// parses. Write: [writeMusicXmlToMxl] wraps a `scoreToMusicXml` string.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../musicxml/xml_reader.dart';
import 'zip.dart';

/// The container that points MusicXML readers at the score entry.
const _containerXml = '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<container><rootfiles>'
    '<rootfile full-path="score.xml" '
    'media-type="application/vnd.recordare.musicxml"/>'
    '</rootfiles></container>\n';

/// Extracts the MusicXML document from a `.mxl` archive's [bytes]. Follows the
/// `META-INF/container.xml` rootfile when present (the standard layout), else
/// falls back to the first non-`META-INF` `.xml`/`.musicxml` entry.
String readMusicXmlFromMxl(Uint8List bytes) {
  final container =
      readZipEntry(bytes, (name) => name == 'META-INF/container.xml');
  if (container != null) {
    final path = parseXml(utf8.decode(container))
        .child('rootfiles')
        ?.child('rootfile')
        ?.attributes['full-path'];
    if (path != null) {
      final score = readZipEntry(bytes, (name) => name == path);
      if (score != null) return utf8.decode(score);
    }
  }
  final fallback = readZipEntry(bytes, (name) {
    if (name.startsWith('META-INF/')) return false;
    final lower = name.toLowerCase();
    return lower.endsWith('.xml') || lower.endsWith('.musicxml');
  });
  if (fallback != null) return utf8.decode(fallback);
  throw const FormatException('no MusicXML entry found in .mxl');
}

/// Packs a MusicXML document [musicXml] into a `.mxl` archive: a
/// `META-INF/container.xml` pointing at a deflated `score.xml`.
Uint8List writeMusicXmlToMxl(String musicXml) => zipArchive([
      ('META-INF/container.xml', utf8.encode(_containerXml)),
      ('score.xml', utf8.encode(musicXml)),
    ]);
