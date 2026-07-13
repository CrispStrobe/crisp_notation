import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Score-model lacuna (Phase 2.2): cross-staff notes & beaming — a beam that
/// spans both staves of a grand staff. Each note stays on its own staff; the
/// engine defers the joined notes' stems and the grand-staff pass draws one
/// beam between the staves.
late final LayoutSettings settings;

Score upperStaff() => Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement.note(const Pitch(Step.g, octave: 4), NoteDuration.eighth,
              id: 'u0'),
        ]),
      ],
    );

Score lowerStaff() => Score(
      clef: Clef.bass,
      measures: [
        Measure([
          NoteElement.note(const Pitch(Step.c, octave: 3), NoteDuration.eighth,
              id: 'l0'),
        ]),
      ],
    );

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    settings = LayoutSettings(
      metadata:
          SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>),
    );
  });

  test('CrossStaffBeam and GrandStaff value semantics', () {
    expect(
        const CrossStaffBeam(['u0', 'l0']), const CrossStaffBeam(['u0', 'l0']));
    expect(const CrossStaffBeam(['u0', 'l0']),
        isNot(const CrossStaffBeam(['l0', 'u0'])));
    final withBeam = GrandStaff(
      upper: upperStaff(),
      lower: lowerStaff(),
      crossStaffBeams: const [
        CrossStaffBeam(['u0', 'l0'])
      ],
    );
    expect(
      withBeam,
      GrandStaff(
        upper: upperStaff(),
        lower: lowerStaff(),
        crossStaffBeams: const [
          CrossStaffBeam(['u0', 'l0'])
        ],
      ),
    );
    // The beams participate in equality.
    expect(withBeam == GrandStaff(upper: upperStaff(), lower: lowerStaff()),
        isFalse);
  });

  test('a cross-staff beam defers stems and draws one connecting beam', () {
    final layout = layoutGrandStaff(
      GrandStaff(
        upper: upperStaff(),
        lower: lowerStaff(),
        crossStaffBeams: const [
          CrossStaffBeam(['u0', 'l0'])
        ],
      ),
      settings,
    );

    // Both notes' stems were deferred, so a stub is recorded for each.
    expect(layout.upper.crossStaffStubs.keys, contains('u0'));
    expect(layout.lower.crossStaffStubs.keys, contains('l0'));

    // One beam is drawn in the upper frame, spanning to the lower staff.
    final beams = layout.upper.primitives.whereType<BeamPrimitive>().toList();
    expect(beams, hasLength(1));
    // Its right edge sits below its left edge only if slanted; here it is level
    // and lies between the staves (below the upper staff's bottom line, y = 4).
    expect(beams.single.start.y, greaterThan(4));

    // Neither joined note kept its own stem line.
    expect(
      layout.upper.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.elementId == 'u0'),
      isEmpty,
    );
    expect(
      layout.lower.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.elementId == 'l0'),
      isEmpty,
    );
  });

  test('without a cross-staff beam the notes keep their own stems', () {
    final layout = layoutGrandStaff(
      GrandStaff(upper: upperStaff(), lower: lowerStaff()),
      settings,
    );
    expect(layout.upper.primitives.whereType<BeamPrimitive>(), isEmpty);
    // The lone eighth gets its own stem again.
    expect(
      layout.upper.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.elementId == 'u0'),
      isNotEmpty,
    );
    expect(layout.upper.crossStaffStubs, isEmpty);
  });
}
