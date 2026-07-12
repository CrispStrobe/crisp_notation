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

  testWidgets('renders both clefs without errors', (tester) async {
    await tester.pumpWidget(
      wrap(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StaffView(score: Score.simple(notes: 'c4:q d4 e4 f4')),
            StaffView(
              score: Score.simple(clef: Clef.bass, notes: 'c3:h e3:h'),
              staffSpace: 10,
            ),
          ],
        ),
      ),
    );
    expect(find.byType(StaffView), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit staffSpace determines the pixel size', (tester) async {
    final score = Score.simple(notes: 'c4:q');
    await tester.pumpWidget(wrap(StaffView(score: score, staffSpace: 10)));
    final renderObject =
        tester.renderObject<RenderStaffView>(find.byType(StaffView));
    final layout = renderObject.scoreLayout!;
    final size = tester.getSize(find.byType(StaffView));
    expect(size.width, closeTo(layout.width * 10, 0.01));
    expect(size.height, closeTo(layout.height * 10, 0.01));
    expect(renderObject.scale, 10);
  });

  testWidgets('null staffSpace fits the available width', (tester) async {
    final score = Score.simple(notes: 'c4:q d4 e4 f4');
    await tester.pumpWidget(
      wrap(SizedBox(width: 400, child: StaffView(score: score))),
    );
    final renderObject =
        tester.renderObject<RenderStaffView>(find.byType(StaffView));
    expect(tester.getSize(find.byType(StaffView)).width, 400);
    expect(
      renderObject.scale,
      closeTo(400 / renderObject.scoreLayout!.width, 1e-9),
    );
  });

  testWidgets('tapping an element reports its id', (tester) async {
    final tapped = <String>[];
    final score = Score.simple(notes: 'c4:q d4 e4 f4');
    await tester.pumpWidget(
      wrap(StaffView(score: score, staffSpace: 12, onElementTap: tapped.add)),
    );
    final renderObject =
        tester.renderObject<RenderStaffView>(find.byType(StaffView));
    final region = renderObject.scoreLayout!.regions
        .firstWhere((r) => r.elementId == 'e1');
    final center = (region.bounds.topLeft + region.bounds.bottomRight) * 0.5;
    final local = renderObject.staffToLocal(center);
    final topLeft = tester.getTopLeft(find.byType(StaffView));
    await tester.tapAt(topLeft + local);
    expect(tapped, ['e1']);
  });

  testWidgets('changing highlights repaints without relayout', (tester) async {
    final score = Score.simple(notes: 'c4:q d4 e4 f4');
    Widget build(Set<String> highlights) => wrap(
          StaffView(score: score, staffSpace: 12, highlightedIds: highlights),
        );
    await tester.pumpWidget(build(const {}));
    final renderObject =
        tester.renderObject<RenderStaffView>(find.byType(StaffView));
    final layoutBefore = renderObject.scoreLayout;
    await tester.pumpWidget(build(const {'e0', 'e2'}));
    // Identical layout object: no relayout happened.
    expect(identical(renderObject.scoreLayout, layoutBefore), isTrue);
  });

  testWidgets('kid mode inflates hit slop', (tester) async {
    final tappedStandard = <String>[];
    final tappedKids = <String>[];
    final score = Score.simple(notes: 'c5:w');

    Future<void> run(PartituraTheme theme, List<String> sink) async {
      await tester.pumpWidget(
        wrap(StaffView(
          score: score,
          staffSpace: 12,
          theme: theme,
          onElementTap: sink.add,
        )),
      );
      final renderObject =
          tester.renderObject<RenderStaffView>(find.byType(StaffView));
      final region = renderObject.scoreLayout!.regions.single.bounds;
      // A probe 1 staff space above the notehead's box: outside the
      // standard slop (0.5), inside the kids slop (1.5).
      final probe = renderObject.staffToLocal(
        math.Point((region.left + region.right) / 2, region.top - 1.0),
      );
      final topLeft = tester.getTopLeft(find.byType(StaffView));
      await tester.tapAt(topLeft + probe);
      await tester.pump();
    }

    await run(PartituraTheme.standard, tappedStandard);
    await run(PartituraTheme.kids, tappedKids);
    expect(tappedStandard, isEmpty);
    expect(tappedKids, ['e0']);
  });
}
