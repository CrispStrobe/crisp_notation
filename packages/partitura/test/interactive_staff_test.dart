import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

Widget wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    );

void main() {
  setUpAll(setUpPartituraForTests);

  RenderStaffView renderStaff(WidgetTester tester) =>
      tester.renderObject<RenderStaffView>(find.bySubtype<StaffView>());

  testWidgets('tap on an element reports the id, not a StaffTarget',
      (tester) async {
    final elementTaps = <String>[];
    final staffTaps = <StaffTarget>[];
    await tester.pumpWidget(
      wrap(InteractiveStaff(
        score: Score.simple(notes: 'c4:q d4 e4 f4'),
        staffSpace: 12,
        onElementTap: elementTaps.add,
        onStaffTap: staffTaps.add,
      )),
    );
    final staff = renderStaff(tester);
    final region =
        staff.scoreLayout!.regions.firstWhere((r) => r.elementId == 'e2');
    final center = (region.bounds.topLeft + region.bounds.bottomRight) * 0.5;
    final topLeft = tester.getTopLeft(find.bySubtype<StaffView>());
    await tester.tapAt(topLeft + staff.staffToLocal(center));
    expect(elementTaps, ['e2']);
    expect(staffTaps, isEmpty);
  });

  testWidgets('tap on empty staff quantizes to a StaffTarget', (tester) async {
    final staffTaps = <StaffTarget>[];
    await tester.pumpWidget(
      wrap(InteractiveStaff(
        score: Score.simple(notes: 'c5:q | r:q'),
        staffSpace: 12,
        onStaffTap: staffTaps.add,
      )),
    );
    final staff = renderStaff(tester);
    final topLeft = tester.getTopLeft(find.bySubtype<StaffView>());
    final measure1 = staff.scoreLayout!.measureRegions[1];

    // Tap the bottom staff line (position 0) inside measure 1, at an x
    // clear of the rest element's (slop-inflated) hit box.
    final local = staff.staffToLocal(math.Point(measure1.endX - 0.4, 4.0));
    await tester.tapAt(topLeft + local);
    expect(staffTaps, hasLength(1));
    expect(staffTaps.single.staffPosition, 0);
    expect(staffTaps.single.measureIndex, 1);

    // A space between lines quantizes too: position 5 = y 1.5 (measure 0).
    final measure0 = staff.scoreLayout!.measureRegions[0];
    await tester.tapAt(
      topLeft + staff.staffToLocal(math.Point(measure0.endX - 0.4, 1.5)),
    );
    expect(staffTaps, hasLength(2));
    expect(staffTaps.last.staffPosition, 5);
    expect(staffTaps.last.measureIndex, 0);
  });

  testWidgets('StaffTarget.pitchFor maps positions through the clef',
      (tester) async {
    const target = StaffTarget(staffPosition: 4, measureIndex: 0);
    expect(target.pitchFor(Clef.treble), const Pitch(Step.b));
    expect(target.pitchFor(Clef.bass), const Pitch(Step.d, octave: 3));
    expect(
      target.pitchFor(Clef.treble, preferredAlter: -1),
      const Pitch(Step.b, alter: -1),
    );
  });

  testWidgets('drag shows a quantized ghost note and drops a StaffTarget',
      (tester) async {
    final staffTaps = <StaffTarget>[];
    await tester.pumpWidget(
      wrap(InteractiveStaff(
        score: Score.simple(notes: 'c5:q | r:q'),
        staffSpace: 12,
        ghostDuration: NoteDuration.half,
        onStaffTap: staffTaps.add,
      )),
    );
    final staff = renderStaff(tester);
    final topLeft = tester.getTopLeft(find.bySubtype<StaffView>());
    final measure1 = staff.scoreLayout!.measureRegions[1];
    // x clear of the rest's hit box so the drop lands on empty staff.
    final start = staff.staffToLocal(math.Point(measure1.endX - 0.4, 4.0));
    final end = staff.staffToLocal(math.Point(measure1.endX - 0.4, 1.0));

    final gesture = await tester.startGesture(topLeft + start);
    // Move well past the touch slop so the pan gesture is accepted.
    await gesture.moveTo(topLeft + end);
    await tester.pump();
    expect(staff.ghostNote, isNotNull);
    expect(staff.ghostNote!.duration, NoteDuration.half);
    // y = 1.0 -> staff position 6.
    expect(staff.ghostNote!.staffPosition, 6);

    await gesture.up();
    await tester.pump();
    expect(staff.ghostNote, isNull, reason: 'ghost clears on drop');
    expect(staffTaps, hasLength(1));
    expect(staffTaps.single.staffPosition, 6);
    expect(staffTaps.single.measureIndex, 1);
  });

  testWidgets('showGhostNote: false suppresses the preview', (tester) async {
    await tester.pumpWidget(
      wrap(InteractiveStaff(
        score: Score.simple(notes: 'c5:q'),
        staffSpace: 12,
        showGhostNote: false,
        onStaffTap: (_) {},
      )),
    );
    final staff = renderStaff(tester);
    final topLeft = tester.getTopLeft(find.bySubtype<StaffView>());
    final gesture = await tester.startGesture(topLeft + const Offset(60, 40));
    await gesture.moveBy(const Offset(10, 10));
    await tester.pump();
    expect(staff.ghostNote, isNull);
    await gesture.up();
  });

  testWidgets('kid mode hit targets are at least 44x44 px at default size',
      (tester) async {
    // Default staff size = 12 px per staff space (RenderStaffView default).
    await tester.pumpWidget(
      wrap(InteractiveStaff(
        score: Score.simple(notes: 'c5:w'), // whole note: smallest region
        staffSpace: 12,
        theme: PartituraTheme.kids,
        onElementTap: (_) {},
      )),
    );
    final staff = renderStaff(tester);
    final region = staff.scoreLayout!.regions.single.bounds;
    final slop = PartituraTheme.kids.hitSlop;
    final widthPx = (region.width + 2 * slop) * staff.scale;
    final heightPx = (region.height + 2 * slop) * staff.scale;
    expect(widthPx, greaterThanOrEqualTo(44));
    expect(heightPx, greaterThanOrEqualTo(44));
  });

  testWidgets('highlight change through InteractiveStaff never relayouts',
      (tester) async {
    final score = Score.simple(notes: 'c4:q d4 e4');
    Widget build(Set<String> highlights) => wrap(InteractiveStaff(
          score: score,
          staffSpace: 12,
          highlightedIds: highlights,
          onElementTap: (_) {},
        ));
    await tester.pumpWidget(build(const {}));
    final layoutBefore = renderStaff(tester).scoreLayout;
    await tester.pumpWidget(build(const {'e1'}));
    expect(identical(renderStaff(tester).scoreLayout, layoutBefore), isTrue);
  });
}
