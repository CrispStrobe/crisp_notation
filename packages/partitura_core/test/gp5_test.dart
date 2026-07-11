import 'dart:typed_data';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// The GP5 reader's positive path is validated against real binaries in
/// `partitura_cli/test/gp_fixtures_test.dart`; this guards the entry point and
/// the header-only edge cases (which need no full file).
void main() {
  test('rejects a file that is not Guitar Pro 5', () {
    // A byte-size string "hello" — not a "v5." version tag.
    final bytes =
        Uint8List.fromList([5, ...'hello'.codeUnits, ...List.filled(25, 0)]);
    expect(() => gp5ToScore(bytes), throwsFormatException);
  });

  test('reads a hand-built minimal GP5 header without a track', () {
    // Enough of a header to reach measureCount=0/trackCount=0 and return an
    // empty (whole-rest) score, exercising the header parse path.
    final b = BytesBuilder();
    void intByteString(String s) {
      b.add(_le32(s.length + 1));
      b.addByte(s.length);
      b.add(s.codeUnits);
    }

    // version: byte-size string in a 30-byte field
    const version = 'FICHIER GUITAR PRO v5.00';
    b.addByte(version.length);
    b.add(version.codeUnits);
    b.add(List.filled(30 - version.length, 0));
    for (var i = 0; i < 9; i++) {
      intByteString(''); // info strings
    }
    b.add(_le32(0)); // notice count
    b.add(_le32(0)); // lyric track
    for (var i = 0; i < 5; i++) {
      b.add(_le32(0)); // measure
      b.add(_le32(0)); // string length
    }
    // page setup
    b.add(List.filled(4 * 2 + 4 * 4, 0));
    b.add(_le32(0)); // proportion
    b.add(_le16(0)); // header/footer
    for (var i = 0; i < 10; i++) {
      intByteString('');
    }
    intByteString(''); // tempo name
    b.add(_le32(120)); // tempo
    b.addByte(0); // key
    b.add(_le32(0)); // octave
    b.add(List.filled(64 * (4 + 6 + 2), 0)); // midi channels
    b.add(List.filled(19 * 2, 0)); // directions
    b.add(_le32(0)); // master reverb
    b.add(_le32(0)); // measure count
    b.add(_le32(0)); // track count
    b.addByte(0); // trailing

    final score = gp5ToScore(b.toBytes());
    expect(score.measures.single.elements.single, isA<RestElement>());
  });
}

List<int> _le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _le32(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
