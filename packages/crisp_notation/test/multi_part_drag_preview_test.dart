// Verifies InteractiveMultiPartView.dragPreviewOpacity (C12, as single-part
// C10b): while an element is dragged the view hides it from the normal pass
// and re-paints the *real* glyph following the pointer, snapped to the part
// and line/space under it. Also that part-aware hits report the DOCUMENT part
// when a system hides some parts.

import 'dart:ui' as ui;

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step, PageMetrics;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_setup.dart';

void main() {
  setUpAll(setUpCrispNotationForTests);

  const green = Color(0xFF43A047);
  const staffSpace = 10.0;

  Score part(String p, Clef clef, Pitch pitch) => Score(
        clef: clef,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            for (var i = 0; i < 4; i++)
              NoteElement.note(pitch, NoteDuration.quarter, id: '$p$i'),
          ]),
        ],
      );

  final duo = MultiPartScore([
    part('a', Clef.treble, const Pitch(Step.g, octave: 4)),
    part('b', Clef.bass, const Pitch(Step.c, octave: 3)),
  ]);

  // (green pixel count, mean y) of the last RepaintBoundary.
  Future<(int, double)> greenCentroid(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).last,
    );
    var count = 0;
    var sumY = 0.0;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final w = image.width;
      final data =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      for (var i = 0; i < data.lengthInBytes; i += 4) {
        final r = data.getUint8(i), g = data.getUint8(i + 1);
        final b = data.getUint8(i + 2);
        if ((r - 0x43).abs() < 45 &&
            (g - 0xA0).abs() < 45 &&
            (b - 0x47).abs() < 45) {
          count++;
          sumY += ((i ~/ 4) ~/ w).toDouble();
        }
      }
    });
    return (count, count == 0 ? 0.0 : sumY / count);
  }

  Future<ElementRegionController> pump(WidgetTester tester,
      {double? opacity}) async {
    final controller = ElementRegionController();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: RepaintBoundary(
            child: ColoredBox(
              color: Colors.white,
              child: InteractiveMultiPartView(
                document: duo,
                metrics: const PageMetrics(width: 50, height: 40),
                staffSpace: staffSpace,
                elementColors: const {'a1': green},
                dragPreviewOpacity: opacity,
                controller: controller,
                onElementDragEnd: (_, __, ___) {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return controller;
  }

  testWidgets('the real glyph follows the pointer up', (tester) async {
    final controller = await pump(tester, opacity: 1.0);
    final rest = await greenCentroid(tester);
    expect(rest.$1, greaterThan(20), reason: 'the green note is visible');

    final topLeft = tester.getTopLeft(find.byType(InteractiveMultiPartView));
    final region = controller.elementRegions.firstWhere((r) => r.id == 'a1');
    final gesture = await tester.startGesture(topLeft + region.bounds.center);
    await tester.pump();
    await gesture.moveBy(const Offset(0, -3 * staffSpace));
    await tester.pump();

    final dragged = await greenCentroid(tester);
    expect(dragged.$1, greaterThan(20), reason: 'still painted, moved');
    expect(dragged.$2, lessThan(rest.$2 - staffSpace));
    await gesture.up();
    await tester.pump();
    final after = await greenCentroid(tester);
    expect(after.$2, closeTo(rest.$2, 1.0), reason: 'back home on release');
  });

  testWidgets('dragged into the next part, it lands on that staff',
      (tester) async {
    final controller = await pump(tester, opacity: 1.0);
    final rest = await greenCentroid(tester);
    final topLeft = tester.getTopLeft(find.byType(InteractiveMultiPartView));
    final region = controller.elementRegions.firstWhere((r) => r.id == 'a1');
    final gesture = await tester.startGesture(topLeft + region.bounds.center);
    await tester.pump();
    // Down past the staff gap, onto the bass staff.
    await gesture.moveBy(const Offset(0, 9 * staffSpace));
    await tester.pump();
    final dragged = await greenCentroid(tester);
    expect(dragged.$2, greaterThan(rest.$2 + 5 * staffSpace));
    await gesture.up();
  });

  testWidgets('without the option the note stays put while dragged',
      (tester) async {
    final controller = await pump(tester);
    final rest = await greenCentroid(tester);
    final topLeft = tester.getTopLeft(find.byType(InteractiveMultiPartView));
    final region = controller.elementRegions.firstWhere((r) => r.id == 'a1');
    final gesture = await tester.startGesture(topLeft + region.bounds.center);
    await tester.pump();
    await gesture.moveBy(const Offset(0, -3 * staffSpace));
    await tester.pump();
    final dragged = await greenCentroid(tester);
    expect(dragged.$2, closeTo(rest.$2, 1.0));
    await gesture.up();
  });

  testWidgets('a tap reports the document part when parts are hidden',
      (tester) async {
    // An ossia above part a, only in bar 1 of a 30-bar piece: on later
    // systems the ossia is not drawn, so part a is the TOP staff there but
    // still document part 1.
    Score long(String p, Clef clef, Pitch pitch) => Score(
          clef: clef,
          timeSignature: TimeSignature.fourFour,
          measures: [
            for (var b = 0; b < 30; b++)
              Measure([
                for (var i = 0; i < 4; i++)
                  NoteElement.note(pitch, NoteDuration.quarter, id: '$p$b.$i'),
              ]),
          ],
        );
    final doc = MultiPartScore([
      long('a', Clef.treble, const Pitch(Step.g, octave: 4)),
      long('b', Clef.bass, const Pitch(Step.c, octave: 3)),
    ]).withOssia(0, 0, [
      Measure([
        for (var i = 0; i < 4; i++)
          NoteElement.note(const Pitch(Step.e, octave: 5), NoteDuration.quarter,
              id: 'o$i'),
      ]),
    ]);
    final hits = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: InteractiveMultiPartView(
            document: doc,
            metrics: const PageMetrics(width: 60, height: 200),
            staffSpace: 4,
            onStaffTap: (part, _) => hits.add(part),
          ),
        ),
      ),
    ));
    await tester.pump();
    final render = tester.renderObject<RenderMultiPartView>(
        find.byWidgetPredicate((w) => w is MultiPartView));
    final regions = render.elementRegions;
    // The last part-a bar on this page sits on a later system: its staff is
    // the top one there, but it is part 1.
    final later = regions.lastWhere((r) => r.id.startsWith('a'));
    expect(later.measureIndex, greaterThan(4), reason: 'a later system');
    final hit = render.targetAt(later.bounds.center)!;
    expect(hit.partIndex, 1);
    expect(hit.target.staffIndex, 1);
    // And on the first system, where the ossia is drawn, it is still part 1.
    final first = regions.firstWhere((r) => r.id == 'a0.0');
    expect(render.targetAt(first.bounds.center)!.partIndex, 1);
    expect(
        render
            .targetAt(regions.firstWhere((r) => r.id == 'o0').bounds.center)!
            .partIndex,
        0);
  });
}
