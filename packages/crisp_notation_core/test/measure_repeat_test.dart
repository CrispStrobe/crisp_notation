import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

import 'support/layout_lint.dart';

/// Phase 2.7: measure-repeat (simile) signs.
late final LayoutSettings settings;

Score withRepeat(int count) => Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          NoteElement.note(const Pitch(Step.c), NoteDuration.whole),
        ]),
        Measure(const [], measureRepeat: count),
        Measure([
          NoteElement.note(const Pitch(Step.d), NoteDuration.whole),
        ]),
      ],
    );

void main() {
  setUpAll(() {
    final meta = SmuflMetadata.fromJson(jsonDecode(
        File('../crisp_notation/assets/smufl/bravura_metadata.json')
            .readAsStringSync()) as Map<String, Object?>);
    settings = LayoutSettings(metadata: meta);
  });

  group('model', () {
    test('only 1, 2 or 4 are allowed, and no elements', () {
      expect(() => Measure(const [], measureRepeat: 1), returnsNormally);
      expect(() => Measure(const [], measureRepeat: 3), throwsA(isA<Error>()));
      expect(
          () => Measure([
                NoteElement.note(const Pitch(Step.c), NoteDuration.whole),
              ], measureRepeat: 1),
          throwsA(isA<Error>()));
    });

    test('participates in equality and copyWith', () {
      expect(Measure(const [], measureRepeat: 2),
          Measure(const [], measureRepeat: 2));
      expect(Measure(const [], measureRepeat: 2),
          isNot(Measure(const [], measureRepeat: 4)));
      expect(const Measure([]).copyWith(measureRepeat: 4).measureRepeat, 4);
    });
  });

  group('layout', () {
    test('draws the simile glyph centred on the staff', () {
      final glyphs = const LayoutEngine()
          .layout(withRepeat(1), settings)
          .primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == 'repeat1Bar')
          .toList();
      expect(glyphs, hasLength(1));
      expect(glyphs.single.position.y, closeTo(2.0, 1e-9)); // centred
    });

    test('2- and 4-bar variants pick their own glyph', () {
      String repeatGlyph(int count) => const LayoutEngine()
          .layout(withRepeat(count), settings)
          .primitives
          .whereType<GlyphPrimitive>()
          .map((g) => g.smuflName)
          .firstWhere((n) => n.startsWith('repeat'));
      expect(repeatGlyph(2), 'repeat2Bars');
      expect(repeatGlyph(4), 'repeat4Bars');
    });

    test('the repeated bar still occupies its own measure region', () {
      final layout = const LayoutEngine().layout(withRepeat(1), settings);
      expect(layout.measureRegions, hasLength(3));
    });

    test('in a system, the repeated bar closes with the other staves', () {
      // A drum staff repeating its bar under a busier staff: the simile's
      // own fixed width closed the drum bar well before the staff above.
      final busy = Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: 'c5:q d5 e5 f5 | c5:e d5 e5 f5 g5 a5 b5 c6 | c5:w');
      final system = StaffSystem([busy, withRepeat(1)]);
      final layout = layoutStaffSystem(system, settings);
      expect(systemMisalignments(layout), isEmpty);
      final drum = layout.staves[1];
      final glyph = drum.primitives
          .whereType<GlyphPrimitive>()
          .firstWhere((g) => g.smuflName == 'repeat1Bar');
      final bar = drum.measureRegions[1];
      final width = settings.metadata.bBoxOf('repeat1Bar').width;
      // Still centred in its (wider) bar.
      expect(glyph.position.x + width / 2,
          closeTo((bar.startX + bar.endX) / 2, 0.01));
    });
  });
}
