import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// House styles as style sheets: a JSON object of settings over a preset.
void main() {
  late SmuflMetadata metadata;
  setUpAll(() {
    metadata = SmuflMetadata.fromJson(jsonDecode(
        File('../crisp_notation/assets/smufl/bravura_metadata.json')
            .readAsStringSync()) as Map<String, Object?>);
  });

  test('a style sheet overrides its base preset', () {
    final s = LayoutSettings.fromStyle(
        {'base': 'engraved', 'lyricSize': 1.3, 'drawTempoMarks': false},
        metadata: metadata);
    final engraved = LayoutSettings.engraved(metadata: metadata);
    expect(s.spacingBase, engraved.spacingBase);
    expect(s.lyricSize, 1.3);
    expect(s.drawTempoMarks, isFalse);
  });

  test('choices and glyph maps read by name', () {
    final s = LayoutSettings.fromStyle({
      'noteheadScheme': 'pitchName',
      'fingeringPlacement': 'belowStaff',
      'microtonalGlyphs': {
        MicrotonalAccidental.values.first.name: 'accidentalQuarterToneFlatStein'
      },
    }, metadata: metadata);
    expect(s.noteheadScheme, NoteheadScheme.pitchName);
    expect(s.fingeringPlacement, FingeringPlacement.belowStaff);
    expect(s.microtonalGlyphs.values.single, 'accidentalQuarterToneFlatStein');
  });

  test('toStyle round-trips', () {
    final s = LayoutSettings.spacious(metadata: metadata);
    final again = LayoutSettings.fromStyle(
        jsonDecode(jsonEncode(s.toStyle())) as Map<String, Object?>,
        metadata: metadata);
    expect(again.toStyle(), s.toStyle());
  });

  test('a typo or a wrong kind of value is an error that names it', () {
    expect(
        () => LayoutSettings.fromStyle({'lyricsize': 1.2}, metadata: metadata),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('lyricsize'))));
    expect(
        () =>
            LayoutSettings.fromStyle({'lyricSize': 'big'}, metadata: metadata),
        throwsFormatException);
    expect(
        () => LayoutSettings.fromStyle({'base': 'tight'}, metadata: metadata),
        throwsFormatException);
  });

  test('a style changes the layout', () {
    final score = Score.simple(notes: 'c4:q d4 e4 f4 | g4:w');
    double width(LayoutSettings s) =>
        const LayoutEngine().layout(score, s).width;
    expect(
        width(
            LayoutSettings.fromStyle({'spacingBase': 3.0}, metadata: metadata)),
        greaterThan(width(LayoutSettings(metadata: metadata))));
  });
}
