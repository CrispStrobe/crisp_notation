import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

/// Live verification for lyrics: real paint output (pixel sampling of the
/// text ink), tap behavior on the grown hit regions, and multi-system
/// interplay.
void main() {
  setUpAll(setUpPartituraForTests);

  Score song() => Score.simple(
        notes: 'c5:q d5 e5 f5',
        lyrics: 'twin- kle lit- tle',
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
    if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
      return const Color(0xFFFFFFFF); // outside the image = blank
    }
    final i = (y * image.width + x) * 4;
    return Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  }

  // Alpha participates: unpainted (transparent) pixels must not read as
  // black ink.
  bool near(Color a, Color b, int tolerance) =>
      ((a.a - b.a) * 255).abs() < tolerance &&
      ((a.r - b.r) * 255).abs() < tolerance &&
      ((a.g - b.g) * 255).abs() < tolerance &&
      ((a.b - b.b) * 255).abs() < tolerance;

  /// Counts pixels within [radius] px of the staff-space [anchor] whose
  /// color is near [target].
  Future<int> countNear(
    WidgetTester tester,
    RenderStaffView staff,
    math.Point<double> anchor,
    Color target, {
    int radius = 14,
    int tolerance = 60,
  }) async {
    final (image, data) = await capture(tester);
    final staffTopLeft = tester.getTopLeft(find.bySubtype<StaffView>());
    final boundaryTopLeft =
        tester.getTopLeft(find.byType(RepaintBoundary).last);
    final local = staffTopLeft - boundaryTopLeft + staff.staffToLocal(anchor);
    var count = 0;
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        final c = colorAt(
          image,
          data,
          local.dx.round() + dx,
          local.dy.round() + dy,
        );
        if (near(c, target, tolerance)) count++;
      }
    }
    return count;
  }

  math.Point<double> lyricAnchorOf(RenderStaffView staff, String id) {
    final text = staff.scoreLayout!.primitives
        .whereType<TextPrimitive>()
        .firstWhere((t) => t.elementId == id);
    return text.position;
  }

  testWidgets('lyric text actually paints below the staff', (tester) async {
    await tester.pumpWidget(scene(StaffView(score: song(), staffSpace: 12)));
    final staff =
        tester.renderObject<RenderStaffView>(find.bySubtype<StaffView>());
    final anchor = lyricAnchorOf(staff, 'e0');
    // Sample slightly above the baseline, where the glyph body sits.
    final inked = await countNear(
      tester,
      staff,
      math.Point(anchor.x, anchor.y - 0.5),
      PartituraTheme.standard.noteColor,
    );
    expect(inked, greaterThan(8), reason: 'syllable ink expected');
    // Control: no ink at the same spot without lyrics.
    await tester.pumpWidget(scene(StaffView(
      score: Score.simple(notes: 'c5:q d5 e5 f5'),
      staffSpace: 12,
    )));
    final blank = await countNear(
      tester,
      staff,
      math.Point(anchor.x, anchor.y - 0.5),
      PartituraTheme.standard.noteColor,
    );
    expect(blank, 0);
  });

  testWidgets('highlighting a note recolors its syllable', (tester) async {
    await tester.pumpWidget(scene(StaffView(
      score: song(),
      staffSpace: 12,
      highlightedIds: const {'e0'},
    )));
    final staff =
        tester.renderObject<RenderStaffView>(find.bySubtype<StaffView>());
    final anchor = lyricAnchorOf(staff, 'e0');
    final highlighted = await countNear(
      tester,
      staff,
      math.Point(anchor.x, anchor.y - 0.5),
      PartituraTheme.standard.highlightColor,
    );
    expect(highlighted, greaterThan(8));
    // The un-highlighted neighbor stays note-colored.
    final neighbor = lyricAnchorOf(staff, 'e1');
    final plain = await countNear(
      tester,
      staff,
      math.Point(neighbor.x, neighbor.y - 0.5),
      PartituraTheme.standard.noteColor,
    );
    expect(plain, greaterThan(8));
  });

  testWidgets('tapping a syllable reports its note element', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(scene(StaffView(
      score: song(),
      staffSpace: 12,
      onElementTap: tapped.add,
    )));
    final staff =
        tester.renderObject<RenderStaffView>(find.bySubtype<StaffView>());
    final anchor = lyricAnchorOf(staff, 'e2');
    final topLeft = tester.getTopLeft(find.bySubtype<StaffView>());
    await tester.tapAt(
        topLeft + staff.staffToLocal(math.Point(anchor.x, anchor.y - 0.5)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, ['e2']);
  });

  testWidgets('lyrics flow with line breaking in MultiSystemView',
      (tester) async {
    final score = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5 | c5:q b4 a4 g4 | c4:w',
      lyrics: 'one two three four five six sev- en eight nine ten e- lev',
    );
    await tester.pumpWidget(scene(SizedBox(
      width: 340,
      child: MultiSystemView(score: score, staffSpace: 10),
    )));
    expect(tester.takeException(), isNull);
    final render = tester
        .renderObject<RenderMultiSystemView>(find.bySubtype<MultiSystemView>());
    final layout = render.multiSystemLayout!;
    expect(layout.systems.length, greaterThan(1));
    final total = layout.systems
        .map((s) => s.layout.primitives.whereType<TextPrimitive>().length)
        .reduce((a, b) => a + b);
    expect(total, score.lyrics.length);
  });

  testWidgets('value-equal score with lyrics does not relayout',
      (tester) async {
    await tester.pumpWidget(scene(StaffView(score: song(), staffSpace: 12)));
    final staff =
        tester.renderObject<RenderStaffView>(find.bySubtype<StaffView>());
    final before = staff.scoreLayout;
    await tester.pumpWidget(scene(StaffView(score: song(), staffSpace: 12)));
    expect(identical(staff.scoreLayout, before), isTrue);
    // Different lyrics = different score = relayout.
    await tester.pumpWidget(scene(StaffView(
      score: Score.simple(
        notes: 'c5:q d5 e5 f5',
        lyrics: 'star light star bright',
      ),
      staffSpace: 12,
    )));
    expect(identical(staff.scoreLayout, before), isFalse);
  });
}
