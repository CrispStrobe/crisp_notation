import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

late final LayoutSettings settings;

/// The filled fingering dots (round-capped, zero-length lines).
Iterable<LinePrimitive> dots(ScoreLayout l) => l.primitives
    .whereType<LinePrimitive>()
    .where((p) => p.round && p.from == p.to);

Iterable<String> texts(ScoreLayout l) =>
    l.primitives.whereType<TextPrimitive>().map((t) => t.text);

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    settings = LayoutSettings(
      metadata:
          SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>),
    );
  });

  test('an open C chord: dots, open/muted markers and a name', () {
    // High-e first: e0 B1 G0 D2 A3 lowE-x.
    final layout = layoutChordDiagram(
      const ChordDiagram([0, 1, 0, 2, 3, -1], name: 'C'),
      settings,
    );
    expect(dots(layout), hasLength(3)); // B, D, A fretted
    expect(texts(layout).where((t) => t == 'o'), hasLength(2)); // G, high e
    expect(texts(layout).where((t) => t == 'x'), hasLength(1)); // low E
    expect(texts(layout), contains('C'));
  });

  test('the nut is a thick top line at base fret 1', () {
    final layout =
        layoutChordDiagram(const ChordDiagram([0, 0, 0, 0, 0, 0]), settings);
    final horizontals = layout.primitives
        .whereType<LinePrimitive>()
        .where((l) => l.from.y == l.to.y && !l.round)
        .toList();
    final topLine = horizontals.reduce((a, b) => a.from.y < b.from.y ? a : b);
    // The nut is noticeably thicker than the ordinary fret lines.
    expect(topLine.thickness, greaterThan(settings.staffLineThickness * 2));
  });

  test('a higher position shows a base-fret label and no thick nut', () {
    final layout = layoutChordDiagram(
      const ChordDiagram([5, 7, 7, 7, 5, -1], name: 'D', baseFret: 5),
      settings,
    );
    expect(texts(layout), contains('5fr'));
    final horizontals = layout.primitives
        .whereType<LinePrimitive>()
        .where((l) => l.from.y == l.to.y && !l.round);
    expect(
      horizontals.every((l) => l.thickness <= settings.staffLineThickness * 2),
      isTrue,
    );
  });

  test('a barre draws one horizontal round line and replaces its dots', () {
    final layout = layoutChordDiagram(
      const ChordDiagram([1, 1, 2, 3, 3, 1], name: 'F', barreFret: 1),
      settings,
    );
    final barre = layout.primitives
        .whereType<LinePrimitive>()
        .where((p) => p.round && p.from.y == p.to.y && p.from.x != p.to.x);
    expect(barre, hasLength(1));
    // The three fret-1 strings are covered by the barre, leaving dots only on
    // frets 2 and 3 (G at 2; D, A at 3) → 3 individual dots.
    expect(dots(layout), hasLength(3));
  });

  test('finger numbers render below the grid', () {
    final layout = layoutChordDiagram(
      const ChordDiagram([0, 1, 0, 2, 3, -1],
          name: 'C', fingers: [null, 1, null, 2, 3, null]),
      settings,
    );
    expect(texts(layout), containsAll(['1', '2', '3']));
  });

  test('renders through the SVG emitter', () {
    final svg = scoreToSvg(
      layoutChordDiagram(
          const ChordDiagram([0, 1, 0, 2, 3, -1], name: 'C'), settings),
    );
    expect(svg, contains('<svg'));
    expect(svg, contains('stroke-linecap="round"')); // the dots
  });

  test('a placed diagram renders above the notation staff over its note', () {
    final base = Score.simple(notes: 'c4:q d4');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      chordDiagrams: const [
        PlacedChordDiagram('e0', ChordDiagram([0, 1, 0, 2, 3, -1], name: 'C')),
      ],
    );
    final layout = const LayoutEngine().layout(score, settings);
    expect(texts(layout), contains('C'));
    expect(dots(layout), hasLength(3)); // the diagram's fingering dots
    expect(layout.top, lessThan(-3.0)); // the block sits well above the staff
  });

  test('a placed diagram renders above the tab staff', () {
    final base = Score.simple(notes: 'e2:q');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      chordDiagrams: const [
        PlacedChordDiagram('e0', ChordDiagram([0, 1, 0, 2, 3, -1], name: 'Em')),
      ],
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    expect(texts(layout), contains('Em'));
    expect(dots(layout), hasLength(3));
    expect(layout.top, lessThan(-3.0));
  });

  test('a diagram on an unknown note id throws', () {
    final base = Score.simple(notes: 'c4:q');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      chordDiagrams: const [
        PlacedChordDiagram('nope', ChordDiagram([0, 0, 0, 0, 0, 0])),
      ],
    );
    expect(() => const LayoutEngine().layout(score, settings),
        throwsArgumentError);
  });

  test('value semantics', () {
    const a = ChordDiagram([0, 1, 0, 2, 3, -1], name: 'C');
    const b = ChordDiagram([0, 1, 0, 2, 3, -1], name: 'C');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == const ChordDiagram([0, 1, 0, 2, 3, 0], name: 'C'), isFalse);
  });
}
