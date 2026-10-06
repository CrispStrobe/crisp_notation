import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'grand_staff_view_test.dart' show wrap;
import 'test_setup.dart';

void main() {
  setUpAll(setUpCrispNotationForTests);

  testWidgets('changing fingering placement relayouts and preserves line boost',
      (tester) async {
    final score = Score.simple(notes: 'c4:e=1 d4:e=2 e4:e=3 f4:e=4');
    Widget build(FingeringPlacement placement) => wrap(StaffView(
          score: score,
          staffSpace: 10,
          theme: CrispNotationTheme(
            fingeringPlacement: placement,
            lineBoost: 1.4,
          ),
        ));
    await tester.pumpWidget(build(FingeringPlacement.aboveStaff));
    final render = tester.renderObject<RenderStaffView>(find.byType(StaffView));
    final above = render.scoreLayout!;
    await tester.pumpWidget(build(FingeringPlacement.belowStaff));
    final below = render.scoreLayout!;
    expect(identical(above, below), isFalse);
    final fingers = below.primitives.whereType<GlyphPrimitive>().where(
          (glyph) => glyph.smuflName.startsWith('fingering'),
        );
    expect(fingers, hasLength(4));
    expect(fingers.every((glyph) => glyph.position.y > 4), isTrue);
    expect(
        CrispNotationTheme.standard.copyWith(
          fingeringPlacement: FingeringPlacement.belowStaff,
        ),
        const CrispNotationTheme(
            fingeringPlacement: FingeringPlacement.belowStaff));
  });

  testWidgets('piano fingerings sit outside the grand staff', (tester) async {
    await tester.pumpWidget(wrap(RepaintBoundary(
      key: const ValueKey('engraving'),
      child: ColoredBox(
        color: const Color(0xFFFFFFFF),
        child: GrandStaffView(
          grandStaff: GrandStaff(
            upper: Score.simple(
                notes:
                    'c4:e=1 d4:e=2 e4:e=3 f4:e=1 g4:e=2 a4:e=3 b4:e=4 c5:e=5'),
            lower: Score.simple(
                clef: Clef.bass,
                notes:
                    'c3:e=5 d3:e=4 e3:e=3 f3:e=2 g3:e=1 a3:e=3 b3:e=2 c4:e=1'),
          ),
          staffSpace: 12,
          theme: const CrispNotationTheme(
              fingeringPlacement: FingeringPlacement.outsideStaff),
        ),
      ),
    )));
    final render =
        tester.renderObject<RenderGrandStaffView>(find.byType(GrandStaffView));
    for (final staff in [
      render.grandLayout!.upper,
      render.grandLayout!.lower
    ]) {
      final fingers = staff.primitives
          .whereType<GlyphPrimitive>()
          .where((glyph) => glyph.smuflName.startsWith('fingering'))
          .toList();
      expect(fingers, hasLength(8));
      expect(
          fingers.every((glyph) => identical(staff, render.grandLayout!.upper)
              ? glyph.position.y < 0
              : glyph.position.y > 4),
          isTrue);
    }
    await expectLater(find.byKey(const ValueKey('engraving')),
        matchesGoldenFile('goldens/staff_fingering_placement.png'));
  });
}
