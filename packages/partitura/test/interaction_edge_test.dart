import 'dart:math' as math;

import 'package:flutter/material.dart';
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

  testWidgets('a StaffView without callbacks ignores taps gracefully',
      (tester) async {
    await tester.pumpWidget(
      wrap(StaffView(score: Score.simple(notes: 'c4:q'), staffSpace: 12)),
    );
    await tester.tap(find.byType(StaffView), warnIfMissed: false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('dropping a drag onto an element fires no StaffTarget',
      (tester) async {
    final staffTaps = <StaffTarget>[];
    final elementTaps = <String>[];
    await tester.pumpWidget(
      wrap(InteractiveStaff(
        score: Score.simple(notes: 'c5:w'),
        staffSpace: 12,
        onStaffTap: staffTaps.add,
        onElementTap: elementTaps.add,
      )),
    );
    final staff = renderStaff(tester);
    final region = staff.scoreLayout!.regions.single.bounds;
    final center = (region.topLeft + region.bottomRight) * 0.5;
    final topLeft = tester.getTopLeft(find.bySubtype<StaffView>());
    final onElement = topLeft + staff.staffToLocal(center);

    final gesture = await tester.startGesture(onElement + const Offset(0, 60));
    await gesture.moveTo(onElement);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(staffTaps, isEmpty, reason: 'drop landed on the note');
    expect(elementTaps, isEmpty, reason: 'a drag is not a tap');
    expect(staff.ghostNote, isNull);
  });

  testWidgets('quantization clamps to the supported ledger range',
      (tester) async {
    await tester.pumpWidget(
      wrap(InteractiveStaff(
        score: Score.simple(notes: 'r:w'),
        staffSpace: 8,
        onStaffTap: (_) {},
      )),
    );
    final staff = renderStaff(tester);
    final width = staff.scoreLayout!.width;

    // Points far above/below the staff clamp to the ledger range −6..14
    // (taps outside the widget can't physically land, so drive the
    // quantizer through the same API the gesture path uses).
    final (high, _) = staff.quantizeStaffPosition(
        staff.staffToLocal(math.Point(width - 3, -20.0)));
    final (low, _) = staff
        .quantizeStaffPosition(staff.staffToLocal(math.Point(width - 3, 25.0)));
    expect(high, 14);
    expect(low, -6);

    // In-range points quantize to the nearest line/space exactly.
    for (var position = -6; position <= 14; position++) {
      final (quantized, _) = staff.quantizeStaffPosition(
        staff.staffToLocal(math.Point(width - 3, (8 - position) / 2)),
      );
      expect(quantized, position);
    }
  });

  testWidgets('every element of a dense score is tappable by id',
      (tester) async {
    final tapped = <String>[];
    final score = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:e d4 e4+g4 f4:s g4:s | r:q a4:h. | b4:w',
    );
    await tester.pumpWidget(
      wrap(InteractiveStaff(
        score: score,
        staffSpace: 14,
        onElementTap: tapped.add,
      )),
    );
    final staff = renderStaff(tester);
    final topLeft = tester.getTopLeft(find.bySubtype<StaffView>());
    final regions = staff.scoreLayout!.regions;
    expect(regions, hasLength(8));
    for (final region in regions) {
      tapped.clear();
      final center = (region.bounds.topLeft + region.bounds.bottomRight) * 0.5;
      await tester.tapAt(topLeft + staff.staffToLocal(center));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tapped, [region.elementId],
          reason: 'tapping center of ${region.elementId}');
    }
  });

  testWidgets('live game loop: staff taps grow the score, note taps select',
      (tester) async {
    await tester.pumpWidget(const _MiniPlacementGame());
    final staff = renderStaff(tester);
    expect(staff.scoreLayout!.regions, isEmpty);

    // The staff widens (and re-centers) after every placement, so the
    // widget origin must be re-read before each tap.
    Offset topLeft() => tester.getTopLeft(find.bySubtype<StaffView>());

    // Place three notes on distinct positions. Tap just before the end of
    // the (growing) measure so the tap never lands on an existing note;
    // while the measure is empty it has zero width, so aim between the
    // measure start and the final barline instead.
    for (final y in [4.0, 3.0, 2.0]) {
      final layout = staff.scoreLayout!;
      final measure = layout.measureRegions.single;
      final x = measure.endX > measure.startX + 0.5
          ? measure.endX - 0.3
          : (measure.startX + layout.width) / 2;
      await tester.tapAt(topLeft() + staff.staffToLocal(math.Point(x, y)));
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(staff.scoreLayout!.regions, hasLength(3));

    final state =
        tester.state<_MiniPlacementGameState>(find.byType(_MiniPlacementGame));
    expect(state.placed.map((n) => n.pitches.single.staffPosition(Clef.treble)),
        [0, 2, 4]);

    // Tap the first placed note: it becomes selected (highlighted).
    final region =
        staff.scoreLayout!.regions.firstWhere((r) => r.elementId == 'p0');
    final center = (region.bounds.topLeft + region.bounds.bottomRight) * 0.5;
    await tester.tapAt(topLeft() + staff.staffToLocal(center));
    await tester.pump(const Duration(milliseconds: 400));
    expect(state.selected, {'p0'});
    expect(staff.highlightedIds, {'p0'});

    // Tap it again: deselected.
    await tester.tapAt(topLeft() + staff.staffToLocal(center));
    await tester.pump(const Duration(milliseconds: 400));
    expect(state.selected, isEmpty);
  });

  testWidgets('taps repeat: the same element reports once per tap',
      (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      wrap(StaffView(
        score: Score.simple(notes: 'c5:w'),
        staffSpace: 12,
        onElementTap: tapped.add,
      )),
    );
    final staff = renderStaff(tester);
    final region = staff.scoreLayout!.regions.single.bounds;
    final center = (region.topLeft + region.bottomRight) * 0.5;
    final at = tester.getTopLeft(find.bySubtype<StaffView>()) +
        staff.staffToLocal(center);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, ['e0', 'e0']);
  });

  testWidgets('adding callbacks to a live widget makes it tappable',
      (tester) async {
    final tapped = <String>[];
    final score = Score.simple(notes: 'c5:w');
    Widget build({void Function(String)? onTap}) => wrap(
          StaffView(score: score, staffSpace: 12, onElementTap: onTap),
        );

    await tester.pumpWidget(build());
    final staff = renderStaff(tester);
    final region = staff.scoreLayout!.regions.single.bounds;
    final center = (region.topLeft + region.bottomRight) * 0.5;
    final at = tester.getTopLeft(find.bySubtype<StaffView>()) +
        staff.staffToLocal(center);

    // Without callbacks the widget doesn't claim the tap.
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, isEmpty);

    await tester.pumpWidget(build(onTap: tapped.add));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, ['e0']);
  });

  testWidgets('overlapping kid-mode hit regions resolve to the smallest',
      (tester) async {
    final tapped = <String>[];
    // C4 carries a ledger line (bigger region) next to D4 (smaller);
    // with the kids hit slop of 1.5 spaces their inflated regions overlap.
    await tester.pumpWidget(
      wrap(StaffView(
        score: Score.simple(notes: 'c4:q d4:q'),
        staffSpace: 12,
        theme: PartituraTheme.kids,
        onElementTap: tapped.add,
      )),
    );
    final staff = renderStaff(tester);
    final regions = {
      for (final r in staff.scoreLayout!.regions) r.elementId: r.bounds,
    };
    final c4 = regions['e0']!;
    final d4 = regions['e1']!;
    final c4Area = (c4.width + 3) * (c4.height + 3);
    final d4Area = (d4.width + 3) * (d4.height + 3);
    expect(d4Area, lessThan(c4Area), reason: 'test setup: e1 is smaller');

    // A probe between them, inside both inflated regions.
    final probe = math.Point(
      (c4.right + d4.left) / 2,
      (d4.top + d4.bottom) / 2,
    );
    expect(c4.right + 1.5, greaterThan(probe.x), reason: 'inside e0+slop');
    expect(d4.left - 1.5, lessThan(probe.x), reason: 'inside e1+slop');

    await tester.tapAt(
      tester.getTopLeft(find.bySubtype<StaffView>()) +
          staff.staffToLocal(probe),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, ['e1'], reason: 'smallest containing region wins');
  });

  testWidgets('px <-> staff space mapping round-trips', (tester) async {
    await tester.pumpWidget(
      wrap(StaffView(
        score: Score.simple(notes: 'c4:q d4 | e4:h'),
        staffSpace: 13,
      )),
    );
    final staff = renderStaff(tester);
    for (final point in [
      const math.Point(0.0, 0.0),
      const math.Point(5.5, -2.25),
      const math.Point(17.3, 6.75),
      const math.Point(1.0, 4.0),
    ]) {
      final roundTripped = staff.localToStaff(staff.staffToLocal(point));
      expect(roundTripped.x, closeTo(point.x, 1e-9));
      expect(roundTripped.y, closeTo(point.y, 1e-9));
    }
    // And the anchor identity: staff origin maps to (0, -top) px.
    final origin = staff.staffToLocal(const math.Point(0.0, 0.0));
    expect(origin.dx, 0);
    expect(origin.dy, -staff.scoreLayout!.top * staff.scale);
  });

  testWidgets('computeDryLayout matches the laid-out size', (tester) async {
    await tester.pumpWidget(
      wrap(StaffView(score: Score.simple(notes: 'c4:q d4'), staffSpace: 12)),
    );
    final staff = renderStaff(tester);
    final dry = staff.computeDryLayout(const BoxConstraints());
    expect(dry, staff.size);
  });

  testWidgets('swapping the score relayouts; equal scores do not',
      (tester) async {
    Widget build(String notes) => wrap(
          StaffView(score: Score.simple(notes: notes), staffSpace: 12),
        );
    await tester.pumpWidget(build('c4:q d4'));
    final staff = renderStaff(tester);
    final first = staff.scoreLayout;

    // Value-equal score: no relayout.
    await tester.pumpWidget(build('c4:q d4'));
    expect(identical(staff.scoreLayout, first), isTrue);

    // Different score: new layout with more regions and a wider staff.
    await tester.pumpWidget(build('c4:q d4 e4 f4'));
    expect(identical(staff.scoreLayout, first), isFalse);
    expect(staff.scoreLayout!.regions, hasLength(4));
    expect(staff.scoreLayout!.width, greaterThan(first!.width));
  });

  testWidgets('staffSpace and lineBoost changes relayout; colors do not',
      (tester) async {
    Widget build(
            {double staffSpace = 12,
            PartituraTheme theme = PartituraTheme.standard}) =>
        wrap(StaffView(
          score: Score.simple(notes: 'c4:q d4'),
          staffSpace: staffSpace,
          theme: theme,
        ));

    await tester.pumpWidget(build());
    final staff = renderStaff(tester);
    final first = staff.scoreLayout;
    final firstSize = tester.getSize(find.bySubtype<StaffView>());

    // Color-only theme change: same layout object.
    await tester.pumpWidget(build(
      theme: const PartituraTheme(noteColor: Color(0xFFAA0000)),
    ));
    expect(identical(staff.scoreLayout, first), isTrue);

    // lineBoost change: relayout (thickness lives in the primitives).
    await tester.pumpWidget(build(
      theme: const PartituraTheme(lineBoost: 1.4),
    ));
    expect(identical(staff.scoreLayout, first), isFalse);

    // staffSpace change: scale and size change.
    await tester.pumpWidget(build(staffSpace: 16));
    expect(staff.scale, 16);
    expect(
      tester.getSize(find.bySubtype<StaffView>()).width,
      greaterThan(firstSize.width),
    );
  });
}

/// A minimal "place a note" game, exercising the same loop the real
/// minigames use: staff tap -> mutate score -> rebuild; note tap -> select.
class _MiniPlacementGame extends StatefulWidget {
  const _MiniPlacementGame();

  @override
  State<_MiniPlacementGame> createState() => _MiniPlacementGameState();
}

class _MiniPlacementGameState extends State<_MiniPlacementGame> {
  final List<NoteElement> placed = [];
  final Set<String> selected = {};
  var _nextId = 0;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: InteractiveStaff(
          score: Score(
            clef: Clef.treble,
            measures: [Measure(List.of(placed))],
          ),
          staffSpace: 12,
          highlightedIds: Set.of(selected),
          onStaffTap: (target) => setState(() {
            placed.add(NoteElement.note(
              target.pitchFor(Clef.treble),
              NoteDuration.quarter,
              id: 'p${_nextId++}',
            ));
          }),
          onElementTap: (id) => setState(() {
            if (!selected.remove(id)) selected.add(id);
          }),
        ),
      ),
    );
  }
}
