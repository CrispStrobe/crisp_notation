import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// The layout engine must not confuse a voice's DISPLAY slot with its number.
///
/// `Measure.voices` is a compacting view — it drops empty voices — while
/// `effectiveDurationAt` and `TupletSpan.voice` take the absolute voice number.
/// The two disagree the moment a voice is empty, and the engine was indexing one
/// by the other: with nothing in voice 2 and notes in voice 3, display slot 1
/// held voice 3's elements while the duration lookup read voice 2's, which is
/// empty. That is a RangeError, i.e. the score does not render AT ALL.
///
/// The shape is not exotic — the codecs produce it. MEI names its layers, so a
/// `<layer n="4">` can arrive with no layer 3.
void main() {
  late LayoutSettings settings;

  setUpAll(() {
    final meta = SmuflMetadata.fromJson(jsonDecode(
        File('../crisp_notation/assets/smufl/bravura_metadata.json')
            .readAsStringSync()) as Map<String, Object?>);
    settings = LayoutSettings(metadata: meta);
  });

  NoteElement n(int midi, String id) => NoteElement(
        pitches: [Pitch.fromMidi(midi)],
        duration: const NoteDuration(DurationBase.quarter),
        id: id,
      );

  test('a score whose voice 2 is empty and voice 3 is not still lays out', () {
    final score = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        Measure(
          [n(72, 'a'), n(74, 'b'), n(76, 'c'), n(77, 'd')],
          voice3: [n(55, 'e'), n(57, 'f'), n(59, 'g')],
          tuplets: [const TupletSpan(0, 2, actual: 3, normal: 2, voice: 2)],
        ),
      ],
    );
    expect(() => LayoutEngine().layout(score, settings), returnsNormally);
  });

  test('voice 4 alone lays out', () {
    final score = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(2, 4),
      measures: [
        Measure([n(72, 'a'), n(74, 'b')], voice4: [n(48, 'g'), n(50, 'h')]),
      ],
    );
    expect(() => LayoutEngine().layout(score, settings), returnsNormally);
  });

  test('the ordinary contiguous case is unaffected', () {
    final score = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(2, 4),
      measures: [
        Measure(
          [n(72, 'a'), n(74, 'b')],
          voice2: [n(64, 'c'), n(65, 'd')],
          voice3: [n(55, 'e'), n(57, 'f')],
          voice4: [n(48, 'g'), n(50, 'h')],
        ),
      ],
    );
    expect(() => LayoutEngine().layout(score, settings), returnsNormally);
  });
}
