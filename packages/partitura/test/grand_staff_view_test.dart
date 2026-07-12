import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

Widget wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    );

GrandStaff demo() => GrandStaff(
      upper: Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:q d5 e5 f5 | g5:w',
      ),
      lower: Score.simple(
        clef: Clef.bass,
        timeSignature: TimeSignature.fourFour,
        notes: 'c3:h e3:h | c3:w',
      ),
    );

void main() {
  setUpAll(setUpPartituraForTests);

  testWidgets('renders a grand staff without errors', (tester) async {
    await tester.pumpWidget(
      wrap(GrandStaffView(grandStaff: demo(), staffSpace: 8)),
    );
    expect(find.byType(GrandStaffView), findsOneWidget);
    expect(tester.takeException(), isNull);
    final render =
        tester.renderObject<RenderGrandStaffView>(find.byType(GrandStaffView));
    expect(render.grandLayout, isNotNull);
    // Two staves: measures align.
    final layout = render.grandLayout!;
    expect(layout.upper.measureRegions[0].endX,
        closeTo(layout.lower.measureRegions[0].endX, 1e-9));
  });

  testWidgets('sizes from the layout plus the brace inset', (tester) async {
    await tester.pumpWidget(
      wrap(GrandStaffView(grandStaff: demo(), staffSpace: 8)),
    );
    final render =
        tester.renderObject<RenderGrandStaffView>(find.byType(GrandStaffView));
    final layout = render.grandLayout!;
    final size = tester.getSize(find.byType(GrandStaffView));
    expect(
      size.width,
      closeTo((layout.width + RenderGrandStaffView.braceInset) * 8, 0.01),
    );
    expect(size.height, closeTo(layout.height * 8, 0.01));
  });

  testWidgets('element taps resolve on both staves', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      wrap(GrandStaffView(
        grandStaff: demo(),
        staffSpace: 10,
        onElementTap: tapped.add,
      )),
    );
    final render =
        tester.renderObject<RenderGrandStaffView>(find.byType(GrandStaffView));
    final layout = render.grandLayout!;
    final topLeft = tester.getTopLeft(find.byType(GrandStaffView));

    Offset centerOf(ScoreLayout staff, Offset origin, String id) {
      final region = staff.regions.firstWhere((r) => r.elementId == id).bounds;
      final center = (region.topLeft + region.bottomRight) * 0.5;
      return topLeft +
          origin +
          Offset(center.x * render.scale, center.y * render.scale);
    }

    // Upper staff note e1, then a lower staff note (same id space would
    // clash — the demo uses default ids per score, so tap by geometry).
    await tester.tapAt(centerOf(layout.upper, render.upperOrigin, 'e1'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(centerOf(layout.lower, render.lowerOrigin, 'e0'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, ['e1', 'e0']);
  });

  testWidgets('lower staff sits below the upper by the staff gap',
      (tester) async {
    await tester.pumpWidget(
      wrap(GrandStaffView(grandStaff: demo(), staffSpace: 8, staffGap: 6)),
    );
    final render =
        tester.renderObject<RenderGrandStaffView>(find.byType(GrandStaffView));
    final gapPx =
        render.lowerOrigin.dy - (render.upperOrigin.dy + 4 * render.scale);
    expect(gapPx, closeTo(6 * 8, 0.01));
  });

  testWidgets('highlight changes never relayout', (tester) async {
    Widget build(Set<String> highlights) => wrap(GrandStaffView(
          grandStaff: demo(),
          staffSpace: 8,
          highlightedIds: highlights,
        ));
    await tester.pumpWidget(build(const {}));
    final render =
        tester.renderObject<RenderGrandStaffView>(find.byType(GrandStaffView));
    final before = render.grandLayout;
    await tester.pumpWidget(build(const {'e0'}));
    expect(identical(render.grandLayout, before), isTrue);
  });

  testWidgets('geometry helpers stay consistent', (tester) async {
    await tester.pumpWidget(
      wrap(GrandStaffView(grandStaff: demo(), staffSpace: 8)),
    );
    final render =
        tester.renderObject<RenderGrandStaffView>(find.byType(GrandStaffView));
    // The brace inset shifts both staves identically.
    expect(render.upperOrigin.dx, render.lowerOrigin.dx);
    expect(render.upperOrigin.dx,
        closeTo(RenderGrandStaffView.braceInset * 8, 1e-9));
    // A point on the upper staff's top line maps back inside the widget.
    final probe = render.upperOrigin + const Offset(30, 0);
    expect(render.elementIdAt(probe), isNull); // top line, no element
    expect(probe.dy, greaterThan(0));
    expect(
      probe.dy,
      lessThan(tester.getSize(find.byType(GrandStaffView)).height),
    );
  });
}
