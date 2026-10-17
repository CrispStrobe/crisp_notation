import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Square notation from GABC: notes at the staff positions the letters
/// name, neumes joined as printed, bars and syllables.
void main() {
  late LayoutSettings settings;
  setUpAll(() {
    settings = LayoutSettings(
        metadata: SmuflMetadata.fromJson(jsonDecode(
            File('../crisp_notation/assets/smufl/bravura_metadata.json')
                .readAsStringSync()) as Map<String, Object?>));
  });

  List<GlyphPrimitive> glyphs(ScoreLayout l, String prefix) => [
        for (final g in l.primitives.whereType<GlyphPrimitive>())
          if (g.smuflName.startsWith(prefix)) g,
      ];

  test('a four-line staff with the clef on its line', () {
    final l = layoutChant('%%\n(c3) A(d)', settings);
    final staff = l.primitives
        .whereType<LinePrimitive>()
        .where((p) => p.from.y == p.to.y && p.to.x - p.from.x > 2)
        .map((p) => p.from.y)
        .toSet();
    expect(staff, {0.0, 1.0, 2.0, 3.0});
    expect(glyphs(l, 'chantCclef').single.position.y, 1.0); // line 3
  });

  test('letters are staff positions: d on the bottom line, j on the top', () {
    final l = layoutChant('%%\n(c4) a(d) b(f) c(h) d(j)', settings);
    expect([for (final g in glyphs(l, 'chantPunctum')) g.position.y],
        [3.0, 2.0, 1.0, 0.0]);
  });

  test('note shapes follow the GABC modifiers', () {
    final l = layoutChant('%%\n(c4) a(gv) b(gw) c(go) d(G) e(g~)', settings);
    final names = [
      for (final g in l.primitives.whereType<GlyphPrimitive>())
        if (g.elementId != null) g.smuflName,
    ];
    expect(names, [
      'chantPunctumVirga',
      'chantQuilisma',
      'chantOriscusAscending',
      'chantPunctumInclinatum',
      'chantPunctumDeminutum',
    ]);
  });

  test('a pes stacks its notes; a clivis sets them side by side', () {
    final pes = glyphs(layoutChant('%%\n(c4) a(fg)', settings), 'chantPunctum');
    expect(pes[0].position.x, pes[1].position.x);
    expect(pes[1].position.y, lessThan(pes[0].position.y));
    final clivis =
        glyphs(layoutChant('%%\n(c4) a(gf)', settings), 'chantPunctum');
    expect(clivis[1].position.x, greaterThan(clivis[0].position.x));
  });

  test('every note has an id and a hit region; syllables are text', () {
    final l = layoutChant('%%\n(c4) Ky(f)ri(gh)e(g.) (::)', settings);
    expect([for (final r in l.regions) r.elementId], ['n0', 'n1', 'n2', 'n3']);
    expect([for (final t in l.primitives.whereType<TextPrimitive>()) t.text],
        containsAll(['Ky', 'ri', 'e']));
    expect(glyphs(l, 'augmentationDot'), hasLength(1));
  });

  test('syllables never overlap, however close their notes', () {
    final l = layoutChant(
        '%%\n(c4) Glo(f)ri(f)a(f) in(f) ex(f)cel(f)sis(f)', settings);
    final texts = l.primitives.whereType<TextPrimitive>().toList();
    for (var i = 1; i < texts.length; i++) {
      final a = texts[i - 1], b = texts[i];
      expect(
          b.position.x - estimateTextHalfWidth(b.text, b.size),
          greaterThanOrEqualTo(
              a.position.x + estimateTextHalfWidth(a.text, a.size)),
          reason: '${a.text} / ${b.text}');
    }
  });

  test('long chant breaks into lines that each open with the clef', () {
    final gabc = '%%\n(c3) ${List.filled(30, 'la(f)').join(' ')} (::)';
    final lines = layoutChantLines(gabc, settings, maxWidth: 40);
    expect(lines.length, greaterThan(1));
    for (final line in lines) {
      expect(line.width, lessThanOrEqualTo(40));
      expect(glyphs(line, 'chantCclef'), hasLength(1));
    }
    // Ids run on across lines.
    expect(lines[1].regions.first.elementId, isNot('n0'));
  });
}
