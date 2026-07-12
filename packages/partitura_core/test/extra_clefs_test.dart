import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Phase 5.2: French violin, soprano, mezzo-soprano, baritone and sub-bass
/// clef positions.
void main() {
  late final LayoutSettings settings;
  setUpAll(() {
    final meta = SmuflMetadata.fromJson(jsonDecode(
        File('../partitura/assets/smufl/bravura_metadata.json')
            .readAsStringSync()) as Map<String, Object?>);
    settings = LayoutSettings(metadata: meta);
  });

  // (clef, bottom-line pitch, expected clef glyph, MusicXML sign+line)
  final cases = [
    (Clef.frenchViolin, const Pitch(Step.g, octave: 4), 'gClef', 'G', 1),
    (Clef.soprano, const Pitch(Step.c, octave: 4), 'cClef', 'C', 1),
    (Clef.mezzoSoprano, const Pitch(Step.a, octave: 3), 'cClef', 'C', 2),
    (Clef.baritone, const Pitch(Step.b, octave: 2), 'fClef', 'F', 3),
    (Clef.subbass, const Pitch(Step.e, octave: 2), 'fClef', 'F', 5),
  ];

  test('each clef puts the right natural on its bottom line', () {
    for (final (clef, bottom, _, _, _) in cases) {
      expect(clef.pitchAt(0), bottom, reason: '$clef');
    }
  });

  test('each clef draws its expected glyph', () {
    for (final (clef, _, glyph, _, _) in cases) {
      final names = (const LayoutEngine())
          .layout(
            Score(clef: clef, measures: [
              Measure([
                NoteElement.note(clef.pitchAt(4), NoteDuration.quarter, id: 'n')
              ])
            ]),
            settings,
          )
          .primitives
          .whereType<GlyphPrimitive>()
          .map((g) => g.smuflName);
      expect(names, contains(glyph), reason: '$clef');
    }
  });

  test('MusicXML round-trips every clef position', () {
    for (final (clef, _, _, sign, line) in cases) {
      final score = Score(
        clef: clef,
        measures: [
          Measure([
            NoteElement.note(clef.pitchAt(2), NoteDuration.whole, id: 'e0')
          ]),
        ],
      );
      final xml = scoreToMusicXml(score);
      expect(xml, contains('<sign>$sign</sign><line>$line</line>'),
          reason: '$clef');
      expect(scoreFromMusicXml(xml).clef, clef, reason: '$clef');
    }
  });

  test('key signatures stay on the staff in the new clefs', () {
    for (final (clef, _, _, _, _) in cases) {
      for (final fifths in [7, -7, 4, -3]) {
        final layout = (const LayoutEngine()).layout(
          Score(
            clef: clef,
            keySignature: KeySignature(fifths),
            measures: [
              Measure([
                NoteElement.note(clef.pitchAt(4), NoteDuration.whole, id: 'n')
              ])
            ],
          ),
          settings,
        );
        final accidentals = layout.primitives
            .whereType<GlyphPrimitive>()
            .where((g) =>
                g.elementId == null &&
                (g.smuflName == 'accidentalSharp' ||
                    g.smuflName == 'accidentalFlat'))
            .toList();
        expect(accidentals, hasLength(fifths.abs()), reason: '$clef $fifths');
        for (final a in accidentals) {
          expect(a.position.y, inInclusiveRange(-0.5, 4.5),
              reason: '$clef $fifths at ${a.position}');
        }
      }
    }
  });
}
