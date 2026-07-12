import 'dart:io';
import 'dart:typed_data';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// The pure-Dart [deflate] encoder is checked two ways: it must round-trip
/// through the matching [inflate], and — the stronger claim — its output must
/// be standard DEFLATE that `dart:io`'s reference `ZLibDecoder` reads back.
Uint8List ioInflate(Uint8List d) =>
    Uint8List.fromList(ZLibDecoder(raw: true).convert(d));

void main() {
  final cases = <String, Uint8List>{
    'empty': Uint8List(0),
    'short': Uint8List.fromList('hi'.codeUnits),
    'repetitive': Uint8List.fromList(List.filled(5000, 0x41)),
    'ascii prose':
        Uint8List.fromList(('the quick brown fox. ' * 200).codeUnits),
    'binary 0..255':
        Uint8List.fromList([for (var i = 0; i < 4000; i++) i & 0xff]),
    'score xml': Uint8List.fromList((() {
      final b = StringBuffer('<museScore><Score>');
      for (var m = 0; m < 300; m++) {
        b.write('<Measure><voice><Chord><durationType>quarter</durationType>'
            '<Note><pitch>${60 + m % 12}</pitch><tpc>14</tpc></Note>'
            '</Chord></voice></Measure>');
      }
      return (b..write('</Score></museScore>')).toString().codeUnits;
    })()),
  };

  for (final entry in cases.entries) {
    test('round-trips through inflate: ${entry.key}', () {
      expect(inflate(deflate(entry.value)), entry.value);
    });

    test('output is standard DEFLATE (dart:io reads it): ${entry.key}', () {
      expect(ioInflate(deflate(entry.value)), entry.value);
    });
  }

  test('actually compresses repetitive / structured data', () {
    final xml = cases['score xml']!;
    expect(deflate(xml).length, lessThan(xml.length ~/ 2));
    final rep = cases['repetitive']!;
    expect(deflate(rep).length, lessThan(100)); // 5000 bytes → tiny
  });

  test('a full randomised sweep round-trips exactly', () {
    var seed = 987654321;
    int rnd(int m) => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) % m;
    for (var t = 0; t < 40; t++) {
      final len = rnd(3000);
      final data = Uint8List.fromList([
        for (var i = 0; i < len; i++)
          rnd(t.isEven ? 6 : 256), // low/high entropy
      ]);
      expect(inflate(deflate(data)), data, reason: 'trial $t len $len');
    }
  });
}
