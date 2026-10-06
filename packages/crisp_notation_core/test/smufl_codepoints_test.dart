import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Every glyph name the library can produce has a codepoint (#10).
///
/// A note with `<staccatissimo/>` crashed every debug build: the engine drew
/// `articStaccatissimoAbove`, and the hand-kept codepoint table lacked it. So
/// did the four Stein-Zimmermann quarter-tone accidentals, and two entries
/// pointed at the wrong glyph. The table is now generated from the SMuFL
/// glyph list. These tests pin that every name the code builds is in it.
void main() {
  void has(String name, [String? why]) => expect(
        smuflCodepoints.containsKey(name),
        isTrue,
        reason: 'no codepoint for $name${why == null ? '' : ' ($why)'}',
      );

  test('staccatissimo resolves, above and below, to U+E4A6 / U+E4A7', () {
    expect(smuflCodepoints['articStaccatissimoAbove'], '\uE4A6');
    expect(smuflCodepoints['articStaccatissimoBelow'], '\uE4A7');
  });

  test('the two formerly wrong codepoints are SMuFL\'s', () {
    expect(smuflCodepoints['dynamicSforzatoFF'], '\uE53B');
    expect(smuflCodepoints['dynamicRinforzando1'], '\uE53C');
  });

  test('every articulation, above and below', () {
    for (final a in Articulation.values) {
      for (final above in [true, false]) {
        has(SmuflGlyph.articulationGlyph(a, above: above), '$a above=$above');
      }
    }
  });

  test('every dynamic, ornament and microtone', () {
    for (final d in DynamicLevel.values) {
      has(SmuflGlyph.dynamicGlyph(d), '$d');
    }
    for (final o in Ornament.values) {
      has(SmuflGlyph.ornamentGlyph(o), '$o');
    }
    for (final m in MicrotonalAccidental.values) {
      has(m.defaultGlyph, '$m');
    }
  });

  test('every digit, stroke count, repeat sign and accidental', () {
    for (var d = 0; d <= 9; d++) {
      has(SmuflGlyph.timeSigDigit(d));
      has(SmuflGlyph.tupletDigit(d));
      has(SmuflGlyph.fingeringDigit(d));
      has(SmuflGlyph.figbassDigit(d));
    }
    for (var s = 1; s <= 5; s++) {
      has(SmuflGlyph.tremoloStrokes(s));
    }
    for (final c in [1, 2, 4]) {
      has(SmuflGlyph.measureRepeat(c));
    }
    for (var a = -2; a <= 2; a++) {
      has(SmuflGlyph.accidentalFor(a));
    }
  });

  test('every glyph-name literal in the glyph table resolves', () {
    // The constants and switch arms of `SmuflGlyph`, read from the source so
    // a newly added name is checked without editing this test. Interpolated
    // names (`articStaccato$suffix`) are expanded with each suffix used.
    final src = File('lib/src/smufl/glyph_names.dart').readAsStringSync();
    final names = <String>{};
    // `static const String x = 'name'`, a switch arm `=> 'name'`, and the
    // entries of a const list of names.
    final glyphLiteral = RegExp(
        r"(?:static const String \w+\s*=\s*|=>\s*|^\s+)'([A-Za-z0-9]+(?:\$suffix)?)'",
        multiLine: true);
    for (final m in glyphLiteral.allMatches(src)) {
      final lit = m[1]!;
      if (lit.contains(r'$suffix')) {
        for (final sfx in ['Above', 'Below']) {
          names.add(lit.replaceAll(r'$suffix', sfx));
        }
      } else {
        names.add(lit);
      }
    }
    // Strings in that file that are not glyph names.
    names.removeWhere((n) => RegExp(r'^\d+$').hasMatch(n));
    names.removeAll({'digit', 'strokes', 'alter', 'Above', 'Below'});
    // Navigation words (`Fine`, `To Coda`) are text, not glyphs.
    names.removeWhere((n) => RegExp(r'^[A-Z]').hasMatch(n));
    expect(names.length, greaterThan(100));
    for (final n in names) {
      has(n, 'literal in glyph_names.dart');
    }
  });

  test('a laid-out staccatissimo note draws a glyph the table knows', () {
    final xml = '''
<score-partwise version="3.1">
<part-list><score-part id="P1"><part-name>M</part-name></score-part></part-list>
<part id="P1"><measure number="1">
<attributes><divisions>24</divisions><key><fifths>0</fifths></key>
<time><beats>4</beats><beat-type>4</beat-type></time>
<clef><sign>G</sign><line>2</line></clef></attributes>
<note><pitch><step>D</step><octave>5</octave></pitch><duration>24</duration>
<voice>1</voice><type>quarter</type>
<notations><articulations><staccatissimo/></articulations></notations></note>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>24</duration>
<voice>1</voice><type>quarter</type>
<notations><articulations><staccatissimo/></articulations></notations></note>
<note><rest/><duration>48</duration><voice>1</voice><type>half</type></note>
</measure></part></score-partwise>''';
    final settings = LayoutSettings(
        metadata: SmuflMetadata.fromJson(jsonDecode(
            File('../crisp_notation/assets/smufl/bravura_metadata.json')
                .readAsStringSync()) as Map<String, Object?>));
    final layout =
        const LayoutEngine().layout(scoreFromMusicXml(xml), settings);
    final glyphs = layout.primitives.whereType<GlyphPrimitive>().toList();
    expect(glyphs.map((g) => g.smuflName),
        containsAll(['articStaccatissimoAbove', 'articStaccatissimoBelow']));
    for (final g in glyphs) {
      has(g.smuflName);
    }
    // And the SVG carries the glyph characters.
    final svg = scoreToSvg(layout);
    expect(svg, contains('\uE4A6'));
    expect(svg, contains('\uE4A7'));
  });
}
