import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.7 Phase 1.4: forced beam slant (custom slope / force-horizontal).
late final SmuflMetadata metadata;
late final LayoutSettings settings;

Score slanted(List<BeamSlant> beams) {
  final base = Score.simple(
    timeSignature: TimeSignature.fourFour,
    notes: 'c5:e d5 e5 f5 g5 a5 b5 c6',
  );
  return Score(
    clef: base.clef,
    timeSignature: base.timeSignature,
    measures: base.measures,
    beamSlants: beams,
  );
}

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<BeamPrimitive> beamsOf(ScoreLayout l) =>
    l.primitives.whereType<BeamPrimitive>().toList();

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('model', () {
    test('value semantics', () {
      expect(const BeamSlant('a', 'b'), const BeamSlant('a', 'b'));
      expect(const BeamSlant('a', 'b'),
          isNot(const BeamSlant('a', 'b', slant: 1)));
    });

    test('participates in Score equality', () {
      expect(slanted(const [BeamSlant('e0', 'e7')]),
          slanted(const [BeamSlant('e0', 'e7')]));
      expect(slanted(const [BeamSlant('e0', 'e7')]), isNot(slanted(const [])));
    });
  });

  group('layout', () {
    test('forces the ascending run into one horizontal beam', () {
      final layout = layoutOf(slanted(const [BeamSlant('e0', 'e7')]));
      final beams = beamsOf(layout);
      // Eight eighths would normally be two beat groups; the slant merges
      // them into one, and slant 0 makes the primary beam horizontal.
      expect(beams, hasLength(1));
      expect(beams.single.start.y, closeTo(beams.single.end.y, 1e-9));
    });

    test('a non-zero slant tilts the beam by exactly that rise', () {
      final beams = beamsOf(layoutOf(slanted(const [
        BeamSlant('e0', 'e7', slant: 2),
      ])));
      // beamY(last) − beamY(first) = slope·dx = slant.
      expect(beams.single.end.y - beams.single.start.y, closeTo(2, 1e-9));
    });

    test('the ascending run naturally slopes without a forced slant', () {
      final beams = beamsOf(layoutOf(slanted(const [])));
      // More than one beat group, and each naturally tilts (not flat).
      expect(beams.length, greaterThan(1));
      expect(
        beams.any((b) => (b.end.y - b.start.y).abs() > 1e-6),
        isTrue,
      );
    });

    test('layout with a forced slant is deterministic', () {
      String render() => layoutOf(slanted(const [BeamSlant('e0', 'e7')]))
          .primitives
          .map((p) => p.toString())
          .join('\n');
      expect(render(), render());
    });
  });

  group('transpose preserves the slant', () {
    test('transposedBy keeps beamSlants', () {
      final up = slanted(const [BeamSlant('e0', 'e7', slant: 1.5)])
          .transposedBy(Interval.majorSecond);
      expect(up.beamSlants, const [BeamSlant('e0', 'e7', slant: 1.5)]);
    });
  });
}
