import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

/// Live paint verification: renders to an image and samples pixels, so
/// these tests check what actually reaches the screen (colors, highlight
/// precedence, ghost notes) rather than just render-object state.
void main() {
  setUpAll(setUpPartituraForTests);

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

  Future<(ui.Image, ByteData)> capture(WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).last,
    );
    late ui.Image image;
    late ByteData data;
    await tester.runAsync(() async {
      image = await boundary.toImage();
      data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });
    return (image, data);
  }

  Color colorAt(ui.Image image, ByteData data, int x, int y) {
    final i = (y.clamp(0, image.height - 1) * image.width +
            x.clamp(0, image.width - 1)) *
        4;
    return Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  }

  bool near(Color a, Color b, int tolerance) =>
      ((a.r - b.r) * 255).abs() < tolerance &&
      ((a.g - b.g) * 255).abs() < tolerance &&
      ((a.b - b.b) * 255).abs() < tolerance;

  /// Offset of a staff-space point inside the RepaintBoundary's image.
  Offset boundaryLocalOf(
    WidgetTester tester,
    RenderStaffView staff,
    math.Point<double> point,
  ) {
    final staffTopLeft = tester.getTopLeft(find.bySubtype<StaffView>());
    final boundaryTopLeft =
        tester.getTopLeft(find.byType(RepaintBoundary).last);
    return staffTopLeft - boundaryTopLeft + staff.staffToLocal(point);
  }

  /// Counts pixels of (roughly) [expected] color inside the bounding box of
  /// the element's notehead. Robust against hollow noteheads (whole/half)
  /// and anti-aliasing: ink is asserted to exist, not to sit at one pixel.
  Future<int> noteheadPixelsNear(
    WidgetTester tester,
    RenderStaffView staff,
    String elementId,
    Color expected, {
    int tolerance = 32,
  }) async {
    final glyph = staff.scoreLayout!.primitives
        .whereType<GlyphPrimitive>()
        .firstWhere(
          (g) => g.elementId == elementId && g.smuflName.startsWith('notehead'),
        );
    final topLeft = boundaryLocalOf(
      tester,
      staff,
      math.Point(glyph.position.x, glyph.position.y - 0.6),
    );
    final bottomRight = boundaryLocalOf(
      tester,
      staff,
      math.Point(glyph.position.x + 1.8, glyph.position.y + 0.6),
    );
    final (image, data) = await capture(tester);
    var hits = 0;
    for (var y = topLeft.dy.floor(); y <= bottomRight.dy.ceil(); y++) {
      for (var x = topLeft.dx.floor(); x <= bottomRight.dx.ceil(); x++) {
        if (near(colorAt(image, data, x, y), expected, tolerance)) hits++;
      }
    }
    return hits;
  }

  testWidgets('element colors, highlights and staff ink reach the screen',
      (tester) async {
    const green = Color(0xFF43A047);
    const highlight = Color(0xFF1E88E5);
    const ink = Color(0xFF1A1A1A);
    await tester.pumpWidget(scene(
      StaffView(
        score: Score.simple(notes: 'c4:q d4 e4'),
        staffSpace: 12,
        theme: const PartituraTheme(elementColors: {'e0': green}),
        highlightedIds: const {'e1'},
      ),
    ));
    final staff =
        tester.renderObject<RenderStaffView>(find.bySubtype<StaffView>());

    // Each notehead paints in its effective color. (Plain ink pixels also
    // appear in every box — the staff lines run through it — so only the
    // presence of the expected color is asserted; a mis-colored notehead
    // would leave its own color count at ~0.)
    expect(
        await noteheadPixelsNear(tester, staff, 'e0', green), greaterThan(10));
    expect(await noteheadPixelsNear(tester, staff, 'e1', highlight),
        greaterThan(10));
    expect(await noteheadPixelsNear(tester, staff, 'e2', ink), greaterThan(10));
    // And the overridden/highlighted colors don't bleed onto neighbors.
    expect(await noteheadPixelsNear(tester, staff, 'e2', green), 0);
    expect(await noteheadPixelsNear(tester, staff, 'e0', highlight), 0);

    // Top staff line far right, clear of any note: dark staff ink.
    final (image, data) = await capture(tester);
    final lineSample = boundaryLocalOf(
      tester,
      staff,
      math.Point(staff.scoreLayout!.width - 4, 0.0),
    );
    expect(
      colorAt(image, data, lineSample.dx.round(), lineSample.dy.round())
          .computeLuminance(),
      lessThan(0.5),
      reason: 'staff line missing',
    );
    // Empty area above the staff: white background.
    final skySample = boundaryLocalOf(
      tester,
      staff,
      math.Point(staff.scoreLayout!.width - 4, -2.5),
    );
    expect(
      near(
        colorAt(image, data, skySample.dx.round(), skySample.dy.round()),
        Colors.white,
        16,
      ),
      isTrue,
    );
  });

  testWidgets('highlight wins over a per-element color', (tester) async {
    const green = Color(0xFF43A047);
    const highlight = Color(0xFFF4511E);
    await tester.pumpWidget(scene(
      StaffView(
        score: Score.simple(notes: 'c5:w'),
        staffSpace: 12,
        theme: const PartituraTheme(
          elementColors: {'e0': green},
          highlightColor: highlight,
        ),
        highlightedIds: const {'e0'},
      ),
    ));
    final staff =
        tester.renderObject<RenderStaffView>(find.bySubtype<StaffView>());
    expect(await noteheadPixelsNear(tester, staff, 'e0', highlight),
        greaterThan(10));
    expect(await noteheadPixelsNear(tester, staff, 'e0', green), 0,
        reason: 'the element color must not shine through the highlight');
  });

  testWidgets('StaffView.elementColors colors notes and overrides the theme',
      (tester) async {
    const themeGreen = Color(0xFF43A047);
    const renderRed = Color(0xFFD32F2F);
    await tester.pumpWidget(scene(
      StaffView(
        score: Score.simple(notes: 'c4:q d4'),
        staffSpace: 12,
        theme: const PartituraTheme(elementColors: {'e0': themeGreen}),
        elementColors: const {'e0': renderRed, 'e1': renderRed},
      ),
    ));
    final staff =
        tester.renderObject<RenderStaffView>(find.bySubtype<StaffView>());
    // The render-param color wins over the theme's for e0…
    expect(await noteheadPixelsNear(tester, staff, 'e0', renderRed),
        greaterThan(10));
    expect(await noteheadPixelsNear(tester, staff, 'e0', themeGreen), 0);
    // …and colors e1, which the theme did not.
    expect(await noteheadPixelsNear(tester, staff, 'e1', renderRed),
        greaterThan(10));
  });

  testWidgets('ghost note paints during the drag and vanishes after',
      (tester) async {
    await tester.pumpWidget(scene(
      InteractiveStaff(
        score: Score.simple(notes: 'c5:q | r:q'),
        staffSpace: 12,
        onStaffTap: (_) {},
      ),
    ));
    final staff =
        tester.renderObject<RenderStaffView>(find.bySubtype<StaffView>());
    final measure1 = staff.scoreLayout!.measureRegions[1];
    final targetStaffPoint = math.Point(measure1.endX - 0.4, 4.0);
    final staffTopLeft = tester.getTopLeft(find.bySubtype<StaffView>());
    final targetGlobal = staffTopLeft + staff.staffToLocal(targetStaffPoint);

    Future<int> bluishPixels() async {
      final (image, data) = await capture(tester);
      final ghost = staff.ghostNote;
      final aroundStaff = ghost == null
          ? targetStaffPoint
          : math.Point(ghost.xSpaces, (8 - ghost.staffPosition) / 2);
      final topLeft = boundaryLocalOf(
        tester,
        staff,
        math.Point(aroundStaff.x - 1.2, aroundStaff.y - 0.8),
      );
      var count = 0;
      for (var dy = 0; dy < 20; dy++) {
        for (var dx = 0; dx < 30; dx++) {
          final c = colorAt(
            image,
            data,
            topLeft.dx.round() + dx,
            topLeft.dy.round() + dy,
          );
          if (c.b > c.r + 0.1 && c.computeLuminance() < 0.93) count++;
        }
      }
      return count;
    }

    expect(await bluishPixels(), 0, reason: 'no ghost before the drag');

    final gesture =
        await tester.startGesture(targetGlobal - const Offset(0, 30));
    await gesture.moveTo(targetGlobal);
    await tester.pump();
    expect(staff.ghostNote, isNotNull);
    expect(await bluishPixels(), greaterThan(10),
        reason: 'ghost visible during the drag');

    await gesture.up();
    await tester.pump();
    expect(staff.ghostNote, isNull);
    expect(await bluishPixels(), 0, reason: 'ghost gone after the drop');
  });

  testWidgets('kid mode paints visibly bolder staff lines', (tester) async {
    Future<double> darkFraction(PartituraTheme theme) async {
      await tester.pumpWidget(scene(
        StaffView(
          score: Score.simple(notes: 'c5:w'),
          staffSpace: 12,
          theme: theme,
        ),
      ));
      final staff =
          tester.renderObject<RenderStaffView>(find.bySubtype<StaffView>());
      final (image, data) = await capture(tester);
      final x = staff.scoreLayout!.width - 4;
      var dark = 0;
      const samples = 60;
      for (var i = 0; i < samples; i++) {
        final local = boundaryLocalOf(
          tester,
          staff,
          math.Point(x, -0.5 + i * (5.0 / samples)),
        );
        final color = colorAt(image, data, local.dx.round(), local.dy.round());
        if (color.computeLuminance() < 0.5) dark++;
      }
      return dark / samples;
    }

    final standard = await darkFraction(PartituraTheme.standard);
    final kids = await darkFraction(PartituraTheme.kids);
    expect(standard, greaterThan(0));
    expect(kids, greaterThan(standard),
        reason: 'kid lines standard=$standard kids=$kids');
  });
}
