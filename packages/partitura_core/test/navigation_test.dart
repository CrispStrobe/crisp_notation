import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.7.1: navigation marks (Coda, Segno, D.C., D.S., Fine) above the staff.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('model + DSL', () {
    test('!nav directive parses onto the measure', () {
      final score = Score.simple(
        notes: '!nav=segno c4:q | d4:q | !nav=dalSegnoAlFine e4:q',
      );
      expect(score.measures[0].navigation, NavigationMark.segno);
      expect(score.measures[1].navigation, isNull);
      expect(score.measures[2].navigation, NavigationMark.dalSegnoAlFine);
    });

    test('every enum name is a valid directive', () {
      for (final mark in NavigationMark.values) {
        final score = Score.simple(notes: '!nav=${mark.name} c4:q');
        expect(score.measures.single.navigation, mark);
      }
    });

    test('an unknown navigation mark throws', () {
      expect(
        () => Score.simple(notes: '!nav=coda2 c4:q'),
        throwsA(isA<FormatException>()),
      );
    });

    test('targets sit at the start, instructions at the end', () {
      expect(NavigationMark.segno.isTarget, isTrue);
      expect(NavigationMark.coda.isTarget, isTrue);
      expect(NavigationMark.daCapo.isTarget, isFalse);
      expect(NavigationMark.fine.isTarget, isFalse);
    });

    test('navigation participates in measure value equality', () {
      final a = Score.simple(notes: '!nav=fine c4:q');
      final b = Score.simple(notes: '!nav=fine c4:q');
      final c = Score.simple(notes: '!nav=daCapo c4:q');
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('layout', () {
    test('a segno target draws its glyph above the staff at the start', () {
      final layout = layoutOf(Score.simple(notes: '!nav=segno c4:q d4:q'));
      final glyphs = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.segno)
          .toList();
      expect(glyphs, hasLength(1));
      // Above the top staff line (negative y) and near the measure start.
      expect(glyphs.single.position.y, lessThan(0));
      expect(glyphs.single.position.x, lessThan(layout.width / 2));
    });

    test('a coda target uses the coda glyph', () {
      final layout = layoutOf(Score.simple(notes: '!nav=coda c4:q'));
      expect(
        layout.primitives
            .whereType<GlyphPrimitive>()
            .where((g) => g.smuflName == SmuflGlyph.coda),
        hasLength(1),
      );
    });

    test('an instruction draws its label as text above the staff', () {
      final layout =
          layoutOf(Score.simple(notes: 'c4:q d4:q !nav=daCapoAlFine'));
      final texts = layout.primitives.whereType<TextPrimitive>().toList();
      expect(texts, hasLength(1));
      expect(texts.single.text, 'D.C. al Fine');
      expect(texts.single.position.y, lessThan(0));
    });

    test('an instruction is right-aligned toward the closing barline', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q d4:q !nav=fine'));
      final text = layout.primitives.whereType<TextPrimitive>().single;
      // Its center sits past the measure's own midpoint (right-aligned).
      final region = layout.measureRegions.single;
      expect(text.position.x, greaterThan((region.startX + region.endX) / 2));
    });

    test('the mark grows the layout bounding box upward', () {
      final plain = layoutOf(Score.simple(notes: 'c4:q'));
      final withNav = layoutOf(Score.simple(notes: '!nav=coda c4:q'));
      expect(withNav.top, lessThan(plain.top));
    });

    test('layout with navigation is deterministic', () {
      String render() => layoutOf(Score.simple(
            notes: '!nav=segno c4:q | d4:q | !nav=dalSegnoAlCoda e4:q',
          )).primitives.map((p) => p.toString()).join('\n');
      expect(render(), render());
    });
  });

  group('transpose + line breaking preserve navigation', () {
    test('transposedBy keeps the mark', () {
      final score = Score.simple(notes: '!nav=coda c4:q');
      final up = score.transposedBy(Interval.majorSecond);
      expect(up.measures.single.navigation, NavigationMark.coda);
    });

    test('line breaking keeps each measure its own mark', () {
      final score = Score.simple(
        notes: '!nav=segno c4:w | d4:w | e4:w | !nav=dalSegno f4:w',
      );
      final systems = layoutSystems(score, settings, maxWidth: 16).systems;
      final glyphs = [
        for (final system in systems)
          ...system.layout.primitives
              .whereType<GlyphPrimitive>()
              .map((g) => g.smuflName),
      ];
      final texts = [
        for (final system in systems)
          ...system.layout.primitives
              .whereType<TextPrimitive>()
              .map((t) => t.text),
      ];
      expect(glyphs.where((n) => n == SmuflGlyph.segno), hasLength(1));
      expect(texts.where((t) => t == 'D.S.'), hasLength(1));
    });
  });
}
