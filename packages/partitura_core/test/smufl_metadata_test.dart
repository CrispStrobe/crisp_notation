import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  group('SmuflMetadata.fromJson', () {
    test('parses defaults, boxes and anchors; ignores malformed entries', () {
      final metadata = SmuflMetadata.fromJson({
        'engravingDefaults': {
          'stemThickness': 0.12,
          'textFontFamily': ['Academico'], // non-numeric: ignored
        },
        'glyphBBoxes': {
          'noteheadBlack': {
            'bBoxNE': [1.18, 0.5],
            'bBoxSW': [0.0, -0.5],
          },
          'broken1': {'bBoxNE': 'nope'},
          'broken2': {
            'bBoxNE': [1.0],
            'bBoxSW': [0.0, 0.0],
          },
        },
        'glyphsWithAnchors': {
          'noteheadBlack': {
            'stemUpSE': [1.18, 0.168],
            'stemDownNW': [0.0, -0.168],
            'somethingElse': [9, 9], // unknown anchor: ignored
          },
          'brokenAnchor': {
            'stemUpSE': ['x', 'y'],
          },
        },
        'unrelatedKey': 42,
      });

      expect(metadata.engravingDefault('stemThickness', orElse: 9), 0.12);
      expect(metadata.engravingDefault('missing', orElse: 9), 9);
      expect(
        metadata.engravingDefault('textFontFamily', orElse: 7),
        7,
        reason: 'non-numeric defaults are dropped',
      );

      final box = metadata.bBoxOf('noteheadBlack');
      expect(box.width, closeTo(1.18, 1e-9));
      expect(box.height, closeTo(1.0, 1e-9));
      expect(() => metadata.bBoxOf('broken1'), throwsArgumentError);
      expect(() => metadata.bBoxOf('broken2'), throwsArgumentError);

      final anchors = metadata.anchorsOf('noteheadBlack');
      expect(anchors.stemUpSE!.x, 1.18);
      expect(anchors.stemDownNW!.y, -0.168);
      expect(metadata.anchorsOf('brokenAnchor').stemUpSE, isNull);
      expect(metadata.anchorsOf('unknownGlyph').stemUpSE, isNull);
    });

    test('tolerates missing top-level sections', () {
      final metadata = SmuflMetadata.fromJson({});
      expect(metadata.engravingDefault('stemThickness', orElse: 0.5), 0.5);
      expect(metadata.anchorsOf('anything').stemUpSE, isNull);
      expect(() => metadata.bBoxOf('anything'), throwsArgumentError);
    });

    test('the real Bravura metadata has everything the engine draws', () {
      final source = File('../partitura/assets/smufl/bravura_metadata.json')
          .readAsStringSync();
      final metadata =
          SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);

      final drawnGlyphs = [
        SmuflGlyph.gClef,
        SmuflGlyph.fClef,
        SmuflGlyph.cClef,
        SmuflGlyph.noteheadWhole,
        SmuflGlyph.noteheadHalf,
        SmuflGlyph.noteheadBlack,
        SmuflGlyph.flag8thUp,
        SmuflGlyph.flag8thDown,
        SmuflGlyph.flag16thUp,
        SmuflGlyph.flag16thDown,
        SmuflGlyph.restWhole,
        SmuflGlyph.restHalf,
        SmuflGlyph.restQuarter,
        SmuflGlyph.rest8th,
        SmuflGlyph.rest16th,
        SmuflGlyph.rest32nd,
        SmuflGlyph.rest64th,
        SmuflGlyph.restDoubleWhole,
        SmuflGlyph.noteheadDoubleWhole,
        SmuflGlyph.flag32ndUp,
        SmuflGlyph.flag32ndDown,
        SmuflGlyph.flag64thUp,
        SmuflGlyph.flag64thDown,
        SmuflGlyph.accidentalDoubleFlat,
        SmuflGlyph.accidentalFlat,
        SmuflGlyph.accidentalNatural,
        SmuflGlyph.accidentalSharp,
        SmuflGlyph.accidentalDoubleSharp,
        SmuflGlyph.augmentationDot,
        SmuflGlyph.repeatDots,
        ...SmuflGlyph.timeSigDigits,
        for (var d = 0; d <= 9; d++) SmuflGlyph.tupletDigit(d),
        for (final a in Articulation.values) ...[
          SmuflGlyph.articulationGlyph(a, above: true),
          SmuflGlyph.articulationGlyph(a, above: false),
        ],
        for (final d in DynamicLevel.values) SmuflGlyph.dynamicGlyph(d),
      ];
      for (final glyph in drawnGlyphs) {
        final box = metadata.bBoxOf(glyph); // throws if absent
        expect(box.width, greaterThan(0), reason: glyph);
      }
      // Stemmed noteheads must carry stem anchors.
      for (final glyph in [SmuflGlyph.noteheadHalf, SmuflGlyph.noteheadBlack]) {
        final anchors = metadata.anchorsOf(glyph);
        expect(anchors.stemUpSE, isNotNull, reason: glyph);
        expect(anchors.stemDownNW, isNotNull, reason: glyph);
      }
    });
  });

  group('SmuflGlyph helpers', () {
    test('accidentalFor covers -2..2 and rejects the rest', () {
      expect(SmuflGlyph.accidentalFor(-2), SmuflGlyph.accidentalDoubleFlat);
      expect(SmuflGlyph.accidentalFor(-1), SmuflGlyph.accidentalFlat);
      expect(SmuflGlyph.accidentalFor(0), SmuflGlyph.accidentalNatural);
      expect(SmuflGlyph.accidentalFor(1), SmuflGlyph.accidentalSharp);
      expect(SmuflGlyph.accidentalFor(2), SmuflGlyph.accidentalDoubleSharp);
      expect(() => SmuflGlyph.accidentalFor(3), throwsArgumentError);
      expect(() => SmuflGlyph.accidentalFor(-3), throwsArgumentError);
    });

    test('timeSigDigit maps 0..9', () {
      for (var d = 0; d <= 9; d++) {
        expect(SmuflGlyph.timeSigDigit(d), 'timeSig$d');
      }
    });
  });

  group('LayoutSettings', () {
    late SmuflMetadata bravura;

    setUpAll(() {
      final source = File('../partitura/assets/smufl/bravura_metadata.json')
          .readAsStringSync();
      bravura =
          SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    });

    test('seeds engraving values from the font metadata', () {
      final settings = LayoutSettings(metadata: bravura);
      expect(settings.staffLineThickness, 0.13);
      expect(settings.stemThickness, 0.12);
      expect(settings.legerLineExtension, 0.4);
      expect(settings.beamThickness, 0.5);
      expect(settings.beamSpacing, 0.25);
      expect(settings.thickBarlineThickness, 0.5);
    });

    test('explicit overrides win and flow into the layout', () {
      final settings = LayoutSettings(
        metadata: bravura,
        staffLineThickness: 0.3,
        stemThickness: 0.25,
      );
      final layout =
          const LayoutEngine().layout(Score.simple(notes: 'a4:q'), settings);
      final staffLines = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.thickness == 0.3);
      expect(staffLines, hasLength(5));
      final stems = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.thickness == 0.25);
      expect(stems, hasLength(1));
    });
  });
}
