import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

void main() {
  setUpAll(setUpPartituraForTests);

  // A left-hand arpeggio that climbs out of the bass staff into the treble:
  // the upper notes are engraved on the staff above and beamed across the gap.
  GrandStaff pianoCrossStaff() {
    // Two ascending arpeggios; the top note of each is drawn a staff up.
    NoteElement e(String pitch, String id) =>
        NoteElement.note(Pitch.parse(pitch), NoteDuration.eighth, id: id);
    final lower = Score(
      clef: Clef.bass,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          e('c3', 'a'),
          e('g3', 'b'),
          e('e4', 'c'),
          e('g4', 'd'),
          e('d3', 'e'),
          e('a3', 'f'),
          e('f4', 'g'),
          e('a4', 'h'),
        ]),
      ],
      crossStaff: const [
        CrossStaffNote('c', staffShift: -1),
        CrossStaffNote('d', staffShift: -1),
        CrossStaffNote('g', staffShift: -1),
        CrossStaffNote('h', staffShift: -1),
      ],
    );
    final upper = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'r:h r:h',
    );
    return GrandStaff(upper: upper, lower: lower);
  }

  testWidgets('cross-staff notes are engraved on the upper staff',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: GrandStaffView(
              grandStaff: pianoCrossStaff(), staffSpace: 12, staffGap: 6),
        ),
      ),
    ));
    final render =
        tester.renderObject<RenderGrandStaffView>(find.byType(GrandStaffView));
    // The cross-staff notes push the lower staff's ink well above its own top
    // line (they reach up into the treble staff).
    expect(render.grandLayout!.lower.top, lessThan(-6));
  });

  testWidgets('122 piano cross-staff: left hand beamed into the treble',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: GrandStaffView(
                    grandStaff: pianoCrossStaff(), staffSpace: 12, staffGap: 6),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/122_cross_staff.png'),
    );
  });
}
