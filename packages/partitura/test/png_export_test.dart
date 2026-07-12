import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

/// PNG signature bytes.
const _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// Reads the width from a PNG's IHDR chunk (bytes 16–19, big-endian).
int _pngWidth(List<int> b) =>
    (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];

void main() {
  setUpAll(setUpPartituraForTests);

  testWidgets('renders a notation layout to a valid PNG', (tester) async {
    final layout = const LayoutEngine().layout(
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | g4:h a4',
      ),
      LayoutSettings(metadata: Bravura.metadataOrNull!),
    );

    late final List<int> png;
    await tester.runAsync(() async {
      png = await renderLayoutToPng(layout, staffSpace: 16);
    });

    expect(png.sublist(0, 8), _pngMagic);
    // The image is sized to the layout width (× staffSpace).
    expect(_pngWidth(png), (layout.width * 16).ceil());
    expect(png.length, greaterThan(200)); // non-trivial content
  });

  testWidgets('renders a tab layout to PNG', (tester) async {
    final layout = const TabLayoutEngine().layout(
      Score.simple(notes: 'e2:q a2 d3 g3'),
      Tuning.standardGuitar,
      LayoutSettings(metadata: Bravura.metadataOrNull!),
    );
    late final List<int> png;
    await tester.runAsync(() async {
      png = await renderLayoutToPng(layout);
    });
    expect(png.sublist(0, 8), _pngMagic);
  });

  testWidgets('writes a PNG file that decodes', (tester) async {
    final layout = const LayoutEngine().layout(
      Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | g4:h a4',
      ),
      LayoutSettings(metadata: Bravura.metadataOrNull!),
    );
    late final List<int> png;
    await tester.runAsync(() async {
      png = await renderLayoutToPng(layout, staffSpace: 24);
    });
    final dir = Directory.systemTemp.createTempSync('partitura_png');
    final file = File('${dir.path}/score.png')..writeAsBytesSync(png);
    expect(file.lengthSync(), png.length);
    dir.deleteSync(recursive: true);
  });
}
