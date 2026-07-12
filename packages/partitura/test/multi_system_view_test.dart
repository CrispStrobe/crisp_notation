import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

/// Eight simple 4/4 measures — breaks into several systems at narrow
/// widths.
Score eightMeasures() => Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5 | c5:q b4 a4 g4 | f4:q e4 d4 c4 |'
          'e4:q f4 g4 a4 | b4:q a4 g4 f4 | e4:q d4 c4 d4 | c4:w',
    );

Widget wrap(Widget child, {double width = 400}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SizedBox(width: width, child: child)),
    );

RenderMultiSystemView renderOf(WidgetTester tester) => tester
    .renderObject<RenderMultiSystemView>(find.bySubtype<MultiSystemView>());

void main() {
  setUpAll(setUpPartituraForTests);

  testWidgets('breaks a long score into systems that fit the width',
      (tester) async {
    await tester.pumpWidget(
      wrap(MultiSystemView(score: eightMeasures(), staffSpace: 10)),
    );
    expect(tester.takeException(), isNull);
    final render = renderOf(tester);
    final layout = render.multiSystemLayout!;
    expect(layout.systems.length, greaterThan(1));
    // 400 px at 10 px/space = 40 spaces.
    expect(layout.maxWidth, closeTo(40, 1e-9));
    final size = tester.getSize(find.bySubtype<MultiSystemView>());
    expect(size.width, lessThanOrEqualTo(400 + 0.01));
  });

  testWidgets('height stacks all systems plus gaps', (tester) async {
    await tester.pumpWidget(
      wrap(MultiSystemView(
        score: eightMeasures(),
        staffSpace: 10,
        systemGap: 6,
      )),
    );
    final render = renderOf(tester);
    final layout = render.multiSystemLayout!;
    final size = tester.getSize(find.bySubtype<MultiSystemView>());
    expect(size.height, closeTo(layout.heightWith(6) * 10, 0.01));
  });

  testWidgets('resizing rebreaks the score', (tester) async {
    Widget at(double width) => wrap(
          MultiSystemView(score: eightMeasures(), staffSpace: 10),
          width: width,
        );
    await tester.pumpWidget(at(400));
    final narrow = renderOf(tester).multiSystemLayout!.systems.length;
    await tester.pumpWidget(at(900));
    final wide = renderOf(tester).multiSystemLayout!.systems.length;
    expect(wide, lessThan(narrow));
  });

  testWidgets('element taps resolve on every system', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      wrap(MultiSystemView(
        score: eightMeasures(),
        staffSpace: 10,
        onElementTap: tapped.add,
      )),
    );
    final render = renderOf(tester);
    final layout = render.multiSystemLayout!;
    expect(layout.systems.length, greaterThan(1));
    final topLeft = tester.getTopLeft(find.bySubtype<MultiSystemView>());

    Offset centerOf(int system, String id) {
      final bounds = layout.systems[system].layout.regions
          .firstWhere((r) => r.elementId == id)
          .bounds;
      final center = (bounds.topLeft + bounds.bottomRight) * 0.5;
      return topLeft +
          render.originOfSystem(system) +
          Offset(center.x * render.scale, center.y * render.scale);
    }

    // First element of the first system and first element of the last
    // system.
    final lastSystem = layout.systems.length - 1;
    final lastFirstId =
        'e${layout.systems[lastSystem].firstMeasure * 4}'; // 4 notes/measure
    await tester.tapAt(centerOf(0, 'e0'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tapAt(centerOf(lastSystem, lastFirstId));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, ['e0', lastFirstId]);
  });

  testWidgets('taps outside any element report nothing', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      wrap(MultiSystemView(
        score: eightMeasures(),
        staffSpace: 10,
        systemGap: 8,
        onElementTap: tapped.add,
      )),
    );
    final render = renderOf(tester);
    // A point in the gap between system 0 and system 1.
    final topLeft = tester.getTopLeft(find.bySubtype<MultiSystemView>());
    final gapProbe = topLeft +
        render.originOfSystem(1) +
        Offset(
            5,
            -(render.multiSystemLayout!.systems[1].layout.top + 1) *
                render.scale);
    expect(render.elementIdAt(gapProbe - topLeft), isNull);
    await tester.tapAt(gapProbe);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, isEmpty);
  });

  testWidgets('highlight changes never relayout', (tester) async {
    Widget build(Set<String> highlights) => wrap(MultiSystemView(
          score: eightMeasures(),
          staffSpace: 10,
          highlightedIds: highlights,
        ));
    await tester.pumpWidget(build(const {}));
    final render = renderOf(tester);
    final before = render.multiSystemLayout;
    await tester.pumpWidget(build(const {'e0', 'e12'}));
    expect(identical(render.multiSystemLayout, before), isTrue);
  });

  testWidgets('value-equal score swap does not relayout', (tester) async {
    await tester.pumpWidget(
      wrap(MultiSystemView(score: eightMeasures(), staffSpace: 10)),
    );
    final render = renderOf(tester);
    final before = render.multiSystemLayout;
    await tester.pumpWidget(
      wrap(MultiSystemView(score: eightMeasures(), staffSpace: 10)),
    );
    expect(identical(render.multiSystemLayout, before), isTrue);
  });

  testWidgets('justify: false leaves non-final systems unstretched',
      (tester) async {
    await tester.pumpWidget(
      wrap(MultiSystemView(
        score: eightMeasures(),
        staffSpace: 10,
        justify: false,
      )),
    );
    final layout = renderOf(tester).multiSystemLayout!;
    final slack = layout.systems
        .take(layout.systems.length - 1)
        .map((s) => layout.maxWidth - s.layout.width);
    expect(slack.any((gap) => gap > 1), isTrue);
  });

  testWidgets('every system paints its own clef', (tester) async {
    await tester.pumpWidget(
      wrap(MultiSystemView(score: eightMeasures(), staffSpace: 10)),
    );
    final layout = renderOf(tester).multiSystemLayout!;
    for (final system in layout.systems) {
      final clefs = system.layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.gClef);
      expect(clefs, isNotEmpty);
    }
  });
}
