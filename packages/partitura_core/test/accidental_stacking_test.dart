import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

/// Element-tagged accidental glyphs of the only element, leftmost first.
List<GlyphPrimitive> accidentalsOf(ScoreLayout layout) => layout.primitives
    .whereType<GlyphPrimitive>()
    .where((g) => g.smuflName.startsWith('accidental') && g.elementId != null)
    .toList()
  ..sort((a, b) => a.position.x.compareTo(b.position.x));

/// Distinct accidental column x-positions (rounded to tolerance).
Set<int> columnsOf(List<GlyphPrimitive> accidentals) =>
    accidentals.map((g) => (g.position.x * 100).round()).toSet();

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  test('far-apart accidentals share one column', () {
    // f#4 (position 3) and f#5 (position 10): 7 apart ≥ 6 → same column.
    final accidentals =
        accidentalsOf(layoutOf(Score.simple(notes: 'f#4+f#5:h')));
    expect(accidentals, hasLength(2));
    expect(columnsOf(accidentals), hasLength(1));
  });

  test('close accidentals fan out into separate columns', () {
    // f#4 (3) and a#4 (5): 2 apart < 6 → two columns.
    final accidentals =
        accidentalsOf(layoutOf(Score.simple(notes: 'f#4+a#4:h')));
    expect(accidentals, hasLength(2));
    expect(columnsOf(accidentals), hasLength(2));
  });

  test('zigzag: top accidental sits closest to the note', () {
    final accidentals =
        accidentalsOf(layoutOf(Score.simple(notes: 'f#4+a#4:h')));
    // Rightmost (largest x) = higher staff position (a#4).
    final rightmost =
        accidentals.reduce((a, b) => a.position.x > b.position.x ? a : b);
    final leftmost =
        accidentals.reduce((a, b) => a.position.x < b.position.x ? a : b);
    expect(rightmost.position.y, lessThan(leftmost.position.y));
  });

  test('dense triple stack: outer pair shares, middle takes column two', () {
    // c#4 (1), e#4? — use c#4, d#5, c#6: positions 1, 9, 15.
    // 1↔9 = 8 ≥ 6 share; but zigzag order is c#6, c#4, d#5:
    // c#6 col 0, c#4 col 0 (14 apart), d#5 col 0 too (6 and 8 apart).
    final one = accidentalsOf(layoutOf(Score.simple(notes: 'c#4+d#5+c#6:h')));
    expect(columnsOf(one), hasLength(1));
    // c#4 (1), d#4 (2), e#4 (3): all adjacent → three columns.
    final three = accidentalsOf(layoutOf(Score.simple(notes: 'c#4+d#4+e#4:h')));
    expect(columnsOf(three), hasLength(3));
  });

  test('stacking narrows the element compared to one column each', () {
    // Two shareable accidentals: leading width shrinks vs. adjacent ones.
    final shared = layoutOf(Score.simple(notes: 'f#4+f#5:h'));
    final fanned = layoutOf(Score.simple(notes: 'f#4+a#4:h'));
    double leadingOf(ScoreLayout layout) => layout.regions.single.bounds.width;
    expect(leadingOf(shared), lessThan(leadingOf(fanned)));
  });

  test('single accidentals and plain chords are unchanged shapes', () {
    final plain = layoutOf(Score.simple(notes: 'c4+e4+g4:h'));
    expect(accidentalsOf(plain), isEmpty);
    final single = accidentalsOf(layoutOf(Score.simple(notes: 'f#4:q')));
    expect(single, hasLength(1));
  });

  test('deterministic', () {
    final score = Score.simple(notes: 'c#4+f#4+a#4+c#5+f#5:w');
    expect(layoutOf(score).primitives.toString(),
        layoutOf(score).primitives.toString());
  });
}
