import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A note tied over the barline does not repeat its accidental: the tie
/// carries it (Gould). A later note on the same step in that bar does
/// restate it. Found by counting accidentals per bar against Verovio: 188
/// songs drew one too many, every one a tied-over note.
void main() {
  late LayoutSettings settings;
  setUpAll(() {
    settings = LayoutSettings(
        metadata: SmuflMetadata.fromJson(jsonDecode(
            File('../crisp_notation/assets/smufl/bravura_metadata.json')
                .readAsStringSync()) as Map<String, Object?>));
  });

  List<String?> accidentalsOn(Score score) => [
        for (final g in const LayoutEngine()
            .layout(score, settings)
            .primitives
            .whereType<GlyphPrimitive>())
          if (g.smuflName.startsWith('accidental')) g.elementId,
      ];

  NoteElement db5(String id, NoteDuration d, {bool tie = false}) =>
      NoteElement.note(const Pitch(Step.d, alter: -1, octave: 5), d,
          id: id, tieToNext: tie);

  test('the tied-over note keeps no accidental; the next one restates it', () {
    final score = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          NoteElement.note(const Pitch(Step.c, octave: 5), NoteDuration.half,
              id: 'c'),
          db5('a', NoteDuration.half, tie: true),
        ]),
        Measure([
          db5('b', NoteDuration.half),
          db5('later', NoteDuration.half),
        ]),
      ],
    );
    expect(accidentalsOn(score), ['a', 'later']);
  });

  test('an accidental the source states on the tied note still prints', () {
    final score = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([db5('a', NoteDuration.whole, tie: true)]),
        Measure([
          NoteElement.note(
              const Pitch(Step.d, alter: -1, octave: 5), NoteDuration.whole,
              id: 'b', showAccidental: true),
        ]),
      ],
    );
    expect(accidentalsOn(score), ['a', 'b']);
  });
}
