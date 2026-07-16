import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_setup.dart';

GrandStaff eightBarPiano() => GrandStaff(
      upper: Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes:
            'c5:q d5 e5 f5 | g5:q a5 b5 c6 | c6:q b5 a5 g5 | f5:q e5 d5 c5 | '
            'e5:q f5 g5 a5 | b5:q a5 g5 f5 | e5:q d5 c5 d5 | c5:w',
      ),
      lower: Score.simple(
        clef: Clef.bass,
        timeSignature: TimeSignature.fourFour,
        notes: 'c3:h e3 | g3:h c4 | e3:h c3 | g2:h c3 | '
            'c3:h g3 | e3:h c3 | g3:h g2 | c3:w',
      ),
    );

Widget wrap(Widget child, {double width = 400}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SizedBox(width: width, child: child)),
    );

RenderInteractiveGrandStaffView renderOf(WidgetTester tester) =>
    tester.renderObject<RenderInteractiveGrandStaffView>(
        find.bySubtype<InteractiveGrandStaffView>());

void main() {
  setUpAll(setUpCrispNotationForTests);

  testWidgets('wraps a grand staff into multiple systems', (tester) async {
    await tester.pumpWidget(
      wrap(InteractiveGrandStaffView(
          grandStaff: eightBarPiano(), staffSpace: 10)),
    );
    expect(tester.takeException(), isNull);
    final systems = renderOf(tester).grandStaffSystems!;
    expect(systems.systems.length, greaterThan(1));
  });

  testWidgets('element tap on either staff reports the id', (tester) async {
    final ids = <String>[];
    await tester.pumpWidget(
      wrap(InteractiveGrandStaffView(
        grandStaff: eightBarPiano(),
        staffSpace: 10,
        onElementTap: ids.add,
      )),
    );
    final render = renderOf(tester);
    final systems = render.grandStaffSystems!;
    final topLeft =
        tester.getTopLeft(find.bySubtype<InteractiveGrandStaffView>());

    // First upper-staff note of system 0.
    final upperBounds = systems.systems[0].layout.upper.regions
        .firstWhere((r) => r.elementId == 'e0')
        .bounds;
    final upperCenter = (upperBounds.topLeft + upperBounds.bottomRight) * 0.5;
    await tester.tapAt(topLeft +
        render.upperOrigin(0) +
        Offset(upperCenter.x * render.scale, upperCenter.y * render.scale));
    await tester.pump(const Duration(milliseconds: 400));

    // First lower-staff note of system 0.
    final lowerBounds = systems.systems[0].layout.lower.regions
        .firstWhere((r) => r.elementId == 'e0')
        .bounds;
    final lowerCenter = (lowerBounds.topLeft + lowerBounds.bottomRight) * 0.5;
    await tester.tapAt(topLeft +
        render.lowerOrigin(0) +
        Offset(lowerCenter.x * render.scale, lowerCenter.y * render.scale));
    await tester.pump(const Duration(milliseconds: 400));

    // Both staves start their ids at e0 (unique-id contract is the caller's).
    expect(ids, ['e0', 'e0']);
  });

  testWidgets('staff tap resolves system, staff and quantized position',
      (tester) async {
    final targets = <StaffTarget>[];
    await tester.pumpWidget(
      wrap(InteractiveGrandStaffView(
        grandStaff: eightBarPiano(),
        staffSpace: 10,
        onStaffTap: targets.add,
      )),
    );
    final render = renderOf(tester);
    final systems = render.grandStaffSystems!;

    Offset upperProbe(int system, double xSpaces, double ySpaces) =>
        render.upperOrigin(system) +
        Offset(xSpaces * render.scale, ySpaces * render.scale);
    Offset lowerProbe(int system, double xSpaces, double ySpaces) =>
        render.lowerOrigin(system) +
        Offset(xSpaces * render.scale, ySpaces * render.scale);

    // Top line of the upper staff, system 0, first measure -> staff 0, pos 8.
    final um0 = systems.systems[0].layout.upper.measureRegions.first;
    final up = render.resolveStaffTarget(upperProbe(0, um0.startX + 2, 0))!;
    expect(up.systemIndex, 0);
    expect(up.staffIndex, 0);
    expect(up.staffPosition, 8);
    expect(up.measureIndex, 0);

    // Middle line of the lower staff, last system -> staff 1, pos 4.
    final last = systems.systems.length - 1;
    final lm = systems.systems[last].layout.lower.measureRegions.first;
    final low = render.resolveStaffTarget(lowerProbe(last, lm.startX + 2, 2))!;
    expect(low.systemIndex, last);
    expect(low.staffIndex, 1);
    expect(low.staffPosition, 4);
    expect(low.measureIndex, systems.systems[last].firstMeasure);
  });

  testWidgets('elementRegions cover both staves with local geometry',
      (tester) async {
    await tester.pumpWidget(
      wrap(InteractiveGrandStaffView(
          grandStaff: eightBarPiano(), staffSpace: 10)),
    );
    final render = renderOf(tester);
    final regions = render.elementRegions;
    expect(regions, isNotEmpty);
    // Both staves contribute (their notes both start at id 'e0').
    expect(regions.where((r) => r.id == 'e0').length, greaterThanOrEqualTo(2));
    // A marquee over an element's own bounds selects it.
    final any = regions.first;
    expect(render.elementIdsIn(any.bounds), contains(any.id));
  });

  testWidgets('justify fills non-final systems (shared two-staff stretch)',
      (tester) async {
    Future<({double first, double last, int count})> widths(
        bool justify) async {
      await tester.pumpWidget(
        wrap(
          InteractiveGrandStaffView(
            grandStaff: eightBarPiano(),
            staffSpace: 10,
            justify: justify,
          ),
          width: 320,
        ),
      );
      final systems = renderOf(tester).grandStaffSystems!.systems;
      return (
        first: systems.first.layout.width,
        last: systems.last.layout.width,
        count: systems.length,
      );
    }

    final justified = await widths(true);
    final ragged = await widths(false);
    expect(justified.count, greaterThan(1));
    // The first (non-final) system is wider when justified; the last is not
    // stretched either way.
    expect(justified.first, greaterThan(ragged.first + 0.5));
    expect(justified.last, closeTo(ragged.last, 0.01));
    // Both staves of a justified system share the same width (barlines align).
    await tester.pumpWidget(
      wrap(
        InteractiveGrandStaffView(grandStaff: eightBarPiano(), staffSpace: 10),
        width: 320,
      ),
    );
    final sys0 = renderOf(tester).grandStaffSystems!.systems.first.layout;
    expect(sys0.upper.width, closeTo(sys0.lower.width, 1e-6));
  });

  testWidgets('onHover reports the staff target and null on exit',
      (tester) async {
    final hovered = <StaffTarget?>[];
    await tester.pumpWidget(
      wrap(InteractiveGrandStaffView(
        grandStaff: eightBarPiano(),
        staffSpace: 10,
        onHover: hovered.add,
      )),
    );
    final render = renderOf(tester);
    final topLeft =
        tester.getTopLeft(find.bySubtype<InteractiveGrandStaffView>());
    final lm =
        render.grandStaffSystems!.systems[0].layout.lower.measureRegions.first;
    final overLower = topLeft +
        render.lowerOrigin(0) +
        Offset((lm.startX + 2) * render.scale, 2 * render.scale);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(() => mouse.removePointer());
    await mouse.moveTo(overLower);
    await tester.pump();
    expect(hovered.last, isA<StaffTarget>());
    expect(hovered.last!.staffIndex, 1); // lower staff

    await mouse.moveTo(topLeft - const Offset(300, 300));
    await tester.pump();
    expect(hovered.last, isNull);
  });

  testWidgets('dragging an element on either staff reports start/end',
      (tester) async {
    final log = <String>[];
    StaffTarget? endTarget;
    await tester.pumpWidget(
      wrap(InteractiveGrandStaffView(
        grandStaff: eightBarPiano(),
        staffSpace: 10,
        onElementDragStart: (id) => log.add('start:$id'),
        onElementDragEnd: (id, t) {
          log.add('end:$id');
          endTarget = t;
        },
      )),
    );
    final render = renderOf(tester);
    final topLeft =
        tester.getTopLeft(find.bySubtype<InteractiveGrandStaffView>());
    final bounds = render.grandStaffSystems!.systems[0].layout.upper.regions
        .firstWhere((r) => r.elementId == 'e0')
        .bounds;
    final center = (bounds.topLeft + bounds.bottomRight) * 0.5;
    final start = topLeft +
        render.upperOrigin(0) +
        Offset(center.x * render.scale, center.y * render.scale);

    final g = await tester.startGesture(start);
    await g.moveTo(start + const Offset(0, -20));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(log.first, 'start:e0');
    expect(log.last, 'end:e0');
    expect(endTarget, isNotNull);
    expect(endTarget!.staffIndex, 0);
  });

  testWidgets('caret and ghost paint without error, repaint-only',
      (tester) async {
    Widget build({EditorCaret? caret, StaffTarget? ghost}) => wrap(
          InteractiveGrandStaffView(
            grandStaff: eightBarPiano(),
            staffSpace: 10,
            caret: caret,
            ghostTarget: ghost,
          ),
        );
    await tester.pumpWidget(build());
    final render = renderOf(tester);
    final before = render.grandStaffSystems;
    await tester.pumpWidget(build(
      caret: const EditorCaret(measureIndex: 2),
      ghost:
          const StaffTarget(staffPosition: 4, measureIndex: 2, staffIndex: 1),
    ));
    expect(tester.takeException(), isNull);
    expect(identical(render.grandStaffSystems, before), isTrue);
  });

  testWidgets('rectOfElement locates notes on either staff (scroll-to-note)',
      (tester) async {
    await tester.pumpWidget(
      wrap(InteractiveGrandStaffView(
          grandStaff: eightBarPiano(), staffSpace: 10)),
    );
    final render = renderOf(tester);
    final rect = render.rectOfElement('e0')!;
    // Its centre hit-tests back to an element (the upper e0 is found first).
    expect(render.elementIdAt(rect.center), 'e0');
    // A later measure's note has a rect further down the widget (later system).
    final systems = render.grandStaffSystems!;
    final last = systems.systems.length - 1;
    final lastId = 'e${systems.systems[last].firstMeasure * 4}';
    final lastRect = render.rectOfElement(lastId);
    if (lastRect != null) {
      expect(lastRect.top, greaterThan(rect.top));
    }
    expect(render.rectOfElement('no-such-id'), isNull);
  });

  testWidgets('errorOverlay and loopRange paint without error, repaint-only',
      (tester) async {
    Widget build({
      Map<String, EditorMark> overlay = const {},
      (String, String)? loop,
    }) =>
        wrap(InteractiveGrandStaffView(
          grandStaff: eightBarPiano(),
          staffSpace: 10,
          errorOverlay: overlay,
          loopRange: loop,
        ));
    await tester.pumpWidget(build());
    final render = renderOf(tester);
    final before = render.grandStaffSystems;

    await tester.pumpWidget(build(
      overlay: const {
        'e2': EditorMark(Color(0xFFD32F2F), message: 'wrong pitch'),
        'e9': EditorMark(Color(0xFF388E3C)),
      },
      // A loop spanning from the first system into a later one.
      loop: ('e1', 'e20'),
    ));
    expect(tester.takeException(), isNull);
    // Overlays are repaint-only — never relayout.
    expect(identical(render.grandStaffSystems, before), isTrue);
  });

  testWidgets('showMeasureNumbers labels wrapped systems without error',
      (tester) async {
    await tester.pumpWidget(
      wrap(InteractiveGrandStaffView(
        grandStaff: eightBarPiano(),
        staffSpace: 10,
        showMeasureNumbers: true,
      )),
    );
    expect(tester.takeException(), isNull);
    final systems = renderOf(tester).grandStaffSystems!.systems;
    // Wraps into >1 system, so a later system starts past bar 1 (gets a number).
    expect(systems.any((s) => s.firstMeasure > 0), isTrue);
  });

  testWidgets('showNoteNames engraves names on both staves', (tester) async {
    await tester.pumpWidget(
      wrap(InteractiveGrandStaffView(
        grandStaff: eightBarPiano(),
        staffSpace: 10,
        showNoteNames: true,
        noteNameStyle: NoteNameStyle.german,
      )),
    );
    expect(tester.takeException(), isNull);
    final render = renderOf(tester);
    expect(render.showNoteNames, isTrue);
    expect(render.noteNameStyle, NoteNameStyle.german);
    final texts = render.grandStaffSystems!.systems
        .expand(
            (s) => [...s.layout.upper.primitives, ...s.layout.lower.primitives])
        .whereType<TextPrimitive>();
    expect(texts, isNotEmpty);
  });
}
