import 'dart:math' as math;

import 'package:flutter/material.dart' hide Interval;
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

/// Live verification for Score.transposedBy: the transposed score
/// renders, ids keep working for taps/highlights, and the drawing
/// actually changed (noteheads moved, key signature updated).
void main() {
  setUpAll(setUpPartituraForTests);

  Score original() => Score.simple(
        keySignature: const KeySignature(0),
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q e4 g4 c5',
      );

  Widget scene(Score score, {void Function(String)? onTap}) => MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: StaffView(
              score: score,
              staffSpace: 10,
              onElementTap: onTap,
            ),
          ),
        ),
      );

  testWidgets('transposed score renders with moved noteheads and new key',
      (tester) async {
    await tester.pumpWidget(scene(original()));
    final staff =
        tester.renderObject<RenderStaffView>(find.bySubtype<StaffView>());
    double headY(ScoreLayout layout, String id) => layout.primitives
        .whereType<GlyphPrimitive>()
        .firstWhere(
            (g) => g.elementId == id && g.smuflName.startsWith('notehead'))
        .position
        .y;
    final before = staff.scoreLayout!;
    final beforeY = headY(before, 'e0');
    final beforeSharps = before.primitives
        .whereType<GlyphPrimitive>()
        .where((g) =>
            g.smuflName == SmuflGlyph.accidentalSharp && g.elementId == null)
        .length;
    expect(beforeSharps, 0);

    await tester
        .pumpWidget(scene(original().transposedBy(Interval.majorSecond)));
    expect(tester.takeException(), isNull);
    final after = staff.scoreLayout!;
    // D major: two leading sharps, notehead one staff position higher.
    final afterSharps = after.primitives
        .whereType<GlyphPrimitive>()
        .where((g) =>
            g.smuflName == SmuflGlyph.accidentalSharp && g.elementId == null)
        .length;
    expect(afterSharps, 2);
    expect(headY(after, 'e0'), beforeY - 0.5);
  });

  testWidgets('ids survive transposition: taps and highlights still work',
      (tester) async {
    final tapped = <String>[];
    final transposed = original().transposedBy(Interval.perfectFourth);
    await tester.pumpWidget(scene(transposed, onTap: tapped.add));
    final staff =
        tester.renderObject<RenderStaffView>(find.bySubtype<StaffView>());
    final region = staff.scoreLayout!.regions
        .firstWhere((r) => r.elementId == 'e2')
        .bounds;
    final center = (region.topLeft + region.bottomRight) * 0.5;
    final topLeft = tester.getTopLeft(find.bySubtype<StaffView>());
    await tester
        .tapAt(topLeft + staff.staffToLocal(math.Point(center.x, center.y)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, ['e2']);
    // The playback timeline of the transposed score drives the same ids.
    final timeline = playbackTimeline(transposed);
    expect(timeline.map((n) => n.elementId), ['e0', 'e1', 'e2', 'e3']);
  });
}
