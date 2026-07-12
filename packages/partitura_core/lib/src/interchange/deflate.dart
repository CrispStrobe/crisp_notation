/// Pure-Dart raw DEFLATE (RFC 1951) compression — the encoder half of
/// [inflate], so the `.gp`/`.mscz` ZIP writers can emit *compressed* entries
/// (smaller files) without `dart:io`, staying web-safe / WASM-compatible.
///
/// Uses greedy LZ77 matching (32 KB window, hash-chain search) with the
/// **fixed** Huffman code tables (one BTYPE=01 block). That skips emitting
/// per-block Huffman trees — simpler than zlib's dynamic Huffman and a little
/// larger, but the output is standard DEFLATE any inflater reads (this one,
/// `dart:io`, browsers, MuseScore, Guitar Pro).
library;

import 'dart:typed_data';

const _minMatch = 3;
const _maxMatch = 258;
const _maxDistance = 32768;
const _maxChain = 256; // hash-chain search depth (speed vs. ratio)

/// Compresses [data] to a raw DEFLATE stream (no zlib/gzip wrapper), readable
/// by [inflate] and any RFC 1951 decoder.
Uint8List deflate(Uint8List data) {
  final out = _BitOutput();
  out.writeBits(1, 1); // BFINAL = 1 (single block)
  out.writeBits(1, 2); // BTYPE  = 01 (fixed Huffman)

  final n = data.length;
  final hashSize = 1 << 15;
  final head = Int32List(hashSize)..fillRange(0, hashSize, -1);
  final prev = Int32List(n == 0 ? 1 : n);

  int hash(int i) =>
      ((data[i] << 10) ^ (data[i + 1] << 5) ^ data[i + 2]) & (hashSize - 1);

  void insert(int i) {
    final h = hash(i);
    prev[i] = head[h];
    head[h] = i;
  }

  var i = 0;
  while (i < n) {
    var bestLen = 0;
    var bestDist = 0;
    if (i + _minMatch <= n) {
      final maxLen = (n - i) < _maxMatch ? (n - i) : _maxMatch;
      var j = head[hash(i)];
      var chain = _maxChain;
      while (j >= 0 && chain-- > 0) {
        if (i - j > _maxDistance) break;
        var len = 0;
        while (len < maxLen && data[j + len] == data[i + len]) {
          len++;
        }
        if (len > bestLen) {
          bestLen = len;
          bestDist = i - j;
          if (len >= maxLen) break;
        }
        j = prev[j];
      }
    }

    if (bestLen >= _minMatch) {
      _writeLength(out, bestLen);
      _writeDistance(out, bestDist);
      final end = i + bestLen;
      while (i < end) {
        if (i + _minMatch <= n) insert(i);
        i++;
      }
    } else {
      _writeLiteral(out, data[i]);
      if (i + _minMatch <= n) insert(i);
      i++;
    }
  }

  _writeSymbol(out, 256); // end of block
  return out.finish();
}

/// Emits a literal/length symbol with its fixed-Huffman code (§3.2.6).
void _writeSymbol(_BitOutput out, int symbol) {
  if (symbol <= 143) {
    out.writeCode(0x30 + symbol, 8);
  } else if (symbol <= 255) {
    out.writeCode(0x190 + symbol - 144, 9);
  } else if (symbol <= 279) {
    out.writeCode(symbol - 256, 7);
  } else {
    out.writeCode(0xc0 + symbol - 280, 8);
  }
}

void _writeLiteral(_BitOutput out, int byte) => _writeSymbol(out, byte);

/// Emits a match [length] (3..258) as its length symbol + extra bits.
void _writeLength(_BitOutput out, int length) {
  for (var i = 0; i < _lenBase.length; i++) {
    final extraBits = _lenExtra[i];
    final base = _lenBase[i];
    if (length >= base && length <= base + ((1 << extraBits) - 1)) {
      _writeSymbol(out, 257 + i);
      if (extraBits > 0) out.writeBits(length - base, extraBits);
      return;
    }
  }
}

/// Emits a match [distance] (1..32768) as its 5-bit fixed distance code +
/// extra bits.
void _writeDistance(_BitOutput out, int distance) {
  for (var i = _distBase.length - 1; i >= 0; i--) {
    if (distance >= _distBase[i]) {
      out.writeCode(i, 5); // distance codes are a 5-bit fixed table
      if (_distExtra[i] > 0) {
        out.writeBits(distance - _distBase[i], _distExtra[i]);
      }
      return;
    }
  }
}

/// LSB-first bit writer (DEFLATE bit order).
class _BitOutput {
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  int _cur = 0;
  int _n = 0;

  /// Writes the low [count] bits of [value], least-significant bit first
  /// (for BTYPE and length/distance extra bits).
  void writeBits(int value, int count) {
    for (var i = 0; i < count; i++) {
      _cur |= ((value >> i) & 1) << _n;
      if (++_n == 8) {
        _bytes.addByte(_cur);
        _cur = 0;
        _n = 0;
      }
    }
  }

  /// Writes a Huffman [code] of [length] bits, most-significant bit first
  /// (RFC 1951 packs codes starting from their MSB).
  void writeCode(int code, int length) {
    for (var i = length - 1; i >= 0; i--) {
      _cur |= ((code >> i) & 1) << _n;
      if (++_n == 8) {
        _bytes.addByte(_cur);
        _cur = 0;
        _n = 0;
      }
    }
  }

  Uint8List finish() {
    if (_n > 0) _bytes.addByte(_cur);
    return _bytes.toBytes();
  }
}

// RFC 1951 length codes (symbols 257..285) and distance codes (0..29) —
// the same tables the decoder uses, kept local so each file stands alone.
const _lenBase = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, //
  67, 83, 99, 115, 131, 163, 195, 227, 258
];
const _lenExtra = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, //
  4, 4, 4, 4, 5, 5, 5, 5, 0
];
const _distBase = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, //
  769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
];
const _distExtra = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, //
  9, 9, 10, 10, 11, 11, 12, 12, 13, 13
];
