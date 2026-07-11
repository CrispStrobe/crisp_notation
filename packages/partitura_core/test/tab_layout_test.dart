import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.8: tablature layout.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout tabOf(Score score, [Tuning? tuning]) => const TabLayoutEngine()
    .layout(score, tuning ?? Tuning.standardGuitar, settings);

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  test('draws six string lines and a tab clef', () {
    final layout = tabOf(Score.simple(notes: 'e2:q a2 d3 g3'));
    // Horizontal line segments exist at six distinct string y-positions.
    final lineYs = layout.primitives
        .whereType<LinePrimitive>()
        .where((l) => l.from.y == l.to.y)
        .map((l) => l.from.y)
        .toSet();
    expect(lineYs.length, 6);
    expect(
      layout.primitives.whereType<GlyphPrimitive>().map((g) => g.smuflName),
      contains(SmuflGlyph.sixStringTabClef),
    );
  });

  test('open strings render as 0 on descending lines', () {
    final layout = tabOf(Score.simple(notes: 'e2:q a2 d3 g3 b3 e4'));
    final digits = layout.primitives.whereType<TextPrimitive>().toList();
    expect(digits.every((d) => d.text == '0'), isTrue);
    expect(digits, hasLength(6));
    // e2 sits on the bottom line, e4 on the top line.
    final bottom = digits.reduce((a, b) => a.position.y > b.position.y ? a : b);
    final top = digits.reduce((a, b) => a.position.y < b.position.y ? a : b);
    expect(bottom.position.x, lessThan(top.position.x)); // e2 comes first
  });

  test('a fretted note shows its fret number', () {
    final layout = tabOf(Score.simple(notes: 'g4:q')); // 3rd fret, high E
    final digit = layout.primitives.whereType<TextPrimitive>().single;
    expect(digit.text, '3');
  });

  test('a chord stacks a digit per string', () {
    final layout = tabOf(Score.simple(notes: 'e2+b2+e4:h'));
    expect(layout.primitives.whereType<TextPrimitive>(), hasLength(3));
  });

  test('measures produce regions and barlines', () {
    final layout = tabOf(Score.simple(notes: 'e2:q a2 | d3:q g3'));
    expect(layout.measureRegions, hasLength(2));
    final barlines = layout.primitives
        .whereType<LinePrimitive>()
        .where((l) => l.from.x == l.to.x);
    expect(barlines.length, greaterThanOrEqualTo(2));
  });

  test('stemmed notes get stems below the staff', () {
    final layout = tabOf(Score.simple(notes: 'e2:q a2:h'));
    const bottomY = 5 * TabLayoutEngine.lineGap; // 6-string staff
    final stems = layout.primitives
        .whereType<LinePrimitive>()
        .where((l) => l.from.x == l.to.x && l.from.y > bottomY);
    expect(stems, hasLength(2)); // quarter + half both stemmed
  });

  test('a whole note carries no stem', () {
    final layout = tabOf(Score.simple(notes: 'e2:w'));
    const bottomY = 5 * TabLayoutEngine.lineGap;
    expect(
      layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.x == l.to.x && l.from.y > bottomY),
      isEmpty,
    );
  });

  test('eighth notes beam per beat', () {
    // Four eighths in 4/4 → two beamed pairs (one beam each).
    final layout = tabOf(Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'e2:e a2 d3 g3',
    ));
    expect(layout.primitives.whereType<BeamPrimitive>(), hasLength(2));
  });

  test('a glissando renders a slide line between two frets', () {
    final base = Score.simple(notes: 'a3:q c4');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      glissandos: const [Glissando('e0', 'e1')],
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    // A diagonal (non-vertical, non-horizontal) line: the slide.
    expect(
      layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.x != l.to.x && l.from.y != l.to.y),
      hasLength(1),
    );
  });

  test('a slur renders a hammer-on/pull-off arc', () {
    final base = Score.simple(notes: 'd3:q( f3)');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      slurs: base.slurs,
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    expect(layout.primitives.whereType<CurvePrimitive>(), hasLength(1));
  });

  test('a bend draws an arrow curve and its amount label', () {
    final base = Score.simple(notes: 'g4:q b4');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      bends: const [Bend('e0'), Bend('e1', steps: 0.5)],
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    final labels =
        layout.primitives.whereType<TextPrimitive>().map((t) => t.text);
    expect(labels, containsAll(['full', '½']));
    expect(layout.primitives.whereType<CurvePrimitive>(), hasLength(2));
  });

  test('a vibrato draws a wavy line above the fret', () {
    final base = Score.simple(notes: 'g4:q b4');
    final plain = const TabLayoutEngine()
        .layout(base, Tuning.standardGuitar, settings)
        .primitives
        .whereType<CurvePrimitive>()
        .length;
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      vibratos: const [Vibrato('e0')],
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    // The wavy line adds several curve segments above the plain baseline.
    expect(
      layout.primitives.whereType<CurvePrimitive>().length,
      greaterThan(plain),
    );
    // The wave sits above the fret digit (smaller y = higher on the staff).
    final digitY = layout.primitives
        .whereType<TextPrimitive>()
        .firstWhere((t) => t.text == '3')
        .position
        .y;
    expect(
      layout.primitives
          .whereType<CurvePrimitive>()
          .every((c) => c.start.y < digitY),
      isTrue,
    );
  });

  test('a wide vibrato uses a larger amplitude than a normal one', () {
    Score scoreWith(bool wide) {
      final base = Score.simple(notes: 'g4:q');
      return Score(
        clef: base.clef,
        measures: base.measures,
        vibratos: [Vibrato('e0', wide: wide)],
      );
    }

    double span(Score s) {
      final ys = const TabLayoutEngine()
          .layout(s, Tuning.standardGuitar, settings)
          .primitives
          .whereType<CurvePrimitive>()
          .expand((c) => [c.control1.y, c.control2.y]);
      return ys.reduce(max) - ys.reduce(min);
    }

    expect(span(scoreWith(true)), greaterThan(span(scoreWith(false))));
  });

  test('deterministic', () {
    String render() => tabOf(Score.simple(notes: 'e2:q a2 d3 g3'))
        .primitives
        .map((p) => p.toString())
        .join('\n');
    expect(render(), render());
  });
}
