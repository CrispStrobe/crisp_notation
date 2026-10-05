import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Beam endpoints reach the outer edges of the outermost stems, not their
/// center lines: `_addBeam` extends each end by half a stem thickness along
/// the beam's slope, and the cross-staff pass overhangs the same way. The
/// middle-line clearance accounts for that overhang so a clamped beam still
/// clears the line by its full thickness.
late final SmuflMetadata metadata;

LayoutSettings settingsWith(double stemThickness) => LayoutSettings(
      metadata: metadata,
      stemThickness: stemThickness,
    );

ScoreLayout layoutOf(String notes, LayoutSettings settings) =>
    const LayoutEngine().layout(Score.simple(notes: notes), settings);

List<LinePrimitive> stemsOf(ScoreLayout l) => l.primitives
    .whereType<LinePrimitive>()
    .where((line) => line.elementId != null && line.from.x == line.to.x)
    .toList();

List<BeamPrimitive> beamsOf(ScoreLayout l) =>
    l.primitives.whereType<BeamPrimitive>().toList();

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
  });

  // Ordinary (4/4 eighths), secondary (sixteenths), and descending groups.
  for (final notes in ['c4:e d4 e4 f4', 'c6:e b5 a5 g5', 'c5:s d5 e5 f5']) {
    // The default 0.12 plus a deliberately heavy stem to make the overhang
    // unmistakable.
    for (final thickness in [0.12, 0.3]) {
      test('beams cover the outer stem edges: $notes, $thickness', () {
        final layout = layoutOf(notes, settingsWith(thickness));
        final stems = stemsOf(layout);
        final beams = beamsOf(layout);
        expect(beams, isNotEmpty);
        for (final beam in beams) {
          expect(
              stems.any((stem) =>
                  (stem.from.x - thickness / 2 - beam.start.x).abs() < 1e-9),
              isTrue);
          expect(
              stems.any((stem) =>
                  (stem.from.x + thickness / 2 - beam.end.x).abs() < 1e-9),
              isTrue);
        }
      });
    }
  }

  test('the cross-staff beam overhangs the outer stems too', () {
    final settings = settingsWith(0.3);
    final layout = layoutGrandStaff(
      GrandStaff(
        upper: Score(
          clef: Clef.treble,
          measures: [
            Measure([
              NoteElement.note(
                  const Pitch(Step.g, octave: 4), NoteDuration.eighth,
                  id: 'u0'),
            ]),
          ],
        ),
        lower: Score(
          clef: Clef.bass,
          measures: [
            Measure([
              NoteElement.note(
                  const Pitch(Step.c, octave: 3), NoteDuration.eighth,
                  id: 'l0'),
            ]),
          ],
        ),
        crossStaffBeams: const [
          CrossStaffBeam(['u0', 'l0'])
        ],
      ),
      settings,
    );
    final beam = layout.upper.primitives.whereType<BeamPrimitive>().single;
    // The joined notes' own stems are deferred and drawn by the cross-staff
    // pass at the stub x positions, so compare against those.
    final stubXs = [
      layout.upper.crossStaffStubs['u0']!.stemX,
      layout.lower.crossStaffStubs['l0']!.stemX,
    ]..sort();
    expect(beam.start.x, closeTo(stubXs.first - 0.3 / 2, 1e-9));
    expect(beam.end.x, closeTo(stubXs.last + 0.3 / 2, 1e-9));
  });
}
