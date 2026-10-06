import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'grand_staff_view_test.dart' show demo, wrap;
import 'interactive_grand_staff_view_test.dart' show eightBarPiano;
import 'test_setup.dart';

double staffLineThickness(GrandStaffLayout layout) =>
    layout.upper.primitives.whereType<LinePrimitive>().first.thickness;

void main() {
  setUpAll(setUpCrispNotationForTests);

  for (final space in [5.0, 12.0]) {
    testWidgets('start line spans both staves edge to edge at scale $space',
        (tester) async {
      await tester.pumpWidget(wrap(GrandStaffView(
        grandStaff: demo(),
        staffSpace: space,
      )));
      final render = tester.renderObject<RenderGrandStaffView>(
        find.byType(GrandStaffView),
      );
      final overhang =
          Offset(0, staffLineThickness(render.grandLayout!) / 2 * space);
      expect(
          render,
          paints
            ..something((method, arguments) =>
                method == #drawLine &&
                arguments[0] == render.upperOrigin - overhang &&
                arguments[1] ==
                    render.lowerOrigin + Offset(0, 4 * space) + overhang));
    });
  }

  testWidgets('every wrapped system has a full start line', (tester) async {
    await tester.pumpWidget(wrap(SizedBox(
      width: 350,
      child: InteractiveGrandStaffView(
        grandStaff: eightBarPiano(),
        staffSpace: 8,
      ),
    )));
    final render = tester.renderObject<RenderInteractiveGrandStaffView>(
      find.byType(InteractiveGrandStaffView),
    );
    expect(render.grandStaffSystems!.systems.length, greaterThan(1));
    for (var i = 0; i < render.grandStaffSystems!.systems.length; i++) {
      final overhang = Offset(
          0,
          staffLineThickness(render.grandStaffSystems!.systems[i].layout) /
              2 *
              8);
      expect(
          render,
          paints
            ..something((method, arguments) =>
                method == #drawLine &&
                arguments[0] == render.upperOrigin(i) - overhang &&
                arguments[1] ==
                    render.lowerOrigin(i) + const Offset(0, 32) + overhang));
    }
  });
}
