import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Phase 5.2: neutral / unpitched percussion clef.
void main() {
  late final LayoutSettings settings;
  setUpAll(() {
    final meta = SmuflMetadata.fromJson(jsonDecode(
        File('../partitura/assets/smufl/bravura_metadata.json')
            .readAsStringSync()) as Map<String, Object?>);
    settings = LayoutSettings(metadata: meta);
  });

  List<GlyphPrimitive> glyphs(Score s) => (const LayoutEngine())
      .layout(s, settings)
      .primitives
      .whereType<GlyphPrimitive>()
      .toList();

  test('draws the neutral percussion clef glyph, not a pitched clef', () {
    final names = glyphs(Score(
      clef: Clef.percussion,
      measures: [
        Measure([
          NoteElement.note(const Pitch(Step.b, octave: 4), NoteDuration.quarter,
              id: 'n')
        ]),
      ],
    )).map((g) => g.smuflName);
    expect(names, contains('unpitchedPercussionClef1'));
    expect(names, isNot(contains('gClef')));
  });

  test('a percussion staff shows no key signature', () {
    // Even with a key set, a neutral staff draws no accidentals.
    final accidentals = glyphs(Score(
      clef: Clef.percussion,
      keySignature: const KeySignature(3),
      measures: [
        Measure([
          NoteElement.note(const Pitch(Step.b, octave: 4), NoteDuration.quarter,
              id: 'n')
        ]),
      ],
    )).where((g) => g.smuflName == 'accidentalSharp' && g.elementId == null);
    expect(accidentals, isEmpty);
  });

  test('MusicXML round-trips the percussion clef', () {
    final score = Score(
      clef: Clef.percussion,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          NoteElement.note(const Pitch(Step.f, octave: 4), NoteDuration.quarter,
              id: 'e0'),
          NoteElement.note(const Pitch(Step.f, octave: 4), NoteDuration.quarter,
              id: 'e1'),
        ]),
      ],
    );
    final xml = scoreToMusicXml(score);
    expect(xml, contains('<sign>percussion</sign>'));
    final back = scoreFromMusicXml(xml);
    expect(back.clef, Clef.percussion);
    expect(back, score);
  });

  test('ABC clef=perc imports as the percussion clef', () {
    final score = scoreFromAbc('X:1\nM:4/4\nL:1/4\nK:C clef=perc\nBBBB|\n');
    expect(score.clef, Clef.percussion);
  });

  test('ABC per-voice clef=perc on a system staff', () {
    final sys = staffSystemFromAbc('X:1\nM:4/4\nL:1/4\n'
        'V:1 clef=treble\n'
        'V:2 clef=perc\n'
        'K:C\n'
        'V:1\nCDEF|\n'
        'V:2\nBBBB|\n');
    expect(sys.staves[0].clef, Clef.treble);
    expect(sys.staves[1].clef, Clef.percussion);
  });
}
