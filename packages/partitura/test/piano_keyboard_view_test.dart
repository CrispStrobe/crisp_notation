import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

void main() {
  setUpAll(setUpPartituraForTests);

  // Center gives loose constraints, so the CustomPaint takes its intrinsic
  // size (at the tightly-constrained root it would fill the window).
  Widget wrap(Widget child) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: child),
      );

  testWidgets('sizes to the white-key count', (tester) async {
    await tester.pumpWidget(
      wrap(const PianoKeyboardView(
          firstMidi: 60, lastMidi: 72, whiteKeyWidth: 20, height: 90)),
    );
    // C4..C5 inclusive → 8 white keys (C D E F G A B C).
    final size = tester.getSize(find.byType(PianoKeyboardView));
    expect(size.width, 8 * 20);
    expect(size.height, 90);
  });

  testWidgets('snaps a black-key range to full white keys', (tester) async {
    // 61 (C#4) .. 66 (F#4): snaps to 60 (C4) .. 67 (G4) → 5 whites (C D E F G).
    await tester.pumpWidget(
      wrap(const PianoKeyboardView(
          firstMidi: 61, lastMidi: 66, whiteKeyWidth: 10, height: 60)),
    );
    expect(tester.getSize(find.byType(PianoKeyboardView)).width, 5 * 10);
  });

  testWidgets('repaints on highlight change without error', (tester) async {
    Widget build(Set<int> lit) =>
        wrap(PianoKeyboardView(highlightedPitches: lit));
    await tester.pumpWidget(build({60, 64, 67}));
    await tester.pumpWidget(build({62, 65, 69})); // black + white keys
    expect(tester.takeException(), isNull);
  });
}
