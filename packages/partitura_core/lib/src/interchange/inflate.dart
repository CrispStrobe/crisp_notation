/// Pure-Dart raw DEFLATE (RFC 1951) decompression.
///
/// Enough to unpack the deflated entries inside `.gp`/`.mscz` ZIP archives
/// without `dart:io`'s `ZLibDecoder`, so the container readers stay web-safe
/// (they compile to WASM). Handles all three block types — stored, fixed and
/// dynamic Huffman. Structured after zlib's reference "puff" decoder.
library;

import 'dart:typed_data';

/// Inflates *raw* DEFLATE [data] (no zlib/gzip wrapper) into the original bytes.
/// Throws [FormatException] on a malformed stream.
Uint8List inflate(Uint8List data) {
  final input = _BitInput(data);
  final out = BytesBuilder(copy: false);
  final window = <int>[]; // full output, for LZ77 back-references
  var last = false;
  while (!last) {
    last = input.readBit() == 1;
    switch (input.readBits(2)) {
      case 0:
        _stored(input, window);
      case 1:
        _block(input, window, _fixedLitLen, _fixedDist);
      case 2:
        final (litLen, dist) = _dynamicTables(input);
        _block(input, window, litLen, dist);
      default:
        throw const FormatException('invalid DEFLATE block type');
    }
  }
  out.add(window);
  return out.toBytes();
}

void _stored(_BitInput input, List<int> window) {
  input.alignToByte();
  final len = input.readBits(16);
  input.readBits(16); // ~len (NLEN), unchecked
  for (var i = 0; i < len; i++) {
    window.add(input.readByte());
  }
}

void _block(_BitInput input, List<int> window, _Huffman litLen, _Huffman dist) {
  while (true) {
    final symbol = litLen.decode(input);
    if (symbol < 256) {
      window.add(symbol);
    } else if (symbol == 256) {
      return; // end of block
    } else {
      final l = symbol - 257;
      if (l >= _lenBase.length) throw const FormatException('bad length code');
      final length = _lenBase[l] + input.readBits(_lenExtra[l]);
      final d = dist.decode(input);
      final distance = _distBase[d] + input.readBits(_distExtra[d]);
      var from = window.length - distance;
      if (from < 0) throw const FormatException('back-reference before start');
      for (var i = 0; i < length; i++) {
        window.add(window[from++]);
      }
    }
  }
}

(_Huffman, _Huffman) _dynamicTables(_BitInput input) {
  final hlit = input.readBits(5) + 257;
  final hdist = input.readBits(5) + 1;
  final hclen = input.readBits(4) + 4;
  const order = [
    16,
    17,
    18,
    0,
    8,
    7,
    9,
    6,
    10,
    5,
    11,
    4,
    12,
    3,
    13,
    2,
    14,
    1,
    15
  ];
  final clLengths = List.filled(19, 0);
  for (var i = 0; i < hclen; i++) {
    clLengths[order[i]] = input.readBits(3);
  }
  final clHuff = _Huffman(clLengths);

  final lengths = <int>[];
  while (lengths.length < hlit + hdist) {
    final symbol = clHuff.decode(input);
    if (symbol < 16) {
      lengths.add(symbol);
    } else if (symbol == 16) {
      if (lengths.isEmpty) throw const FormatException('repeat with no prev');
      final repeat = 3 + input.readBits(2);
      final prev = lengths.last;
      for (var i = 0; i < repeat; i++) {
        lengths.add(prev);
      }
    } else if (symbol == 17) {
      final repeat = 3 + input.readBits(3);
      for (var i = 0; i < repeat; i++) {
        lengths.add(0);
      }
    } else {
      final repeat = 11 + input.readBits(7);
      for (var i = 0; i < repeat; i++) {
        lengths.add(0);
      }
    }
  }
  return (
    _Huffman(lengths.sublist(0, hlit)),
    _Huffman(lengths.sublist(hlit, hlit + hdist)),
  );
}

/// A canonical Huffman decoder built from per-symbol code [lengths].
class _Huffman {
  static const _maxBits = 15;
  final Int32List _counts; // codes of each bit length
  final Int32List _symbols; // symbols ordered by (length, symbol)

  _Huffman(List<int> lengths)
      : _counts = Int32List(_maxBits + 1),
        _symbols = Int32List(lengths.length) {
    for (final len in lengths) {
      if (len > _maxBits) throw const FormatException('over-long Huffman code');
      _counts[len]++;
    }
    _counts[0] = 0;
    final offsets = Int32List(_maxBits + 2);
    for (var len = 1; len <= _maxBits; len++) {
      offsets[len + 1] = offsets[len] + _counts[len];
    }
    for (var symbol = 0; symbol < lengths.length; symbol++) {
      if (lengths[symbol] != 0) _symbols[offsets[lengths[symbol]]++] = symbol;
    }
  }

  int decode(_BitInput input) {
    var code = 0, first = 0, index = 0;
    for (var len = 1; len <= _maxBits; len++) {
      code |= input.readBit();
      final count = _counts[len];
      if (code - first < count) return _symbols[index + (code - first)];
      index += count;
      first = (first + count) << 1;
      code <<= 1;
    }
    throw const FormatException('incomplete Huffman code');
  }
}

/// LSB-first bit reader over a byte buffer (DEFLATE bit order).
class _BitInput {
  final Uint8List data;
  int _byte = 0;
  int _bit = 0;
  _BitInput(this.data);

  int readBit() {
    if (_byte >= data.length) throw const FormatException('unexpected EOF');
    final value = (data[_byte] >> _bit) & 1;
    if (++_bit == 8) {
      _bit = 0;
      _byte++;
    }
    return value;
  }

  int readBits(int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      value |= readBit() << i;
    }
    return value;
  }

  void alignToByte() {
    if (_bit != 0) {
      _bit = 0;
      _byte++;
    }
  }

  int readByte() {
    if (_byte >= data.length) throw const FormatException('unexpected EOF');
    return data[_byte++];
  }
}

// RFC 1951 length codes (symbols 257..285) and distance codes (0..29).
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

/// Fixed Huffman tables (RFC 1951 §3.2.6), built once.
final _Huffman _fixedLitLen = _Huffman([
  for (var i = 0; i < 288; i++)
    if (i < 144) 8 else if (i < 256) 9 else if (i < 280) 7 else 8
]);
final _Huffman _fixedDist = _Huffman(List.filled(30, 5));
