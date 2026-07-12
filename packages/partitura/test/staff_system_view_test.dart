import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

void main() {
  setUpAll(setUpPartituraForTests);

  StaffSystem system() => StaffSystem([
        Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5'),
        Score.simple(clef: Clef.bass, notes: 'c3:q d3 e3 f3'),
      ]);

  testWidgets('lays out both staves and sizes to them', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: StaffSystemView(system: system(), staffSpace: 12),
        ),
      ),
    ));
    final render = tester
        .renderObject<RenderStaffSystemView>(find.byType(StaffSystemView));
    expect(render.systemLayout!.staves, hasLength(2));
    // The bottom staff sits below the top one.
    expect(render.staffOrigin(1).dy, greaterThan(render.staffOrigin(0).dy));
    expect(render.size.height, greaterThan(0));
  });

  testWidgets('taps report ids from either staff', (tester) async {
    String? tapped;
    final sys = StaffSystem([
      Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5'), // e0..e3
      Score(
        clef: Clef.bass,
        measures: [
          Measure([
            NoteElement.note(
                const Pitch(Step.c, octave: 3), NoteDuration.quarter,
                id: 'low0'),
            NoteElement.note(
                const Pitch(Step.d, octave: 3), NoteDuration.quarter,
                id: 'low1'),
          ]),
        ],
      ),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: StaffSystemView(
            system: sys,
            staffSpace: 14,
            onElementTap: (id) => tapped = id,
          ),
        ),
      ),
    ));
    final render = tester
        .renderObject<RenderStaffSystemView>(find.byType(StaffSystemView));
    // Find the bottom-staff note 'low1' region and tap its center.
    final layout = render.systemLayout!;
    final region =
        layout.staves[1].regions.firstWhere((r) => r.elementId == 'low1');
    final origin = render.staffOrigin(1);
    final center = Offset(
      origin.dx + (region.bounds.left + region.bounds.width / 2) * 14,
      origin.dy + (region.bounds.top + region.bounds.height / 2) * 14,
    );
    final topLeft = tester.getTopLeft(find.byType(StaffSystemView));
    await tester.tapAt(topLeft + center);
    await tester.pump();
    expect(tapped, 'low1');
  });
}
