/// Subsetting of `sfnt` fonts (TrueType `glyf` and OpenType/CFF) for PDF
/// embedding: the file keeps only the outlines of the glyphs a document
/// draws, so a PDF carries a few kilobytes of a font rather than all of it.
///
/// Glyph ids do not change — an unused glyph stays in the font as an empty
/// outline — so the content streams, `/W` widths and `/ToUnicode` maps that
/// address glyphs by id need no renumbering, and `hmtx` and `cmap` stay as
/// they are. Tables for shaping and hinting devices that a PDF viewer never
/// reads (`GSUB`, `GPOS`, `kern`, `DSIG` …) are dropped, and `post` loses its
/// glyph names.
library;

import 'dart:convert';
import 'dart:typed_data';

/// [font] reduced to the outlines of [glyphIds] (and `.notdef`, and the
/// components a composite glyph is built from), or null when the font is
/// one this does not subset — a CID-keyed or CFF2 font, or a malformed file
/// — so the caller embeds it whole.
///
/// ⚠️ The result is a font only for drawing those glyphs by id: other
/// glyphs still have their advance widths and `cmap` entries, but no
/// outline.
Uint8List? subsetFont(List<int> font, Set<int> glyphIds) {
  try {
    return _subset(Uint8List.fromList(font), glyphIds);
  } on RangeError {
    return null;
  } on FormatException {
    return null;
  }
}

/// A six-letter tag naming a subset, as the PDF specification asks a subset
/// font's name to begin with (`ABCDEF+Bravura`): the same glyphs give the
/// same tag, so a document's bytes do not change from run to run.
String subsetTag(Iterable<int> glyphIds) {
  var h = 0x811c9dc5;
  for (final g in [...glyphIds]..sort()) {
    h = ((h ^ g) * 0x01000193) & 0xffffffff;
  }
  final b = StringBuffer();
  for (var i = 0; i < 6; i++) {
    b.writeCharCode(0x41 + h % 26);
    h ~/= 26;
  }
  return b.toString();
}

/// Tables a PDF viewer does not use: shaping (the writer places each glyph
/// itself), device hinting caches and the signature (void once the file
/// changes).
const _dropped = {
  'GSUB', 'GPOS', 'GDEF', 'BASE', 'JSTF', 'MATH', 'kern', 'DSIG', 'hdmx', //
  'VDMX', 'LTSH', 'morx', 'mort', 'feat', 'PCLT',
};

Uint8List? _subset(Uint8List bytes, Set<int> glyphIds) {
  final d = ByteData.sublistView(bytes);
  final tables = <String, Uint8List>{};
  for (var i = 0; i < d.getUint16(4); i++) {
    final rec = 12 + 16 * i;
    final tag = latin1.decode(bytes.sublist(rec, rec + 4));
    final at = d.getUint32(rec + 8), length = d.getUint32(rec + 12);
    tables[tag] = Uint8List.sublistView(bytes, at, at + length);
  }
  final maxp = tables['maxp'], head = tables['head'];
  if (maxp == null || head == null || tables.containsKey('CFF2')) return null;
  final numGlyphs = ByteData.sublistView(maxp).getUint16(4);
  final keep = {
    0,
    for (final g in glyphIds)
      if (g < numGlyphs) g
  };

  final out = <String, Uint8List>{
    for (final MapEntry(:key, :value) in tables.entries)
      if (!_dropped.contains(key)) key: value,
  };
  if (tables['post'] case final post? when post.length >= 32) {
    // Version 3: no glyph names.
    out['post'] = Uint8List.fromList(post.sublist(0, 32))
      ..setRange(0, 4, const [0, 3, 0, 0]);
  }
  if (tables['CFF '] case final cff?) {
    final subset = _subsetCff(cff, keep);
    if (subset == null) return null;
    out['CFF '] = subset;
  } else if (tables['glyf'] case final glyf?) {
    final loca = tables['loca'];
    if (loca == null) return null;
    final longLoca = ByteData.sublistView(head).getInt16(50) == 1;
    final (newGlyf, newLoca) =
        _subsetGlyf(glyf, loca, longLoca, numGlyphs, keep);
    out['glyf'] = newGlyf;
    out['loca'] = newLoca;
    // The new `loca` is always the long format.
    out['head'] = Uint8List.fromList(head)..setRange(50, 52, const [0, 1]);
  } else {
    return null;
  }
  return _writeSfnt(d.getUint32(0), out);
}

// ---------------------------------------------------------------------------
// TrueType outlines.

(Uint8List, Uint8List) _subsetGlyf(Uint8List glyf, Uint8List loca,
    bool longLoca, int numGlyphs, Set<int> keep) {
  final l = ByteData.sublistView(loca);
  final g = ByteData.sublistView(glyf);
  int offset(int i) => longLoca ? l.getUint32(4 * i) : 2 * l.getUint16(2 * i);
  Uint8List data(int i) =>
      Uint8List.sublistView(glyf, offset(i), offset(i + 1));

  // A composite glyph draws its components: keep them too.
  final queue = [...keep];
  while (queue.isNotEmpty) {
    final gid = queue.removeLast();
    final start = offset(gid);
    if (offset(gid + 1) - start < 10 || g.getInt16(start) >= 0) continue;
    var at = start + 10;
    while (true) {
      final flags = g.getUint16(at);
      final component = g.getUint16(at + 2);
      if (component < numGlyphs && keep.add(component)) queue.add(component);
      at += 4 + ((flags & 0x1) != 0 ? 4 : 2);
      if ((flags & 0x8) != 0) {
        at += 2;
      } else if ((flags & 0x40) != 0) {
        at += 4;
      } else if ((flags & 0x80) != 0) {
        at += 8;
      }
      if ((flags & 0x20) == 0) break;
    }
  }

  final newGlyf = BytesBuilder(copy: false);
  final newLoca = ByteData(4 * (numGlyphs + 1));
  for (var i = 0; i < numGlyphs; i++) {
    newLoca.setUint32(4 * i, newGlyf.length);
    if (!keep.contains(i)) continue;
    final glyph = data(i);
    newGlyf.add(glyph);
    if (glyph.length % 4 != 0) newGlyf.add(Uint8List(4 - glyph.length % 4));
  }
  newLoca.setUint32(4 * numGlyphs, newGlyf.length);
  return (newGlyf.toBytes(), newLoca.buffer.asUint8List());
}

// ---------------------------------------------------------------------------
// CFF outlines.

/// An INDEX's items and the offset just past it.
(List<Uint8List>, int) _readIndex(Uint8List cff, int at) {
  final d = ByteData.sublistView(cff);
  final count = d.getUint16(at);
  if (count == 0) return (const [], at + 2);
  final offSize = cff[at + 2];
  if (offSize < 1 || offSize > 4) throw const FormatException('CFF offSize');
  int off(int i) {
    var v = 0;
    for (var k = 0; k < offSize; k++) {
      v = (v << 8) | cff[at + 3 + i * offSize + k];
    }
    return v;
  }

  final base = at + 2 + (count + 1) * offSize; // offsets count from 1
  return (
    [
      for (var i = 0; i < count; i++)
        Uint8List.sublistView(cff, base + off(i), base + off(i + 1)),
    ],
    base + off(count),
  );
}

Uint8List _writeIndex(List<List<int>> items) {
  if (items.isEmpty) return Uint8List(2);
  final total = items.fold<int>(1, (s, i) => s + i.length);
  final offSize = total < 0x100
      ? 1
      : total < 0x10000
          ? 2
          : total < 0x1000000
              ? 3
              : 4;
  final b = BytesBuilder(copy: false)
    ..add([items.length >> 8, items.length & 0xff, offSize]);
  void off(int v) {
    for (var k = offSize - 1; k >= 0; k--) {
      b.addByte((v >> (8 * k)) & 0xff);
    }
  }

  var o = 1;
  off(o);
  for (final item in items) {
    o += item.length;
    off(o);
  }
  for (final item in items) {
    b.add(item);
  }
  return b.toBytes();
}

/// One DICT entry: its operator (`12 x` as `1200 + x`), its operands'
/// bytes as written, and their values where they are integers.
class _DictEntry {
  final int op;
  final List<int> raw;
  final List<num> values;
  _DictEntry(this.op, this.raw, this.values);
}

List<_DictEntry> _readDict(Uint8List dict) {
  final out = <_DictEntry>[];
  var raw = <int>[];
  var values = <num>[];
  var i = 0;
  while (i < dict.length) {
    final b0 = dict[i];
    if (b0 <= 21) {
      final op = b0 == 12 ? 1200 + dict[i + 1] : b0;
      i += b0 == 12 ? 2 : 1;
      out.add(_DictEntry(op, raw, values));
      raw = [];
      values = [];
      continue;
    }
    final start = i;
    if (b0 == 28) {
      values.add(ByteData.sublistView(dict, i + 1, i + 3).getInt16(0));
      i += 3;
    } else if (b0 == 29) {
      values.add(ByteData.sublistView(dict, i + 1, i + 5).getInt32(0));
      i += 5;
    } else if (b0 == 30) {
      // A real: nibbles up to an 0xf one.
      i++;
      while ((dict[i] & 0xf) != 0xf && (dict[i] >> 4) != 0xf) {
        i++;
      }
      i++;
      values.add(0);
    } else if (b0 >= 32 && b0 <= 246) {
      values.add(b0 - 139);
      i++;
    } else if (b0 >= 247 && b0 <= 250) {
      values.add((b0 - 247) * 256 + dict[i + 1] + 108);
      i += 2;
    } else if (b0 >= 251 && b0 <= 254) {
      values.add(-(b0 - 251) * 256 - dict[i + 1] - 108);
      i += 2;
    } else {
      throw const FormatException('CFF DICT operand');
    }
    raw.addAll(dict.sublist(start, i));
  }
  return out;
}

/// [entries] written back, the operands of the operators in [offsets]
/// replaced by those values as fixed five-byte integers (so the DICT's
/// length does not depend on them).
Uint8List _writeDict(List<_DictEntry> entries, Map<int, List<int>> offsets) {
  final b = BytesBuilder(copy: false);
  for (final e in entries) {
    if (offsets[e.op] case final values?) {
      for (final v in values) {
        b.add([
          29,
          (v >> 24) & 0xff,
          (v >> 16) & 0xff,
          (v >> 8) & 0xff,
          v & 0xff
        ]);
      }
    } else {
      b.add(e.raw);
    }
    b.add(e.op >= 1200 ? [12, e.op - 1200] : [e.op]);
  }
  return b.toBytes();
}

const _charsetOp = 15, _encodingOp = 16, _charStringsOp = 17;
const _privateOp = 18, _subrsOp = 19;

/// The CFF table with every glyph outside [keep] reduced to `endchar`;
/// null for a CID-keyed font (FDArray/FDSelect), which this does not
/// rewrite.
Uint8List? _subsetCff(Uint8List cff, Set<int> keep) {
  final hdrSize = cff[2];
  final header = Uint8List.sublistView(cff, 0, hdrSize);
  final (names, afterNames) = _readIndex(cff, hdrSize);
  final (topDicts, afterTop) = _readIndex(cff, afterNames);
  final (_, afterStrings) = _readIndex(cff, afterTop);
  final (globalSubrs, _) = _readIndex(cff, afterStrings);
  if (names.length != 1 || topDicts.length != 1) return null;
  final nameIndex = Uint8List.sublistView(cff, hdrSize, afterNames);
  final strings = Uint8List.sublistView(cff, afterTop, afterStrings);

  final top = _readDict(topDicts.single);
  int? operand(int op, [int i = 0]) {
    for (final e in top) {
      if (e.op == op && e.values.length > i) return e.values[i].toInt();
    }
    return null;
  }

  // ROS, FDArray or FDSelect: CID-keyed.
  if (top.any((e) => e.op == 1230 || e.op == 1236 || e.op == 1237)) {
    return null;
  }
  final charStringsAt = operand(_charStringsOp);
  if (charStringsAt == null) return null;
  final (charStrings, _) = _readIndex(cff, charStringsAt);
  final nGlyphs = charStrings.length;

  // charset and Encoding: copied as they are, unless predefined.
  Uint8List? charset;
  final charsetAt = operand(_charsetOp) ?? 0;
  if (charsetAt > 2) {
    final format = cff[charsetAt];
    var length = 1;
    if (format == 0) {
      length += 2 * (nGlyphs - 1);
    } else if (format == 1 || format == 2) {
      for (var covered = 1; covered < nGlyphs;) {
        final nLeft = format == 1
            ? cff[charsetAt + length + 2]
            : (cff[charsetAt + length + 2] << 8) | cff[charsetAt + length + 3];
        covered += 1 + nLeft;
        length += format == 1 ? 3 : 4;
      }
    } else {
      return null;
    }
    charset = Uint8List.sublistView(cff, charsetAt, charsetAt + length);
  }
  Uint8List? encoding;
  final encodingAt = operand(_encodingOp) ?? 0;
  if (encodingAt > 1) {
    final format = cff[encodingAt] & 0x7f;
    var length = switch (format) {
      0 => 2 + cff[encodingAt + 1],
      1 => 2 + 2 * cff[encodingAt + 1],
      _ => throw const FormatException('CFF Encoding'),
    };
    if (cff[encodingAt] & 0x80 != 0) length += 1 + 3 * cff[encodingAt + length];
    encoding = Uint8List.sublistView(cff, encodingAt, encodingAt + length);
  }

  // The Private DICT, its local Subrs moved to just after it.
  final privateSize = operand(_privateOp, 0);
  final privateAt = operand(_privateOp, 1);
  if (privateSize == null || privateAt == null) return null;
  final private =
      _readDict(Uint8List.sublistView(cff, privateAt, privateAt + privateSize));
  List<Uint8List>? localSubrs;
  for (final e in private) {
    if (e.op == _subrsOp && e.values.isNotEmpty) {
      (localSubrs, _) = _readIndex(cff, privateAt + e.values.first.toInt());
    }
  }

  // Subroutines no kept glyph calls become a bare `return`, keeping their
  // numbers (a call's index is relative to the count). If the calls cannot
  // be followed, all are kept.
  final used = _usedSubrs([
    for (final g in keep)
      if (g < charStrings.length) charStrings[g]
  ], globalSubrs, localSubrs ?? const []);
  List<List<int>> pruned(List<Uint8List> subrs, Set<int>? kept) => [
        for (final (i, subr) in subrs.indexed)
          kept == null || kept.contains(i) ? subr : const [11], // return
      ];
  final newGlobalSubrs = _writeIndex(pruned(globalSubrs, used?.$1));
  final subrs =
      localSubrs == null ? null : _writeIndex(pruned(localSubrs, used?.$2));
  final privateLength = _writeDict(private, {
    _subrsOp: [0]
  }).length;
  final newPrivate = _writeDict(private, {
    if (subrs != null) _subrsOp: [privateLength],
  });

  final newCharStrings = _writeIndex([
    for (var i = 0; i < nGlyphs; i++)
      keep.contains(i) ? charStrings[i] : const [14], // endchar
  ]);

  // The Top DICT's length is fixed by its five-byte offsets: lay out with
  // placeholders, then write it with the real ones.
  Map<int, List<int>> offsetsFrom(int topLength) {
    var at = hdrSize +
        nameIndex.length +
        _writeIndex([Uint8List(topLength)]).length +
        strings.length +
        newGlobalSubrs.length;
    final charsetOffset = charset == null ? charsetAt : at;
    at += charset?.length ?? 0;
    final encodingOffset = encoding == null ? encodingAt : at;
    at += encoding?.length ?? 0;
    final charStringsOffset = at;
    at += newCharStrings.length;
    return {
      if (charset != null) _charsetOp: [charsetOffset],
      if (encoding != null) _encodingOp: [encodingOffset],
      _charStringsOp: [charStringsOffset],
      _privateOp: [newPrivate.length, at],
    };
  }

  final topLength = _writeDict(top, offsetsFrom(0)).length;
  final newTop = _writeDict(top, offsetsFrom(topLength));
  return (BytesBuilder(copy: false)
        ..add(header)
        ..add(nameIndex)
        ..add(_writeIndex([newTop]))
        ..add(strings)
        ..add(newGlobalSubrs)
        ..add(charset ?? const [])
        ..add(encoding ?? const [])
        ..add(newCharStrings)
        ..add(newPrivate)
        ..add(subrs ?? const []))
      .toBytes();
}

/// The global and local subroutines that [charStrings] call, directly or
/// through other subroutines — or null when a call's number is computed
/// (by the arithmetic or storage operators) rather than written, which
/// cannot be followed without running the program.
(Set<int>, Set<int>)? _usedSubrs(List<Uint8List> charStrings,
    List<Uint8List> globalSubrs, List<Uint8List> localSubrs) {
  int bias(int count) => count < 1240
      ? 107
      : count < 33900
          ? 1131
          : 32768;
  final globalBias = bias(globalSubrs.length);
  final localBias = bias(localSubrs.length);
  final usedGlobal = <int>{}, usedLocal = <int>{};

  // One glyph's program: the operand stack and stem count carry through
  // its subroutine calls.
  final stack = <num>[];
  var stems = 0;
  var depth = 0;

  /// Runs [code]; false at `endchar`, which ends the whole glyph.
  bool run(Uint8List code) {
    if (++depth > 10) throw const FormatException('CFF subr nesting');
    try {
      var i = 0;
      while (i < code.length) {
        final b0 = code[i];
        if (b0 >= 32 || b0 == 28) {
          if (b0 == 28) {
            stack.add(ByteData.sublistView(code, i + 1, i + 3).getInt16(0));
            i += 3;
          } else if (b0 <= 246) {
            stack.add(b0 - 139);
            i++;
          } else if (b0 <= 250) {
            stack.add((b0 - 247) * 256 + code[i + 1] + 108);
            i += 2;
          } else if (b0 <= 254) {
            stack.add(-(b0 - 251) * 256 - code[i + 1] - 108);
            i += 2;
          } else {
            stack.add(
                ByteData.sublistView(code, i + 1, i + 5).getInt32(0) / 65536);
            i += 5;
          }
          continue;
        }
        i++;
        switch (b0) {
          case 1 || 3 || 18 || 23: // hstem, vstem, hstemhm, vstemhm
            stems += stack.length ~/ 2;
            stack.clear();
          case 19 || 20: // hintmask, cntrmask: an implied vstem first
            stems += stack.length ~/ 2;
            stack.clear();
            i += (stems + 7) ~/ 8;
          case 10 || 29: // callsubr, callgsubr
            if (stack.isEmpty) throw const FormatException('CFF call');
            final local = b0 == 10;
            final n =
                stack.removeLast().toInt() + (local ? localBias : globalBias);
            final subrs = local ? localSubrs : globalSubrs;
            if (n < 0 || n >= subrs.length) {
              throw const FormatException('CFF subr number');
            }
            (local ? usedLocal : usedGlobal).add(n);
            if (!run(subrs[n])) return false;
          case 11: // return
            return true;
          case 14: // endchar
            return false;
          case 12:
            final op = code[i++];
            // Only the flex operators: the rest compute values.
            if (op < 34 || op > 37) throw const _Computed();
            stack.clear();
          default:
            stack.clear();
        }
      }
      return true;
    } finally {
      depth--;
    }
  }

  try {
    for (final code in charStrings) {
      stack.clear();
      stems = 0;
      run(code);
    }
  } on _Computed {
    return null;
  }
  return (usedGlobal, usedLocal);
}

/// A subroutine number computed at run time: [_usedSubrs] gives up.
class _Computed implements Exception {
  const _Computed();
}

// ---------------------------------------------------------------------------
// The sfnt container.

Uint8List _writeSfnt(int version, Map<String, Uint8List> tables) {
  final tags = tables.keys.toList()..sort();
  final n = tags.length;
  var power = 1, log2 = 0;
  while (power * 2 <= n) {
    power *= 2;
    log2++;
  }
  final dirLength = 12 + 16 * n;
  var size = dirLength;
  for (final t in tags) {
    size += (tables[t]!.length + 3) & ~3;
  }
  final out = Uint8List(size);
  final d = ByteData.sublistView(out)
    ..setUint32(0, version)
    ..setUint16(4, n)
    ..setUint16(6, 16 * power)
    ..setUint16(8, log2)
    ..setUint16(10, 16 * n - 16 * power);
  var at = dirLength;
  int? headAt;
  for (final (i, tag) in tags.indexed) {
    final data = tables[tag]!;
    if (tag == 'head') {
      headAt = at;
      out.setRange(at, at + data.length, data);
      d.setUint32(at + 8, 0); // checkSumAdjustment, set below
    } else {
      out.setRange(at, at + data.length, data);
    }
    final rec = 12 + 16 * i;
    out.setRange(rec, rec + 4, latin1.encode(tag));
    d
      ..setUint32(rec + 4, _checksum(out, at, data.length))
      ..setUint32(rec + 8, at)
      ..setUint32(rec + 12, data.length);
    at += (data.length + 3) & ~3;
  }
  if (headAt != null) {
    d.setUint32(
        headAt + 8, (0xB1B0AFBA - _checksum(out, 0, out.length)) & 0xffffffff);
  }
  return out;
}

int _checksum(Uint8List bytes, int at, int length) {
  var sum = 0;
  for (var i = 0; i < length; i += 4) {
    var word = 0;
    for (var k = 0; k < 4; k++) {
      word = (word << 8) | (i + k < length ? bytes[at + i + k] : 0);
    }
    sum = (sum + word) & 0xffffffff;
  }
  return sum;
}
