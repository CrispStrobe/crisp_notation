import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.3.2: slurs.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<CurvePrimitive> curvesOf(ScoreLayout layout) =>
    layout.primitives.whereType<CurvePrimitive>().toList();

Point<double> cubicPoint(CurvePrimitive curve, double t) {
  final u = 1 - t;
  return Point(
    u * u * u * curve.start.x +
        3 * u * u * t * curve.control1.x +
        3 * u * t * t * curve.control2.x +
        t * t * t * curve.end.x,
    u * u * u * curve.start.y +
        3 * u * u * t * curve.control1.y +
        3 * u * t * t * curve.control2.y +
        t * t * t * curve.end.y,
  );
}

bool intersectsPadded(Rectangle<double> rect, Point<double> point,
        {double pad = 0.04}) =>
    point.x >= rect.left - pad &&
    point.x <= rect.right + pad &&
    point.y >= rect.top - pad &&
    point.y <= rect.bottom + pad;

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('model + DSL', () {
    test('( and ) suffixes produce a Slur span', () {
      final score = Score.simple(notes: 'c4:q( d4 e4 f4)');
      expect(score.slurs, [const Slur('e0', 'e3')]);
    });

    test('slurs cross barlines and can chain end-to-start', () {
      final score = Score.simple(notes: 'c4:q( d4 | e4)( f4)');
      expect(score.slurs, [const Slur('e0', 'e2'), const Slur('e2', 'e3')]);
    });

    test('malformed slurs are rejected', () {
      expect(() => Score.simple(notes: 'c4:q( d4'), throwsFormatException);
      expect(() => Score.simple(notes: 'c4:q) d4'), throwsFormatException);
      expect(
        () => Score.simple(notes: 'c4:q( d4( e4) f4)'),
        throwsFormatException,
      );
      expect(() => Score.simple(notes: 'r:q( c4)'), throwsFormatException);
    });

    test('slurs participate in Score equality', () {
      expect(
        Score.simple(notes: 'c4:q( d4)'),
        Score.simple(notes: 'c4:q( d4)'),
      );
      expect(
        Score.simple(notes: 'c4:q( d4)'),
        isNot(Score.simple(notes: 'c4:q d4')),
      );
      expect(const Slur('a', 'b'), const Slur('a', 'b'));
      expect(const Slur('a', 'b'), isNot(const Slur('a', 'c')));
      expect(const Slur('a', 'b').toString(), 'Slur(a -> b)');
    });
  });

  group('layout', () {
    test('a slur yields one curve spanning start to end', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q( d4 e4 f4)'));
      final curve = curvesOf(layout).single;
      final heads = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.noteheadBlack)
          .toList();
      expect(curve.start.x, closeTo((heads.first.position.x + 0.6), 0.7));
      expect(curve.end.x, closeTo((heads.last.position.x + 0.6), 0.7));
    });

    test('below when all stems are up, above otherwise', () {
      // c4..f4 all stem up -> slur below (start y beneath the noteheads).
      final below =
          curvesOf(layoutOf(Score.simple(notes: 'c4:q( d4 e4 f4)'))).single;
      expect(below.start.y, greaterThan(4.5));
      expect(below.control1.y, greaterThan(below.start.y));
      // c5..f5 all stem down -> above.
      final above =
          curvesOf(layoutOf(Score.simple(notes: 'c5:q( d5 e5 f5)'))).single;
      expect(above.start.y, lessThan(1.5));
      expect(above.control1.y, lessThan(above.start.y));
      // Mixed stems -> above.
      final mixed =
          curvesOf(layoutOf(Score.simple(notes: 'a4:q( b4 c5 d5)'))).single;
      expect(mixed.control1.y, lessThan(mixed.start.y));
    });

    test('the arc clears a high middle note', () {
      // g4 .. c6 .. g4: the slur (above) must clear C6's region.
      final layout = layoutOf(Score.simple(notes: 'g4:q( c6 g4)'));
      final curve = curvesOf(layout).single;
      final c6Top =
          layout.regions.firstWhere((r) => r.elementId == 'e1').bounds.top;
      expect(curve.control1.y, lessThan(c6Top));
    });

    test('long slur sampled path clears intervening note ink', () {
      final layout = layoutOf(
        Score.simple(notes: 'f4:e( c5 e5 g4 a4 b4 c5 d5 e5 f5 g5 a4)'),
      );
      final curve = curvesOf(layout).single;
      final regions = layout.regions.where((r) =>
          r.elementId != 'e0' && r.elementId != 'e10' && r.elementId != 'e11');

      for (var i = 1; i < 32; i++) {
        final point = cubicPoint(curve, i / 32);
        for (final region in regions) {
          expect(intersectsPadded(region.bounds, point), isFalse,
              reason: 'slur $curve intersects ${region.elementId} at $point');
        }
      }
    });

    test('long phrase slurs anchor outside the staff', () {
      final above = curvesOf(
        layoutOf(Score.simple(notes: 'c5:e( d5 e5 f5 g5 a5 b5 c6)')),
      ).single;
      expect(above.start.y, lessThanOrEqualTo(-0.65));
      expect(above.end.y, lessThanOrEqualTo(-0.65));

      final below = curvesOf(
        layoutOf(Score.simple(notes: 'c4:e( d4 e4 f4 g4 a4 b4 c5)')),
      ).single;
      expect(below.start.y, greaterThanOrEqualTo(4.65));
      expect(below.end.y, greaterThanOrEqualTo(4.65));
    });

    test('slurs and ties coexist', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q( d4 e4~ e4)'));
      expect(curvesOf(layout), hasLength(2));
    });

    test('unknown or reversed ids are skipped, not fatal', () {
      Score withSlur(Slur slur) => Score(
            clef: Clef.treble,
            measures: [
              Measure([
                NoteElement.note(const Pitch(Step.c), NoteDuration.quarter,
                    id: 'a'),
                NoteElement.note(const Pitch(Step.d), NoteDuration.quarter,
                    id: 'b'),
              ]),
            ],
            slurs: [slur],
          );
      // A dangling ('a'→'nope') or reversed ('b'→'a') slur is skipped, not
      // fatal — it simply draws no curve; a valid slur still does.
      expect(curvesOf(layoutOf(withSlur(const Slur('a', 'nope')))), isEmpty);
      expect(curvesOf(layoutOf(withSlur(const Slur('b', 'a')))), isEmpty);
      expect(curvesOf(layoutOf(withSlur(const Slur('a', 'b')))), hasLength(1));
    });

    test('slur ink stays inside the layout bounds', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q( c6 a3 f5)'));
      final curve = curvesOf(layout).single;
      for (final p in [
        curve.start,
        curve.control1,
        curve.control2,
        curve.end
      ]) {
        expect(layout.bounds.containsPoint(p), isTrue, reason: '$curve');
      }
    });
  });
}
