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

  group('text overlap safety', () {
    // The engine reserves ~0.62 em per character (0.31 em half-width) for
    // center-anchored text; assert no two texts sharing a baseline overlap.
    double halfW(TextPrimitive t) =>
        0.31 * t.size * (t.text.isEmpty ? 1 : t.text.length);

    void expectNoTextOverlap(ScoreLayout layout) {
      final byRow = <String, List<TextPrimitive>>{};
      for (final t in layout.primitives.whereType<TextPrimitive>()) {
        byRow.putIfAbsent(t.position.y.toStringAsFixed(3), () => []).add(t);
      }
      for (final row in byRow.values) {
        row.sort((a, b) => a.position.x.compareTo(b.position.x));
        for (var i = 1; i < row.length; i++) {
          final prevRight = row[i - 1].position.x + halfW(row[i - 1]);
          final curLeft = row[i].position.x - halfW(row[i]);
          expect(curLeft, greaterThanOrEqualTo(prevRight - 1e-6),
              reason: '"${row[i - 1].text}" overlaps "${row[i].text}"');
        }
      }
    }

    test('wide chord symbols on fast notes do not overlap', () {
      expectNoTextOverlap(layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:e e4 g4 c5 g4 e4 c4 e4',
        annotations: 'Cmaj7 Am7 Dm7 G7 Cmaj7 Fmaj7 Bm7b5 E7',
      )));
    });

    test('long lyric syllables on fast notes do not overlap', () {
      expectNoTextOverlap(layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:s d4 e4 f4 g4 a4 b4 c5',
        lyrics: 'Su- per- ca- li- fra- gi- lis- tic',
      )));
    });

    test('verses stack on distinct baselines, each internally spaced', () {
      final base = Score.simple(notes: 'c4:q d4 e4 f4');
      final layout = layoutOf(Score(
        clef: base.clef,
        measures: base.measures,
        lyrics: [
          for (var i = 0; i < 4; i++) Lyric('e$i', 'aa', verse: 1),
          for (var i = 0; i < 4; i++) Lyric('e$i', 'bb', verse: 2),
        ],
      ));
      final rows = <double, List<TextPrimitive>>{};
      for (final t in layout.primitives.whereType<TextPrimitive>()) {
        rows.putIfAbsent(t.position.y, () => []).add(t);
      }
      // Two rows (verse 1 above verse 2).
      expect(rows.keys, hasLength(2));
      final ys = rows.keys.toList()..sort();
      expect(rows[ys[0]]!.every((t) => t.text == 'aa'), isTrue);
      expect(rows[ys[1]]!.every((t) => t.text == 'bb'), isTrue);
      expectNoTextOverlap(layout);
    });

    test('spacing text still keeps its note order (monotonic x)', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        annotations: 'Cmaj7 Am7 Dm7 G7',
        notes: 'c4:q e4 g4 c5',
      ));
      final ann = layout.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.text.length > 1)
          .toList();
      for (var i = 1; i < ann.length; i++) {
        expect(ann[i].position.x, greaterThan(ann[i - 1].position.x));
      }
    });
  });

  group('breath marks', () {
    test('comma and caesura draw their glyphs after the note', () {
      final base = Score.simple(notes: 'c5:q d5');
      final layout = layoutOf(Score(
        clef: base.clef,
        measures: base.measures,
        breathMarks: const [
          BreathMark('e0', BreathSymbol.comma),
          BreathMark('e1', BreathSymbol.caesura),
        ],
      ));
      final names = layout.primitives
          .whereType<GlyphPrimitive>()
          .map((g) => g.smuflName)
          .toSet();
      expect(
          names,
          containsAll(<String>[
            SmuflGlyph.breathMarkComma,
            SmuflGlyph.caesura,
          ]));
    });
  });

  group('figured bass', () {
    test('figures render as stacked figbass glyphs under the note', () {
      final base = Score.simple(clef: Clef.bass, notes: 'c3:q g2');
      final layout = layoutOf(Score(
        clef: base.clef,
        measures: base.measures,
        figuredBass: const [
          FiguredBass('e1', ['#6', '4']),
        ],
      ));
      final glyphs = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName.startsWith('figbass'))
          .toList();
      final names = glyphs.map((g) => g.smuflName).toSet();
      expect(
          names,
          containsAll(<String>[
            SmuflGlyph.figbassSharp,
            SmuflGlyph.figbassDigit(6),
            SmuflGlyph.figbassDigit(4),
          ]));
      // Two rows: the '4' sits below the '#6' row.
      final sixY = glyphs
          .firstWhere((g) => g.smuflName == SmuflGlyph.figbassDigit(6))
          .position
          .y;
      final fourY = glyphs
          .firstWhere((g) => g.smuflName == SmuflGlyph.figbassDigit(4))
          .position
          .y;
      expect(fourY, greaterThan(sixY));
    });
  });

  group('jazz articulations', () {
    test('each mark draws its brass glyph beside the note', () {
      final base = Score.simple(notes: 'g4:q b4 d5 g5');
      final layout = layoutOf(Score(
        clef: base.clef,
        measures: base.measures,
        jazzMarks: const [
          JazzMark('e0', JazzArticulation.scoop),
          JazzMark('e1', JazzArticulation.doit),
          JazzMark('e2', JazzArticulation.fall),
          JazzMark('e3', JazzArticulation.plop),
        ],
      ));
      final glyphs = layout.primitives
          .whereType<GlyphPrimitive>()
          .map((g) => g.smuflName)
          .toSet();
      expect(
          glyphs,
          containsAll(<String>[
            SmuflGlyph.brassScoop,
            SmuflGlyph.brassDoitMedium,
            SmuflGlyph.brassFallLipShort,
            SmuflGlyph.brassPlop,
          ]));
    });

    test('before-marks sit left of the note, after-marks right', () {
      final base = Score.simple(notes: 'g4:q');
      final scoop = layoutOf(Score(
        clef: base.clef,
        measures: base.measures,
        jazzMarks: const [JazzMark('e0', JazzArticulation.scoop)],
      ));
      final doit = layoutOf(Score(
        clef: base.clef,
        measures: base.measures,
        jazzMarks: const [JazzMark('e0', JazzArticulation.doit)],
      ));
      double noteX(ScoreLayout l) => l.primitives
          .whereType<GlyphPrimitive>()
          .firstWhere((g) => g.smuflName.startsWith('notehead'))
          .position
          .x;
      double markX(ScoreLayout l, String name) => l.primitives
          .whereType<GlyphPrimitive>()
          .firstWhere((g) => g.smuflName == name)
          .position
          .x;
      expect(markX(scoop, SmuflGlyph.brassScoop), lessThan(noteX(scoop)));
      expect(markX(doit, SmuflGlyph.brassDoitMedium), greaterThan(noteX(doit)));
    });
  });

  group('notehead shapes', () {
    Set<String> noteheadsOf(ScoreLayout layout) => layout.primitives
        .whereType<GlyphPrimitive>()
        .map((g) => g.smuflName)
        .where((n) => n.startsWith('notehead'))
        .toSet();

    test('each shape selects its duration-appropriate glyph', () {
      final layout = layoutOf(Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            NoteElement.note(
                const Pitch(Step.b, octave: 4), NoteDuration.quarter,
                notehead: NoteheadShape.x, id: 'e0'),
            NoteElement.note(const Pitch(Step.b, octave: 4), NoteDuration.half,
                notehead: NoteheadShape.diamond, id: 'e1'),
            NoteElement.note(
                const Pitch(Step.b, octave: 4), NoteDuration.quarter,
                notehead: NoteheadShape.triangleUp, id: 'e2'),
          ]),
        ],
      ));
      final heads = noteheadsOf(layout);
      expect(heads, contains(SmuflGlyph.noteheadXBlack));
      expect(heads, contains(SmuflGlyph.noteheadDiamondHalf));
      expect(heads, contains(SmuflGlyph.noteheadTriangleUpBlack));
      // No plain oval head slipped in.
      expect(heads, isNot(contains(SmuflGlyph.noteheadBlack)));
    });

    test('a slash head is one glyph regardless of duration', () {
      final q = layoutOf(Score.simple(notes: 'b4:q'));
      final layout = layoutOf(Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(
                const Pitch(Step.b, octave: 4), NoteDuration.quarter,
                notehead: NoteheadShape.slash, id: 'e0'),
          ]),
        ],
      ));
      expect(noteheadsOf(layout), {SmuflGlyph.noteheadSlashVerticalEnds});
      // (sanity) a normal quarter uses the black oval.
      expect(noteheadsOf(q), contains(SmuflGlyph.noteheadBlack));
    });
  });

  group('barline styles', () {
    // Full-height vertical lines (barlines / staff-line edges excluded by the
    // 0→4 span), by thickness class.
    List<LinePrimitive> vlines(ScoreLayout layout, double thickness) =>
        layout.primitives
            .whereType<LinePrimitive>()
            .where((l) =>
                l.from.x == l.to.x &&
                l.from.y <= 0.01 &&
                (l.thickness - thickness).abs() < 1e-9)
            .toList();

    test('a double bar draws two thin lines at the measure edge', () {
      final normal = layoutOf(Score.simple(notes: 'c4:w | d4:w'));
      final doubled =
          layoutOf(Score.simple(notes: 'c4:w !barline=doubleBar | d4:w'));
      // One extra full-height thin line vs a plain barline.
      expect(
        vlines(doubled, settings.thinBarlineThickness).length -
            vlines(normal, settings.thinBarlineThickness).length,
        1,
      );
    });

    test('a heavy bar draws a thick line', () {
      final layout =
          layoutOf(Score.simple(notes: 'c4:w !barline=heavy | d4:w'));
      expect(vlines(layout, settings.thickBarlineThickness), isNotEmpty);
    });

    test('none draws no barline between the measures', () {
      final normal = layoutOf(Score.simple(notes: 'c4:w | d4:w'));
      final blank = layoutOf(Score.simple(notes: 'c4:w !barline=none | d4:w'));
      expect(
        vlines(blank, settings.thinBarlineThickness).length,
        vlines(normal, settings.thinBarlineThickness).length - 1,
      );
    });

    test('a dashed bar is drawn as several short segments', () {
      final layout =
          layoutOf(Score.simple(notes: 'c4:w !barline=dashed | d4:w'));
      final segments = layout.primitives.whereType<LinePrimitive>().where((l) =>
          l.from.x == l.to.x &&
          l.thickness == settings.thinBarlineThickness &&
          (l.to.y - l.from.y).abs() < 3.9); // shorter than a full barline
      expect(segments.length, greaterThan(2));
    });
  });

  group('beams over rests', () {
    Iterable<GlyphPrimitive> flagsOf(ScoreLayout layout) => layout.primitives
        .whereType<GlyphPrimitive>()
        .where((g) => g.smuflName.startsWith('flag'));

    test('a rest within a beat does not break the beam', () {
      // 16th, 16th rest, 16th, 16th — one quarter beat. The beam spans the
      // rest; the notes do not flag individually.
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:s r:s c5:s c5:s',
      ));
      expect(beamsOf(layout), isNotEmpty);
      expect(flagsOf(layout), isEmpty);
    });

    test('a rest at a beat boundary still separates beams', () {
      // Two eighths fill beat 1; an eighth rest then a lone eighth in beat 2.
      // The lone eighth flags — the beam does not reach back over the boundary.
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:e c5:e r:e c5:e',
      ));
      expect(beamsOf(layout), isNotEmpty); // beat 1's pair
      expect(flagsOf(layout), isNotEmpty); // beat 2's lone eighth
    });
  });
}
