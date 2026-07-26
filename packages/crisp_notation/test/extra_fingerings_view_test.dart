import 'dart:typed_data';

import 'package:crisp_notation/crisp_notation.dart';
// Material's Stepper also exports a `Step`; crisp_notation's wins here.
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/rendering.dart';
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

  testWidgets('MultiSystemView takes them too (the Song Book path)',
      (tester) async {
    // Long enough to wrap, so the marks have to survive the per-system slicing
    // inside layoutSystems (ids absent from a slice are simply not drawn in it).
    final score = Score.simple(
      clef: Clef.bass,
      notes: 'c3:q d3 e3 f3 | g3:q a3 b3 c4 | c3:q d3 e3 f3 | g3:q a3 b3 c4',
    );
    final ids = <String>[
      for (final measure in score.measures)
        for (final element in measure.elements)
          if (element is NoteElement && element.id != null) element.id!,
    ];
    expect(ids, isNotEmpty, reason: 'Score.simple should id its notes');

    // The view fills its box, so size cannot be the signal — compare the ink.
    Future<ByteData> paint(Map<String, List<int>> extra) async {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox(
                  width: 300,
                  height: 400,
                  child: MultiSystemView(score: score, extraFingerings: extra),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).last,
      );
      late ByteData data;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        data = (await image.toByteData())!;
        image.dispose();
      });
      return data;
    }

    final bare = await paint(const {});
    final fingered = await paint({
      for (final id in ids) id: const [3]
    });
    expect(fingered.buffer.asUint8List(), isNot(bare.buffer.asUint8List()),
        reason: 'fingering digits should add ink');
  });
}
