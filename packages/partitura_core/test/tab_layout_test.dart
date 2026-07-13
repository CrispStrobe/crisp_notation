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

  test('alternate fretted instruments render with their own line count', () {
    int stringLines(ScoreLayout l) => l.primitives
        .whereType<LinePrimitive>()
        .where((line) => line.from.y == line.to.y)
        .map((line) => line.from.y)
        .toSet()
        .length;
    // Ukulele → 4 lines; a 7-string guitar → 7 lines.
    expect(stringLines(tabOf(Score.simple(notes: 'c4:q'), Tuning.ukulele)), 4);
    expect(
        stringLines(
            tabOf(Score.simple(notes: 'e2:q'), Tuning.sevenStringGuitar)),
        7);
    // The low B1 of the 7-string plays open on its 7th string.
    final low = const TabLayoutEngine()
        .layout(Score.simple(notes: 'b1:q'), Tuning.sevenStringGuitar, settings)
        .primitives
        .whereType<TextPrimitive>()
        .single;
    expect(low.text, '0');
  });

  test('secondary tab beams subdivide at the quarter in cut time', () {
    // A half-note beat of eight sixteenths: one continuous primary beam, with
    // the secondary beam broken at the quarter (two segments, not one).
    final layout = tabOf(Score.simple(
      timeSignature: TimeSignature.cutTime,
      notes: 'e2:s a2 d3 g3 b3 e4 g3 d3 r:h',
    ));
    final beams = layout.primitives.whereType<BeamPrimitive>().toList();
    expect(beams, hasLength(3)); // 1 primary + 2 subdivided secondaries
    final byWidth = beams
      ..sort((a, b) => (a.end.x - a.start.x).compareTo(b.end.x - b.start.x));
    final primary = byWidth.last;
    final secondaries = byWidth.take(2).toList()
      ..sort((a, b) => a.start.x.compareTo(b.start.x));
    // Secondaries are shorter than the primary and don't touch (break at 1/4).
    for (final secondary in secondaries) {
      expect(secondary.end.x - secondary.start.x,
          lessThan(primary.end.x - primary.start.x));
    }
    expect(secondaries[0].end.x, lessThan(secondaries[1].start.x));
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

  group('tab techniques (Phase 6.4)', () {
    Score withTab(Score Function(Score base) build) {
      final base = Score.simple(notes: 'g4:q');
      return build(base);
    }

    List<String> texts(ScoreLayout l) =>
        l.primitives.whereType<TextPrimitive>().map((t) => t.text).toList();

    test('right-hand fingering draws the p-i-m-a letter below the fret', () {
      final score = withTab((b) => Score(
            clef: b.clef,
            measures: b.measures,
            tabFingerings: const [TabFingering('e0', RightHandFinger.thumb)],
          ));
      final layout = tabOf(score);
      expect(texts(layout), contains('p'));
      // The letter sits below the fret digit ('3').
      final digit = layout.primitives
          .whereType<TextPrimitive>()
          .firstWhere((t) => t.text == '3');
      final letter = layout.primitives
          .whereType<TextPrimitive>()
          .firstWhere((t) => t.text == 'p');
      expect(letter.position.y, greaterThan(digit.position.y));
    });

    test('slap and pop draw S and P above the fret', () {
      final slap = tabOf(withTab((b) => Score(
          clef: b.clef,
          measures: b.measures,
          slapPops: const [SlapPop('e0')])));
      expect(texts(slap), contains('S'));
      final pop = tabOf(withTab((b) => Score(
          clef: b.clef,
          measures: b.measures,
          slapPops: const [SlapPop('e0', pop: true)])));
      expect(texts(pop), contains('P'));
    });

    test('tremolo picking draws one slash per stroke', () {
      final score = withTab((b) => Score(
            clef: b.clef,
            measures: b.measures,
            tremoloPickings: const [TremoloPicking('e0', strokes: 3)],
          ));
      // Diagonal lines (neither horizontal nor vertical) are the slashes.
      final slashes = tabOf(score)
          .primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.x != l.to.x && l.from.y != l.to.y);
      expect(slashes, hasLength(3));
    });

    test('techniques on an unknown note id are ignored', () {
      final score = withTab((b) => Score(
            clef: b.clef,
            measures: b.measures,
            slapPops: const [SlapPop('nope')],
          ));
      expect(texts(tabOf(score)), isNot(contains('S')));
    });

    test('ornaments and articulations render above the fret', () {
      final score = Score(clef: Clef.treble, measures: [
        Measure([
          NoteElement(
            pitches: [Pitch.parse('g4')],
            duration: const NoteDuration(DurationBase.quarter),
            id: 'e0',
            ornament: Ornament.trill,
            articulations: const {Articulation.staccato},
          ),
        ]),
      ]);
      final glyphs = tabOf(score)
          .primitives
          .whereType<GlyphPrimitive>()
          .map((g) => g.smuflName)
          .toList();
      expect(glyphs, contains(SmuflGlyph.ornamentTrill));
      expect(
          glyphs,
          contains(SmuflGlyph.articulationGlyph(Articulation.staccato,
              above: true)));
    });

    test('rasgueado draws a downward strum arrow', () {
      final score = withTab((b) => Score(
          clef: b.clef,
          measures: b.measures,
          rasgueados: const [Rasgueado('e0')]));
      // The arrowhead is two diagonal lines.
      final arrowhead = tabOf(score)
          .primitives
          .whereType<LinePrimitive>()
          .where((l) => l.from.x != l.to.x && l.from.y != l.to.y);
      expect(arrowhead, hasLength(2));
    });
  });

  group('grace notes (Phase 6.4)', () {
    test('a grace note adds a smaller fret digit and a legato arc', () {
      final plain = tabOf(Score.simple(notes: 'a4:q'));
      final layout = tabOf(Score.simple(notes: '{g4}a4:q'));
      final digits = layout.primitives.whereType<TextPrimitive>().toList();
      // Two digits: the grace and the principal.
      expect(digits, hasLength(2));
      // Exactly one is drawn small (the grace).
      final small =
          digits.where((d) => d.size < TabLayoutEngine.fretSize).toList();
      expect(small, hasLength(1));
      // The grace sits to the left of the principal.
      final principal =
          digits.firstWhere((d) => d.size == TabLayoutEngine.fretSize);
      expect(small.single.position.x, lessThan(principal.position.x));
      // One legato arc that the plain (grace-less) score lacks.
      expect(layout.primitives.whereType<CurvePrimitive>().length,
          plain.primitives.whereType<CurvePrimitive>().length + 1);
    });

    Score graceScore(GraceStyle style) => Score(
          clef: Clef.treble,
          measures: [
            Measure([
              NoteElement.note(
                const Pitch(Step.a, octave: 4),
                NoteDuration.quarter,
                graceNotes: const [Pitch(Step.g, octave: 4)],
                graceStyle: style,
                id: 'e0',
              ),
            ]),
          ],
        );

    test('an acciaccatura slashes the grace digit; an appoggiatura does not',
        () {
      bool diagonal(LinePrimitive l) =>
          l.from.x != l.to.x && l.from.y != l.to.y;
      final acc = tabOf(graceScore(GraceStyle.acciaccatura))
          .primitives
          .whereType<LinePrimitive>()
          .where(diagonal)
          .length;
      final app = tabOf(graceScore(GraceStyle.appoggiatura))
          .primitives
          .whereType<LinePrimitive>()
          .where(diagonal)
          .length;
      expect(acc, 1); // the slash through the grace digit
      expect(app, 0); // no slash
    });

    test('each of several grace notes gets its own small digit', () {
      final layout = tabOf(Score.simple(notes: '{e4,g4}a4:q'));
      final small = layout.primitives
          .whereType<TextPrimitive>()
          .where((d) => d.size < TabLayoutEngine.fretSize)
          .toList();
      expect(small, hasLength(2));
      // They stack left of each other in reading order.
      small.sort((a, b) => a.position.x.compareTo(b.position.x));
      final principal = layout.primitives
          .whereType<TextPrimitive>()
          .firstWhere((d) => d.size == TabLayoutEngine.fretSize);
      expect(small.last.position.x, lessThan(principal.position.x));
    });
  });

  group('technique tail (Phase 6.4)', () {
    // One note 'g4' (id 'e0') to hang each technique on.
    Score onG4(Score Function(Score base) build) =>
        build(Score.simple(notes: 'g4:q'));

    int diagonals(ScoreLayout l) => l.primitives
        .whereType<LinePrimitive>()
        .where((x) => x.from.x != x.to.x && x.from.y != x.to.y)
        .length;

    List<String> texts(ScoreLayout l) =>
        l.primitives.whereType<TextPrimitive>().map((t) => t.text).toList();

    test('a bend-release contour labels the peak and draws no simple arrow', () {
      final plainCurves = tabOf(Score.simple(notes: 'g4:q'))
          .primitives
          .whereType<CurvePrimitive>()
          .length;
      final layout = tabOf(onG4((b) => Score(
            clef: b.clef,
            measures: b.measures,
            bends: const [
              Bend.curve('e0', [BendPoint(0.5, 1.0), BendPoint(1.0, 0.0)]),
            ],
          )));
      // The rise target is labelled 'full'.
      expect(texts(layout).where((t) => t == 'full'), hasLength(1));
      // The contour is a polyline of lines (two rise/fall segments + a
      // two-legged up-arrow), *not* the single-arrow CurvePrimitive.
      expect(diagonals(layout), 4);
      expect(layout.primitives.whereType<CurvePrimitive>().length, plainCurves);
    });

    test('a prebend starts already bent and still labels the target', () {
      final layout = tabOf(onG4((b) => Score(
            clef: b.clef,
            measures: b.measures,
            bends: const [
              Bend.curve('e0', [BendPoint(0.0, 1.0), BendPoint(1.0, 0.0)]),
            ],
          )));
      expect(texts(layout), contains('full'));
    });

    test('a whammy dive-and-return draws a down-arrow with its amount', () {
      final layout = tabOf(onG4((b) => Score(
            clef: b.clef,
            measures: b.measures,
            tremoloBars: const [
              TremoloBar.curve('e0', [BendPoint(0.5, -1.0), BendPoint(1.0, 0.0)]),
            ],
          )));
      // A down dive to -1 whole tone is labelled '-1'.
      expect(texts(layout), contains('-1'));
      // Two dive/return segments + the down-arrow's two legs.
      expect(diagonals(layout), 4);
    });

    test('each slide direction adds one diagonal at the fret', () {
      final plain = diagonals(tabOf(Score.simple(notes: 'g4:q')));
      for (final dir in SlideInOut.values) {
        final layout = tabOf(onG4((b) => Score(
              clef: b.clef,
              measures: b.measures,
              slideInOuts: [TabSlide('e0', dir)],
            )));
        expect(diagonals(layout), plain + 1, reason: '$dir');
      }
    });

    test('a downstroke draws a bracket and an upstroke draws a vee', () {
      LinePrimitive vees(ScoreLayout l) => l.primitives
          .whereType<LinePrimitive>()
          .firstWhere((x) => x.from.x != x.to.x && x.from.y != x.to.y);
      final down = tabOf(onG4((b) => Score(
            clef: b.clef,
            measures: b.measures,
            pickStrokes: const [PickStroke('e0')],
          )));
      final up = tabOf(onG4((b) => Score(
            clef: b.clef,
            measures: b.measures,
            pickStrokes: const [PickStroke('e0', up: true)],
          )));
      // The downstroke ⊓ has a horizontal top bar; the upstroke ∨ does not.
      final downBars = down.primitives
          .whereType<LinePrimitive>()
          .where((x) => x.from.y == x.to.y && x.from.x != x.to.x)
          .where((x) => x.from.y < 0); // above the top string line
      expect(downBars, isNotEmpty);
      // The upstroke is made of two diagonals (the vee), no horizontal bar.
      expect(vees(up), isNotNull);
      final upBars = up.primitives
          .whereType<LinePrimitive>()
          .where((x) => x.from.y == x.to.y && x.from.x != x.to.x)
          .where((x) => x.from.y < 0);
      expect(upBars, isEmpty);
    });

    test('an arpeggiated chord draws a wavy vertical line with an arrowhead',
        () {
      final plainCurves = tabOf(Score.simple(notes: 'e2+b2+e4:h'))
          .primitives
          .whereType<CurvePrimitive>()
          .length;
      final score = Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(
              pitches: const [
                Pitch(Step.e, octave: 2),
                Pitch(Step.b, octave: 2),
                Pitch(Step.e, octave: 4),
              ],
              duration: const NoteDuration(DurationBase.half),
              id: 'e0',
              arpeggio: Arpeggio.up,
            ),
          ]),
        ],
      );
      final layout = tabOf(score);
      // The wavy line adds several curve segments over the plain baseline.
      expect(layout.primitives.whereType<CurvePrimitive>().length,
          greaterThan(plainCurves + 1));
      // Arrow at the top (up-roll) means diagonal legs exist.
      expect(diagonals(layout), greaterThanOrEqualTo(2));
    });

    test('model equality distinguishes the new marks', () {
      expect(const Bend('e0'), isNot(const Bend.curve('e0', [BendPoint(1, 1)])));
      expect(const Bend.curve('e0', [BendPoint(0.5, 1)]),
          const Bend.curve('e0', [BendPoint(0.5, 1)]));
      expect(const TabSlide('e0', SlideInOut.inFromBelow),
          isNot(const TabSlide('e0', SlideInOut.outUpward)));
      expect(const PickStroke('e0'), isNot(const PickStroke('e0', up: true)));
    });

    test('transposedBy carries the new tab marks through', () {
      final score = Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(const Pitch(Step.g, octave: 4),
                const NoteDuration(DurationBase.quarter),
                id: 'e0'),
          ]),
        ],
        bends: const [
          Bend.curve('e0', [BendPoint(0.5, 1.0), BendPoint(1.0, 0.0)]),
        ],
        tremoloBars: const [
          TremoloBar.curve('e0', [BendPoint(0.5, -1.0), BendPoint(1.0, 0.0)]),
        ],
        slideInOuts: const [TabSlide('e0', SlideInOut.inFromBelow)],
        pickStrokes: const [PickStroke('e0', up: true)],
      );
      final up = score.transposedBy(const Interval(IntervalQuality.major, 2));
      expect(up.bends, score.bends);
      expect(up.tremoloBars, score.tremoloBars);
      expect(up.slideInOuts, score.slideInOuts);
      expect(up.pickStrokes, score.pickStrokes);
    });
  });

  group('Tier-3 tail (Phase 6.4)', () {
    Score onG4(Score Function(Score base) build) =>
        build(Score.simple(notes: 'g4:q'));

    List<String> texts(ScoreLayout l) =>
        l.primitives.whereType<TextPrimitive>().map((t) => t.text).toList();

    int diagonals(ScoreLayout l) => l.primitives
        .whereType<LinePrimitive>()
        .where((x) => x.from.x != x.to.x && x.from.y != x.to.y)
        .length;

    test('tapped/semi/feedback harmonics bracket the fret and label it', () {
      for (final (style, label) in [
        (TabNoteStyle.tappedHarmonic, 'T.H.'),
        (TabNoteStyle.semiHarmonic, 'S.H.'),
        (TabNoteStyle.feedbackHarmonic, 'Fbk.'),
      ]) {
        final layout = tabOf(onG4((b) => Score(
              clef: b.clef,
              measures: b.measures,
              tabNoteMarks: [TabNoteMark('e0', style)],
            )));
        expect(texts(layout), contains('<3>'), reason: '$style fret');
        expect(texts(layout), contains(label), reason: '$style label');
      }
    });

    test('a rasgueado pattern label is drawn above the strum', () {
      final layout = tabOf(onG4((b) => Score(
            clef: b.clef,
            measures: b.measures,
            rasgueados: const [Rasgueado('e0', pattern: 'p a m i')],
          )));
      expect(texts(layout), contains('p a m i'));
    });

    test('a golpe draws a cross (two diagonals)', () {
      final plain = diagonals(tabOf(Score.simple(notes: 'g4:q')));
      final layout = tabOf(onG4((b) => Score(
            clef: b.clef,
            measures: b.measures,
            golpes: const [Golpe('e0')],
          )));
      expect(diagonals(layout), plain + 2); // the "×"
    });

    test('a wah draws o (open) or + (closed)', () {
      final open = tabOf(onG4((b) => Score(
            clef: b.clef,
            measures: b.measures,
            wahs: const [Wah('e0', open: true)],
          )));
      final closed = tabOf(onG4((b) => Score(
            clef: b.clef,
            measures: b.measures,
            wahs: const [Wah('e0')],
          )));
      expect(texts(open), contains('o'));
      expect(texts(closed), contains('+'));
    });

    test('a fade draws a wedge; in and out open opposite ways', () {
      Score fade(bool out) => Score(
            clef: Clef.treble,
            measures: [
              Measure([
                NoteElement.note(const Pitch(Step.g, octave: 4),
                    const NoteDuration(DurationBase.quarter),
                    id: 'e0'),
                NoteElement.note(const Pitch(Step.a, octave: 4),
                    const NoteDuration(DurationBase.quarter),
                    id: 'e1'),
              ]),
            ],
            fades: [Fade('e0', 'e1', out: out)],
          );
      // The wedge is two lines meeting at an apex. For a fade-in the apex is on
      // the left (both lines start at the smaller x); for a fade-out, the right.
      double apexX(ScoreLayout l) {
        final wedge = l.primitives
            .whereType<LinePrimitive>()
            .where((x) => x.from.y != x.to.y && x.from.y < 0)
            .toList();
        expect(wedge, hasLength(2));
        // The shared point is the apex (equal endpoints on both lines).
        return wedge.first.from.x;
      }

      expect(apexX(tabOf(fade(false))),
          lessThan(apexX(tabOf(fade(true)))));
    });

    test('transposedBy carries golpes / wahs / fades through', () {
      final score = Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(const Pitch(Step.g, octave: 4),
                const NoteDuration(DurationBase.quarter),
                id: 'e0'),
          ]),
        ],
        golpes: const [Golpe('e0')],
        wahs: const [Wah('e0', open: true)],
        fades: const [Fade('e0', 'e0')],
      );
      final up = score.transposedBy(const Interval(IntervalQuality.major, 2));
      expect(up.golpes, score.golpes);
      expect(up.wahs, score.wahs);
      expect(up.fades, score.fades);
    });
  });
}
