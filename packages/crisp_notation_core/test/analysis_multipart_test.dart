import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

Pitch n(String s) {
  final m = RegExp(r'^([a-g])([#b]*)(-?\d+)$').firstMatch(s)!;
  final acc = m[2]!;
  return Pitch(
    Step.values.firstWhere((st) => st.name == m[1]),
    alter: acc.isEmpty ? 0 : (acc.startsWith('#') ? acc.length : -acc.length),
    octave: int.parse(m[3]!),
  );
}

const _whole = NoteDuration(DurationBase.whole);
const _half = NoteDuration(DurationBase.half);

/// One single-line part per voice — the shape a real multi-staff import gives.
Score line(List<List<String>> bars, NoteDuration d) => Score(
      clef: Clef.treble,
      measures: [
        for (final bar in bars)
          Measure([
            for (final p in bar) NoteElement(pitches: [n(p)], duration: d),
          ]),
      ],
    );

void main() {
  group('analyzeParts', () {
    test('slices ACROSS parts, so four lines make one chord', () {
      // Four independent single-note lines that together spell C major then G7.
      // NB the second chord needs a real seventh: C-G-E-C then B-F-D-G. An
      // earlier version wrote B-G-D-G, which is a plain G triad — the analyser
      // was right and the fixture was wrong.
      final score = MultiPartScore([
        line([
          ['c5', 'b4']
        ], _half),
        line([
          ['g4', 'f4']
        ], _half),
        line([
          ['e4', 'd4']
        ], _half),
        line([
          ['c3', 'g2']
        ], _half),
      ]);
      final r = analyzeParts(score);
      expect(
        r.segments.where((s) => s.chord != null).map((s) => s.chord!.symbol),
        ['C', 'G7'],
      );
    });

    test('a single part behaves exactly like analyze()', () {
      final one = line([
        ['c4', 'd4', 'e4', 'f4']
      ], NoteDuration(DurationBase.quarter));
      final viaParts = analyzeParts(MultiPartScore([one]));
      final direct = analyze(one);
      expect(viaParts.segments.length, direct.segments.length);
      expect(viaParts.key.toString(), direct.key.toString());
    });

    test('the key is read from EVERY part, not just the top line', () {
      // The top line alone is ambiguous; the bass settles it.
      final score = MultiPartScore([
        line([
          ['e4']
        ], _whole),
        line([
          ['a2']
        ], _whole),
      ]);
      expect(analyzeParts(score).key, isNotNull);
    });

    test('auto never has to guess here — several parts ARE polyphony', () {
      final score = MultiPartScore([
        line([
          ['c5']
        ], _whole),
        line([
          ['e4']
        ], _whole),
        line([
          ['g3']
        ], _whole),
      ]);
      final auto = analyzeParts(score, weighting: HarmonicWeighting.auto);
      final slice = analyzeParts(score, weighting: HarmonicWeighting.perSlice);
      expect(auto.segments.length, slice.segments.length);
      // C/G, not C: the lowest part is G3, so this is second inversion — which
      // is exactly the information that collapsing staves into one Score
      // destroys.
      expect(auto.segments.single.chord?.symbol, 'C/G');
    });

    test('parts of unequal length do not throw', () {
      final score = MultiPartScore([
        line([
          ['c4'],
          ['d4']
        ], _whole),
        line([
          ['e4']
        ], _whole),
      ]);
      expect(analyzeParts(score).segments, isNotEmpty);
    });
  });
}
