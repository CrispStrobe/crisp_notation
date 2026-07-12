import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Edge-case and sweep tests for the layout engine, complementing the
/// rule-by-rule suite in layout_test.dart.
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

List<GlyphPrimitive> glyphsNamed(ScoreLayout layout, String name) =>
    layout.primitives
        .whereType<GlyphPrimitive>()
        .where((g) => g.smuflName == name)
        .toList();

List<GlyphPrimitive> flagsOf(ScoreLayout layout) => layout.primitives
    .whereType<GlyphPrimitive>()
    .where((g) => g.smuflName.startsWith('flag'))
    .toList();

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('stem direction sweep', () {
    test('single notes: down iff position >= 4, both clefs', () {
      for (final clef in Clef.values) {
        for (var position = -6; position <= 14; position++) {
          final score = Score(clef: clef, measures: [
            Measure([
              NoteElement.note(
                clef.pitchAt(position),
                NoteDuration.quarter,
                id: 'n',
              ),
            ]),
          ]);
          final stem = stemsOf(layoutOf(score)).single;
          final down = stem.to.y > stem.from.y;
          expect(down, position >= 4, reason: '$clef position $position');
        }
      }
    });

    test('chord equidistant from the middle line stems down', () {
      // A4 (p=3) and C5 (p=5) are equidistant around position 4.
      final layout = layoutOf(Score.simple(notes: 'a4+c5:q'));
      final stem = stemsOf(layout).single;
      expect(stem.to.y, greaterThan(stem.from.y));
    });

    test('chord direction follows the farther extreme', () {
      // E4 (p=-... treble e4 p=0? E4 = 0) vs D5 (p=6): E4 is 4 below, D5 is
      // 2 above -> stems up.
      final up = stemsOf(layoutOf(Score.simple(notes: 'e4+d5:q'))).single;
      expect(up.to.y, lessThan(up.from.y));
      // C4 (p=-2, 6 below) vs A5 (p=10, 6 above): tie -> down.
      final tie = stemsOf(layoutOf(Score.simple(notes: 'c4+a5:q'))).single;
      expect(tie.to.y, greaterThan(tie.from.y));
    });
  });

  group('beaming edge cases', () {
    test('dotted eighth + sixteenth beam with a beamlet stub', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:e. d5:s c5:h.',
      ));
      final beams = beamsOf(layout);
      // Primary beam over both + a short stub for the lone sixteenth.
      expect(beams, hasLength(2));
      expect(flagsOf(layout), isEmpty);
      final primary = beams[0];
      final stub = beams[1];
      expect(
        stub.end.x - stub.start.x,
        lessThan(primary.end.x - primary.start.x),
      );
    });

    test('eighths across a beat boundary in 3/4 do not merge', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.threeFour,
        notes: 'c5:q. d5:e e5:e f5:e',
      ));
      // d5 fills beat 2's second half; e5+f5 fill beat 3: d5 stays a flag.
      expect(beamsOf(layout), hasLength(1));
      expect(flagsOf(layout), hasLength(1));
    });

    test('2/4 with four eighths merges into one beam', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.twoFour,
        notes: 'c5:e d5 e5 f5',
      ));
      expect(beamsOf(layout), hasLength(1));
      expect(stemsOf(layout), hasLength(4));
    });

    test('x/8 meters fall back to flags (simple-meter grouping only)', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.sixEight,
        notes: 'c5:e d5 e5 f5 g5 a5',
      ));
      expect(beamsOf(layout), isEmpty);
      expect(flagsOf(layout), hasLength(6));
    });

    test('5/4 (odd numerator) beams per quarter without merging', () {
      final layout = layoutOf(Score.simple(
        timeSignature: const TimeSignature(5, 4),
        notes: 'c5:e d5 e5 f5 g5 a5 b5 c6 c5 d5',
      ));
      expect(beamsOf(layout), hasLength(5));
    });

    test('unmetered scores beam per quarter-note window', () {
      final layout = layoutOf(Score.simple(notes: 'c5:e d5 e5 f5'));
      expect(beamsOf(layout), hasLength(2));
    });

    test('a group of exactly two sixteenths gets primary + secondary', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:s d5:s r:e c5:h r:q',
      ));
      expect(beamsOf(layout), hasLength(2));
    });

    test('beamed chords use one stem per chord', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4+e4:e d4+f4:e c4:h.',
      ));
      expect(stemsOf(layout), hasLength(3)); // 2 beamed chords + the half
      expect(beamsOf(layout), hasLength(1));
    });
  });

  group('accidental bookkeeping', () {
    Score singleMeasure(List<MusicElement> elements) =>
        Score(clef: Clef.treble, measures: [Measure(elements)]);

    List<GlyphPrimitive> tagged(ScoreLayout layout) => layout.primitives
        .whereType<GlyphPrimitive>()
        .where(
            (g) => g.smuflName.startsWith('accidental') && g.elementId != null)
        .toList();

    test('showAccidental: false hides and does not update state', () {
      final layout = layoutOf(singleMeasure([
        const NoteElement(
          pitches: [Pitch(Step.f, alter: 1)],
          duration: NoteDuration.quarter,
          showAccidental: false,
          id: 'hidden',
        ),
        NoteElement.note(
          const Pitch(Step.f, alter: 1),
          NoteDuration.quarter,
          id: 'auto',
        ),
      ]));
      final shown = tagged(layout);
      // The hidden one draws nothing; the automatic one still needs its
      // sharp because the hidden accidental never became "written".
      expect(shown, hasLength(1));
      expect(shown.single.elementId, 'auto');
    });

    test('showAccidental: true forces a redundant accidental', () {
      final layout = layoutOf(singleMeasure([
        NoteElement.note(
          const Pitch(Step.f, alter: 1),
          NoteDuration.quarter,
          id: 'first',
        ),
        const NoteElement(
          pitches: [Pitch(Step.f, alter: 1)],
          duration: NoteDuration.quarter,
          showAccidental: true,
          id: 'courtesy',
        ),
      ]));
      expect(tagged(layout).map((g) => g.elementId), ['first', 'courtesy']);
    });

    test('chord accidental applies to later single notes of that pitch', () {
      final layout = layoutOf(Score.simple(notes: 'f#4+a4:q f#4:q'));
      // The chord introduces F#; the following f#4 needs no accidental.
      expect(tagged(layout), hasLength(1));
    });

    test('three-accidental chord stacks three distinct columns', () {
      final layout = layoutOf(Score.simple(notes: 'f#4+a#4+c#5:q'));
      final sharps = glyphsNamed(layout, SmuflGlyph.accidentalSharp);
      expect(sharps, hasLength(3));
      expect(sharps.map((g) => g.position.x).toSet(), hasLength(3));
    });
  });

  group('chords', () {
    test('down-stem second flips the lower note to the left', () {
      // D5 (p=6) + E5 (p=7): stems down; walking from the top, E5 keeps
      // the column and D5 flips left of the stem.
      final layout = layoutOf(Score.simple(notes: 'd5+e5:q'));
      final heads = glyphsNamed(layout, SmuflGlyph.noteheadBlack);
      final d5 = heads.firstWhere((h) => h.position.y == 1.0);
      final e5 = heads.firstWhere((h) => h.position.y == 0.5);
      expect(d5.position.x, lessThan(e5.position.x));
    });

    test('three-note cluster alternates columns', () {
      final layout = layoutOf(Score.simple(notes: 'c4+d4+e4:q'));
      final heads = glyphsNamed(layout, SmuflGlyph.noteheadBlack);
      final xByY = {for (final h in heads) h.position.y: h.position.x};
      // Up-stem: C4 (y=5) normal, D4 (y=4.5) flipped, E4 (y=4) normal.
      expect(xByY[5.0], xByY[4.0]);
      expect(xByY[4.5], greaterThan(xByY[5.0]!));
    });

    test('whole-note seconds offset without any stem', () {
      final layout = layoutOf(Score.simple(notes: 'c4+d4:w'));
      expect(stemsOf(layout), isEmpty);
      final heads = glyphsNamed(layout, SmuflGlyph.noteheadWhole);
      expect(heads.map((h) => h.position.x).toSet(), hasLength(2));
    });

    test('chord ledger lines span all notehead columns', () {
      // B3+C4 second below the staff, both need the C4 ledger width.
      final layout = layoutOf(Score.simple(notes: 'b3+c4:q'));
      final heads = glyphsNamed(layout, SmuflGlyph.noteheadBlack);
      final ledger = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) =>
              l.from.y == l.to.y && l.thickness == settings.legerLineThickness)
          .single;
      final headWidth = metadata.bBoxOf(SmuflGlyph.noteheadBlack).width;
      for (final head in heads) {
        expect(ledger.from.x, lessThanOrEqualTo(head.position.x));
        expect(
          ledger.to.x,
          greaterThanOrEqualTo(head.position.x + headWidth),
        );
      }
    });
  });

  group('spacing sweep', () {
    test('advance grows strictly with duration', () {
      double gapFor(String duration, String glyph) {
        final layout =
            layoutOf(Score.simple(notes: 'c5:$duration d5:$duration'));
        final heads = glyphsNamed(layout, glyph);
        return heads[1].position.x - heads[0].position.x;
      }

      final gaps = [
        gapFor('s', SmuflGlyph.noteheadBlack),
        gapFor('e', SmuflGlyph.noteheadBlack),
        gapFor('q', SmuflGlyph.noteheadBlack),
        gapFor('h', SmuflGlyph.noteheadHalf),
        gapFor('w', SmuflGlyph.noteheadWhole),
      ];
      for (var i = 1; i < gaps.length; i++) {
        expect(gaps[i], greaterThan(gaps[i - 1]), reason: 'step $i of $gaps');
      }
    });

    test('dots increase the advance of the same base', () {
      double gap(String duration) {
        final layout =
            layoutOf(Score.simple(notes: 'c5:$duration d5:$duration'));
        final heads = glyphsNamed(layout, SmuflGlyph.noteheadBlack);
        return heads[1].position.x - heads[0].position.x;
      }

      expect(gap('q.'), greaterThan(gap('q')));
      expect(gap('q..'), greaterThan(gap('q.')));
    });

    test('all primitives stay within the layout bounds (stress corpus)', () {
      final corpus = [
        Score.simple(notes: 'a3:s b3 c4 d4 | e6:e d6 c6:q'),
        Score.simple(
          clef: Clef.bass,
          keySignature: const KeySignature(-7),
          timeSignature: TimeSignature.threeFour,
          notes: 'gb2:q ab2+cb3 r | eb3+gb3+bb3:h.',
        ),
        Score.simple(
          keySignature: const KeySignature(7),
          timeSignature: const TimeSignature(5, 8),
          notes: 'c#5:s d#5 e#5 f#5 g#5:e | r:e a#4:e b4:s cn5:s r:e',
        ),
      ];
      for (final score in corpus) {
        final layout = layoutOf(score);
        for (final region in layout.regions) {
          expect(layout.bounds.containsRectangle(region.bounds), isTrue,
              reason: '$score -> ${region.elementId}');
        }
        expect(
            layout.measureRegions.last.endX, lessThanOrEqualTo(layout.width));
      }
    });
  });

  group('structure sweep', () {
    test('every key signature lays out with correct count in both clefs', () {
      for (final clef in Clef.values) {
        if (clef == Clef.percussion) continue; // neutral: no key signature
        for (var fifths = -7; fifths <= 7; fifths++) {
          final layout = layoutOf(Score(
            clef: clef,
            keySignature: KeySignature(fifths),
            measures: [
              Measure([
                NoteElement.note(clef.pitchAt(4), NoteDuration.whole, id: 'n'),
              ]),
            ],
          ));
          final glyph = fifths >= 0
              ? SmuflGlyph.accidentalSharp
              : SmuflGlyph.accidentalFlat;
          final drawn = glyphsNamed(layout, glyph)
              .where((g) => g.elementId == null)
              .toList();
          expect(drawn, hasLength(fifths.abs()),
              reason: '$clef fifths $fifths');
          for (final accidental in drawn) {
            // All signature accidentals sit in or near the staff.
            expect(accidental.position.y, inInclusiveRange(-1.0, 5.0),
                reason: '$clef fifths $fifths at ${accidental.position}');
          }
        }
      }
    });

    test('n measures produce n-1 inner barlines plus the final pair', () {
      for (var n = 1; n <= 5; n++) {
        final layout = layoutOf(
          Score.simple(notes: List.filled(n, 'c5:q').join(' | ')),
        );
        final vertical = layout.primitives
            .whereType<LinePrimitive>()
            .where((l) => l.from.x == l.to.x && l.from.y == 0 && l.to.y == 4)
            .toList();
        final thin =
            vertical.where((l) => l.thickness == settings.thinBarlineThickness);
        final thick = vertical
            .where((l) => l.thickness == settings.thickBarlineThickness);
        expect(thin, hasLength(n), reason: '$n measures');
        expect(thick, hasLength(1), reason: '$n measures');
        expect(layout.measureRegions, hasLength(n));
      }
    });

    test('time signature numerator and denominator share a center', () {
      for (final time in [
        TimeSignature.fourFour,
        TimeSignature.threeFour,
        const TimeSignature(12, 8),
        const TimeSignature(2, 2),
      ]) {
        final layout = layoutOf(
          Score.simple(timeSignature: time, notes: 'c5:w'),
        );
        double center(List<GlyphPrimitive> row) {
          final left = row
              .map((g) => g.position.x + metadata.bBoxOf(g.smuflName).swX)
              .reduce(min);
          final right = row
              .map((g) => g.position.x + metadata.bBoxOf(g.smuflName).neX)
              .reduce(max);
          return (left + right) / 2;
        }

        final digits = layout.primitives
            .whereType<GlyphPrimitive>()
            .where((g) => g.smuflName.startsWith('timeSig'))
            .toList();
        final numerator = digits.where((g) => g.position.y == 1.0).toList();
        final denominator = digits.where((g) => g.position.y == 3.0).toList();
        expect(numerator, isNotEmpty);
        expect(denominator, isNotEmpty);
        expect(center(numerator), closeTo(center(denominator), 0.01),
            reason: '$time');
      }
    });

    test('regions are unique per element id and non-degenerate', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:e d4 e4+g4 f4:s g4:s | r:q a4:h.',
      ));
      final ids = layout.regions.map((r) => r.elementId).toList();
      expect(ids.toSet().length, ids.length);
      for (final region in layout.regions) {
        expect(region.bounds.width, greaterThan(0), reason: '$region');
        expect(region.bounds.height, greaterThan(0), reason: '$region');
      }
    });

    test('determinism across a mixed corpus', () {
      final sources = [
        'c4:q d4 e4 f4',
        'c5:e d5 e5 f5 g5 a5 b5 c6',
        'f#4+a4+c5:h. r:q',
        'a3:s b3 c4 d4 e4:e f4 g4:q',
      ];
      for (final source in sources) {
        final a = layoutOf(Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: source,
        ));
        final b = layoutOf(Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: source,
        ));
        expect(
          a.primitives.map((p) => p.toString()).join('\n'),
          b.primitives.map((p) => p.toString()).join('\n'),
          reason: source,
        );
      }
    });
  });

  group('errors', () {
    test('a NoteElement without pitches fails layout loudly', () {
      final score = Score(clef: Clef.treble, measures: [
        const Measure([
          NoteElement(pitches: [], duration: NoteDuration.quarter),
        ]),
      ]);
      expect(() => layoutOf(score), throwsArgumentError);
    });

    test('unknown glyph names fail metadata lookup loudly', () {
      expect(() => metadata.bBoxOf('noSuchGlyph'), throwsArgumentError);
    });
  });
}
