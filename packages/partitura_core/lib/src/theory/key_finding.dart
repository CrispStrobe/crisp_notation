/// Key finding (Phase 4.3).
///
/// Krumhansl-Schmuckler key finding: correlate a pitch-class weight profile
/// (note counts or summed durations) against the 24 major/minor key profiles
/// and return the best match. [localKeys] runs it over a sliding window to
/// track modulation. Pure theory (no rendering).
library;

import 'dart:math';

import 'key.dart';
import 'pitch.dart';

// Krumhansl-Kessler tonic-relative key profiles (index 0 = the tonic).
const _major = [
  6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88 //
];
const _minor = [
  6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17 //
];

/// The best-matching [Key] for the 12-element pitch-class weight vector
/// [weights] (index 0 = C … 11 = B; note counts or summed durations). Correlates
/// [weights] against all 24 rotated major/minor profiles and returns the
/// highest. Null if the weights are empty or all zero.
Key? findKey(List<double> weights) {
  assert(weights.length == 12, 'weights must have 12 entries (C..B)');
  if (weights.fold<double>(0, (s, w) => s + w) <= 0) return null;
  var bestR = -2.0;
  var bestTonic = 0;
  var bestMajor = true;
  for (var t = 0; t < 12; t++) {
    for (final major in const [true, false]) {
      final profile = major ? _major : _minor;
      final rotated = [
        for (var p = 0; p < 12; p++) profile[(p - t + 12) % 12],
      ];
      final r = _correlation(weights, rotated);
      if (r > bestR) {
        bestR = r;
        bestTonic = t;
        bestMajor = major;
      }
    }
  }
  final tonic = _spellTonic(bestTonic, bestMajor);
  return bestMajor ? Key.major(tonic) : Key.minor(tonic);
}

/// The best-matching [Key] for [pitches], each weighted by the matching entry
/// in [durations] (default 1 per note). Convenience over [findKey].
Key? keyOf(List<Pitch> pitches, {List<double>? durations}) {
  final weights = List<double>.filled(12, 0);
  for (var i = 0; i < pitches.length; i++) {
    weights[pitches[i].midiNumber % 12] +=
        durations == null ? 1.0 : durations[i];
  }
  return findKey(weights);
}

/// The local key over each sliding [window] of [pitches] (advancing by [step])
/// — a simple modulation tracker. Empty when there are fewer than [window]
/// pitches.
List<Key?> localKeys(List<Pitch> pitches, {int window = 8, int step = 1}) {
  final keys = <Key?>[];
  for (var i = 0; i + window <= pitches.length; i += step) {
    keys.add(keyOf(pitches.sublist(i, i + window)));
  }
  return keys;
}

/// Pearson correlation between two equal-length vectors (0 if either is flat).
double _correlation(List<double> x, List<double> y) {
  final n = x.length;
  var sx = 0.0, sy = 0.0;
  for (var i = 0; i < n; i++) {
    sx += x[i];
    sy += y[i];
  }
  final mx = sx / n, my = sy / n;
  var num = 0.0, dx = 0.0, dy = 0.0;
  for (var i = 0; i < n; i++) {
    final a = x[i] - mx, b = y[i] - my;
    num += a * b;
    dx += a * a;
    dy += b * b;
  }
  final denom = sqrt(dx * dy);
  return denom == 0 ? 0.0 : num / denom;
}

/// A musically sensible spelling of tonic pitch class [pc] (flats for the usual
/// flat keys; sharps where those are conventional, e.g. C♯/G♯ minor, F♯).
Pitch _spellTonic(int pc, bool major) {
  const majorTable = [
    (Step.c, 0), (Step.d, -1), (Step.d, 0), (Step.e, -1), //
    (Step.e, 0), (Step.f, 0), (Step.f, 1), (Step.g, 0),
    (Step.a, -1), (Step.a, 0), (Step.b, -1), (Step.b, 0),
  ];
  const minorTable = [
    (Step.c, 0), (Step.c, 1), (Step.d, 0), (Step.e, -1), //
    (Step.e, 0), (Step.f, 0), (Step.f, 1), (Step.g, 0),
    (Step.g, 1), (Step.a, 0), (Step.b, -1), (Step.b, 0),
  ];
  final (step, alter) = (major ? majorTable : minorTable)[pc];
  return Pitch(step, alter: alter, octave: 4);
}
