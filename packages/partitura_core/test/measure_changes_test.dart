import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.3.8: mid-score clef/key/time changes, repeats and voltas.
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
    test('directives parse into measure attributes', () {
      final score = Score.simple(
        notes: 'c4:q | !clef=bass !key=-2 !time=3/4 c3:q | '
            '!repeat d3:q | !endrepeat !volta=1 e3:q',
      );
      expect(score.measures[0].clefChange, isNull);
      expect(score.measures[1].clefChange, Clef.bass);
      expect(score.measures[1].keyChange, const KeySignature(-2));
      expect(score.measures[1].timeChange, const TimeSignature(3, 4));
      expect(score.measures[2].startRepeat, isTrue);
      expect(score.measures[3].endRepeat, isTrue);
      expect(score.measures[3].volta, 1);
    });

    test('malformed directives are rejected', () {
      expect(
          () => Score.simple(notes: '!clef=foo c4:q'), throwsFormatException);
      expect(() => Score.simple(notes: '!key=9 c4:q'), throwsFormatException);
      expect(
          () => Score.simple(notes: '!time=3-4 c4:q'), throwsFormatException);
      expect(() => Score.simple(notes: '!volta=0 c4:q'), throwsFormatException);
      expect(() => Score.simple(notes: '!nope c4:q'), throwsFormatException);
    });

    test('changes participate in Measure equality', () {
      expect(
        Score.simple(notes: '!clef=bass c3:q'),
        Score.simple(notes: '!clef=bass c3:q'),
      );
      expect(
        Score.simple(notes: '!clef=bass c3:q'),
        isNot(Score.simple(notes: 'c3:q')),
      );
      expect(
        Score.simple(notes: '!repeat c4:q'),
        isNot(Score.simple(notes: 'c4:q')),
      );
    });
  });

  group('layout: clef changes', () {
    test('notes after a clef change use the new clef', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q | !clef=bass c4:q'));
      final heads = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.noteheadBlack)
          .toList();
      // C4 in treble sits at y=5; in bass at y=-1.
      expect(heads[0].position.y, 5.0);
      expect(heads[1].position.y, -1.0);
    });

    test('the change clef draws small at the measure start', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q | !clef=bass c3:q'));
      final clefs = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.fClef)
          .toList();
      expect(clefs, hasLength(1));
      expect(clefs.single.scale, 0.8);
      expect(clefs.single.position.y, 1.0); // anchored on the F3 line
    });
  });

  group('layout: key changes', () {
    test('a dropped key draws cancellation naturals', () {
      // D major (2 sharps) -> C major: two naturals, no new accidentals.
      final layout = layoutOf(Score.simple(
        keySignature: const KeySignature(2),
        notes: 'f#4:q | !key=0 f4:q',
      ));
      final naturals = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) =>
              g.smuflName == SmuflGlyph.accidentalNatural &&
              g.elementId == null)
          .toList();
      expect(naturals, hasLength(2));
      // And the f4 in measure 2 needs no accidental (C major implies it).
      final tagged = layout.primitives.whereType<GlyphPrimitive>().where(
          (g) => g.smuflName.startsWith('accidental') && g.elementId != null);
      expect(tagged, isEmpty);
    });

    test('a key change to more sharps draws the new signature', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q | !key=2 f#4:q'));
      final sharps = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) =>
              g.smuflName == SmuflGlyph.accidentalSharp && g.elementId == null)
          .toList();
      expect(sharps, hasLength(2));
      // The f#4 after the change is implied: no tagged sharp.
      final tagged = layout.primitives.whereType<GlyphPrimitive>().where(
          (g) => g.smuflName.startsWith('accidental') && g.elementId != null);
      expect(tagged, isEmpty);
    });
  });

  group('layout: time changes', () {
    test('new digits are drawn and beam windows follow', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:e d5 e5 f5 g5 a5 b5 c6 | !time=3/4 c5:e d5 e5 f5 g5 a5',
      ));
      // 4/4 digits + 3/4 digits: three 4s in total.
      expect(
        layout.primitives
            .whereType<GlyphPrimitive>()
            .where((g) => g.smuflName == 'timeSig4'),
        hasLength(3),
      );
      expect(
        layout.primitives
            .whereType<GlyphPrimitive>()
            .where((g) => g.smuflName == 'timeSig3'),
        hasLength(1),
      );
      // Measure 1 merges to 2 beams (4/4); measure 2 beams per beat (3).
      expect(layout.primitives.whereType<BeamPrimitive>(), hasLength(5));
    });
  });

  group('layout: repeats and voltas', () {
    test('start and end repeats draw dots and double lines', () {
      final layout =
          layoutOf(Score.simple(notes: '!repeat c4:q | !endrepeat d4:q'));
      final dots = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.repeatDots)
          .toList();
      expect(dots, hasLength(2));
      expect(dots[0].position.y, 4.0);
      final thick = layout.primitives.whereType<LinePrimitive>().where((l) =>
          l.from.x == l.to.x && l.thickness == settings.thickBarlineThickness);
      // Start repeat + end repeat + final barline.
      expect(thick, hasLength(3));
    });

    test('an end repeat replaces the inter-measure barline', () {
      final layout = layoutOf(Score.simple(notes: '!endrepeat c4:q | d4:q'));
      final thins = layout.primitives.whereType<LinePrimitive>().where((l) =>
          l.from.x == l.to.x &&
          l.from.y == 0 &&
          l.to.y == 4 &&
          l.thickness == settings.thinBarlineThickness);
      // End-repeat thin + final thin (no plain barline between measures).
      expect(thins, hasLength(2));
    });

    test('volta bracket spans the measure with its number', () {
      final layout =
          layoutOf(Score.simple(notes: '!volta=1 c4:q d4 | !volta=2 e4:q f4'));
      final digits = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName.startsWith('tuplet') && g.scale == 0.8)
          .toList();
      expect(digits.map((g) => g.smuflName).toList(), ['tuplet1', 'tuplet2']);
      for (final digit in digits) {
        expect(digit.position.y, lessThan(0));
      }
      final thickness =
          metadata.engravingDefault('repeatEndingLineThickness', orElse: 0.16);
      final voltaLines = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.thickness == thickness && l.from.y < 0)
          .toList();
      // Two brackets x (rail + two hooks).
      expect(voltaLines, hasLength(6));
    });
  });

  group('determinism', () {
    test('changes, repeats and voltas are deterministic', () {
      String render() => layoutOf(Score.simple(
            keySignature: const KeySignature(1),
            timeSignature: TimeSignature.fourFour,
            notes: '!repeat g4:q a4 b4 c5 | '
                '!endrepeat !volta=1 !key=-1 !time=2/4 bb4:q c5 | '
                '!clef=tenor !volta=2 c4:h',
          )).primitives.map((p) => p.toString()).join('\n');
      expect(render(), render());
      expect(render(), contains('repeatDots'));
      expect(render(), contains('cClef'));
    });
  });
}
