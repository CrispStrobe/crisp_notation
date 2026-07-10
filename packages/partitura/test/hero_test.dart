import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

/// Renders the README hero image (goldens/hero.png, copied to doc/).
void main() {
  setUpAll(setUpPartituraForTests);

  testWidgets('hero image', (tester) async {
    await tester.binding.setSurfaceSize(const Size(880, 260));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(20),
                child: StaffView(
                  score: Score.simple(
                    keySignature: const KeySignature(1),
                    timeSignature: TimeSignature.fourFour,
                    notes: 'g4:e a4 b4 c5 d5:q d5 | e5:e e5 e5 e5 d5:h | '
                        'c5+e5:q g4+c5 e4+g4 d4+g4 | g4+b4+d5:w',
                  ),
                  staffSpace: 13,
                  highlightedIds: const {'e6', 'e14'},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/hero.png'),
    );
  });
}
