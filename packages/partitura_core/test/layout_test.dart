import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<GlyphPrimitive> glyphsNamed(ScoreLayout layout, String name) =>
    layout.primitives
        .whereType<GlyphPrimitive>()
        .where((g) => g.smuflName == name)
        .toList();

/// Vertical lines with stem thickness = stems.
List<LinePrimitive> stemsOf(ScoreLayout layout) => layout.primitives
    .whereType<LinePrimitive>()
    .where((l) => l.from.x == l.to.x && l.thickness == settings.stemThickness)
    .toList();

/// Horizontal element-tagged lines with ledger thickness = ledger lines.
List<LinePrimitive> ledgerLinesOf(ScoreLayout layout) => layout.primitives
    .whereType<LinePrimitive>()
    .where((l) =>
        l.from.y == l.to.y &&
        l.thickness == settings.legerLineThickness &&
        l.elementId != null)
    .toList();

/// Vertical full-staff lines with thin-barline thickness = thin barlines.
List<LinePrimitive> thinBarlinesOf(ScoreLayout layout) => layout.primitives
    .whereType<LinePrimitive>()
    .where((l) =>
        l.from.x == l.to.x &&
        l.from.y == 0 &&
        l.to.y == 4 &&
        l.thickness == settings.thinBarlineThickness)
    .toList();

List<BeamPrimitive> beamsOf(ScoreLayout layout) =>
    layout.primitives.whereType<BeamPrimitive>().toList();

List<GlyphPrimitive> taggedAccidentalsOf(ScoreLayout layout) => layout
    .primitives
    .whereType<GlyphPrimitive>()
    .where((g) => g.smuflName.startsWith('accidental') && g.elementId != null)
    .toList();

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('rule 1: staff and clef', () {
    test('five staff lines at y = 0..4 across the full width', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q'));
      final staffLines = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.thickness == settings.staffLineThickness)
          .toList();
      expect(staffLines, hasLength(5));
      for (var i = 0; i < 5; i++) {
        expect(staffLines[i].from, Point(0.0, i.toDouble()));
        expect(staffLines[i].to, Point(layout.width, i.toDouble()));
      }
    });

    test('gClef anchored on the G4 line (y = 3)', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q'));
      final clef = glyphsNamed(layout, SmuflGlyph.gClef).single;
      expect(clef.position.y, 3.0);
      expect(clef.elementId, isNull);
    });

    test('fClef anchored on the F3 line (y = 1)', () {
      final layout = layoutOf(Score.simple(clef: Clef.bass, notes: 'c3:q'));
      final clef = glyphsNamed(layout, SmuflGlyph.fClef).single;
      expect(clef.position.y, 1.0);
    });
  });

  group('rule 2: key signature', () {
    test('F# major: six sharps at F C G D A E positions (treble)', () {
      final layout = layoutOf(Score.simple(
        keySignature: const KeySignature(6),
        notes: 'c4:q',
      ));
      final sharps = glyphsNamed(layout, SmuflGlyph.accidentalSharp);
      expect(sharps, hasLength(6));
      // Staff positions 8 5 9 6 3 7 -> y = (8 - p) / 2.
      expect(
        sharps.map((g) => g.position.y).toList(),
        [0.0, 1.5, -0.5, 1.0, 2.5, 0.5],
      );
      // Left to right in writing order.
      final xs = sharps.map((g) => g.position.x).toList();
      expect(xs, orderedEquals([...xs]..sort()));
    });

    test('Ab major: four flats at B E A D positions (treble)', () {
      final layout = layoutOf(Score.simple(
        keySignature: const KeySignature(-4),
        notes: 'c4:q',
      ));
      final flats = glyphsNamed(layout, SmuflGlyph.accidentalFlat);
      expect(flats, hasLength(4));
      // Staff positions 4 7 3 6.
      expect(
        flats.map((g) => g.position.y).toList(),
        [2.0, 0.5, 2.5, 1.0],
      );
    });

    test('bass clef shifts every accidental down a third', () {
      final treble = layoutOf(Score.simple(
        keySignature: const KeySignature(3),
        notes: 'c4:q',
      ));
      final bass = layoutOf(Score.simple(
        clef: Clef.bass,
        keySignature: const KeySignature(3),
        notes: 'c3:q',
      ));
      final trebleYs = glyphsNamed(treble, SmuflGlyph.accidentalSharp)
          .map((g) => g.position.y)
          .toList();
      final bassYs = glyphsNamed(bass, SmuflGlyph.accidentalSharp)
          .map((g) => g.position.y)
          .toList();
      expect(bassYs, [for (final y in trebleYs) y + 1.0]);
    });

    test('C major draws no signature accidentals', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q'));
      expect(glyphsNamed(layout, SmuflGlyph.accidentalSharp), isEmpty);
      expect(glyphsNamed(layout, SmuflGlyph.accidentalFlat), isEmpty);
    });
  });

  group('rule 3: time signature', () {
    test('3/4: digits vertically centered at y = 1 and y = 3', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.threeFour,
        notes: 'c4:q d4 e4',
      ));
      expect(glyphsNamed(layout, 'timeSig3').single.position.y, 1.0);
      expect(glyphsNamed(layout, 'timeSig4').single.position.y, 3.0);
    });

    test('12/8: multi-digit numerator, denominator centered under it', () {
      final layout = layoutOf(Score.simple(
        timeSignature: const TimeSignature(12, 8),
        notes: 'c4:q',
      ));
      final one = glyphsNamed(layout, 'timeSig1').single;
      final two = glyphsNamed(layout, 'timeSig2').single;
      final eight = glyphsNamed(layout, 'timeSig8').single;
      expect(one.position.y, 1.0);
      expect(two.position.y, 1.0);
      expect(eight.position.y, 3.0);
      expect(two.position.x, greaterThan(one.position.x));
      // Denominator sits horizontally within the numerator group.
      expect(eight.position.x, greaterThan(one.position.x));
      expect(eight.position.x, lessThan(two.position.x));
    });

    test('unmetered score draws no time signature', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q'));
      for (var d = 0; d <= 9; d++) {
        expect(glyphsNamed(layout, SmuflGlyph.timeSigDigit(d)), isEmpty);
      }
    });
  });

  group('rule 4: noteheads', () {
    test('glyph follows duration', () {
      final layout = layoutOf(Score.simple(notes: 'c5:w d5:h e5:q f5:e g5:s'));
      expect(glyphsNamed(layout, SmuflGlyph.noteheadWhole), hasLength(1));
      expect(glyphsNamed(layout, SmuflGlyph.noteheadHalf), hasLength(1));
      expect(glyphsNamed(layout, SmuflGlyph.noteheadBlack), hasLength(3));
    });

    test('vertical position from staffPosition', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q b4 f5'));
      final heads = glyphsNamed(layout, SmuflGlyph.noteheadBlack);
      // C4 p=-2 -> y=5; B4 p=4 -> y=2; F5 p=8 -> y=0.
      expect(heads.map((g) => g.position.y).toList(), [5.0, 2.0, 0.0]);
    });

    test('bass clef positions differ', () {
      final layout = layoutOf(Score.simple(clef: Clef.bass, notes: 'd3:q c4'));
      final heads = glyphsNamed(layout, SmuflGlyph.noteheadBlack);
      // D3 p=4 -> y=2 (middle line); C4 p=10 -> y=-1 (ledger above).
      expect(heads.map((g) => g.position.y).toList(), [2.0, -1.0]);
    });
  });

  group('rule 5: stems', () {
    test('down on or above the middle line, up below', () {
      final layout = layoutOf(Score.simple(notes: 'a4:q b4'));
      final stems = stemsOf(layout);
      expect(stems, hasLength(2));
      // A4 (p=3, y=2.5): stem up -> tip above the notehead.
      expect(stems[0].to.y, closeTo(2.5 - 3.5, 1e-9));
      expect(stems[0].to.y, lessThan(stems[0].from.y));
      // B4 (p=4, y=2): stem down -> tip below.
      expect(stems[1].to.y, closeTo(2.0 + 3.5, 1e-9));
      expect(stems[1].to.y, greaterThan(stems[1].from.y));
    });

    test('default length is one octave (3.5 spaces)', () {
      final layout = layoutOf(Score.simple(notes: 'g4:q'));
      final stem = stemsOf(layout).single;
      // G4 y=3, stem up: tip at -0.5; attachment near the notehead.
      expect(stem.to.y, closeTo(-0.5, 1e-9));
      expect(stem.from.y, closeTo(3.0, 0.3));
    });

    test('far ledger notes extend to the middle line', () {
      // C6 (p=12, y=-2): stem down, default tip 1.5 -> extended to 2.
      final high = layoutOf(Score.simple(notes: 'c6:q'));
      expect(stemsOf(high).single.to.y, 2.0);
      // A3 (p=-4, y=6): stem up, default tip 2.5 -> extended to 2.
      final low = layoutOf(Score.simple(notes: 'a3:q'));
      expect(stemsOf(low).single.to.y, 2.0);
    });

    test('up-stems attach right of the notehead, down-stems left', () {
      final layout = layoutOf(Score.simple(notes: 'a4:q c5'));
      final heads = glyphsNamed(layout, SmuflGlyph.noteheadBlack);
      final stems = stemsOf(layout);
      final headWidth = metadata.bBoxOf(SmuflGlyph.noteheadBlack).width;
      // A4 up: stem near the right edge.
      expect(
        stems[0].from.x,
        closeTo(heads[0].position.x + headWidth, 0.15),
      );
      // C5 down: stem near the left edge.
      expect(stems[1].from.x, closeTo(heads[1].position.x, 0.15));
    });

    test('whole notes have no stem', () {
      final layout = layoutOf(Score.simple(notes: 'c5:w'));
      expect(stemsOf(layout), isEmpty);
    });
  });

  group('rule 6: flags', () {
    test('unbeamed eighths and sixteenths get flags matching stem direction',
        () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'a4:e r:e c5:s r:e. g4:q',
      ));
      expect(glyphsNamed(layout, SmuflGlyph.flag8thUp), hasLength(1));
      expect(glyphsNamed(layout, SmuflGlyph.flag16thDown), hasLength(1));
      expect(glyphsNamed(layout, SmuflGlyph.flag8thDown), isEmpty);
      expect(glyphsNamed(layout, SmuflGlyph.flag16thUp), isEmpty);
    });

    test('flag sits at the stem tip', () {
      final layout = layoutOf(Score.simple(notes: 'a4:e'));
      final stem = stemsOf(layout).single;
      final flag = glyphsNamed(layout, SmuflGlyph.flag8thUp).single;
      expect(flag.position.y, stem.to.y);
      expect(flag.position.x, closeTo(stem.from.x, 0.1));
    });

    test('beamed notes get no flags', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:e d5 e5 f5 g5 a5 b5 c6',
      ));
      expect(glyphsNamed(layout, SmuflGlyph.flag8thUp), isEmpty);
      expect(glyphsNamed(layout, SmuflGlyph.flag8thDown), isEmpty);
    });
  });

  group('rule 7: beaming', () {
    test('4/4 measure of 8 eighths yields 2 beams', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:e d5 e5 f5 g5 a5 b5 c6',
      ));
      expect(beamsOf(layout), hasLength(2));
      expect(stemsOf(layout), hasLength(8));
    });

    test('3/4 measure of 6 eighths yields 3 beams (per beat)', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.threeFour,
        notes: 'c5:e d5 e5 f5 g5 a5',
      ));
      expect(beamsOf(layout), hasLength(3));
    });

    test('no beaming across rests', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:e r:e d5:e e5:e c5:h',
      ));
      // c5 is alone -> flag; d5+e5 share a beat -> one beam.
      expect(beamsOf(layout), hasLength(1));
      expect(glyphsNamed(layout, SmuflGlyph.flag8thDown), hasLength(1));
    });

    test('no beaming across beats (quarter groups for sixteenths)', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:s d5 e5 f5 g5 a5 b5 c6 c5:h',
      ));
      // Two beat groups of 4 sixteenths, each with primary + secondary.
      expect(beamsOf(layout), hasLength(4));
    });

    test(
        'secondary beams subdivide at the quarter within a longer beat '
        '(cut time)', () {
      // In cut time the beat is a half note, so all eight sixteenths beam as
      // one group. The primary beam stays continuous across the beat while the
      // secondary beam breaks at the quarter-note metric point — two secondary
      // segments, not one over-long one.
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.cutTime,
        notes: 'c5:s d5 e5 f5 g5 a5 b5 c6 r:h',
      ));
      final beams = beamsOf(layout);
      // One continuous primary + two subdivided secondary segments.
      expect(beams, hasLength(3));

      final byWidth = [...beams]
        ..sort((a, b) => (a.end.x - a.start.x).compareTo(b.end.x - b.start.x));
      final primary = byWidth.last; // spans the whole group
      final secondaries = byWidth.take(2).toList()
        ..sort((a, b) => a.start.x.compareTo(b.start.x));

      final fullWidth = primary.end.x - primary.start.x;
      for (final secondary in secondaries) {
        // Offset toward the noteheads, and shorter than the primary.
        expect(secondary.start.y, isNot(primary.start.y));
        expect(secondary.end.x - secondary.start.x, lessThan(fullWidth));
      }
      // A real break at the quarter: the two secondary segments do not touch.
      expect(secondaries[0].end.x, lessThan(secondaries[1].start.x));
    });

    test('sixteenths get a secondary beam', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:s d5 e5 f5 r:q r:h',
      ));
      final beams = beamsOf(layout);
      expect(beams, hasLength(2));
      // Secondary beam is offset toward the noteheads (down-stems: above).
      expect(beams[1].start.y, isNot(beams[0].start.y));
      expect((beams[1].start.y - beams[0].start.y).abs(),
          closeTo(settings.beamThickness + settings.beamSpacing, 1e-9));
    });

    test('lone sixteenth between eighths gets a beamlet stub', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:e d5:s e5:s r:q r:h',
      ));
      // Group c5(e) d5(s) e5(s): primary + one secondary for d5-e5 run.
      final beams = beamsOf(layout);
      expect(beams, hasLength(2));
      final primary = beams[0];
      final secondary = beams[1];
      expect(secondary.end.x - secondary.start.x,
          lessThan(primary.end.x - primary.start.x));
    });

    test('beam slant is clamped to one staff space', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:e c6 c5 c6 c5 c6 c5 c6',
      ));
      for (final beam in beamsOf(layout)) {
        expect((beam.end.y - beam.start.y).abs(), lessThanOrEqualTo(1.0));
      }
    });

    test('all stems in a beamed group share a direction and reach the beam',
        () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'g4:e a4 b4 c5 r:h',
      ));
      final beam = beamsOf(layout).single;
      final stems = stemsOf(layout);
      expect(stems, hasLength(4));
      for (final stem in stems) {
        // G4 lies farther below the middle line than C5 above it, so the
        // whole group stems up.
        expect(stem.to.y, lessThan(stem.from.y + 1e-9));
        final t = (stem.from.x - beam.start.x) / (beam.end.x - beam.start.x);
        final beamYAtStem = beam.start.y + t * (beam.end.y - beam.start.y);
        expect(stem.to.y, closeTo(beamYAtStem, 1e-9));
      }
    });
  });

  group('rule 8: ledger lines', () {
    test('C4 in treble gets one ledger line through the notehead', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q'));
      final ledgers = ledgerLinesOf(layout);
      expect(ledgers, hasLength(1));
      expect(ledgers.single.from.y, 5.0);
    });

    test('A3 in treble gets two ledger lines (C4 and A3 lines)', () {
      final layout = layoutOf(Score.simple(notes: 'a3:q'));
      expect(
        ledgerLinesOf(layout).map((l) => l.from.y).toSet(),
        {5.0, 6.0},
      );
    });

    test('notes above the staff: G5 none, A5 and B5 one, C6 two', () {
      expect(ledgerLinesOf(layoutOf(Score.simple(notes: 'g5:q'))), isEmpty);
      final a5 = ledgerLinesOf(layoutOf(Score.simple(notes: 'a5:q')));
      expect(a5.map((l) => l.from.y).toList(), [-1.0]);
      final b5 = ledgerLinesOf(layoutOf(Score.simple(notes: 'b5:q')));
      expect(b5.map((l) => l.from.y).toList(), [-1.0]);
      final c6 = ledgerLinesOf(layoutOf(Score.simple(notes: 'c6:q')));
      expect(c6.map((l) => l.from.y).toSet(), {-1.0, -2.0});
    });

    test('ledger lines extend beyond the notehead on both sides', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q'));
      final head = glyphsNamed(layout, SmuflGlyph.noteheadBlack).single;
      final headWidth = metadata.bBoxOf(SmuflGlyph.noteheadBlack).width;
      final ledger = ledgerLinesOf(layout).single;
      expect(ledger.from.x,
          closeTo(head.position.x - settings.legerLineExtension, 1e-9));
      expect(
        ledger.to.x,
        closeTo(
          head.position.x + headWidth + settings.legerLineExtension,
          1e-9,
        ),
      );
    });
  });

  group('rule 9: accidentals', () {
    test('shown when deviating from the key signature, tracked per measure',
        () {
      final layout = layoutOf(Score.simple(notes: 'f#4:q f#4 f4 | f4'));
      final tagged = taggedAccidentalsOf(layout);
      // f#4 -> sharp; second f#4 -> implied, none; f4 -> natural (cancels);
      // f4 after the barline -> implied natural again, none.
      expect(tagged, hasLength(2));
      expect(tagged[0].smuflName, SmuflGlyph.accidentalSharp);
      expect(tagged[1].smuflName, SmuflGlyph.accidentalNatural);
    });

    test('key signature pitches need no accidental', () {
      final layout = layoutOf(Score.simple(
        keySignature: const KeySignature(2), // D major: F#, C#
        notes: 'f#4:q c#5',
      ));
      expect(taggedAccidentalsOf(layout), isEmpty);
    });

    test('natural against the key signature is drawn', () {
      final layout = layoutOf(Score.simple(
        keySignature: const KeySignature(-1), // F major: Bb
        notes: 'bn4:q',
      ));
      final tagged = taggedAccidentalsOf(layout);
      expect(tagged.single.smuflName, SmuflGlyph.accidentalNatural);
    });

    test('accidental state is per octave', () {
      final layout = layoutOf(Score.simple(notes: 'f#4:q f#5'));
      // F#5 is a different staff position: needs its own sharp.
      expect(taggedAccidentalsOf(layout), hasLength(2));
    });

    test('showAccidental forces a courtesy accidental', () {
      // 'n' in the DSL sets showAccidental: true on a natural pitch.
      final layout = layoutOf(Score.simple(notes: 'cn5:q'));
      final tagged = taggedAccidentalsOf(layout);
      expect(tagged.single.smuflName, SmuflGlyph.accidentalNatural);
    });

    test('accidental sits left of the notehead with clearance', () {
      final layout = layoutOf(Score.simple(notes: 'f#4:q'));
      final head = glyphsNamed(layout, SmuflGlyph.noteheadBlack).single;
      final sharp = glyphsNamed(layout, SmuflGlyph.accidentalSharp).single;
      final sharpWidth = metadata.bBoxOf(SmuflGlyph.accidentalSharp).width;
      expect(sharp.position.y, head.position.y);
      expect(
        sharp.position.x + sharpWidth,
        lessThanOrEqualTo(head.position.x - settings.accidentalGap + 1e-9),
      );
    });

    test('chord accidentals stack in columns', () {
      final layout = layoutOf(Score.simple(notes: 'f#4+g#4:q'));
      final sharps = glyphsNamed(layout, SmuflGlyph.accidentalSharp);
      expect(sharps, hasLength(2));
      expect(sharps[0].position.x, isNot(sharps[1].position.x));
    });
  });

  group('rule 10: augmentation dots', () {
    test('dot right of the notehead; line notes dot the space above', () {
      final layout = layoutOf(Score.simple(notes: 'b4:q. a4:q.'));
      final dots = glyphsNamed(layout, SmuflGlyph.augmentationDot);
      expect(dots, hasLength(2));
      // B4 on the middle line (y=2): dot in the space above (y=1.5).
      expect(dots[0].position.y, 1.5);
      // A4 in a space (y=2.5): dot on the same y.
      expect(dots[1].position.y, 2.5);
      final heads = glyphsNamed(layout, SmuflGlyph.noteheadBlack);
      expect(dots[0].position.x, greaterThan(heads[0].position.x));
    });

    test('double dots', () {
      final layout = layoutOf(Score.simple(notes: 'a4:h..'));
      expect(
        glyphsNamed(layout, SmuflGlyph.augmentationDot),
        hasLength(2),
      );
    });

    test('rest dots sit in the third space', () {
      final layout = layoutOf(Score.simple(notes: 'r:q.'));
      final dot = glyphsNamed(layout, SmuflGlyph.augmentationDot).single;
      expect(dot.position.y, 1.5);
    });
  });

  group('rule 11: chords', () {
    test('one shared stem spanning the chord', () {
      final layout = layoutOf(Score.simple(notes: 'c4+e4+g4:q'));
      final stems = stemsOf(layout);
      expect(stems, hasLength(1));
      expect(
        glyphsNamed(layout, SmuflGlyph.noteheadBlack),
        hasLength(3),
      );
      // Up-stem: from near the bottom note (C4, y=5) to above the top
      // note (G4, y=3): tip at 3 - 3.5 = -0.5.
      expect(stems.single.to.y, closeTo(-0.5, 1e-9));
      expect(stems.single.from.y, closeTo(5.0, 0.3));
    });

    test('a second offsets the interfering notehead across the stem', () {
      final layout = layoutOf(Score.simple(notes: 'c4+d4:q'));
      final heads = glyphsNamed(layout, SmuflGlyph.noteheadBlack);
      expect(heads, hasLength(2));
      // Up-stem chord: the upper note of the second flips to the right.
      final c4 = heads.firstWhere((h) => h.position.y == 5.0);
      final d4 = heads.firstWhere((h) => h.position.y == 4.5);
      expect(d4.position.x, greaterThan(c4.position.x));
    });

    test('non-adjacent chord notes share one column', () {
      final layout = layoutOf(Score.simple(notes: 'c4+e4:q'));
      final heads = glyphsNamed(layout, SmuflGlyph.noteheadBlack);
      expect(heads[0].position.x, heads[1].position.x);
    });
  });

  group('rule 12: rests', () {
    test('conventional glyphs and vertical homes', () {
      final layout = layoutOf(Score.simple(notes: 'r:w r:h r:q r:e r:s'));
      expect(
        glyphsNamed(layout, SmuflGlyph.restWhole).single.position.y,
        1.0,
      );
      expect(
        glyphsNamed(layout, SmuflGlyph.restHalf).single.position.y,
        2.0,
      );
      expect(
        glyphsNamed(layout, SmuflGlyph.restQuarter).single.position.y,
        2.0,
      );
      expect(glyphsNamed(layout, SmuflGlyph.rest8th).single.position.y, 2.0);
      expect(
        glyphsNamed(layout, SmuflGlyph.rest16th).single.position.y,
        2.0,
      );
    });
  });

  group('rule 13: horizontal spacing and barlines', () {
    test('longer durations advance further', () {
      final quarters = layoutOf(Score.simple(notes: 'c5:q d5:q'));
      final halves = layoutOf(Score.simple(notes: 'c5:h d5:h'));
      double gap(ScoreLayout l, String glyph) {
        final heads = glyphsNamed(l, glyph);
        return heads[1].position.x - heads[0].position.x;
      }

      expect(
        gap(halves, SmuflGlyph.noteheadHalf),
        greaterThan(gap(quarters, SmuflGlyph.noteheadBlack)),
      );
    });

    test('leading elements come in clef, key, time, notes order', () {
      final layout = layoutOf(Score.simple(
        keySignature: const KeySignature(2),
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:w',
      ));
      final clefX = glyphsNamed(layout, SmuflGlyph.gClef).single.position.x;
      final keyX = glyphsNamed(layout, SmuflGlyph.accidentalSharp)
          .map((g) => g.position.x)
          .reduce(min);
      final timeX =
          glyphsNamed(layout, 'timeSig4').map((g) => g.position.x).reduce(min);
      final noteX =
          glyphsNamed(layout, SmuflGlyph.noteheadWhole).single.position.x;
      expect(clefX, lessThan(keyX));
      expect(keyX, lessThan(timeX));
      expect(timeX, lessThan(noteX));
    });

    test('a thin barline separates measures; barlineFinal ends the score', () {
      final layout = layoutOf(Score.simple(notes: 'c5:q | d5:q'));
      final thins = thinBarlinesOf(layout);
      expect(thins, hasLength(2)); // one between + the final's thin stroke
      final thick = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) =>
              l.from.x == l.to.x &&
              l.thickness == settings.thickBarlineThickness)
          .toList();
      expect(thick, hasLength(1));
      // The thick stroke is the rightmost and flush with the width.
      expect(thick.single.from.x, greaterThan(thins.last.from.x));
      expect(
        thick.single.from.x + settings.thickBarlineThickness / 2,
        closeTo(layout.width, 1e-9),
      );
    });

    test('measure regions cover the width in order', () {
      final layout = layoutOf(Score.simple(notes: 'c5:q d5 | e5 f5 | g5:h'));
      expect(layout.measureRegions, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(layout.measureRegions[i].index, i);
        expect(layout.measureRegions[i].endX,
            greaterThan(layout.measureRegions[i].startX));
        if (i > 0) {
          expect(layout.measureRegions[i].startX,
              greaterThanOrEqualTo(layout.measureRegions[i - 1].endX));
        }
      }
    });
  });

  group('rule 14: determinism', () {
    test('identical input produces an identical layout', () {
      Score score() => Score.simple(
            keySignature: const KeySignature(-3),
            timeSignature: TimeSignature.threeFour,
            notes: 'c5:e d5 eb5:s f5 g5:e | c4+eb4+g4:h. | r:q bn4:q. a4:e',
          );
      final a = const LayoutEngine().layout(score(), settings);
      final b = const LayoutEngine().layout(score(), settings);
      expect(a.width, b.width);
      expect(a.height, b.height);
      expect(a.top, b.top);
      expect(a.primitives.map((p) => p.toString()).toList(),
          b.primitives.map((p) => p.toString()).toList());
      expect(a.regions.map((r) => r.toString()).toList(),
          b.regions.map((r) => r.toString()).toList());
    });
  });

  group('regions', () {
    test('every id-tagged element gets a region containing its notehead', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q r:q g5+b5:h'));
      expect(layout.regions, hasLength(3));
      final byId = {for (final r in layout.regions) r.elementId: r};
      expect(byId.keys, containsAll(['e0', 'e1', 'e2']));
      final head = glyphsNamed(layout, SmuflGlyph.noteheadBlack).first;
      expect(
        byId['e0']!.bounds.containsPoint(
              Point(head.position.x + 0.5, head.position.y),
            ),
        isTrue,
      );
    });

    test('note regions include stem and ledger ink', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q'));
      final region = layout.regions.single.bounds;
      final stem = stemsOf(layout).single;
      expect(region.top, lessThanOrEqualTo(stem.to.y));
      final ledger = ledgerLinesOf(layout).single;
      expect(region.left, lessThanOrEqualTo(ledger.from.x));
      expect(region.right, greaterThanOrEqualTo(ledger.to.x));
    });

    test('layout bounds contain all ink', () {
      final layout = layoutOf(Score.simple(notes: 'a3:q c6 | c4+e4:h'));
      expect(layout.top, lessThan(0));
      expect(layout.height, greaterThan(4));
      for (final region in layout.regions) {
        expect(layout.bounds.containsRectangle(region.bounds), isTrue,
            reason: '$region');
      }
    });
  });
}
