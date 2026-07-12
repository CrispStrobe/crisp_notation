import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Phase 1.3: the layout engine is font-agnostic — it reads engraving metrics
/// (line/stem thicknesses) from whatever SMuFL metadata it is handed, so a
/// different font produces a differently-weighted score.
void main() {
  late final Map<String, Object?> bravuraJson;
  setUpAll(() {
    bravuraJson = jsonDecode(
        File('../partitura/assets/smufl/bravura_metadata.json')
            .readAsStringSync()) as Map<String, Object?>;
  });

  // A copy of the Bravura metadata with one engraving default overridden.
  SmuflMetadata withDefault(String key, double value) {
    final json = jsonDecode(jsonEncode(bravuraJson)) as Map<String, Object?>;
    (json['engravingDefaults'] as Map<String, Object?>)[key] = value;
    return SmuflMetadata.fromJson(json);
  }

  test('LayoutSettings seeds thicknesses from the font metadata', () {
    final thin = LayoutSettings(metadata: withDefault('stemThickness', 0.08));
    final thick = LayoutSettings(metadata: withDefault('stemThickness', 0.30));
    expect(thin.stemThickness, 0.08);
    expect(thick.stemThickness, 0.30);
  });

  test('a heavier-stemmed font renders heavier stems', () {
    List<LinePrimitive> stems(SmuflMetadata m) {
      final settings = LayoutSettings(metadata: m);
      final layout = const LayoutEngine()
          .layout(Score.simple(notes: 'c5:q d5 e5 f5'), settings);
      return layout.primitives
          .whereType<LinePrimitive>()
          .where((l) =>
              l.from.x == l.to.x && l.thickness == settings.stemThickness)
          .toList();
    }

    final thinStems = stems(withDefault('stemThickness', 0.08));
    final thickStems = stems(withDefault('stemThickness', 0.30));
    expect(thinStems, isNotEmpty);
    expect(thinStems.length, thickStems.length);
    expect(thinStems.first.thickness, 0.08);
    expect(thickStems.first.thickness, 0.30);
  });

  test('staff-line thickness follows the font too', () {
    final s = LayoutSettings(metadata: withDefault('staffLineThickness', 0.25));
    final layout = const LayoutEngine().layout(Score.simple(notes: 'c5:q'), s);
    final staffLines = layout.primitives
        .whereType<LinePrimitive>()
        .where((l) => l.from.y == l.to.y && l.thickness == 0.25);
    expect(staffLines, hasLength(5));
  });
}
