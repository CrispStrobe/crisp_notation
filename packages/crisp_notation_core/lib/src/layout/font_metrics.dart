/// Reads text-measuring metrics straight out of a font file's binary tables —
/// no `dart:ui`/Skia, so it runs on the server and in the CLI, not only in a
/// Flutter view. Both TrueType (`glyf` outlines) and OpenType/CFF (`OTTO`)
/// files share the same `sfnt` wrapper (table directory, `head`, `hhea`,
/// `hmtx`, `cmap`, `name`), so one reader covers both; the outline tables
/// themselves (`glyf`/`CFF `) are never touched, since only advance widths are
/// needed.
library;

import 'dart:convert';
import 'dart:typed_data';

/// A font's advance-width metrics and family name, read once from its bytes.
///
/// Kerning (the `kern` table or GPOS pair adjustments) is **not** applied —
/// [widthOf] is a plain sum of glyph advances. For running text this is
/// usually within a percent or two of the kerned width; it can be visibly
/// wrong only for strings that lean on specific kerning pairs (e.g. a short
/// all-caps "AV" title), which this reader has no use for lyrics/annotations.
class FontMetrics {
  /// The em size in font design units (`head.unitsPerEm`); advances are in
  /// these units until [widthOf] scales them to the caller's `size`.
  final int unitsPerEm;

  /// The font's family name (`name` table, nameID 1), or null if the table
  /// has neither a Windows (platform 3) nor a Macintosh (platform 1) record
  /// for it.
  final String? familyName;

  /// `hmtx` advance widths indexed by glyph id. A glyph id at or past
  /// [_advances.length] repeats the last entry — `hmtx` itself only stores
  /// widths up to `hhea.numberOfHMetrics`; every later glyph (typically
  /// fixed-width ones) shares that last width by definition of the format.
  final List<int> _advances;

  /// Unicode code point → glyph id, from `cmap` (format 4 merged with format
  /// 12, when present, so codepoints past the BMP resolve too).
  final Map<int, int> _cmap;

  FontMetrics._(this.unitsPerEm, this.familyName, this._advances, this._cmap);

  /// Parses an `sfnt` font (`.ttf`/`.otf`, or the first face of a `.ttc`) from
  /// its raw bytes: the table directory, then `head`, `hhea`, `hmtx`, `cmap`
  /// and `name`. Throws a [FormatException] if the file is not a recognized
  /// `sfnt` (TrueType `\x00\x01\x00\x00`/`true`/`typ1`, or OpenType/CFF
  /// `OTTO`) or is missing a table this reader needs.
  factory FontMetrics.parse(List<int> fontBytes) {
    final bytes =
        fontBytes is Uint8List ? fontBytes : Uint8List.fromList(fontBytes);
    final d = ByteData.sublistView(bytes);
    if (bytes.length < 12) {
      throw const FormatException('font file too short to be sfnt');
    }
    final tag = d.getUint32(0);
    const trueTypeTag = 0x00010000;
    const trueTag = 0x74727565; // 'true'
    const typ1Tag = 0x74797031; // 'typ1'
    const ottoTag = 0x4f54544f; // 'OTTO'
    if (tag != trueTypeTag &&
        tag != trueTag &&
        tag != typ1Tag &&
        tag != ottoTag) {
      throw FormatException(
          'not a TrueType/OpenType font (sfnt tag 0x${tag.toRadixString(16)})');
    }
    final numTables = d.getUint16(4);
    final tables = <String, (int, int)>{}; // tag -> (offset, length)
    for (var i = 0; i < numTables; i++) {
      final rec = 12 + 16 * i;
      final name = ascii.decode(bytes.sublist(rec, rec + 4));
      tables[name] = (d.getUint32(rec + 8), d.getUint32(rec + 12));
    }
    (int, int) need(String name) {
      final t = tables[name];
      if (t == null) {
        throw FormatException('font is missing its "$name" table');
      }
      return t;
    }

    final (headAt, _) = need('head');
    final unitsPerEm = d.getUint16(headAt + 18);

    final (hheaAt, _) = need('hhea');
    final numberOfHMetrics = d.getUint16(hheaAt + 34);

    final (hmtxAt, hmtxLen) = need('hmtx');
    final advances = <int>[];
    for (var i = 0; i < numberOfHMetrics; i++) {
      final at = hmtxAt + 4 * i;
      if (at + 2 > hmtxAt + hmtxLen) break;
      advances.add(d.getUint16(at));
    }

    final cmap = switch (tables['cmap']) {
      (final at, _) => _readCmap(d, bytes, at),
      null => <int, int>{},
    };

    final familyName = switch (tables['name']) {
      (final at, _) => _readFamilyName(d, bytes, at),
      null => null,
    };

    return FontMetrics._(unitsPerEm, familyName, advances, cmap);
  }

  /// The glyph id [codePoint] maps to via `cmap`, or 0 (`.notdef`) if it is
  /// unmapped.
  int glyphIdOf(int codePoint) => _cmap[codePoint] ?? 0;

  /// The advance width of glyph [glyphId], in font design units.
  int advanceOfGlyph(int glyphId) {
    if (_advances.isEmpty) return 0;
    return glyphId < _advances.length ? _advances[glyphId] : _advances.last;
  }

  /// The width of [text] set at em [size] (same units as the result), as the
  /// sum of each character's glyph advance — no kerning (see the class
  /// doc). A character outside the font's `cmap` measures as glyph 0's
  /// advance, same as an unmapped character actually renders.
  double widthOf(String text, double size) {
    if (unitsPerEm == 0) return 0;
    var units = 0;
    for (final rune in text.runes) {
      units += advanceOfGlyph(glyphIdOf(rune));
    }
    return units / unitsPerEm * size;
  }
}

/// A [LayoutSettings.textWidth]-shaped measurer backed by [fontBytes]
/// (TrueType or OpenType/CFF): parses the font once and returns a closure
/// over its metrics, for the renderers that have the real text font (an SVG
/// embedding it, say) but no Flutter/Skia to measure with directly. Kerning
/// is ignored — see [FontMetrics].
double Function(String text, double size) textWidthFromFont(
    List<int> fontBytes) {
  final metrics = FontMetrics.parse(fontBytes);
  return metrics.widthOf;
}

/// Merges `cmap` format 4 (the BMP) with format 12 (full Unicode, present
/// when a font carries codepoints past the BMP — Bravura's musical symbols
/// block, for one) into a single codepoint → glyph id map.
Map<int, int> _readCmap(ByteData d, Uint8List bytes, int cmapAt) {
  final out = <int, int>{};
  final numSubtables = d.getUint16(cmapAt + 2);
  int? format4At;
  int? format12At;
  for (var i = 0; i < numSubtables; i++) {
    final rec = cmapAt + 4 + 8 * i;
    final platform = d.getUint16(rec);
    final encoding = d.getUint16(rec + 2);
    final at = cmapAt + d.getUint32(rec + 4);
    if (at + 2 > bytes.length) continue;
    final format = d.getUint16(at);
    final isWindowsBmp = platform == 3 && (encoding == 1 || encoding == 0);
    final isUnicodePlatform = platform == 0;
    if (format == 4 && (isWindowsBmp || isUnicodePlatform)) {
      // Prefer a Windows BMP subtable over a bare Unicode-platform one.
      if (format4At == null || platform == 3) format4At = at;
    } else if (format == 12 &&
        (platform == 3 && encoding == 10 || isUnicodePlatform)) {
      format12At = at;
    }
  }
  if (format4At != null) _readCmapFormat4(d, format4At, out);
  if (format12At != null) _readCmapFormat12(d, format12At, out);
  return out;
}

void _readCmapFormat4(ByteData d, int at, Map<int, int> out) {
  final segX2 = d.getUint16(at + 6);
  final endsAt = at + 14;
  final startsAt = endsAt + segX2 + 2;
  final deltasAt = startsAt + segX2;
  final rangesAt = deltasAt + segX2;
  for (var s = 0; s < segX2 ~/ 2; s++) {
    final end = d.getUint16(endsAt + 2 * s);
    final start = d.getUint16(startsAt + 2 * s);
    final delta = d.getInt16(deltasAt + 2 * s);
    final rangeOffsetAt = rangesAt + 2 * s;
    final rangeOffset = d.getUint16(rangeOffsetAt);
    for (var c = start; c <= end && c != 0xffff; c++) {
      int gid;
      if (rangeOffset == 0) {
        gid = (c + delta) & 0xffff;
      } else {
        final glyphAt = rangeOffsetAt + rangeOffset + 2 * (c - start);
        gid = d.getUint16(glyphAt);
        if (gid != 0) gid = (gid + delta) & 0xffff;
      }
      if (gid != 0) out[c] = gid;
    }
  }
}

void _readCmapFormat12(ByteData d, int at, Map<int, int> out) {
  final numGroups = d.getUint32(at + 12);
  for (var g = 0; g < numGroups; g++) {
    final rec = at + 16 + 12 * g;
    final startCode = d.getUint32(rec);
    final endCode = d.getUint32(rec + 4);
    final startGlyph = d.getUint32(rec + 8);
    for (var c = startCode; c <= endCode; c++) {
      out[c] = startGlyph + (c - startCode);
    }
  }
}

/// The font's family name (`name` table, nameID 1): the Windows record
/// (platform 3, encoding 1, UTF-16BE) if present, else the Macintosh one
/// (platform 1, encoding 0, treated as Latin-1 — true Mac Roman differs only
/// above 0x7F, which a family name essentially never uses).
String? _readFamilyName(ByteData d, Uint8List bytes, int nameAt) {
  final count = d.getUint16(nameAt + 2);
  final stringAreaAt = nameAt + d.getUint16(nameAt + 4);
  String? windows;
  String? mac;
  for (var i = 0; i < count; i++) {
    final rec = nameAt + 6 + 12 * i;
    final platform = d.getUint16(rec);
    final encoding = d.getUint16(rec + 2);
    final nameId = d.getUint16(rec + 6);
    if (nameId != 1) continue;
    final length = d.getUint16(rec + 8);
    final offset = d.getUint16(rec + 10);
    final at = stringAreaAt + offset;
    if (at + length > bytes.length) continue;
    if (platform == 3 && windows == null) {
      // UTF-16BE, encoding 1 (Unicode BMP) or 10 (full Unicode) — both are
      // UTF-16BE code units for a plain-Latin family name.
      if (encoding == 1 || encoding == 10) {
        final units = <int>[];
        for (var o = 0; o + 1 < length; o += 2) {
          units.add(d.getUint16(at + o));
        }
        windows = String.fromCharCodes(units);
      }
    } else if (platform == 1 && mac == null && encoding == 0) {
      mac = latin1.decode(bytes.sublist(at, at + length));
    }
  }
  return windows ?? mac;
}
