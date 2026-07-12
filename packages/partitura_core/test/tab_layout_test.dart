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

  test('a palm mute draws a P.M. label and a dashed bracket', () {
    final base = Score.simple(notes: 'e2:q a2 d3 g3');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      palmMutes: const [PalmMute('e0', 'e3')],
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    final labels =
        layout.primitives.whereType<TextPrimitive>().map((t) => t.text);
    expect(labels, contains('P.M.'));
    // The bracket sits above the top string line (negative y).
    final aboveLines = layout.primitives
        .whereType<LinePrimitive>()
        .where((l) => l.from.y < 0 && l.to.y < 0 && l.from.y == l.to.y);
    expect(aboveLines, isNotEmpty); // dashed horizontal segments
  });

  test('a let ring draws a let-ring label', () {
    final base = Score.simple(notes: 'e2:q a2');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      letRings: const [LetRing('e0', 'e1')],
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    expect(
      layout.primitives.whereType<TextPrimitive>().map((t) => t.text),
      contains('let ring'),
    );
  });

  test('a single-note palm mute draws only the label and end tick', () {
    final base = Score.simple(notes: 'e2:q');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      palmMutes: const [PalmMute('e0', 'e0')],
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    // No dashed horizontal segment for a zero-length span.
    final horizontalAbove = layout.primitives
        .whereType<LinePrimitive>()
        .where((l) => l.from.y < 0 && l.from.y == l.to.y);
    expect(horizontalAbove, isEmpty);
    expect(
      layout.primitives.whereType<TextPrimitive>().map((t) => t.text),
      contains('P.M.'),
    );
  });

  test('a dead note shows an x instead of its fret', () {
    final base = Score.simple(notes: 'g4:q b4'); // frets 3 and 7 on high E
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      tabNoteMarks: const [TabNoteMark('e0', TabNoteStyle.dead)],
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    final texts = layout.primitives
        .whereType<TextPrimitive>()
        .map((t) => t.text)
        .toList();
    expect(texts, contains('x'));
    expect(texts, isNot(contains('3'))); // fret 3 replaced by x
    expect(texts, contains('7')); // the other note is unaffected
  });

  test('a ghost note wraps its fret in parentheses', () {
    final base = Score.simple(notes: 'g4:q');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      tabNoteMarks: const [TabNoteMark('e0', TabNoteStyle.ghost)],
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    expect(
      layout.primitives.whereType<TextPrimitive>().map((t) => t.text),
      contains('(3)'),
    );
  });

  test('a natural harmonic wraps its fret in angle brackets', () {
    // e5 sits at the 12th-fret (octave) harmonic on the high E string.
    final base = Score.simple(notes: 'e5:q');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      tabNoteMarks: const [TabNoteMark('e0', TabNoteStyle.harmonic)],
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    expect(
      layout.primitives.whereType<TextPrimitive>().map((t) => t.text),
      contains('<12>'),
    );
  });

  test('every string of a dead chord shows an x', () {
    final base = Score.simple(notes: 'e2+b2+e4:q');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      tabNoteMarks: const [TabNoteMark('e0', TabNoteStyle.dead)],
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    final xs = layout.primitives
        .whereType<TextPrimitive>()
        .where((t) => t.text == 'x');
    expect(xs, hasLength(3));
  });

  test('layout bounds cover technique ink above and below the staff', () {
    final base = Score.simple(notes: 'g4:e a4');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      bends: const [Bend('e0', steps: 1.5)], // tall arrow above the staff
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    // Every primitive's y must lie within [top, top + height].
    final top = layout.top;
    final bottom = layout.top + layout.height;
    double lowest = double.infinity, highest = -double.infinity;
    for (final p in layout.primitives) {
      final ys = switch (p) {
        LinePrimitive(:final from, :final to) => [from.y, to.y],
        CurvePrimitive(:final start, :final end) => [start.y, end.y],
        BeamPrimitive(:final start, :final end) => [start.y, end.y],
        TextPrimitive(:final position) => [position.y],
        GlyphPrimitive(:final position) => [position.y],
      };
      for (final y in ys) {
        lowest = lowest < y ? lowest : y;
        highest = highest > y ? highest : y;
      }
    }
    expect(top, lessThanOrEqualTo(lowest));
    expect(bottom, greaterThanOrEqualTo(highest));
    // The tall bend reaches well above the top string line (y = 0).
    expect(top, lessThan(-1.0));
  });

  test('a tab voicing pins a note to a chosen string', () {
    final base = Score.simple(notes: 'b3:q'); // default: fret 0 on the B string
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      tabVoicings: const [
        TabVoicing('e0', [2])
      ], // pin to the G string
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    final digit = layout.primitives.whereType<TextPrimitive>().single;
    expect(digit.text, '4'); // B3 is the 4th fret on the G string
    // ...and it sits on the G-string line (index 2), below the B line (1).
    expect(digit.position.y, greaterThan(1 * TabLayoutEngine.lineGap));
  });

  test('an unplayable voicing falls back to lowest-fret placement', () {
    final base = Score.simple(notes: 'b3:q');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      tabVoicings: const [
        TabVoicing('e0', [0])
      ], // high E string → negative fret
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    expect(layout.primitives.whereType<TextPrimitive>().single.text, '0');
  });

  test('an imported ASCII voicing keeps the written string in tab render', () {
    // Fret 4 on the G string sounds B3, which by default relocates to fret 0
    // on the B string; the imported voicing keeps it as a 4.
    final score = asciiTabToScore('''
e|---|
B|---|
G|-4-|
D|---|
A|---|
E|---|
''');
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    final texts =
        layout.primitives.whereType<TextPrimitive>().map((t) => t.text);
    expect(texts, contains('4'));
    expect(texts, isNot(contains('0')));
  });

  test('a capo shifts the shown fret numbers and adds a label', () {
    final score = Score.simple(notes: 'g4:q'); // fret 3 on the high E string
    final plain = tabOf(score);
    expect(plain.primitives.whereType<TextPrimitive>().single.text, '3');
    final capoed = const TabLayoutEngine()
        .layout(score, Tuning.standardGuitar, settings, capo: 2);
    final texts =
        capoed.primitives.whereType<TextPrimitive>().map((t) => t.text).toSet();
    expect(texts, contains('1')); // 3 − 2
    expect(texts, contains('capo 2'));
  });

  test('showTuning draws each open string note letter', () {
    final layout = const TabLayoutEngine().layout(
        Score.simple(notes: 'e2:q'), Tuning.standardGuitar, settings,
        showTuning: true);
    final texts =
        layout.primitives.whereType<TextPrimitive>().map((t) => t.text);
    // Standard guitar open strings: E B G D A E.
    expect(texts, containsAll(['E', 'B', 'G', 'D', 'A']));
  });

  test('the tuning gutter shifts the staff content right', () {
    final without = tabOf(Score.simple(notes: 'e2:q'));
    final withLabels = const TabLayoutEngine().layout(
        Score.simple(notes: 'e2:q'), Tuning.standardGuitar, settings,
        showTuning: true);
    expect(withLabels.width, greaterThan(without.width));
  });

  test('a tap draws a T above the fret', () {
    final base = Score.simple(notes: 'g4:q');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      taps: const [Tap('e0')],
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    final t = layout.primitives
        .whereType<TextPrimitive>()
        .firstWhere((p) => p.text == 'T');
    final digitY = layout.primitives
        .whereType<TextPrimitive>()
        .firstWhere((p) => p.text == '3')
        .position
        .y;
    expect(t.position.y, lessThan(digitY)); // above the fret digit
  });

  test('a tremolo bar draws a V and its dip amount', () {
    final base = Score.simple(notes: 'g4:q b4');
    final score = Score(
      clef: base.clef,
      measures: base.measures,
      tremoloBars: const [TremoloBar('e0'), TremoloBar('e1', steps: -0.5)],
    );
    final layout =
        const TabLayoutEngine().layout(score, Tuning.standardGuitar, settings);
    final labels =
        layout.primitives.whereType<TextPrimitive>().map((t) => t.text);
    expect(labels, containsAll(['-1', '-½']));
    // Each V is two diagonal line segments above the staff.
    final diagonalsAbove = layout.primitives
        .whereType<LinePrimitive>()
        .where((l) => l.from.x != l.to.x && l.from.y != l.to.y && l.from.y < 0);
    expect(diagonalsAbove.length, greaterThanOrEqualTo(4)); // 2 per bar
  });

  test('a chord assigns each tone to a distinct string', () {
    // E4 and F4 both fret cheapest on the high-E string; the chord must split
    // them onto different lines rather than collide.
    final layout = tabOf(Score.simple(notes: 'e4+f4:q'));
    final digits = layout.primitives.whereType<TextPrimitive>().toList();
    expect(digits, hasLength(2));
    expect(digits.map((d) => d.position.y).toSet(), hasLength(2)); // 2 strings
  });

  test('a six-note chord uses six distinct strings', () {
    // A C-major open voicing: C E G C E — five sounding strings, all distinct.
    final layout = tabOf(Score.simple(notes: 'c3+e3+g3+c4+e4:h'));
    final ys =
        layout.primitives.whereType<TextPrimitive>().map((d) => d.position.y);
    expect(ys.toSet(), hasLength(5)); // no two share a line
  });

  test('deterministic', () {
    String render() => tabOf(Score.simple(notes: 'e2:q a2 d3 g3'))
        .primitives
        .map((p) => p.toString())
        .join('\n');
    expect(render(), render());
  });
}
