import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart' hide Step, PageMetrics;
import 'package:flutter_test/flutter_test.dart';

import 'test_setup.dart';

void main() {
  setUpAll(setUpCrispNotationForTests);

  // Three one-bar parts, vertically separated, on one big page.
  MultiPartScore trio() => MultiPartScore([
        Score.simple(
            clef: Clef.treble,
            timeSignature: TimeSignature.fourFour,
            notes: 'c5:w'),
        Score.simple(
            clef: Clef.treble,
            timeSignature: TimeSignature.fourFour,
            notes: 'e4:w'),
        Score.simple(
            clef: Clef.bass,
            timeSignature: TimeSignature.fourFour,
            notes: 'c3:w'),
      ], brackets: const [
        StaffBracket(0, 2)
      ]);

  const metrics = PageMetrics(width: 60, height: 60);

  RenderMultiPartView renderOf(WidgetTester tester) =>
      tester.renderObject<RenderMultiPartView>(
          find.byWidgetPredicate((w) => w is MultiPartView));

  Future<RenderMultiPartView> pump(
    WidgetTester tester, {
    void Function(int, StaffTarget)? onStaffTap,
    void Function(String)? onElementTap,
    void Function(String, int, StaffTarget)? onElementDragEnd,
    Set<String> suppress = const {},
    ElementRegionController? controller,
    EditorCaret? caret,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: InteractiveMultiPartView(
            document: trio(),
            metrics: metrics,
            staffSpace: 10,
            suppressElementIds: suppress,
            onStaffTap: onStaffTap,
            onElementTap: onElementTap,
            onElementDragEnd: onElementDragEnd,
            controller: controller,
            caret: caret,
          ),
        ),
      ),
    ));
    return renderOf(tester);
  }

  testWidgets('targetAt resolves the part a point falls in', (tester) async {
    final render = await pump(tester);
    // The centre of each part's element region falls in that part.
    for (final region in render.elementRegions) {
      final hit = render.targetAt(region.bounds.center);
      expect(hit, isNotNull);
    }
    // A point in the top part resolves to part 0, the bottom part to part 2.
    final regions = render.elementRegions.toList();
    final top = regions.reduce((a, b) => a.bounds.top < b.bounds.top ? a : b);
    final bottom =
        regions.reduce((a, b) => a.bounds.top > b.bounds.top ? a : b);
    expect(render.targetAt(top.bounds.center)!.partIndex, 0);
    expect(render.targetAt(bottom.bounds.center)!.partIndex, 2);
  });

  testWidgets('tapping an element reports its id', (tester) async {
    String? tapped;
    final render = await pump(tester, onElementTap: (id) => tapped = id);
    final region = render.elementRegions.first;
    await tester.tapAt(_global(tester, region.bounds.center));
    await tester.pump();
    expect(tapped, region.id);
  });

  testWidgets('tapping empty staff reports (partIndex, target)',
      (tester) async {
    int? part;
    StaffTarget? target;
    final render = await pump(tester, onStaffTap: (p, t) {
      part = p;
      target = t;
    });
    // A point on the bottom part's staff, well to the right of its note.
    final bottom = render.elementRegions
        .reduce((a, b) => a.bounds.top > b.bounds.top ? a : b);
    final spot = Offset(bottom.bounds.right + 40, bottom.bounds.center.dy);
    // Guard: the spot must be empty (no element there).
    expect(render.elementIdAt(spot), isNull);
    await tester.tapAt(_global(tester, spot));
    await tester.pump();
    expect(part, 2);
    expect(target, isNotNull);
  });

  testWidgets('dragging an element reports id + drop (partIndex, target)',
      (tester) async {
    String? id;
    int? part;
    StaffTarget? target;
    final render = await pump(tester, onElementDragEnd: (i, p, t) {
      id = i;
      part = p;
      target = t;
    });
    final region = render.elementRegions.first; // part 0's note
    final from = _global(tester, region.bounds.center);
    // An explicit down → move → up so the pan wins the gesture arena.
    final gesture = await tester.startGesture(from);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(id, region.id);
    expect(part, isNotNull);
    expect(target, isNotNull);
  });

  testWidgets('suppressElementIds is accepted and paints without error',
      (tester) async {
    final render = await pump(tester);
    final id = render.elementRegions.first.id;
    // Re-pump with that id suppressed — a clean drag-source hide (C10a).
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: InteractiveMultiPartView(
            document: trio(),
            metrics: metrics,
            staffSpace: 10,
            suppressElementIds: {id},
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an ElementRegionController reports regions across all parts',
      (tester) async {
    final controller = ElementRegionController();
    final render = await pump(tester, controller: controller);
    expect(controller.isAttached, isTrue);
    // One whole-note per part → three regions, one in each of the 3 staves.
    expect(controller.elementRegions, hasLength(3));
    // A marquee over the whole page selects every part's note.
    final all = controller.elementIdsIn(Offset.zero & render.size);
    expect(all.toSet(), render.elementRegions.map((r) => r.id).toSet());
    expect(all, hasLength(3));
  });

  testWidgets('the controller detaches when the view is disposed',
      (tester) async {
    final controller = ElementRegionController();
    await pump(tester, controller: controller);
    expect(controller.isAttached, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.isAttached, isFalse);
  });

  testWidgets('showMeasureNumbers labels wrapped systems without error',
      (tester) async {
    Score part(Clef clef) => Score.simple(
          clef: clef,
          timeSignature: TimeSignature.fourFour,
          notes: 'c5:q d5 e5 f5 | g5:q f5 e5 d5 | c5:q d5 e5 f5 | '
              'g5:q f5 e5 d5 | c5:q d5 e5 f5 | g5:q f5 e5 d5',
        );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: InteractiveMultiPartView(
            document: MultiPartScore([part(Clef.treble), part(Clef.bass)]),
            metrics: const PageMetrics(width: 34, height: 140),
            staffSpace: 8,
            showMeasureNumbers: true,
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    // The narrow page wraps the score, so a later system starts past bar 1 —
    // that is the one that gets a global bar number.
    final systems =
        renderOf(tester).pagedLayout!.pages.expand((p) => p.systems);
    expect(systems.any((s) => s.system.firstMeasure > 0), isTrue);
  });

  testWidgets('an EditorCaret paints before its element (any part)',
      (tester) async {
    final probe = await pump(tester);
    // Pick an element in the *second* part to prove the caret finds its staff.
    final id = probe.elementRegions[1].id;
    await pump(tester, caret: EditorCaret(beforeElementId: id));
    expect(tester.takeException(), isNull);
    // A null caret is a no-op (still no exception).
    await pump(tester, caret: const EditorCaret());
    expect(tester.takeException(), isNull);
  });
}

/// The global offset of a local point inside the interactive view.
Offset _global(WidgetTester tester, Offset local) {
  final box = tester.renderObject<RenderBox>(
      find.byWidgetPredicate((w) => w is MultiPartView));
  return box.localToGlobal(local);
}
