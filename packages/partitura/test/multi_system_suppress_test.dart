// Verifies MultiSystemView.suppressElementIds (C10a): a suppressed element's
// primitives are skipped entirely, so no ink survives — even ink explicitly
// coloured via elementColors. This is the clean, theme-independent hide the
// live-drag preview relies on (the app draws its own ghost in the note's place).

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

void main() {
  setUpAll(setUpPartituraForTests);

  const green = Color(0xFF43A047);

  // Green ink on screen with the first note ('e0') coloured green and either
  // shown or suppressed.
  Future<int> greenPixels(WidgetTester tester, {required bool suppress}) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              child: ColoredBox(
                color: Colors.white,
                child: MultiSystemView(
                  score: Score.simple(notes: 'c4:q d4 e4'),
                  elementColors: const {'e0': green},
                  suppressElementIds: suppress ? const {'e0'} : const {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).last,
    );
    var count = 0;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      for (var i = 0; i < data.lengthInBytes; i += 4) {
        final r = data.getUint8(i), g = data.getUint8(i + 1);
        final b = data.getUint8(i + 2);
        if ((r - 0x43).abs() < 45 &&
            (g - 0xA0).abs() < 45 &&
            (b - 0x47).abs() < 45) {
          count++;
        }
      }
    });
    return count;
  }

  testWidgets('suppressElementIds omits the element entirely', (tester) async {
    final shown = await greenPixels(tester, suppress: false);
    final hidden = await greenPixels(tester, suppress: true);
    expect(
      shown,
      greaterThan(20),
      reason: 'the coloured note should paint its green ink',
    );
    // A clean hide: colouring the note the background was the old hack; here the
    // note is *skipped*, so even its explicit green ink is gone.
    expect(
      hidden * 5,
      lessThan(shown),
      reason: 'suppressing the id should remove (near) all of its ink',
    );
  });
}
