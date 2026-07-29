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
  // Some publishers ship UNCOMPRESSED MusicXML under a `.mxl` extension, so
  // there is no ZIP to open at all. Detect it by the document itself rather
  // than trusting the extension: a real `.mxl` starts with the ZIP magic "PK".
  // Found in the wild on CPDL; without this the reader throws "not a zip file"
  // on a perfectly good score.
  if (bytes.length < 2 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
    final text = _decodeXml(bytes);
    if (text != null) return text;
  }
  final container =
      readZipEntry(bytes, (name) => name == 'META-INF/container.xml');
  if (container != null) {
    try {
      final path = parseXml(utf8.decode(container))
          .child('rootfiles')
          ?.child('rootfile')
          ?.attributes['full-path'];
      if (path != null) {
        final score = readZipEntry(bytes, (name) => name == path);
        if (score != null) return _decodeEntry(score);
      }
    } on FormatException {
      // A malformed container.xml — e.g. an unescaped apostrophe inside a
      // single-quoted `full-path` (a known MuseScore export bug on titles like
      // "Dixie's Land") makes the container itself invalid XML. The score entry
      // is usually fine, so ignore the broken pointer and fall through to it.
    }
  }
  final fallback = readZipEntry(bytes, (name) {
    if (name.startsWith('META-INF/')) return false;
    final lower = name.toLowerCase();
    return lower.endsWith('.xml') || lower.endsWith('.musicxml');
  });
  if (fallback != null) return _decodeEntry(fallback);
  throw const FormatException('no MusicXML entry found in .mxl');
}

/// Decodes [bytes] as a MusicXML document, or null if it is not one.
///
/// Honours a UTF-16 byte-order mark first, then tries UTF-8, then Latin-1
/// (a hand-edited score may declare `encoding="ISO-8859-1"`). Only accepts
/// input that actually looks like a MusicXML document, so a corrupt archive
/// still fails loudly rather than being mistaken for XML.
///
/// UTF-16 is not exotic: MusicXML permits `encoding="UTF-16"` and Finale wrote
/// it by default for years, so a whole publisher's output can arrive that way
/// (the Project Gutenberg Beethoven quartets are UTF-16LE throughout). Decoded
/// byte-wise it becomes NUL-interleaved mojibake that matches none of the
/// document sniffs below, so before this branch existed such a score was
/// silently reported as "not MusicXML" rather than failing loudly.
String? _decodeXml(Uint8List bytes) {
  final text = _decodeUtf16(bytes) ?? _decodeUtf8OrLatin1(bytes);
  final head = text.trimLeft();
  if (!head.startsWith('<?xml') &&
      !head.startsWith('<score-') &&
      !head.startsWith('<!DOCTYPE')) {
    return null;
  }
  return text;
}

/// Decodes [bytes] as UTF-16 when they carry a byte-order mark, else null.
///
/// The BOM is the only reliable signal — the `encoding=` pseudo-attribute is
/// itself inside the document we are trying to decode. Surrogate pairs survive
/// because [String.fromCharCodes] takes UTF-16 code units.
String? _decodeUtf16(Uint8List bytes) {
  if (bytes.length < 2) return null;
  final bigEndian = bytes[0] == 0xFE && bytes[1] == 0xFF;
  if (!bigEndian && !(bytes[0] == 0xFF && bytes[1] == 0xFE)) return null;
  final units = <int>[];
  for (var i = 2; i + 1 < bytes.length; i += 2) {
    units.add(bigEndian
        ? (bytes[i] << 8) | bytes[i + 1]
        : (bytes[i + 1] << 8) | bytes[i]);
  }
  return String.fromCharCodes(units);
}

/// Decodes a ZIP entry already known to be the score, so unlike [_decodeXml]
/// it never returns null — a `.mxl` whose entry is UTF-16 must still open.
String _decodeEntry(Uint8List bytes) =>
    _decodeUtf16(bytes) ?? _decodeUtf8OrLatin1(bytes);

String _decodeUtf8OrLatin1(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return String.fromCharCodes(bytes);
  }
}

/// Packs a MusicXML document [musicXml] into a `.mxl` archive: a
/// `META-INF/container.xml` pointing at a deflated `score.xml`.
Uint8List writeMusicXmlToMxl(String musicXml) => zipArchive([
      ('META-INF/container.xml', utf8.encode(_containerXml)),
      ('score.xml', utf8.encode(musicXml)),
    ]);
