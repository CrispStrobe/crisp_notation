import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_setup.dart';

/// Bar numbers must label the FIRST system too, so the toggle has a visible
/// effect even on a one-system score. Verified by pixels: the only difference
/// between the two renders is the added "1" label, so turning measure numbers
/// on adds ink.
void main() {
  setUpAll(setUpCrispNotationForTests);

  // One 4/4 measure → a single system.
  Score oneMeasure() => Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4',
      );

  Widget scene(Widget staff) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              child: ColoredBox(color: Colors.white, child: staff),
            ),
          ),
        ),
      );

  Future<int> inkPixels(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).last,
    );
    late ByteData data;
    late ui.Image image;
    await tester.runAsync(() async {
      image = await boundary.toImage();
      data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });
    var ink = 0;
    for (var p = 0; p < image.width * image.height; p++) {
      final i = p * 4;
      final r = data.getUint8(i);
      final g = data.getUint8(i + 1);
      final b = data.getUint8(i + 2);
      // Dark-ish pixel on the white background = drawn ink.
      if (r + g + b < 3 * 160) ink++;
    }
    return ink;
  }

  testWidgets('measure numbers label the first (only) system', (tester) async {
    await tester.pumpWidget(
      scene(MultiSystemView(
        score: oneMeasure(),
        staffSpace: 12,
        showMeasureNumbers: false,
      )),
    );
    final off = await inkPixels(tester);

    await tester.pumpWidget(
      scene(MultiSystemView(
        score: oneMeasure(),
        staffSpace: 12,
        showMeasureNumbers: true,
      )),
    );
    final on = await inkPixels(tester);

    // The single system is now numbered ("1"), so more ink is drawn — before
    // this fix a one-system score showed no bar number at all.
    expect(on, greaterThan(off));
  });
}
