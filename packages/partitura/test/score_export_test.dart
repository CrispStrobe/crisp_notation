import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

const _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

Score score() => Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5',
    );

GrandStaff piano() => GrandStaff(
      upper: Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:q d5 e5 f5 | g5:q a5 b5 c6',
      ),
      lower: Score.simple(
        clef: Clef.bass,
        timeSignature: TimeSignature.fourFour,
        notes: 'c3:h e3 | g3:h c4',
      ),
    );

// The export helpers do real async work (image encoding, asset loading), so
// they must run in a real async zone — `tester.runAsync`, not the fake clock.
void main() {
  setUpAll(setUpPartituraForTests);

  testWidgets('exportScoreToPng returns real PNG bytes (C8)', (tester) async {
    final bytes =
        await tester.runAsync(() => exportScoreToPng(score(), staffSpace: 10));
    expect(bytes!.length, greaterThan(200));
    expect(bytes.sublist(0, 8), _pngMagic);
  });

  testWidgets('exportScoreToSvg embeds the engraving font (C8)',
      (tester) async {
    final svg =
        await tester.runAsync(() => exportScoreToSvg(score(), staffSpace: 10));
    expect(svg!, startsWith('<?xml'));
    expect(svg, contains('<svg'));
    expect(svg, contains('@font-face'));
    expect(svg, contains('data:font/otf;base64,'));
    expect(svg, contains('font-family:"Bravura"'));

    // embedFont: false references the family without inlining the bytes.
    final plain = await tester
        .runAsync(() => exportScoreToSvg(score(), embedFont: false));
    expect(plain!, contains('<svg'));
    expect(plain, isNot(contains('@font-face')));
  });

  testWidgets('grand-staff PNG + SVG overloads (C8)', (tester) async {
    final png = await tester
        .runAsync(() => exportGrandStaffToPng(piano(), staffSpace: 9));
    expect(png!.sublist(0, 8), _pngMagic);

    final svg = await tester
        .runAsync(() => exportGrandStaffToSvg(piano(), staffSpace: 9));
    expect(svg!, contains('<svg'));
    expect(svg, contains('data:font/otf;base64,'));
  });
}
