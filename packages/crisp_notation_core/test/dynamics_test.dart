import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// v0.3.5: dynamics and hairpins.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

Score demo({
  List<DynamicMarking> dynamics = const [],
  List<Hairpin> hairpins = const [],
  String notes = 'c5:q d5 e5 f5',
}) {
  final base = Score.simple(
    timeSignature: TimeSignature.fourFour,
    notes: notes,
  );
  return Score(
    clef: base.clef,
    timeSignature: base.timeSignature,
    measures: base.measures,
    dynamics: dynamics,
    hairpins: hairpins,
  );
}

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('model', () {
    test('value semantics', () {
      expect(
        const DynamicMarking('a', DynamicLevel.mf),
        const DynamicMarking('a', DynamicLevel.mf),
      );
      expect(
        const DynamicMarking('a', DynamicLevel.mf),
        isNot(const DynamicMarking('a', DynamicLevel.f)),
      );
      expect(
        const Hairpin('a', 'b', HairpinType.crescendo),
        const Hairpin('a', 'b', HairpinType.crescendo),
      );
      expect(
        const Hairpin('a', 'b', HairpinType.crescendo),
        isNot(const Hairpin('a', 'b', HairpinType.diminuendo)),
      );
      expect(
        demo(dynamics: const [DynamicMarking('e0', DynamicLevel.p)]),
        demo(dynamics: const [DynamicMarking('e0', DynamicLevel.p)]),
      );
      expect(
        demo(dynamics: const [DynamicMarking('e0', DynamicLevel.p)]),
        isNot(demo()),
      );
    });
  });

  group('layout', () {
    test('every level maps to its glyph, centered under the element', () {
      const levels = {
        DynamicLevel.pp: 'dynamicPP',
        DynamicLevel.p: 'dynamicPiano',
        DynamicLevel.mp: 'dynamicMP',
        DynamicLevel.mf: 'dynamicMF',
        DynamicLevel.f: 'dynamicForte',
        DynamicLevel.ff: 'dynamicFF',
      };
      levels.forEach((level, glyphName) {
        final layout = layoutOf(demo(dynamics: [DynamicMarking('e1', level)]));
        final glyph = layout.primitives
            .whereType<GlyphPrimitive>()
            .firstWhere((g) => g.smuflName == glyphName);
        expect(glyph.elementId, 'e1');
        // Below the staff.
        expect(glyph.position.y, greaterThan(5.5), reason: glyphName);
        // Roughly centered under the second notehead.
        final head = layout.primitives
            .whereType<GlyphPrimitive>()
            .where((g) =>
                g.elementId == 'e1' && g.smuflName.startsWith('notehead'))
            .single;
        final box = metadata.bBoxOf(glyphName);
        final glyphCenter = glyph.position.x + box.swX + box.width / 2;
        expect(glyphCenter, closeTo(head.position.x + 0.6, 0.7));
      });
    });

    test('low ink pushes the dynamics line down', () {
      final high = layoutOf(
        demo(dynamics: const [DynamicMarking('e0', DynamicLevel.f)]),
      );
      final low = layoutOf(demo(
        notes: 'c4:q d4 e4 f4', // stems + low heads reach below the staff
        dynamics: const [DynamicMarking('e0', DynamicLevel.f)],
      ));
      double dynamicY(ScoreLayout layout) => layout.primitives
          .whereType<GlyphPrimitive>()
          .firstWhere((g) => g.smuflName == 'dynamicForte')
          .position
          .y;
      expect(dynamicY(low), greaterThan(dynamicY(high)));
    });

    // The dynamic of an upper-voice chord was placed under that chord
    // alone: the lower voice's stems and its triplet bracket below them ran
    // through the letters (Holmès, "Chanson catalane", bars 1-2, 9-12).
    test('clears another voice and its tuplet bracket below the staff', () {
      final base = demo(
        notes: '3[d5:e d5 d5] d5:q d5:h ; f4:e f4 f4 f4:q f4:h',
        dynamics: const [DynamicMarking('e0', DynamicLevel.p)],
      );
      // The lower voice's triplet too (Score.simple takes voice 1's only).
      final bar = base.measures.single;
      final layout = layoutOf(base.copyWith(measures: [
        bar.copyWith(tuplets: [
          ...bar.tuplets,
          const TupletSpan(0, 2, actual: 3, normal: 2, voice: 1),
        ]),
      ]));
      final p = layout.primitives
          .whereType<GlyphPrimitive>()
          .firstWhere((g) => g.smuflName == 'dynamicPiano');
      final box = metadata.bBoxOf('dynamicPiano');
      final pTop = p.position.y - box.neY;
      final pLeft = p.position.x + box.swX;
      final pRight = pLeft + box.width;
      // Every other ink under the letters ends above them.
      for (final prim in layout.primitives) {
        if (identical(prim, p)) continue;
        final (double l, double r, double bottom) = switch (prim) {
          LinePrimitive(:final from, :final to) => (
              min(from.x, to.x),
              max(from.x, to.x),
              max(from.y, to.y)
            ),
          GlyphPrimitive(:final smuflName, :final position) => (
              position.x + metadata.bBoxOf(smuflName).swX,
              position.x + metadata.bBoxOf(smuflName).neX,
              position.y - metadata.bBoxOf(smuflName).swY
            ),
          _ => (0, -1, 0),
        };
        if (r <= pLeft || l >= pRight || bottom < 4.5) continue;
        expect(bottom, lessThan(pTop), reason: '$prim');
      }
    });

    test('crescendo opens to the right, diminuendo to the left', () {
      final layout = layoutOf(demo(hairpins: const [
        Hairpin('e0', 'e1', HairpinType.crescendo),
        Hairpin('e2', 'e3', HairpinType.diminuendo),
      ]));
      final thickness =
          metadata.engravingDefault('hairpinThickness', orElse: 0.16);
      final wedgeLines = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) =>
              l.thickness == thickness &&
              l.from.y != l.to.y &&
              l.from.x != l.to.x)
          .toList();
      expect(wedgeLines, hasLength(4));
      // Crescendo: both lines share their left point (the tip).
      final crescendo = wedgeLines.sublist(0, 2);
      expect(crescendo[0].from, crescendo[1].from);
      expect(crescendo[0].to.y, lessThan(crescendo[1].to.y));
      // Diminuendo: tip on the right.
      final diminuendo = wedgeLines.sublist(2, 4);
      expect(diminuendo[0].from, diminuendo[1].from);
      expect(diminuendo[0].from.x, greaterThan(diminuendo[0].to.x));
    });

    test('hairpins sit below the staff and inside the layout bounds', () {
      final layout = layoutOf(
        demo(hairpins: const [Hairpin('e0', 'e3', HairpinType.crescendo)]),
      );
      final thickness =
          metadata.engravingDefault('hairpinThickness', orElse: 0.16);
      for (final line in layout.primitives.whereType<LinePrimitive>().where(
          (l) =>
              l.thickness == thickness &&
              l.from.y != l.to.y &&
              l.from.x != l.to.x)) {
        expect(line.from.y, greaterThan(4.5));
        expect(layout.bounds.containsPoint(line.from), isTrue);
        expect(layout.bounds.containsPoint(line.to), isTrue);
      }
    });

    test('unknown or reversed ids are skipped, not fatal', () {
      // A dynamic on a missing note, a hairpin to a missing note, and a
      // reversed hairpin are each skipped rather than crashing the render.
      expect(
        () => layoutOf(
            demo(dynamics: const [DynamicMarking('nope', DynamicLevel.p)])),
        returnsNormally,
      );
      expect(
        () => layoutOf(demo(
            hairpins: const [Hairpin('e0', 'nope', HairpinType.crescendo)])),
        returnsNormally,
      );
      expect(
        () => layoutOf(
            demo(hairpins: const [Hairpin('e3', 'e0', HairpinType.crescendo)])),
        returnsNormally,
      );
    });

    test('deterministic with dynamics and hairpins', () {
      String render() => layoutOf(demo(
            dynamics: const [
              DynamicMarking('e0', DynamicLevel.p),
              DynamicMarking('e3', DynamicLevel.ff),
            ],
            hairpins: const [Hairpin('e0', 'e3', HairpinType.crescendo)],
          )).primitives.map((p) => p.toString()).join('\n');
      expect(render(), render());
      expect(render(), contains('dynamicPiano'));
      expect(render(), contains('dynamicFF'));
    });
  });
}
