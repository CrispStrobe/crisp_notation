import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

void main() {
  late final SmuflMetadata metadata;
  late final LayoutSettings settings;

  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  NoteElement note(String step, int oct, DurationBase base, String id) =>
      NoteElement(
        pitches: [Pitch(Step.values.byName(step), octave: oct)],
        duration: NoteDuration(base),
        id: id,
      );

  // Two 4/4 measures: an eighth ends measure 1 (`x`) and an eighth opens
  // measure 2 (`y`); the rest is filled with longer notes.
  Score twoMeasures({List<CrossMeasureBeam> beams = const []}) => Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            note('g', 4, DurationBase.half, 'a'),
            note('g', 4, DurationBase.quarter, 'b'),
            note('a', 4, DurationBase.eighth, 'x'),
          ]),
          Measure([
            note('b', 4, DurationBase.eighth, 'y'),
            note('g', 4, DurationBase.quarter, 'c'),
            note('g', 4, DurationBase.half, 'd'),
          ]),
        ],
        crossMeasureBeams: beams,
      );

  List<BeamPrimitive> beamsOf(ScoreLayout l) =>
      l.primitives.whereType<BeamPrimitive>().toList();
  List<String> flagsOf(ScoreLayout l) => l.primitives
      .whereType<GlyphPrimitive>()
      .map((g) => g.smuflName)
      .where((n) => n.startsWith('flag'))
      .toList();

  test('without a cross-measure beam, the two eighths flag separately', () {
    final layout = const LayoutEngine().layout(twoMeasures(), settings);
    expect(beamsOf(layout), isEmpty);
    expect(flagsOf(layout), hasLength(2)); // x and y each get an 8th flag
  });

  test('a cross-measure beam draws one beam across the barline', () {
    final layout = const LayoutEngine().layout(
      twoMeasures(beams: const [CrossMeasureBeam('x', 'y')]),
      settings,
    );
    final beams = beamsOf(layout);
    expect(beams, hasLength(1));
    // The flags are gone — the notes are beamed instead.
    expect(flagsOf(layout), isEmpty);

    // The beam starts in measure 1 and ends in measure 2 (crosses the barline).
    final m1 = layout.measureRegions[0];
    final m2 = layout.measureRegions[1];
    final beam = beams.single;
    expect(beam.start.x, lessThan(m1.endX));
    expect(beam.end.x, greaterThan(m2.startX));
  });

  test('over a second voice, a cross-measure beam keeps voice 1 stems up', () {
    // High notes alone would take stems down, through the lower voice.
    final score = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          note('g', 5, DurationBase.half, 'a'),
          note('g', 5, DurationBase.quarter, 'b'),
          note('a', 5, DurationBase.eighth, 'x'),
        ], voice2: [
          note('e', 4, DurationBase.whole, 'p'),
        ]),
        Measure([
          note('b', 5, DurationBase.eighth, 'y'),
          note('g', 5, DurationBase.quarter, 'c'),
          note('g', 5, DurationBase.half, 'd'),
        ], voice2: [
          note('e', 4, DurationBase.whole, 'q'),
        ]),
      ],
      crossMeasureBeams: const [CrossMeasureBeam('x', 'y')],
    );
    final beam = beamsOf(const LayoutEngine().layout(score, settings)).single;
    // a5 sits at y = -0.5: a beam over upward stems is well above it.
    expect(max(beam.start.y, beam.end.y), lessThan(-2));
  });

  test('the score keeps value semantics with cross-measure beams', () {
    expect(twoMeasures(beams: const [CrossMeasureBeam('x', 'y')]),
        twoMeasures(beams: const [CrossMeasureBeam('x', 'y')]));
    expect(twoMeasures(beams: const [CrossMeasureBeam('x', 'y')]),
        isNot(twoMeasures()));
  });
}
