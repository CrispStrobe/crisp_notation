import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';

import 'test_setup.dart';

/// Widget-level plumbing for `StaffView.extraFingerings`: fingerings computed at
/// display time (a bowed-string arranger fingering a score it did not build)
/// reach the layout engine and grow the staff's ink upward. The glyph-level
/// behaviour is covered in crisp_notation_core's `fingering_test.dart`.
void main() {
  setUpAll(setUpCrispNotationForTests);

  Score cello() => Score(
        clef: Clef.bass,
        timeSignature: const TimeSignature(2, 4),
        measures: [
          Measure([
            NoteElement.note(
                const Pitch(Step.c, octave: 3), NoteDuration.quarter,
                id: 'n1'),
            NoteElement.note(
                const Pitch(Step.d, octave: 3), NoteDuration.quarter,
                id: 'n2'),
          ]),
        ],
      );

  Future<Size> pump(
    WidgetTester tester,
    Map<String, List<int>> extra,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: StaffView(score: cello(), extraFingerings: extra),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return tester.getSize(find.byType(StaffView));
  }

  testWidgets('extra fingerings grow the staff ink', (tester) async {
    final bare = await pump(tester, const {});
    final fingered = await pump(tester, const {
      'n1': [1],
      'n2': [4],
    });
    expect(fingered.height, greaterThan(bare.height));
  });

  testWidgets('a thumb mark renders like a digit does', (tester) async {
    final digit = await pump(tester, const {
      'n1': [1]
    });
    final thumb = await pump(tester, const {
      'n1': [kFingeringThumb]
    });
    // Both add ink above the note; neither is silently dropped.
    final bare = await pump(tester, const {});
    expect(digit.height, greaterThan(bare.height));
    expect(thumb.height, greaterThan(bare.height));
  });

  testWidgets('an unknown note id changes nothing', (tester) async {
    final bare = await pump(tester, const {});
    final bogus = await pump(tester, const {
      'nope': [3]
    });
    expect(bogus.height, bare.height);
  });
}
