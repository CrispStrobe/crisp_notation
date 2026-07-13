import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

Score eight() => Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5 | c5:q b4 a4 g4 | f4:q e4 d4 c4',
    );

GrandStaff piano() => GrandStaff(
      upper: Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:q d5 e5 f5 | g5:q a5 b5 c6',
      ),
      lower: Score.simple(
        clef: Clef.bass,
        timeSignature: TimeSignature.fourFour,
        notes: 'c3:h e3 | g3:h c4',
      ),
    );

Widget wrap(Widget child, {double width = 400}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SizedBox(width: width, child: child)),
    );

void main() {
  setUpAll(setUpPartituraForTests);

  testWidgets('MultiSystemView feeds a region controller (C7)', (tester) async {
    final controller = ElementRegionController();
    expect(controller.isAttached, isFalse);
    expect(controller.elementRegions, isEmpty); // no view yet

    await tester.pumpWidget(
      wrap(MultiSystemView(
          score: eight(), staffSpace: 10, controller: controller)),
    );

    expect(controller.isAttached, isTrue);
    final regions = controller.elementRegions;
    expect(regions, isNotEmpty);
    expect(regions.any((r) => r.id == 'e0'), isTrue);
    // Every region carries a measure index within the score.
    expect(regions.every((r) => r.measureIndex >= 0 && r.measureIndex < 4),
        isTrue);

    // Marquee: a rect covering the whole canvas returns the element ids.
    final all = controller.elementIdsIn(const Rect.fromLTWH(0, 0, 1e5, 1e5));
    expect(all, contains('e0'));
    // A zero-size rect far away hits nothing.
    expect(controller.elementIdsIn(const Rect.fromLTWH(-1e4, -1e4, 1, 1)),
        isEmpty);

    // Detaches when the view leaves the tree.
    await tester.pumpWidget(wrap(const SizedBox()));
    expect(controller.isAttached, isFalse);
    expect(controller.elementRegions, isEmpty);
  });

  testWidgets('InteractiveGrandStaffView feeds the same controller type',
      (tester) async {
    final controller = ElementRegionController();
    await tester.pumpWidget(
      wrap(InteractiveGrandStaffView(
          grandStaff: piano(), staffSpace: 10, controller: controller)),
    );
    expect(controller.isAttached, isTrue);
    expect(controller.elementRegions, isNotEmpty);
    // The C7 contract name is an alias of ElementRegionController.
    expect(controller, isA<MultiSystemViewController>());
  });

  testWidgets('swapping controllers re-binds; the old one detaches',
      (tester) async {
    final a = ElementRegionController();
    final b = ElementRegionController();
    await tester.pumpWidget(
      wrap(MultiSystemView(score: eight(), staffSpace: 10, controller: a)),
    );
    expect(a.isAttached, isTrue);
    await tester.pumpWidget(
      wrap(MultiSystemView(score: eight(), staffSpace: 10, controller: b)),
    );
    expect(a.isAttached, isFalse);
    expect(b.isAttached, isTrue);
  });
}
