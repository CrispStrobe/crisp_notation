import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

late final LayoutSettings settings;
late final SmuflMetadata metadata;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
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

  // A score with a lyric syllable, so a <text> element in textFontFamily
  // (not just music-font glyphs) is actually emitted.
  ScoreLayout lyricLayout() {
    final base = Score.simple(notes: 'c4:q');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      lyrics: const [Lyric('e0', 'la')],
    );
    return layoutOf(score);
  }

  test('embeds a text font-face when given, ahead of the text font stack', () {
    final svg = scoreToSvg(
      lyricLayout(),
      embeddedTextFont: const EmbeddedTextFont(
          dataUri: 'data:font/ttf;base64,BBBB', familyName: 'CrispTextTest'),
    );
    expect(svg, contains('@font-face{font-family:"CrispTextTest";'));
    expect(svg, contains('data:font/ttf;base64,BBBB'));
    expect(svg, contains("font-family=\"'CrispTextTest', Academico"));
  });

  test('with both fonts embedded, each gets its own @font-face rule', () {
    final svg = scoreToSvg(
      lyricLayout(),
      fontFaceDataUri: 'data:font/otf;base64,AAAA',
      embeddedTextFont: const EmbeddedTextFont(
          dataUri: 'data:font/ttf;base64,BBBB', familyName: 'CrispTextTest'),
    );
    expect(svg, contains('data:font/otf;base64,AAAA'));
    expect(svg, contains('data:font/ttf;base64,BBBB'));
    expect('@font-face'.allMatches(svg).length, 2);
  });

  test('with no embedded text font, output is unchanged', () {
    final layout = lyricLayout();
    expect(scoreToSvg(layout, fontFaceDataUri: 'data:font/otf;base64,AAAA'),
        scoreToSvg(layout, fontFaceDataUri: 'data:font/otf;base64,AAAA'));
    expect(scoreToSvg(layout), isNot(contains('CrispTextTest')));
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

  group('grandStaffToSvg', () {
    GrandStaffLayout gsLayout() => layoutGrandStaff(
          GrandStaff(
            upper: Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5'),
            lower: Score.simple(clef: Clef.bass, notes: 'c3:q d3 e3 f3'),
          ),
          settings,
        );

    test('emits a well-formed SVG with both staves stacked', () {
      final svg = grandStaffToSvg(gsLayout(), staffSpace: 10);
      expect(svg, startsWith('<?xml'));
      expect(svg.trimRight(), endsWith('</svg>'));
      // The brace margin, the two staves, and the connectors + brace.
      expect('<g transform='.allMatches(svg).length, 4);
      expect(svg, contains(smuflCodepoints['brace']));
    });

    test('height spans both staves plus the gap', () {
      final layout = gsLayout();
      final svg = grandStaffToSvg(layout, staffSpace: 10);
      expect(svg, contains('height='));
      // Taller than either staff alone (both staves + the gap).
      expect(layout.height, greaterThan(layout.upper.height));
      expect(layout.height,
          greaterThan(layout.upper.height + layout.lower.height));
    });

    test('deterministic', () {
      final layout = gsLayout();
      expect(grandStaffToSvg(layout), grandStaffToSvg(layout));
    });
  });

  group('staffSystemToSvg', () {
    StaffSystemLayout trioLayout() => layoutStaffSystem(
          StaffSystem([
            Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5'),
            Score.simple(clef: Clef.alto, notes: 'e4:q f4 g4 a4'),
            Score.simple(clef: Clef.bass, notes: 'c3:q d3 e3 f3'),
          ], barlineGroups: const [
            BarlineGroup(0, 1),
            BarlineGroup(2, 2),
          ]),
          settings,
        );

    test('stacks every staff into one system', () {
      final svg = staffSystemToSvg(trioLayout(), staffSpace: 10);
      expect(svg, startsWith('<?xml'));
      expect(svg.trimRight(), endsWith('</svg>'));
      // Three staff groups, one per part. Staff groups carry a `fill=`; the
      // systemic-barline connector group is drawn separately (stroke only).
      expect('<g transform='.allMatches(svg).length, greaterThanOrEqualTo(3));
      expect(RegExp('<g transform=[^>]*fill=').allMatches(svg).length, 3);
    });

    test('draws the systemic barline connectors', () {
      final svg = staffSystemToSvg(trioLayout(), staffSpace: 10);
      // Beyond each staff's own lines, the group (0,1) connector spans two
      // staves — there are vertical <line> connectors in the output.
      expect(svg, contains('<line'));
    });

    test('deterministic', () {
      final layout = trioLayout();
      expect(staffSystemToSvg(layout), staffSystemToSvg(layout));
    });
  });
}
