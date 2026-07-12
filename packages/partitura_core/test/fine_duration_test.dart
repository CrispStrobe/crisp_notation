import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.3.7: 32nd/64th notes and the breve.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<BeamPrimitive> beamsOf(ScoreLayout layout) =>
    layout.primitives.whereType<BeamPrimitive>().toList();

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('durations', () {
    test('fractions: 1/32, 1/64 and the 2/1 breve', () {
      expect(const NoteDuration(DurationBase.thirtySecond).fraction, (1, 32));
      expect(const NoteDuration(DurationBase.sixtyFourth).fraction, (1, 64));
      expect(const NoteDuration(DurationBase.breve).fraction, (2, 1));
      expect(
        const NoteDuration(DurationBase.breve, dots: 1).fraction,
        (3, 1),
      );
      expect(
        const NoteDuration(DurationBase.thirtySecond, dots: 2).fraction,
        (7, 128),
      );
    });

    test('DSL letters t, x, b', () {
      final score = Score.simple(notes: 'c5:t c5:x | c5:b');
      final durations = [
        for (final m in score.measures)
          for (final e in m.elements) e.duration.base,
      ];
      expect(durations, [
        DurationBase.thirtySecond,
        DurationBase.sixtyFourth,
        DurationBase.breve,
      ]);
      // A full 4/4 measure of thirty-seconds sums exactly.
      final full = Score.simple(notes: List.filled(32, 'c5:t').join(' '));
      expect(full.measures.single.totalDuration, Fraction(1, 1));
    });
  });

  group('layout: unbeamed', () {
    test('flags for 32nd and 64th match the stem direction', () {
      // Each note alone in its measure so it flags (rather than beaming over
      // an intervening rest — see the beams-over-rests test).
      final layout = layoutOf(Score.simple(notes: 'c5:t | a4:x | c5:h'));
      final flags = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName.startsWith('flag'))
          .map((g) => g.smuflName)
          .toList();
      expect(flags, ['flag32ndDown', 'flag64thUp']);
    });

    test('multi-flag stems are longer than eighth stems', () {
      double stemLength(String notes) {
        final layout = layoutOf(Score.simple(notes: notes));
        final stem = layout.primitives.whereType<LinePrimitive>().firstWhere(
            (l) => l.from.x == l.to.x && l.thickness == settings.stemThickness);
        return (stem.to.y - stem.from.y).abs();
      }

      expect(stemLength('a4:t'), greaterThan(stemLength('a4:e')));
      expect(stemLength('a4:x'), greaterThan(stemLength('a4:t')));
    });

    test('breve renders a double-whole notehead without a stem', () {
      final layout = layoutOf(Score.simple(notes: 'c5:b'));
      expect(
        layout.primitives
            .whereType<GlyphPrimitive>()
            .where((g) => g.smuflName == SmuflGlyph.noteheadDoubleWhole),
        hasLength(1),
      );
      expect(
        layout.primitives.whereType<LinePrimitive>().where(
            (l) => l.from.x == l.to.x && l.thickness == settings.stemThickness),
        isEmpty,
      );
    });

    test('breve and fine rests use their glyphs', () {
      final layout = layoutOf(Score.simple(notes: 'r:b r:t r:x'));
      expect(
        layout.primitives
            .whereType<GlyphPrimitive>()
            .map((g) => g.smuflName)
            .where((n) => n.startsWith('rest')),
        containsAll(['restDoubleWhole', 'rest32nd', 'rest64th']),
      );
    });

    test('breve advances further than a whole note', () {
      double gap(String d, String glyph) {
        final layout = layoutOf(Score.simple(notes: 'c5:$d d5:$d'));
        final heads = layout.primitives
            .whereType<GlyphPrimitive>()
            .where((g) => g.smuflName == glyph)
            .toList();
        return heads[1].position.x - heads[0].position.x;
      }

      expect(
        gap('b', SmuflGlyph.noteheadDoubleWhole),
        greaterThan(gap('w', SmuflGlyph.noteheadWhole)),
      );
    });
  });

  group('layout: multi-level beams', () {
    test('four 32nds in one beat get three beams', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:t d5 e5 f5 c5:t d5 e5 f5 c5:h.',
      ));
      // Two groups of eight 32nds? No: 8 x 1/32 = 1/4 per beat window.
      // Each window of 8 gets primary + secondary + tertiary.
      expect(beamsOf(layout), hasLength(3));
    });

    test('64ths add a fourth beam level', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '${List.filled(16, 'c5:x').join(' ')} c5:h.',
      ));
      expect(beamsOf(layout), hasLength(4));
    });

    test('mixed 16th/32nd runs get partial tertiary beams', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:s d5:t e5:t f5:s c5:h.',
      ));
      // Primary (all), secondary (all), tertiary only over the two 32nds.
      final beams = beamsOf(layout);
      expect(beams, hasLength(3));
      final tertiary = beams[2];
      final primary = beams[0];
      expect(tertiary.end.x - tertiary.start.x,
          lessThan(primary.end.x - primary.start.x));
    });

    test('beamed multi-level groups keep extended stems', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:t d5 e5 f5 c5:t d5 e5 f5 r:h.',
      ));
      for (final stem in layout.primitives.whereType<LinePrimitive>().where(
          (l) => l.from.x == l.to.x && l.thickness == settings.stemThickness)) {
        expect((stem.to.y - stem.from.y).abs(),
            greaterThanOrEqualTo(settings.stemLength + 0.75 - 0.5));
      }
    });
  });
}
