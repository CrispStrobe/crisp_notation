import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Third layout suite: engraving-quality assertions that go beyond the
/// contract rules — stem lengths, beam placement bounds, accidental
/// ordering, monotonic reading order.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<LinePrimitive> stemsOf(ScoreLayout layout) => layout.primitives
    .whereType<LinePrimitive>()
    .where((l) => l.from.x == l.to.x && l.thickness == settings.stemThickness)
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

  group('stem quality', () {
    test('every beamed stem keeps at least the default length', () {
      final layouts = [
        layoutOf(Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: 'c5:e d5 e5 f5 g5 a5 b5 c6',
        )),
        layoutOf(Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: 'g4:e c5 g4 c5 c4:e e4 g4 c5',
        )),
        layoutOf(Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: 'c5:s d5 e5 f5 c4:s d4 e4 f4 c5:h',
        )),
      ];
      for (final layout in layouts) {
        for (final stem in stemsOf(layout)) {
          expect(
            (stem.to.y - stem.from.y).abs(),
            greaterThanOrEqualTo(settings.stemLength - 0.5),
            reason: 'stem at x=${stem.from.x}',
          );
        }
      }
    });

    test('unbeamed stem lengths are exactly one octave inside the staff', () {
      final layout = layoutOf(Score.simple(notes: 'g4:q a4 b4 c5'));
      for (final stem in stemsOf(layout)) {
        // Attachment is offset by the SMuFL anchor (~0.17), so measure
        // notehead-center to tip.
        final headY =
            stem.to.y < stem.from.y ? stem.from.y + 0.168 : stem.from.y - 0.168;
        expect((stem.to.y - headY).abs(), closeTo(settings.stemLength, 1e-6));
      }
    });
  });

  group('beam placement bounds', () {
    test('downward beams never rise above the middle line', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c6:e d6 e6 f6 g5:e a5 b5 c6',
      ));
      for (final beam in beamsOf(layout)) {
        expect(beam.start.y, greaterThanOrEqualTo(2.0 - 1e-9));
        expect(beam.end.y, greaterThanOrEqualTo(2.0 - 1e-9));
      }
    });

    test('upward beams never drop below the middle line', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:e d4 e4 f4 a3:e b3 c4 d4',
      ));
      for (final beam in beamsOf(layout)) {
        expect(beam.start.y, lessThanOrEqualTo(2.0 + 1e-9));
        expect(beam.end.y, lessThanOrEqualTo(2.0 + 1e-9));
      }
    });

    test('secondary beams stay parallel to the primary', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:s d5 e5 f5 r:q r:h',
      ));
      final beams = beamsOf(layout);
      expect(beams, hasLength(2));
      final primarySlope = (beams[0].end.y - beams[0].start.y) /
          (beams[0].end.x - beams[0].start.x);
      final secondarySlope = (beams[1].end.y - beams[1].start.y) /
          (beams[1].end.x - beams[1].start.x);
      expect(secondarySlope, closeTo(primarySlope, 1e-9));
    });
  });

  group('accidental engraving details', () {
    test('the top accidental of a stack sits closest to the chord', () {
      final layout = layoutOf(Score.simple(notes: 'f#4+g#4:q'));
      final sharps = taggedAccidentalsOf(layout);
      expect(sharps, hasLength(2));
      final byY = {for (final g in sharps) g.position.y: g.position.x};
      final topY = byY.keys.reduce((a, b) => a < b ? a : b);
      final bottomY = byY.keys.reduce((a, b) => a > b ? a : b);
      expect(byY[topY], greaterThan(byY[bottomY]!),
          reason: 'top accidental in the column nearest the noteheads');
    });

    test('sharp, natural, re-sharp within one measure all draw', () {
      final layout = layoutOf(Score.simple(notes: 'f#4:q f4 f#4 f#4'));
      final tagged = taggedAccidentalsOf(layout);
      expect(tagged.map((g) => g.smuflName).toList(), [
        SmuflGlyph.accidentalSharp,
        SmuflGlyph.accidentalNatural,
        SmuflGlyph.accidentalSharp,
      ]);
    });

    test('forced courtesy accidental after a barline', () {
      final layout = layoutOf(Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(
              const Pitch(Step.f, alter: 1),
              NoteDuration.quarter,
              id: 'm0',
            ),
          ]),
          Measure([
            const NoteElement(
              pitches: [Pitch(Step.f, alter: 1)],
              duration: NoteDuration.quarter,
              showAccidental: true,
              id: 'm1',
            ),
          ]),
        ],
      ));
      expect(
        taggedAccidentalsOf(layout).map((g) => g.elementId),
        ['m0', 'm1'],
      );
    });
  });

  group('reading order and structure', () {
    test('notehead x positions strictly increase across a measure', () {
      final corpus = [
        'c4:s d4 e4 f4 g4:e a4 b4:q c5:h',
        'f#4:q bb4 cn5 g##4',
        'c4+e4+g4:e d4+f4:e e4:q c4:h',
      ];
      for (final source in corpus) {
        final layout = layoutOf(Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: source,
        ));
        // Leftmost notehead of each element, in element order.
        final leftmostByElement = <String, double>{};
        for (final glyph in layout.primitives.whereType<GlyphPrimitive>()) {
          if (!glyph.smuflName.startsWith('notehead')) continue;
          final id = glyph.elementId!;
          final x = glyph.position.x;
          leftmostByElement[id] = leftmostByElement.containsKey(id)
              ? (x < leftmostByElement[id]! ? x : leftmostByElement[id]!)
              : x;
        }
        final ordered = leftmostByElement.entries.toList()
          ..sort((a, b) =>
              int.parse(a.key.substring(1)) - int.parse(b.key.substring(1)));
        for (var i = 1; i < ordered.length; i++) {
          expect(ordered[i].value, greaterThan(ordered[i - 1].value),
              reason: '$source: ${ordered[i - 1].key} vs ${ordered[i].key}');
        }
      }
    });

    test('empty measures lay out with zero-width regions and no crash', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q | | d4:q'));
      expect(layout.measureRegions, hasLength(3));
      expect(layout.measureRegions[1].startX, layout.measureRegions[1].endX);
      expect(layout.regions, hasLength(2));
      // Still two inner barlines + the final pair.
      final vertical = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.x == l.to.x && l.from.y == 0 && l.to.y == 4);
      expect(vertical, hasLength(4));
    });

    test('unmetered score with key signature orders clef, key, notes', () {
      final layout = layoutOf(Score.simple(
        keySignature: const KeySignature(-2),
        notes: 'bb4:q',
      ));
      final clefX =
          layout.primitives.whereType<GlyphPrimitive>().first.position.x;
      final keyXs = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) =>
              g.smuflName == SmuflGlyph.accidentalFlat && g.elementId == null)
          .map((g) => g.position.x);
      final noteX = layout.primitives
          .whereType<GlyphPrimitive>()
          .firstWhere((g) => g.smuflName == SmuflGlyph.noteheadBlack)
          .position
          .x;
      expect(keyXs, hasLength(2));
      for (final keyX in keyXs) {
        expect(keyX, greaterThan(clefX));
        expect(keyX, lessThan(noteX));
      }
      // The signature's Bb makes the note's flat implied: no tagged flat.
      expect(taggedAccidentalsOf(layout), isEmpty);
    });

    test('layout top is negative (clef overshoot) and bounds are tight', () {
      final layout = layoutOf(Score.simple(notes: 'c5:q'));
      expect(layout.top, lessThan(0));
      expect(layout.bounds.top, layout.top);
      expect(layout.bounds.width, layout.width);
      expect(layout.bounds.height, layout.height);
      // gClef dips ~2.6 spaces below the staff: height comfortably > 4.
      expect(layout.height, greaterThan(4 + 2.5));
    });

    test('primitives and regions have readable toStrings', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:e d5 e5 f5 r:h',
      ));
      expect(
        layout.primitives.whereType<GlyphPrimitive>().first.toString(),
        contains('gClef'),
      );
      expect(
        layout.primitives.whereType<BeamPrimitive>().first.toString(),
        startsWith('Beam('),
      );
      expect(layout.regions.first.toString(), contains('e0'));
      expect(layout.measureRegions.first.toString(), contains('0'));
      expect(layout.toString(), contains('primitives'));
    });
  });

  group('rests are inert', () {
    test('rests never get stems, flags or beams', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'r:e r:e r:s r:s r:s r:s r:h',
      ));
      expect(stemsOf(layout), isEmpty);
      expect(beamsOf(layout), isEmpty);
      expect(
        layout.primitives
            .whereType<GlyphPrimitive>()
            .where((g) => g.smuflName.startsWith('flag')),
        isEmpty,
      );
      // But each rest still owns a hit region.
      expect(layout.regions, hasLength(7));
    });
  });
}
