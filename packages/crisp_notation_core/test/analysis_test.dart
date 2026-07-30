import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Parses a note like `c4`, `f#4`, `eb5`.
Pitch note(String s) {
  final m = RegExp(r'^([a-g])([#b]*)(-?\d+)$').firstMatch(s)!;
  final step = Step.values.firstWhere((st) => st.name == m[1]);
  final acc = m[2]!;
  final alter =
      acc.isEmpty ? 0 : (acc.startsWith('#') ? acc.length : -acc.length);
  return Pitch(step, alter: alter, octave: int.parse(m[3]!));
}

const _whole = NoteDuration(DurationBase.whole);
const _quarter = NoteDuration(DurationBase.quarter);

/// A score of a single-note melody per measure (quarters).
Score melody(List<List<String>> bars) => Score(
      clef: Clef.treble,
      measures: [
        for (final bar in bars)
          Measure([
            for (final n in bar)
              NoteElement(pitches: [note(n)], duration: _quarter),
          ]),
      ],
    );

/// A score of one block chord per measure.
Score chords(List<List<String>> perMeasure) => Score(
      clef: Clef.treble,
      measures: [
        for (final ch in perMeasure)
          Measure([
            NoteElement(
                pitches: [for (final n in ch) note(n)], duration: _whole),
          ]),
      ],
    );

void main() {
  _harmonicWeightingTests();
  group('functionOf', () {
    Key cMajor() => const Key.major(Pitch(Step.c));
    RomanNumeral rn(List<String> pitches) =>
        romanNumeralOf([for (final p in pitches) note(p)], cMajor())!;

    test('classifies tonic / subdominant / dominant', () {
      expect(functionOf(rn(['c4', 'e4', 'g4'])), HarmonicFunction.tonic); // I
      expect(
        functionOf(rn(['f4', 'a4', 'c5'])),
        HarmonicFunction.subdominant,
      ); // IV
      expect(
        functionOf(rn(['g4', 'b4', 'd5'])),
        HarmonicFunction.dominant,
      ); // V
      expect(functionOf(rn(['a4', 'c5', 'e5'])), HarmonicFunction.tonic); // vi
      expect(
        functionOf(rn(['d4', 'f4', 'a4'])),
        HarmonicFunction.subdominant,
      ); // ii
    });
  });

  group('analyze', () {
    // Short chord-only fixtures are key-ambiguous (G–B–D reads as G major on its
    // own), so pin the key — the app passes the score's key signature likewise.
    const cMaj = Key.major(Pitch(Step.c));

    test('reads I–IV–V–I with functions and an authentic cadence', () {
      final a = analyze(
        chords([
          ['c4', 'e4', 'g4'],
          ['f4', 'a4', 'c5'],
          ['g4', 'b4', 'd5'],
          ['c4', 'e4', 'g4'],
        ]),
      );

      expect(a.key.tonic.step, Step.c);
      expect(a.key.isMajor, isTrue);
      expect(a.segments.length, 4);
      expect(
        [for (final s in a.segments) s.roman!.symbol],
        ['I', 'IV', 'V', 'I'],
      );
      expect(
        [for (final s in a.segments) s.function],
        [
          HarmonicFunction.tonic,
          HarmonicFunction.subdominant,
          HarmonicFunction.dominant,
          HarmonicFunction.tonic,
        ],
      );
      // V (segment 2) → I (segment 3) is an authentic cadence.
      expect(a.cadences.length, 1);
      expect(a.cadences.single.type, CadenceType.authentic);
      expect(a.cadences.single.segmentIndex, 3);
    });

    test('spots a plagal cadence (IV–I)', () {
      final a = analyze(
        chords([
          ['c4', 'e4', 'g4'],
          ['f4', 'a4', 'c5'],
          ['c4', 'e4', 'g4'],
        ]),
        key: cMaj,
      );
      expect(a.cadences.map((c) => c.type), contains(CadenceType.plagal));
    });

    test('spots a deceptive cadence (V–vi)', () {
      final a = analyze(
        chords([
          ['g4', 'b4', 'd5'], // V
          ['a4', 'c5', 'e5'], // vi
        ]),
        key: cMaj,
      );
      expect(a.cadences.map((c) => c.type), contains(CadenceType.deceptive));
    });

    test('spots a half cadence (ends on V)', () {
      final a = analyze(
        chords([
          ['c4', 'e4', 'g4'],
          ['g4', 'b4', 'd5'], // V — the phrase hangs open
        ]),
        key: cMaj,
      );
      expect(a.cadences.map((c) => c.type), contains(CadenceType.half));
    });

    test('flags a non-chord tone over a clean triad', () {
      // C major triad with an F# that belongs to no C chord.
      final a = analyze(
        Score(
          clef: Clef.treble,
          measures: [
            Measure([
              NoteElement(
                pitches: [note('c4'), note('e4'), note('g4'), note('f#4')],
                duration: _whole,
              ),
            ]),
          ],
        ),
      );
      expect(a.segments.single.chord, isNotNull);
      expect(a.segments.single.chord!.root.step, Step.c);
      expect(
        a.segments.single.nonChordTones.map((p) => p.step),
        contains(Step.f),
      );
    });

    test('reads an implied chord from an arpeggiated (melodic) bar', () {
      final a = analyze(
        Score(
          clef: Clef.treble,
          measures: [
            Measure([
              for (final n in ['c4', 'e4', 'g4', 'c5'])
                NoteElement(pitches: [note(n)], duration: _quarter),
            ]),
          ],
        ),
      );
      expect(a.segments, isNotEmpty);
      expect(a.segments.first.chord, isNotNull);
      expect(a.segments.first.roman!.symbol, 'I');
    });

    test('carries the note element ids of each segment', () {
      final a = analyze(
        Score(
          clef: Clef.treble,
          measures: [
            Measure([
              NoteElement(
                pitches: [note('c4'), note('e4'), note('g4')],
                duration: _whole,
                id: 'chord1',
              ),
            ]),
          ],
        ),
      );
      expect(a.segments.single.elementIds, contains('chord1'));
    });

    test('merges a repeated chord into one segment', () {
      final a = analyze(
        chords([
          ['c4', 'e4', 'g4'],
          ['c4', 'e4', 'g4'],
          ['g4', 'b4', 'd5'],
        ]),
        key: cMaj,
      );
      // The two identical tonic bars collapse to a single I segment.
      expect(a.segments.length, 2);
      expect(a.segments[0].roman!.symbol, 'I');
      expect(a.segments[1].roman!.symbol, 'V');
    });
  });

  group('detectForm', () {
    test('reads A–B–A from repeated bars', () {
      final f = detectForm(
        melody([
          ['c4', 'e4', 'g4', 'c5'],
          ['g4', 'f4', 'e4', 'd4'],
          ['c4', 'e4', 'g4', 'c5'],
        ]),
      );
      expect(f.map((s) => s.label).toList(), ['A', 'B', 'A']);
      expect(f[2].startMeasure, 2);
    });

    test('is transpose-invariant (a phrase returning higher is still A)', () {
      final f = detectForm(
        melody([
          ['c4', 'e4', 'g4', 'c5'], // A
          ['g4', 'f4', 'e4', 'd4'], // B
          ['d4', 'f#4', 'a4', 'd5'], // A up a step — same contour + rhythm
        ]),
      );
      expect(f.map((s) => s.label).toList(), ['A', 'B', 'A']);
    });

    test('merges consecutive identical bars into one section', () {
      final f = detectForm(
        melody([
          ['c4', 'e4', 'g4', 'c5'],
          ['c4', 'e4', 'g4', 'c5'],
          ['g4', 'f4', 'e4', 'd4'],
        ]),
      );
      expect(f.length, 2);
      expect(f[0].label, 'A');
      expect(f[0].startMeasure, 0);
      expect(f[0].endMeasure, 1);
      expect(f[1].label, 'B');
    });

    test('groups repeated multi-bar phrases into sections (2-bar A–B–A)', () {
      final f = detectForm(
        melody([
          ['c4', 'e4', 'g4', 'c5'], // ┐ phrase A
          ['g4', 'f4', 'e4', 'd4'], // ┘
          ['e4', 'g4', 'c5', 'e5'], // ┐ phrase B
          ['d4', 'e4', 'f4', 'g4'], // ┘
          ['c4', 'e4', 'g4', 'c5'], // ┐ phrase A again
          ['g4', 'f4', 'e4', 'd4'], // ┘
        ]),
      );
      expect(f.map((s) => s.label).toList(), ['A', 'B', 'A']);
      expect(f[0].startMeasure, 0);
      expect(f[0].endMeasure, 1); // a 2-bar phrase, not a single bar
      expect(f[2].startMeasure, 4);
    });
  });
}

void _harmonicWeightingTests() {
  group('HarmonicWeighting.durationWeightedPerBar', () {
    // Measured on real annotated material: holding the chord identifier fixed
    // and changing only WHICH notes it sees moved maj/min agreement over a
    // 32-point range. A passing note sounding for a sixteenth should not outvote
    // a chord tone held for a half — and a per-slice reading gives them equal
    // say. These pin that difference.
    const half = NoteDuration(DurationBase.half);
    const sixteenth = NoteDuration(DurationBase.sixteenth);

    Score bar(List<(List<String>, NoteDuration)> events) => Score(
          clef: Clef.treble,
          measures: [
            Measure([
              for (final (names, dur) in events)
                NoteElement(
                  pitches: [for (final n in names) note(n)],
                  duration: dur,
                ),
            ]),
          ],
        );

    test('a held triad outvotes the passing notes decorating it', () {
      final score = bar([
        (['c4', 'e4', 'g4'], half),
        (['c#4'], sixteenth),
        (['f#4'], sixteenth),
        (['a#4'], sixteenth),
      ]);
      final weighted = analyze(
        score,
        weighting: HarmonicWeighting.durationWeightedPerBar,
      );
      expect(weighted.segments, hasLength(1));
      expect(weighted.segments.single.chord?.symbol, 'C');
    });

    test('one segment per bar — which is what a lead sheet wants', () {
      final score = chords([
        ['c4', 'e4', 'g4'],
        ['g4', 'b4', 'd5'],
      ]);
      final weighted = analyze(
        score,
        weighting: HarmonicWeighting.durationWeightedPerBar,
      );
      expect(weighted.segments, hasLength(2));
      expect(weighted.segments.first.chord?.symbol, 'C');
      expect(weighted.segments.last.chord?.symbol, 'G');
    });

    test('the default is unchanged — existing callers see identical output',
        () {
      final score = chords([
        ['c4', 'e4', 'g4'],
        ['d4', 'f4', 'a4'],
      ]);
      final a = analyze(score);
      final b = analyze(score, weighting: HarmonicWeighting.perSlice);
      expect(a.segments.length, b.segments.length);
      for (var i = 0; i < a.segments.length; i++) {
        expect(a.segments[i].chord?.symbol, b.segments[i].chord?.symbol);
      }
    });

    test('is deterministic when pitch classes tie on duration', () {
      final score = melody([
        ['c4', 'e4', 'g4', 'b4'],
      ]);
      final first = analyze(
        score,
        weighting: HarmonicWeighting.durationWeightedPerBar,
      ).segments.single.chord?.symbol;
      for (var i = 0; i < 5; i++) {
        expect(
          analyze(
            score,
            weighting: HarmonicWeighting.durationWeightedPerBar,
          ).segments.single.chord?.symbol,
          first,
        );
      }
    });

    test('an empty bar yields no segment rather than throwing', () {
      final score = Score(clef: Clef.treble, measures: [Measure([])]);
      expect(
        analyze(score, weighting: HarmonicWeighting.durationWeightedPerBar)
            .segments,
        isEmpty,
      );
    });
  });
}
