import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

late final SmuflMetadata metadata;
late final LayoutSettings settings;

/// Eight simple 4/4 measures — wide enough to force breaking at small
/// maxWidth values.
Score eightMeasures() => Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5 | c5:q b4 a4 g4 | f4:q e4 d4 c4 |'
          'e4:q f4 g4 a4 | b4:q a4 g4 f4 | e4:q d4 c4 d4 | c4:w',
    );

List<GlyphPrimitive> glyphsNamed(ScoreLayout layout, String name) =>
    layout.primitives
        .whereType<GlyphPrimitive>()
        .where((g) => g.smuflName == name)
        .toList();

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('packing', () {
    test('everything on one system when it fits', () {
      final score = eightMeasures();
      final multi = layoutSystems(score, settings, maxWidth: 10000);
      expect(multi.systems, hasLength(1));
      expect(multi.systems.single.firstMeasure, 0);
      expect(multi.systems.single.lastMeasure, 7);
      // Identical to the plain single-line layout.
      final plain = const LayoutEngine().layout(score, settings);
      expect(multi.systems.single.layout.width, plain.width);
      expect(multi.systems.single.layout.primitives.length,
          plain.primitives.length);
    });

    test('systems cover all measures contiguously in order', () {
      final multi = layoutSystems(eightMeasures(), settings, maxWidth: 40);
      expect(multi.systems.length, greaterThan(1));
      var next = 0;
      for (final system in multi.systems) {
        expect(system.firstMeasure, next);
        expect(system.lastMeasure, greaterThanOrEqualTo(system.firstMeasure));
        next = system.lastMeasure + 1;
      }
      expect(next, 8);
    });

    test('no system exceeds maxWidth (multi-measure systems)', () {
      for (final maxWidth in [30.0, 40.0, 55.0, 80.0]) {
        final multi =
            layoutSystems(eightMeasures(), settings, maxWidth: maxWidth);
        for (final system in multi.systems) {
          if (system.lastMeasure > system.firstMeasure) {
            expect(system.layout.width, lessThanOrEqualTo(maxWidth),
                reason: 'maxWidth $maxWidth, system $system');
          }
        }
      }
    });

    test('an overwide measure gets its own system instead of failing', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:s d4 e4 f4 g4 a4 b4 c5 c5 b4 a4 g4 f4 e4 d4 c4 | c4:w',
      );
      final multi = layoutSystems(score, settings, maxWidth: 12);
      expect(multi.systems.first.firstMeasure, 0);
      expect(multi.systems.first.lastMeasure, 0);
      expect(multi.systems.first.layout.width, greaterThan(12));
      expect(multi.systems, hasLength(2));
    });

    test('maxWidth must be positive', () {
      expect(
        () => layoutSystems(eightMeasures(), settings, maxWidth: 0),
        throwsArgumentError,
      );
    });
  });

  group('justification', () {
    test('non-final systems are stretched to maxWidth', () {
      const maxWidth = 45.0;
      final multi =
          layoutSystems(eightMeasures(), settings, maxWidth: maxWidth);
      expect(multi.systems.length, greaterThan(1));
      for (final system in multi.systems.take(multi.systems.length - 1)) {
        expect(system.layout.width, closeTo(maxWidth, 0.1),
            reason: 'system $system');
      }
    });

    test('the final system keeps its natural width', () {
      const maxWidth = 45.0;
      final justified =
          layoutSystems(eightMeasures(), settings, maxWidth: maxWidth);
      final natural = layoutSystems(eightMeasures(), settings,
          maxWidth: maxWidth, justify: false);
      expect(justified.systems.last.layout.width,
          closeTo(natural.systems.last.layout.width, 1e-9));
    });

    test('justify: false keeps natural widths everywhere', () {
      const maxWidth = 45.0;
      final multi = layoutSystems(eightMeasures(), settings,
          maxWidth: maxWidth, justify: false);
      for (final system in multi.systems) {
        expect(system.layout.width, lessThanOrEqualTo(maxWidth));
      }
      // At least one non-final system is visibly narrower than maxWidth.
      final slack = multi.systems
          .take(multi.systems.length - 1)
          .map((s) => maxWidth - s.layout.width);
      expect(slack.any((gap) => gap > 1), isTrue);
    });

    test('justification stretches note spacing, not the leading segment', () {
      const maxWidth = 45.0;
      final multi =
          layoutSystems(eightMeasures(), settings, maxWidth: maxWidth);
      final natural = layoutSystems(eightMeasures(), settings,
          maxWidth: maxWidth, justify: false);
      final justified = multi.systems.first.layout;
      final unjustified = natural.systems.first.layout;
      // Same leading width (clef at the same spot)…
      expect(justified.measureRegions.first.startX,
          closeTo(unjustified.measureRegions.first.startX, 1e-9));
      // …but wider measures.
      expect(justified.measureRegions.last.endX,
          greaterThan(unjustified.measureRegions.last.endX));
    });
  });

  group('state restatement across breaks', () {
    test('every system restates clef and key signature', () {
      final score = Score.simple(
        keySignature: const KeySignature(2), // D major
        timeSignature: TimeSignature.fourFour,
        notes: 'd4:q e4 g4 a4 | b4:q a4 g4 e4 | d4:q e4 g4 a4 | d4:w',
      );
      final multi = layoutSystems(score, settings, maxWidth: 35);
      expect(multi.systems.length, greaterThan(1));
      for (final system in multi.systems) {
        final clefs = glyphsNamed(system.layout, SmuflGlyph.gClef);
        expect(clefs, isNotEmpty, reason: 'system $system');
        expect(clefs.first.position.x, lessThan(3));
        // D major: two leading sharps on every system.
        final sharps = glyphsNamed(system.layout, SmuflGlyph.accidentalSharp)
            .where((g) => g.elementId == null);
        expect(sharps.length, 2, reason: 'system $system');
      }
    });

    test('the time signature appears only on the first system', () {
      final multi = layoutSystems(eightMeasures(), settings, maxWidth: 40);
      expect(multi.systems.length, greaterThan(1));
      final first =
          glyphsNamed(multi.systems.first.layout, SmuflGlyph.timeSigDigit(4));
      expect(first, isNotEmpty);
      for (final system in multi.systems.skip(1)) {
        expect(
          glyphsNamed(system.layout, SmuflGlyph.timeSigDigit(4)),
          isEmpty,
          reason: 'system $system',
        );
      }
    });

    test('beaming still follows the time signature on later systems', () {
      // 3/4: six eighths beam in three pairs, never four.
      final score = Score.simple(
        timeSignature: const TimeSignature(3, 4),
        notes: 'c4:e d4 e4 f4 g4 a4 | c4:e d4 e4 f4 g4 a4 |'
            'c4:e d4 e4 f4 g4 a4 | c4:h.',
      );
      final multi = layoutSystems(score, settings, maxWidth: 30);
      expect(multi.systems.length, greaterThan(1));
      for (final system in multi.systems) {
        final beams =
            system.layout.primitives.whereType<BeamPrimitive>().toList();
        // Each 3/4 eighth measure carries exactly three pair beams; the
        // closing dotted half carries none.
        expect(beams.length % 3, 0,
            reason: 'three beam pairs per 3/4 measure, system $system');
      }
    });

    test(
        'a mid-score clef change landing on a break becomes the leading '
        'clef of the next system', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5 |'
            '!clef=bass c3:q d3 e3 f3 | g3:q f3 e3 d3',
      );
      // Break after measure 1 → measure 2 starts a system in bass clef.
      final multi = layoutSystems(score, settings, maxWidth: 32);
      final bassSystem = multi.systems
          .firstWhere((s) => s.firstMeasure <= 2 && 2 <= s.lastMeasure);
      if (bassSystem.firstMeasure == 2) {
        final fClefs = glyphsNamed(bassSystem.layout, SmuflGlyph.fClef);
        expect(fClefs, isNotEmpty);
        expect(fClefs.first.position.x, lessThan(3));
        // Full-size leading clef, not the 0.8× change glyph.
        expect(fClefs.first.scale, 1.0);
        // No treble clef on that system.
        expect(glyphsNamed(bassSystem.layout, SmuflGlyph.gClef), isEmpty);
      } else {
        fail('expected the clef-change measure to start a system '
            '(got $bassSystem)');
      }
    });

    test('a clef change inside a system keeps its inline change glyph', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | !clef=bass c3:q d3 e3 f3',
      );
      final multi = layoutSystems(score, settings, maxWidth: 10000);
      final layout = multi.systems.single.layout;
      final fClefs = glyphsNamed(layout, SmuflGlyph.fClef);
      expect(fClefs, hasLength(1));
      expect(fClefs.single.scale, 0.8); // inline change size
    });
  });

  group('span filtering', () {
    test('slurs within one system survive, slurs across breaks are dropped',
        () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q( d4) e4 f4 | g4:q a4 b4 c5 | c5:q( b4 a4 g4) | c4:w',
      );
      // One-line reference: two slur curves.
      final oneLine = layoutSystems(score, settings, maxWidth: 10000);
      final oneLineCurves = oneLine.systems.single.layout.primitives
          .whereType<CurvePrimitive>()
          .length;
      expect(oneLineCurves, 2);

      // Broken: each slur sits inside a single measure, so both survive
      // wherever the breaks fall.
      final multi = layoutSystems(score, settings, maxWidth: 35);
      expect(multi.systems.length, greaterThan(1));
      final total = multi.systems
          .map((s) => s.layout.primitives.whereType<CurvePrimitive>().length)
          .reduce((a, b) => a + b);
      expect(total, 2);
    });

    test('a slur spanning a system break is dropped', () {
      // Slur from measure 0 into measure 3 — forced to break apart.
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q( d4 e4 f4 | g4:q a4 b4 c5 | c5:q b4 a4 g4) | c4:w',
      );
      final multi = layoutSystems(score, settings, maxWidth: 35);
      final slurStart = multi.systems.first;
      final slurEndSystem = multi.systems
          .firstWhere((s) => s.firstMeasure <= 2 && 2 <= s.lastMeasure);
      expect(identical(slurStart, slurEndSystem), isFalse,
          reason: 'the slur must actually span a break for this test');
      for (final system in multi.systems) {
        expect(
          system.layout.primitives.whereType<CurvePrimitive>(),
          isEmpty,
          reason: 'system $system',
        );
      }
    });

    test('dynamics stay attached to their notes on any system', () {
      final base = eightMeasures();
      final score = Score(
        clef: base.clef,
        keySignature: base.keySignature,
        timeSignature: base.timeSignature,
        measures: base.measures,
        dynamics: const [
          DynamicMarking('e0', DynamicLevel.p),
          DynamicMarking('e20', DynamicLevel.f),
        ],
      );
      final multi = layoutSystems(score, settings, maxWidth: 40);
      final dynamicGlyphs = multi.systems
          .expand((s) => s.layout.primitives.whereType<GlyphPrimitive>())
          .where((g) => g.smuflName.startsWith('dynamic'))
          .toList();
      expect(dynamicGlyphs, hasLength(2));
    });

    test('a hairpin across a break is dropped, one inside survives', () {
      final base = eightMeasures();
      final score = Score(
        clef: base.clef,
        keySignature: base.keySignature,
        timeSignature: base.timeSignature,
        measures: base.measures,
        hairpins: const [
          Hairpin('e0', 'e2', HairpinType.crescendo), // inside measure 0
          Hairpin('e2', 'e28', HairpinType.diminuendo), // spans everything
        ],
      );
      final oneLine = layoutSystems(score, settings, maxWidth: 10000);
      final hairpinLines = oneLine.systems.single.layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.y != l.to.y && l.from.x != l.to.x)
          .length;
      expect(hairpinLines, 4); // two wedges, two strokes each

      final multi = layoutSystems(score, settings, maxWidth: 40);
      final broken = multi.systems
          .expand((s) => s.layout.primitives.whereType<LinePrimitive>())
          .where((l) => l.from.y != l.to.y && l.from.x != l.to.x)
          .length;
      expect(broken, 2); // only the measure-0 crescendo remains
    });
  });

  group('content preservation', () {
    test('total tagged noteheads match the single-line layout', () {
      final score = eightMeasures();
      final plain = const LayoutEngine().layout(score, settings);
      int noteheads(ScoreLayout layout) => layout.primitives
          .whereType<GlyphPrimitive>()
          .where(
              (g) => g.smuflName.startsWith('notehead') && g.elementId != null)
          .length;
      for (final maxWidth in [30.0, 45.0, 70.0]) {
        final multi = layoutSystems(score, settings, maxWidth: maxWidth);
        final total = multi.systems
            .map((s) => noteheads(s.layout))
            .reduce((a, b) => a + b);
        expect(total, noteheads(plain), reason: 'maxWidth $maxWidth');
      }
    });

    test('element regions keep their ids across systems', () {
      final multi = layoutSystems(eightMeasures(), settings, maxWidth: 40);
      final ids = <String>{};
      for (final system in multi.systems) {
        for (final region in system.layout.regions) {
          expect(ids.add(region.elementId), isTrue,
              reason: '${region.elementId} appears on two systems');
        }
      }
      expect(ids.length, 29); // 7×4 quarters + 1 whole
    });
  });

  group('MultiSystemLayout', () {
    test('heightWith stacks system heights plus gaps', () {
      final multi = layoutSystems(eightMeasures(), settings, maxWidth: 40);
      final sum =
          multi.systems.map((s) => s.layout.height).reduce((a, b) => a + b);
      expect(
        multi.heightWith(3),
        closeTo(sum + 3 * (multi.systems.length - 1), 1e-9),
      );
    });

    test('toString names the measure range', () {
      final multi = layoutSystems(eightMeasures(), settings, maxWidth: 10000);
      expect(multi.systems.single.toString(), contains('0..7'));
      expect(multi.toString(), contains('1 systems'));
    });
  });
}
