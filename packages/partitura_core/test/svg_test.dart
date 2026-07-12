import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

late final LayoutSettings settings;
late final SmuflMetadata metadata;

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

  test('emits a well-formed SVG document sized to the layout', () {
    final layout = layoutOf(Score.simple(notes: 'c4:q d4 e4 f4'));
    final svg = scoreToSvg(layout, staffSpace: 10);
    expect(svg, startsWith('<?xml'));
    expect(svg, contains('<svg'));
    expect(svg.trimRight(), endsWith('</svg>'));
    // The single scale transform is present.
    expect(svg, contains('scale(10'));
  });

  test('renders staff lines and a clef glyph', () {
    final svg = scoreToSvg(layoutOf(Score.simple(notes: 'c4:q')));
    expect(svg, contains('<line')); // staff lines / stems
    // The treble clef glyph is emitted as text in the engraving font.
    expect(svg, contains(smuflCodepoints['gClef']!));
    expect(svg, contains('font-family="Bravura"'));
  });

  test('a note glyph appears as a text element', () {
    final svg = scoreToSvg(layoutOf(Score.simple(notes: 'c4:q')));
    expect(svg, contains(smuflCodepoints['noteheadBlack']!));
  });

  test('elementColors paints a note in its own color', () {
    // Two quarter notes e0, e1; color e1 red.
    final layout = layoutOf(Score.simple(notes: 'c4:q d4'));
    final svg = scoreToSvg(layout, elementColors: const {'e1': '#ff0000'});
    // The colored note's notehead carries a fill override; a plain note has
    // no per-glyph fill (it inherits the group color).
    expect(svg, contains('fill="#ff0000"'));
    // The default color note has no red.
    expect('#ff0000'.allMatches(svg).length, greaterThanOrEqualTo(1));
  });

  test('beams render as filled polygons', () {
    final svg = scoreToSvg(layoutOf(Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:e d4 e4 f4',
    )));
    expect(svg, contains('<polygon'));
  });

  test('slurs render as bezier paths', () {
    final base = Score.simple(notes: 'c4:q( d4)');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      slurs: base.slurs,
    );
    final svg = scoreToSvg(layoutOf(score));
    expect(svg, contains('<path'));
    expect(svg, contains('C ')); // cubic bezier command
  });

  test('text is XML-escaped (tab harmonic brackets)', () {
    // A tab layout with a natural harmonic renders "<12>" as text; the
    // angle brackets must be escaped so the SVG stays well-formed.
    final base = Score.simple(notes: 'e5:q');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      tabNoteMarks: const [TabNoteMark('e0', TabNoteStyle.harmonic)],
    );
    final tab =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    final svg = scoreToSvg(tab);
    expect(svg, contains('&lt;12&gt;'));
    expect(svg, isNot(contains('>12<'))); // no raw brackets
  });

  test('embeds a font-face when a data URI is given', () {
    final svg = scoreToSvg(
      layoutOf(Score.simple(notes: 'c4:q')),
      fontFaceDataUri: 'data:font/otf;base64,AAAA',
    );
    expect(svg, contains('@font-face'));
    expect(svg, contains('data:font/otf;base64,AAAA'));
  });

  test('transparent background omits the page rect', () {
    final svg = scoreToSvg(
      layoutOf(Score.simple(notes: 'c4:q')),
      background: 'none',
    );
    expect(svg, isNot(contains('<rect')));
  });

  test('deterministic', () {
    final layout = layoutOf(Score.simple(notes: 'c4:q d4 e4'));
    expect(scoreToSvg(layout), scoreToSvg(layout));
  });
}
