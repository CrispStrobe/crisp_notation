// Verifies MultiSystemView's elementColors reaches the screen: the coloured
// note paints in its colour, and without elementColors that colour is absent.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

void main() {
  setUpAll(setUpPartituraForTests);

  const green = Color(0xFF43A047);

  Future<int> greenPixels(WidgetTester tester, {required bool coloured}) async {
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
                  elementColors: coloured ? const {'e0': green} : const {},
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
      final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      for (var i = 0; i < data.lengthInBytes; i += 4) {
        final r = data.getUint8(i), g = data.getUint8(i + 1);
        final b = data.getUint8(i + 2);
        if ((r - 0x43).abs() < 45 && (g - 0xA0).abs() < 45 && (b - 0x47).abs() < 45) {
          count++;
        }
      }
    });
    return count;
  }

  testWidgets('elementColors paints a note in its colour', (tester) async {
    final coloured = await greenPixels(tester, coloured: true);
    final plain = await greenPixels(tester, coloured: false);
    expect(coloured, greaterThan(20),
        reason: 'the coloured note should add green ink');
    expect(plain * 3, lessThan(coloured),
        reason: 'without elementColors there should be (near) no green');
  });
}
