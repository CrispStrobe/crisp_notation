import 'dart:io';
import 'dart:typed_data';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// The pure-Dart [inflate] is validated against `dart:io`'s DEFLATE encoder
/// (the reference), across the compression paths it must handle: stored,
/// fixed-Huffman and dynamic-Huffman blocks. The real-archive path is covered
/// by the CLI's `.gp`/`.mscz` fixture tests, which now decompress through this.
Uint8List deflate(List<int> bytes, {int level = 6}) =>
    Uint8List.fromList(ZLibEncoder(raw: true, level: level).convert(bytes));

void main() {
  test('round-trips ASCII text (dynamic Huffman)', () {
    final data =
        ('the quick brown fox jumps over the lazy dog. ' * 40).codeUnits;
    expect(inflate(deflate(data)), data);
  });

  test('round-trips highly repetitive data (long back-references)', () {
    final data = List.filled(5000, 0x41); // "AAAA…" → long LZ77 copies
    expect(inflate(deflate(data)), data);
  });

  test('round-trips incompressible data (stored blocks)', () {
    // A pseudo-random, non-repeating stream compresses to stored blocks.
    var seed = 12345;
    final data = List<int>.generate(4096, (_) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed & 0xff;
    });
    expect(inflate(deflate(data, level: 0)), data);
  });

  test('round-trips an empty payload', () {
    expect(inflate(deflate(const [])), <int>[]);
  });

  test('round-trips binary bytes across the full 0..255 range', () {
    final data = [for (var i = 0; i < 2000; i++) (i * 7) & 0xff];
    expect(inflate(deflate(data)), data);
  });

  test('round-trips XML that looks like a real score payload', () {
    final xml = StringBuffer('<museScore version="4.20"><Score>');
    for (var m = 0; m < 200; m++) {
      xml.write('<Measure><voice><Chord><durationType>quarter</durationType>'
          '<Note><pitch>${60 + m % 12}</pitch><tpc>14</tpc></Note>'
          '</Chord></voice></Measure>');
    }
    xml.write('</Score></museScore>');
    final data = xml.toString().codeUnits;
    expect(inflate(deflate(data)), data);
  });

  test('throws on a malformed stream', () {
    expect(() => inflate(Uint8List.fromList([0xff, 0xff, 0xff])),
        throwsFormatException);
  });
}
