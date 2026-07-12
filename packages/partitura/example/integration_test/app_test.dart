import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:partitura/partitura.dart';
import 'package:partitura_example/main.dart' as app;

/// End-to-end test: boots the real example app (real asset bundle, real
/// Bravura font, real gestures) and plays the interactive demo.
/// Run on a device: `flutter test integration_test -d macos`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('gallery renders and the interactive demo plays', (tester) async {
    await app.main();
    await tester.pumpAndSettle();

    // Gallery: corpus cards render real notation without errors.
    expect(find.text('C major scale (treble)'), findsOneWidget);
    expect(find.bySubtype<StaffView>(), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Switch to the interactive screen.
    await tester.tap(find.text('Interactive'));
    await tester.pumpAndSettle();

    final staffFinder = find.bySubtype<StaffView>().first;
    final staff = tester.renderObject<RenderStaffView>(staffFinder);
    expect(staff.scoreLayout, isNotNull, reason: 'font metadata loaded');
    expect(staff.scoreLayout!.regions, isEmpty, reason: 'starts empty');

    // Tap an empty spot on the bottom line: a note appears. (The measures
    // start empty and thus zero-width; aim between the first measure's
    // start and the end of the staff.)
    final topLeft = tester.getTopLeft(staffFinder);
    final layout = staff.scoreLayout!;
    final x = (layout.measureRegions.first.startX + layout.width) / 2;
    await tester.tapAt(topLeft + staff.staffToLocal(math.Point(x, 4.0)));
    await tester.pumpAndSettle();
    expect(staff.scoreLayout!.regions, hasLength(1));

    // Tap the placed note: it gets selected (highlighted).
    final region = staff.scoreLayout!.regions.single;
    final center = (region.bounds.topLeft + region.bounds.bottomRight) * 0.5;
    await tester.tapAt(topLeft + staff.staffToLocal(center));
    await tester.pumpAndSettle();
    expect(staff.highlightedIds, hasLength(1));

    // Kid mode switch relayouts with bolder lines, no errors.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Pick the half-note duration (second segment) and place another note:
    // the new notehead must be hollow.
    final durationTexts = find.descendant(
      of: find.byType(SegmentedButton<NoteDuration>),
      matching: find.byType(Text),
    );
    await tester.tap(durationTexts.at(1));
    await tester.pumpAndSettle();
    final layout2 = staff.scoreLayout!;
    await tester.tapAt(
      tester.getTopLeft(staffFinder) +
          staff.staffToLocal(
            math.Point(
              (layout2.measureRegions.first.startX + layout2.width) / 2,
              2.0,
            ),
          ),
    );
    await tester.pumpAndSettle();
    expect(
      staff.scoreLayout!.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == 'noteheadHalf'),
      isNotEmpty,
    );

    // Clear resets the board.
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(staff.scoreLayout!.regions, isEmpty);
  });
}
