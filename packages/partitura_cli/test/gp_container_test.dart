import 'dart:io';
import 'dart:typed_data';

import 'package:partitura_cli/src/gp_container.dart';
import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  // Direct container contract for the .gpx (v6 BCFZ/BCFS) path: the
  // decompression must extract the well-formed score.gpif XML. This pins the
  // container output independently of the GPIF parser, as a safety net for a
  // clean-room reimplementation of the decompressor.
  group('.gpx container extraction (BCFZ/BCFS)', () {
    Uint8List fixture(String n) => File('test/data/gp/$n').readAsBytesSync();

    test('chords.gpx extracts a GPIF document', () {
      final gpif = readGpifFromGpx(fixture('chords.gpx'));
      expect(gpif.length, greaterThan(10000));
      expect(gpif, startsWith('<?xml version="1.0"'));
      expect(gpif, contains('<GPIF>'));
      expect(gpif, contains('<GPRevision>11686</GPRevision>'));
    });

    test('slides.gpx extracts a GPIF document', () {
      final gpif = readGpifFromGpx(fixture('slides.gpx'));
      expect(gpif, startsWith('<?xml version="1.0"'));
      expect(gpif, contains('<GPIF>'));
      // The decompressed content round-trips through the GPIF parser.
      final score = scoreFromGpif(gpif);
      expect(score.glissandos, hasLength(5));
    });

    test('rejects a non-BCFS blob', () {
      expect(
          () => readGpifFromGpx(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
          throwsFormatException);
    });
  });
  test('writeGpFromGpif produces a ZIP with score.gpif that reads back', () {
    final gpif = scoreToGpif(Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'e3:q g3 b3 e4',
    ));
    final gp = writeGpFromGpif(gpif);
    // ZIP local-file-header signature "PK\x03\x04".
    expect(gp.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
    expect(readGpifFromGp(gp), gpif);
  });

  test('a full .gp round-trips the score through the container', () {
    final source = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'e3:q g3 b3 e4 | c4:h g4',
    );
    final back =
        scoreFromGpif(readGpifFromGp(writeGpFromGpif(scoreToGpif(source))));
    final names = back.measures
        .expand((m) => m.elements)
        .whereType<NoteElement>()
        .expand((n) => n.pitches)
        .map((p) => p.toString());
    expect(names, ['E3', 'G3', 'B3', 'E4', 'C4', 'G4']);
  });

  test('rejects non-zip bytes', () {
    expect(() => readGpifFromGp(Uint8List.fromList([1, 2, 3, 4])),
        throwsFormatException);
  });
}
