/// Container handling for Guitar Pro files, which wrap a `score.gpif` XML:
/// GP7/GP8 `.gp` is a ZIP (uses `dart:io`'s DEFLATE), GP6 `.gpx` is a
/// BCFZ-compressed BCFS filesystem (a pure bit/byte codec). Both extract the
/// gpif for `scoreFromGpif`. Kept in the CLI (out of the web-safe core)
/// because `.gp` needs `dart:io`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Extracts the `score.gpif` XML from a `.gp` archive's [bytes].
String readGpifFromGp(Uint8List bytes) {
  // Locate the End Of Central Directory record.
  var eocd = bytes.length - 22;
  while (eocd >= 0 && _u32(bytes, eocd) != 0x06054b50) {
    eocd--;
  }
  if (eocd < 0) throw const FormatException('not a .gp (zip) file');
  final count = _u16(bytes, eocd + 10);
  var p = _u32(bytes, eocd + 16); // central directory offset

  for (var e = 0; e < count; e++) {
    if (_u32(bytes, p) != 0x02014b50) break;
    final method = _u16(bytes, p + 10);
    final compSize = _u32(bytes, p + 20);
    final nameLen = _u16(bytes, p + 28);
    final extraLen = _u16(bytes, p + 30);
    final commentLen = _u16(bytes, p + 32);
    final localOffset = _u32(bytes, p + 42);
    final name = utf8.decode(bytes.sublist(p + 46, p + 46 + nameLen));
    if (name.endsWith('score.gpif')) {
      final lNameLen = _u16(bytes, localOffset + 26);
      final lExtraLen = _u16(bytes, localOffset + 28);
      final dataStart = localOffset + 30 + lNameLen + lExtraLen;
      final comp = bytes.sublist(dataStart, dataStart + compSize);
      final raw = method == 0
          ? comp
          : Uint8List.fromList(ZLibDecoder(raw: true).convert(comp));
      return utf8.decode(raw);
    }
    p += 46 + nameLen + extraLen + commentLen;
  }
  throw const FormatException('Content/score.gpif not found in .gp');
}

/// Packs [gpif] into a minimal `.gp` archive (a ZIP with a single stored
/// `Content/score.gpif` entry).
Uint8List writeGpFromGpif(String gpif) {
  final name = ascii.encode('Content/score.gpif');
  final data = utf8.encode(gpif);
  final crc = _crc32(data);
  final out = BytesBuilder();

  // Local file header (method 0 = stored).
  out.add(_le32(0x04034b50));
  out.add(_le16(20)); // version needed
  out.add(_le16(0)); // flags
  out.add(_le16(0)); // method: stored
  out.add(_le16(0)); // mod time
  out.add(_le16(0x21)); // mod date (valid non-zero)
  out.add(_le32(crc));
  out.add(_le32(data.length)); // compressed size
  out.add(_le32(data.length)); // uncompressed size
  out.add(_le16(name.length));
  out.add(_le16(0)); // extra length
  out.add(name);
  out.add(data);

  final cdOffset = out.length;
  // Central directory record.
  out.add(_le32(0x02014b50));
  out.add(_le16(20)); // version made by
  out.add(_le16(20)); // version needed
  out.add(_le16(0)); // flags
  out.add(_le16(0)); // method
  out.add(_le16(0)); // mod time
  out.add(_le16(0x21)); // mod date
  out.add(_le32(crc));
  out.add(_le32(data.length));
  out.add(_le32(data.length));
  out.add(_le16(name.length));
  out.add(_le16(0)); // extra
  out.add(_le16(0)); // comment
  out.add(_le16(0)); // disk number
  out.add(_le16(0)); // internal attrs
  out.add(_le32(0)); // external attrs
  out.add(_le32(0)); // local header offset
  out.add(name);
  final cdSize = out.length - cdOffset;

  // End of central directory.
  out.add(_le32(0x06054b50));
  out.add(_le16(0)); // disk number
  out.add(_le16(0)); // cd start disk
  out.add(_le16(1)); // entries on this disk
  out.add(_le16(1)); // total entries
  out.add(_le32(cdSize));
  out.add(_le32(cdOffset));
  out.add(_le16(0)); // comment length
  return out.toBytes();
}

/// Extracts the `score.gpif` XML from a Guitar Pro 6 `.gpx` archive's [bytes]
/// (a BCFZ-compressed / BCFS filesystem container). Ported from the algorithm
/// in alphaTab's `GpxFileSystem`.
String readGpifFromGpx(Uint8List bytes) {
  final br = _BitReader(bytes);
  final header = String.fromCharCodes(br.readBytes(4));
  final Uint8List content;
  if (header == 'BCFZ') {
    content = _bcfzDecompress(br);
  } else if (header == 'BCFS') {
    content = bytes.sublist(4);
  } else {
    throw const FormatException('not a .gpx (BCFS) file');
  }
  final files = _readBcfs(content);
  for (final entry in files.entries) {
    if (entry.key.toLowerCase().endsWith('.gpif')) {
      return utf8.decode(entry.value);
    }
  }
  throw const FormatException('score.gpif not found in .gpx');
}

/// BCFZ bitstream decompression (skips the leading 4-byte header of the
/// decompressed BCFS block).
Uint8List _bcfzDecompress(_BitReader src) {
  final out = <int>[];
  final expected = _u32(src.readBytes(4), 0);
  try {
    while (out.length < expected) {
      if (src.readBits(1) == 1) {
        final wordSize = src.readBits(4);
        final offset = src.readBitsReversed(wordSize);
        final size = src.readBitsReversed(wordSize);
        final sourcePos = out.length - offset;
        final toRead = offset < size ? offset : size;
        for (var i = 0; i < toRead; i++) {
          out.add(out[sourcePos + i]);
        }
      } else {
        final size = src.readBitsReversed(2);
        for (var i = 0; i < size; i++) {
          out.add(src.readByte());
        }
      }
    }
  } on _EndOfBits {
    // Ran out mid-token; keep what we decoded.
  }
  return Uint8List.fromList(out.sublist(out.length >= 4 ? 4 : 0));
}

/// Parses the BCFS sector filesystem into name → bytes.
Map<String, Uint8List> _readBcfs(Uint8List data) {
  const sectorSize = 0x1000;
  final files = <String, Uint8List>{};
  var offset = sectorSize;
  while (offset + 3 < data.length) {
    if (_u32(data, offset) == 2) {
      final name = _cString(data, offset + 0x04, 127);
      final fileSize = _u32(data, offset + 0x8c);
      final dataPtr = offset + 0x94;
      final fileData = <int>[];
      var sectorCount = 0;
      while (dataPtr + 4 * sectorCount + 3 < data.length) {
        final sector = _u32(data, dataPtr + 4 * sectorCount++);
        if (sector == 0) break;
        offset = sector * sectorSize;
        final end = offset + sectorSize <= data.length
            ? offset + sectorSize
            : data.length;
        if (offset < data.length) fileData.addAll(data.sublist(offset, end));
      }
      final len = fileSize < fileData.length ? fileSize : fileData.length;
      files[name] = Uint8List.fromList(fileData.sublist(0, len));
    }
    offset += sectorSize;
  }
  return files;
}

String _cString(Uint8List data, int offset, int maxLen) {
  final b = <int>[];
  for (var i = 0; i < maxLen && offset + i < data.length; i++) {
    final c = data[offset + i];
    if (c == 0) break;
    b.add(c);
  }
  return String.fromCharCodes(b);
}

/// Thrown when the BCFZ bit reader runs past the end of its source.
class _EndOfBits implements Exception {}

/// MSB-first bit reader (matches alphaTab's `BitReader`).
class _BitReader {
  final Uint8List data;
  int _bytePos = 0;
  int _cur = 0;
  int _pos = 8;
  _BitReader(this.data);

  int _readBit() {
    if (_pos >= 8) {
      if (_bytePos >= data.length) throw _EndOfBits();
      _cur = data[_bytePos++];
      _pos = 0;
    }
    final v = (_cur >> (8 - _pos - 1)) & 1;
    _pos++;
    return v;
  }

  int readBits(int count) {
    var bits = 0;
    for (var i = count - 1; i >= 0; i--) {
      bits |= _readBit() << i;
    }
    return bits;
  }

  int readBitsReversed(int count) {
    var bits = 0;
    for (var i = 0; i < count; i++) {
      bits |= _readBit() << i;
    }
    return bits;
  }

  int readByte() => readBits(8);

  Uint8List readBytes(int count) {
    final b = Uint8List(count);
    for (var i = 0; i < count; i++) {
      b[i] = readByte() & 0xff;
    }
    return b;
  }
}

int _u16(Uint8List b, int at) => b[at] | (b[at + 1] << 8);
int _u32(Uint8List b, int at) =>
    b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24);
List<int> _le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _le32(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
