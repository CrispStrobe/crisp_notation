/// Container handling for the `.gp`/`.gpx` files, which wrap a `score.gpif` XML:
/// `.gp` (v7/8) is a ZIP, `.gpx` (v6) is a BCFZ-compressed BCFS filesystem (a
/// pure bit/byte codec). Both extract the gpif for `scoreFromGpif`. Pure Dart
/// (web-safe): ZIP entries inflate/deflate through the in-repo [inflate] /
/// [deflate], so no `dart:io` — reads and writes work in the browser / WASM too.
///
/// The `.gpx` codec here is a clean-room implementation written from the
/// *public, community-reverse-engineered* description of the Guitar Pro 6
/// container — the BCFZ bit-compression wrapper and the BCFS sector filesystem,
/// as documented by independent projects (TuxGuitar, DGuitar, the standalone
/// "gpx reader" format notes) — then cross-checked byte-for-byte against the
/// vendored `chords.gpx` / `slides.gpx` fixtures. The bit and sector layout of a
/// file format is factual; none of the surrounding code was ported from any
/// particular implementation.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'deflate.dart';
import 'inflate.dart';

/// Extracts the `score.gpif` XML from a `.gp` archive's [bytes].
///
/// `.gp` (Guitar Pro 7/8) is an ordinary ZIP; the score lives at
/// `Content/score.gpif` (some writers omit the folder). Throws a
/// [FormatException] if [bytes] is not a ZIP or carries no `.gpif` member.
String readGpifFromGp(Uint8List bytes) {
  for (final entry in _readZip(bytes)) {
    if (entry.name.endsWith('.gpif')) return utf8.decode(entry.data);
  }
  throw const FormatException('gp archive contains no .gpif member');
}

/// Packs [gpif] into a minimal `.gp` ZIP holding a deflated `Content/score.gpif`.
///
/// The archive is a single entry and reads back through [readGpifFromGp]
/// unchanged.
Uint8List writeGpFromGpif(String gpif) {
  final nameBytes = ascii.encode('Content/score.gpif');
  final data = utf8.encode(gpif);
  final comp = deflate(Uint8List.fromList(data));
  final crc = _crc32(data);

  final out = _ByteSink();
  // --- Local file header (offset 0). ---
  out.u32(0x04034b50); // "PK\x03\x04"
  out.u16(20); // version needed
  out.u16(0); // flags
  out.u16(8); // method 8 = deflate
  out.u16(0); // mod time
  out.u16(0x21); // mod date (a valid non-zero date)
  out.u32(crc);
  out.u32(comp.length); // compressed size
  out.u32(data.length); // uncompressed size
  out.u16(nameBytes.length);
  out.u16(0); // extra length
  out.bytes(nameBytes);
  out.bytes(comp);

  // --- Central directory. ---
  final cdOffset = out.length;
  out.u32(0x02014b50); // "PK\x01\x02"
  out.u16(20); // version made by
  out.u16(20); // version needed
  out.u16(0); // flags
  out.u16(8); // method 8 = deflate
  out.u16(0); // mod time
  out.u16(0x21); // mod date
  out.u32(crc);
  out.u32(comp.length);
  out.u32(data.length);
  out.u16(nameBytes.length);
  out.u16(0); // extra
  out.u16(0); // comment
  out.u16(0); // disk number start
  out.u16(0); // internal attrs
  out.u32(0); // external attrs
  out.u32(0); // local header offset
  out.bytes(nameBytes);
  final cdSize = out.length - cdOffset;

  // --- End of central directory. ---
  out.u32(0x06054b50); // "PK\x05\x06"
  out.u16(0); // this disk
  out.u16(0); // disk with CD
  out.u16(1); // entries on this disk
  out.u16(1); // total entries
  out.u32(cdSize);
  out.u32(cdOffset);
  out.u16(0); // comment length

  return out.toBytes();
}

/// Extracts the `score.gpif` XML from a `.gpx` container's [bytes].
///
/// A `.gpx` (Guitar Pro 6) begins with a 4-byte ASCII magic: `BCFZ` for the
/// bit-compressed form or `BCFS` for a raw sector filesystem. `BCFZ` is
/// decompressed to a `BCFS` image, whose file entries are then scanned for the
/// one whose name ends in `.gpif`. Throws a [FormatException] on any other
/// input.
String readGpifFromGpx(Uint8List bytes) {
  if (bytes.length < 4) {
    throw const FormatException('gpx: too short for a container magic');
  }
  final magic = ascii.decode(bytes.sublist(0, 4), allowInvalid: true);
  final Uint8List image;
  if (magic == 'BCFZ') {
    image = _bcfzInflate(bytes);
  } else if (magic == 'BCFS') {
    image = bytes;
  } else {
    throw FormatException('gpx: expected BCFZ/BCFS magic, got "$magic"');
  }
  final gpif = _bcfsFindGpif(image);
  if (gpif == null) {
    throw const FormatException('gpx: BCFS image has no .gpif entry');
  }
  return utf8.decode(gpif);
}

// ---------------------------------------------------------------------------
// BCFZ — the bit-compression wrapper.
//
// Layout: "BCFZ", then a little-endian uint32 giving the decompressed length,
// then a bit stream (bytes consumed in order, bits within each byte from the
// most-significant down). Each token starts with a 1-bit tag:
//   tag 0 — literal run: a 2-bit count `n` (low-bit first), then `n` raw bytes
//           (8 bits each, most-significant first).
//   tag 1 — back reference: a 4-bit word width `w`, then a `w`-bit distance and
//           a `w`-bit length (both low-bit first), copying min(length, distance)
//           bytes from `distance` behind the output tail.
// Derived and pinned against the fixtures: the first token of chords.gpx is a
// literal run decoding to "BCF", proving the MSB-first bit/byte order; the
// decompressed image is itself a BCFS blob (it opens with the ASCII magic
// "BCFS"). Termination is guaranteed without an explicit hang guard: every token
// consumes at least its 1-bit tag, so the cursor strictly advances and the input
// is always eventually exhausted. The stream is bit-packed, so its final byte
// carries a few padding bits — the last decoded byte may be padding beyond the
// filesystem's recorded file sizes, so a decode ending one byte short of the
// declared length is expected, not an error.
// ---------------------------------------------------------------------------

Uint8List _bcfzInflate(Uint8List bytes) {
  final expected = _u32le(bytes, 4);
  final bits = _BitCursor(bytes, 8);
  final out = <int>[];

  while (out.length < expected) {
    // No more real input: keep what we decoded (the tail is padding). Because
    // each token consumes >= 1 bit, this is always reached — the decoder can
    // never spin.
    if (bits.exhausted) break;

    if (bits.bit() == 0) {
      // Literal run.
      final count = bits.readLsb(2);
      for (var i = 0; i < count; i++) {
        out.add(bits.readMsb(8));
      }
    } else {
      // Back reference.
      final width = bits.readMsb(4);
      final distance = bits.readLsb(width);
      final length = bits.readLsb(width);
      final from = out.length - distance;
      if (from < 0) {
        throw const FormatException('BCFZ: back reference before start');
      }
      final copy = length < distance ? length : distance;
      for (var i = 0; i < copy; i++) {
        out.add(out[from + i]);
      }
    }
  }
  return Uint8List.fromList(out);
}

/// A most-significant-bit-first cursor over [_data] starting at byte [_pos].
///
/// Reading past the end never throws or advances; it yields 0 and latches
/// [exhausted]. Callers stop as soon as [exhausted] is set, which — combined
/// with every token consuming at least one bit — makes an infinite loop
/// impossible even on a truncated or malformed stream.
class _BitCursor {
  _BitCursor(this._data, this._pos);

  final Uint8List _data;
  int _pos;
  int _shift = 7; // next bit index within the current byte (7 == MSB)

  /// True once a read has run past the end of [_data].
  bool exhausted = false;

  /// Reads a single bit (0 past the end of the source).
  int bit() {
    if (_pos >= _data.length) {
      exhausted = true;
      return 0;
    }
    final value = (_data[_pos] >> _shift) & 1;
    if (_shift == 0) {
      _shift = 7;
      _pos++;
    } else {
      _shift--;
    }
    return value;
  }

  /// Reads [count] bits, most-significant first (first bit is the high bit).
  int readMsb(int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      value = (value << 1) | bit();
    }
    return value;
  }

  /// Reads [count] bits, least-significant first (first bit is the low bit).
  int readLsb(int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      value |= bit() << i;
    }
    return value;
  }
}

// ---------------------------------------------------------------------------
// BCFS — the sector filesystem.
//
// After the 4-byte "BCFS" magic the image is a grid of 0x1000-byte sectors,
// indexed from 0 starting right after the magic (so sector `s` occupies image
// bytes [4 + s*0x1000, 4 + (s+1)*0x1000) — the stored sector indices are in
// this post-magic frame). A sector that begins with the little-endian uint32
// `2` is a file header:
//   +0x04  NUL-terminated name (ASCII)
//   +0x8C  little-endian uint32 file size in bytes
//   +0x94  a NUL-terminated list of little-endian uint32 data-sector indices.
// The file's bytes are the referenced data sectors concatenated and truncated
// to the recorded size. Sectors claimed as one file's data are skipped when the
// scan continues, so a data sector whose first word happens to be `2` can never
// be mistaken for a file header.
// ---------------------------------------------------------------------------

const int _sector = 0x1000;
const int _bcfsBase = 4; // sectors are indexed after the "BCFS" magic

Uint8List? _bcfsFindGpif(Uint8List image) {
  final claimed = <int>{}; // sector indices already spoken for as file data
  for (var s = 1; _bcfsBase + s * _sector + 0x94 <= image.length; s++) {
    if (claimed.contains(s)) continue;
    final sec = _bcfsBase + s * _sector;
    if (_u32le(image, sec) != 2) continue;

    // Read the header's data-sector chain once — it both marks those sectors as
    // data (so they are not re-scanned as headers) and locates the file bytes.
    final chain = <int>[];
    for (var i = sec + 0x94; i + 4 <= image.length; i += 4) {
      final index = _u32le(image, i);
      if (index == 0) break;
      chain.add(index);
    }
    claimed.addAll(chain);

    final name = _asciiZ(image, sec + 0x04, 0x88);
    if (!name.toLowerCase().endsWith('.gpif')) continue;

    final size = _u32le(image, sec + 0x8C);
    final data = <int>[];
    for (final index in chain) {
      if (data.length >= size) break;
      final start = _bcfsBase + index * _sector;
      if (start >= image.length) break;
      final end = start + _sector;
      data.addAll(
          image.sublist(start, end > image.length ? image.length : end));
    }
    return Uint8List.fromList(
        data.length > size ? data.sublist(0, size) : data);
  }
  return null;
}

// ---------------------------------------------------------------------------
// ZIP — just enough of the format for `.gp` archives.
// ---------------------------------------------------------------------------

class _ZipEntry {
  _ZipEntry(this.name, this.data);
  final String name;
  final Uint8List data;
}

/// Reads every member of a ZIP [bytes] via its end-of-central-directory record
/// and central directory. Supports stored (method 0) and deflate (method 8).
List<_ZipEntry> _readZip(Uint8List bytes) {
  final eocd = _findEocd(bytes);
  if (eocd < 0) throw const FormatException('not a ZIP: no end-of-directory');

  final count = _u16le(bytes, eocd + 10);
  var cd = _u32le(bytes, eocd + 16);
  final entries = <_ZipEntry>[];

  for (var i = 0; i < count; i++) {
    if (cd + 46 > bytes.length || _u32le(bytes, cd) != 0x02014b50) {
      throw const FormatException('ZIP: malformed central directory');
    }
    final method = _u16le(bytes, cd + 10);
    final compSize = _u32le(bytes, cd + 20);
    final nameLen = _u16le(bytes, cd + 28);
    final extraLen = _u16le(bytes, cd + 30);
    final commentLen = _u16le(bytes, cd + 32);
    final localOffset = _u32le(bytes, cd + 42);
    final name = utf8.decode(bytes.sublist(cd + 46, cd + 46 + nameLen));

    entries
        .add(_ZipEntry(name, _readLocal(bytes, localOffset, method, compSize)));
    cd += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

Uint8List _readLocal(Uint8List bytes, int offset, int method, int compSize) {
  if (offset + 30 > bytes.length || _u32le(bytes, offset) != 0x04034b50) {
    throw const FormatException('ZIP: malformed local header');
  }
  final nameLen = _u16le(bytes, offset + 26);
  final extraLen = _u16le(bytes, offset + 28);
  final start = offset + 30 + nameLen + extraLen;
  final raw = Uint8List.sublistView(bytes, start, start + compSize);
  switch (method) {
    case 0:
      return Uint8List.fromList(raw); // stored
    case 8:
      return inflate(raw); // raw DEFLATE
    default:
      throw FormatException('ZIP: unsupported compression method $method');
  }
}

/// Locates the end-of-central-directory signature, scanning back from the tail
/// (a trailing variable-length comment forces a search).
int _findEocd(Uint8List bytes) {
  if (bytes.length < 22) return -1;
  for (var i = bytes.length - 22; i >= 0; i--) {
    if (_u32le(bytes, i) == 0x06054b50) return i;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Small byte helpers.
// ---------------------------------------------------------------------------

int _u16le(Uint8List b, int at) => b[at] | (b[at + 1] << 8);

int _u32le(Uint8List b, int at) =>
    b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24);

/// Decodes an ASCII string starting at [offset], stopping at the first NUL or
/// after [maxLen] bytes.
String _asciiZ(Uint8List data, int offset, int maxLen) {
  final end = offset + maxLen;
  var stop = offset;
  while (stop < end && stop < data.length && data[stop] != 0) {
    stop++;
  }
  return ascii.decode(data.sublist(offset, stop), allowInvalid: true);
}

/// Standard (reflected, polynomial 0xEDB88320) CRC-32, as ZIP requires.
int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// A tiny growable little-endian byte writer for the ZIP packer.
class _ByteSink {
  final _bytes = <int>[];

  int get length => _bytes.length;

  void u16(int v) {
    _bytes
      ..add(v & 0xFF)
      ..add((v >> 8) & 0xFF);
  }

  void u32(int v) {
    _bytes
      ..add(v & 0xFF)
      ..add((v >> 8) & 0xFF)
      ..add((v >> 16) & 0xFF)
      ..add((v >> 24) & 0xFF);
  }

  void bytes(List<int> b) => _bytes.addAll(b);

  Uint8List toBytes() => Uint8List.fromList(_bytes);
}
