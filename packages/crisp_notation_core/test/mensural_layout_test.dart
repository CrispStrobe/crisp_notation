import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// White mensural notation from MEI.
void main() {
  late LayoutSettings settings;
  late String mei;
  setUpAll(() {
    settings = LayoutSettings(
        metadata: SmuflMetadata.fromJson(jsonDecode(
            File('../crisp_notation/assets/smufl/bravura_metadata.json')
                .readAsStringSync()) as Map<String, Object?>));
    mei = File('test/data/mensural_excerpt.mei').readAsStringSync();
  });

  List<String> glyphs(ScoreLayout l) => [
        for (final g in l.primitives.whereType<GlyphPrimitive>()) g.smuflName,
      ];

  test('note values take their mensural shapes, with no barlines', () {
    final l = layoutMensural(mei, settings);
    final names = glyphs(l);
    for (final shape in [
      'mensuralCclef',
      'mensuralProlation6', // C: tempus imperfectum, prolatio minor
      'mensuralWhiteBrevis',
      'mensuralWhiteSemibrevis',
      'mensuralWhiteMinima',
      'mensuralWhiteSemiminima',
      'mensuralWhiteLonga',
      'mensuralWhiteMaxima',
      'mensuralRestSemibrevis',
      'mensuralRestBrevis',
      'mensuralCustosUp',
      'accidentalFlat',
      'augmentationDot',
    ]) {
      expect(names, contains(shape));
    }
    // Five staff lines and no vertical barlines.
    final lines = l.primitives.whereType<LinePrimitive>();
    expect(lines.where((p) => p.from.y == p.to.y && p.to.x - p.from.x > 5),
        hasLength(5));
    expect(lines.where((p) => p.from.x == p.to.x), isEmpty);
  });

  test('pitches sit by the clef: C clef on line 1 puts C4 on the bottom line',
      () {
    final l = layoutMensural(
        '<mei><staffDef n="1" clef.shape="C" clef.line="1"/>'
        '<staff n="1"><layer><note pname="c" oct="4" dur="semibrevis"/>'
        '<note pname="e" oct="4" dur="semibrevis"/></layer></staff></mei>',
        settings);
    final notes = [
      for (final g in l.primitives.whereType<GlyphPrimitive>())
        if (g.elementId != null) g.position.y,
    ];
    expect(notes, [4.0, 3.0]);
  });

  test('ids and hit regions in reading order; lines open with the clef', () {
    final l = layoutMensural(mei, settings);
    expect(l.regions.first.elementId, 'm0');
    expect(l.regions, hasLength(13));
    final lines = layoutMensuralLines(mei, settings, maxWidth: 20);
    expect(lines.length, greaterThan(1));
    for (final line in lines) {
      expect(glyphs(line), contains('mensuralCclef'));
    }
  });
}
