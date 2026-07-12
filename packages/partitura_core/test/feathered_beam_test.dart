import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.7 Phase 1.4: feathered (fanned) beams.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

Score feathered(List<FeatheredBeam> beams) {
  final base = Score.simple(
    timeSignature: TimeSignature.fourFour,
    notes: 'c5:e d5 e5 f5 g5 a5 b5 c6',
  );
  return Score(
    clef: base.clef,
    timeSignature: base.timeSignature,
    measures: base.measures,
    featheredBeams: beams,
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
      expect(const FeatheredBeam('a', 'b'), const FeatheredBeam('a', 'b'));
      expect(const FeatheredBeam('a', 'b'),
          isNot(const FeatheredBeam('a', 'b', endBeams: 3)));
    });

    test('equal begin/end is rejected', () {
      expect(() => FeatheredBeam('a', 'b', beginBeams: 2, endBeams: 2),
          throwsA(isA<AssertionError>()));
    });

    test('participates in Score equality', () {
      expect(feathered(const [FeatheredBeam('e0', 'e7')]),
          feathered(const [FeatheredBeam('e0', 'e7')]));
      expect(feathered(const [FeatheredBeam('e0', 'e7')]),
          isNot(feathered(const [])));
    });
  });

  group('layout', () {
    test('a 1->4 feather forces one group: primary + three fan beams', () {
      final layout = layoutOf(feathered(const [FeatheredBeam('e0', 'e7')]));
      // Eight eighths would normally beam as (at least) two beat groups of
      // one beam each; the feather collapses them to one group of four beams.
      expect(beamsOf(layout), hasLength(4));
    });

    test('accelerando fans out toward the end', () {
      final beams = beamsOf(layoutOf(feathered(
        const [FeatheredBeam('e0', 'e7', beginBeams: 1, endBeams: 4)],
      )));
      double range(Iterable<double> ys) =>
          ys.reduce((a, b) => a > b ? a : b) -
          ys.reduce((a, b) => a < b ? a : b);
      // Beams converge at the start (small spread) and fan at the end.
      expect(range(beams.map((b) => b.end.y)),
          greaterThan(range(beams.map((b) => b.start.y))));
    });

    test('ritardando fans out toward the start', () {
      final beams = beamsOf(layoutOf(feathered(
        const [FeatheredBeam('e0', 'e7', beginBeams: 4, endBeams: 1)],
      )));
      double range(Iterable<double> ys) =>
          ys.reduce((a, b) => a > b ? a : b) -
          ys.reduce((a, b) => a < b ? a : b);
      expect(range(beams.map((b) => b.start.y)),
          greaterThan(range(beams.map((b) => b.end.y))));
    });

    test('without a feather the same notes beam normally', () {
      final normal = beamsOf(layoutOf(feathered(const [])));
      // Two beat groups of eighths → two single primary beams, no fan.
      expect(normal.length, lessThan(4));
    });

    test('layout with a feather is deterministic', () {
      String render() => layoutOf(feathered(const [FeatheredBeam('e0', 'e7')]))
          .primitives
          .map((p) => p.toString())
          .join('\n');
      expect(render(), render());
    });
  });

  group('transpose preserves the feather', () {
    test('transposedBy keeps featheredBeams', () {
      final up = feathered(const [FeatheredBeam('e0', 'e7')])
          .transposedBy(Interval.majorSecond);
      expect(up.featheredBeams, const [FeatheredBeam('e0', 'e7')]);
    });
  });
}
