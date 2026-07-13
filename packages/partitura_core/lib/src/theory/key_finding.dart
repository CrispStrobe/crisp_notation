/// Key finding: estimate the most likely major or minor key of a passage from
/// its pitch-class content, using the Krumhansl–Schmuckler algorithm — a
/// Pearson correlation of the passage's pitch-class distribution against the
/// twenty-four rotated Krumhansl–Kessler tonal-hierarchy profiles.
library;

import 'dart:math' as math;

import 'key.dart';
import 'pitch.dart';

/// The Krumhansl–Kessler major-key profile (tonal hierarchy), tonic first.
const List<double> _majorProfile = [
  6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88 //
];

/// The Krumhansl–Kessler minor-key profile, tonic first.
const List<double> _minorProfile = [
  6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17 //
];

// Conventional tonic spellings per pitch class, giving standard key
// signatures (e.g. D♭ major not C♯ major; C♯ minor not D♭ minor).
const List<(Step, int)> _majorTonic = [
  (Step.c, 0), (Step.d, -1), (Step.d, 0), (Step.e, -1), (Step.e, 0), //
  (Step.f, 0), (Step.f, 1), (Step.g, 0), (Step.a, -1), (Step.a, 0), //
  (Step.b, -1), (Step.b, 0),
];
const List<(Step, int)> _minorTonic = [
  (Step.c, 0), (Step.c, 1), (Step.d, 0), (Step.e, -1), (Step.e, 0), //
  (Step.f, 0), (Step.f, 1), (Step.g, 0), (Step.g, 1), (Step.a, 0), //
  (Step.b, -1), (Step.b, 0),
];

Key _keyFor(int tonicPc, bool isMajor) {
  final (step, alter) = (isMajor ? _majorTonic : _minorTonic)[tonicPc % 12];
  final tonic = Pitch(step, alter: alter);
  return isMajor ? Key.major(tonic) : Key.minor(tonic);
}

/// A candidate key with its Pearson correlation against the passage.
class KeyEstimate {
  /// The estimated key.
  final Key key;

  /// Pearson correlation of the passage with this key's rotated profile
  /// (−1…1; higher is a better fit).
  final double correlation;

  /// Creates a key estimate.
  const KeyEstimate(this.key, this.correlation);

  @override
  String toString() => 'KeyEstimate($key, r=${correlation.toStringAsFixed(3)})';
}

double _pearson(List<double> x, List<double> y) {
  final n = x.length;
  var sx = 0.0, sy = 0.0;
  for (var i = 0; i < n; i++) {
    sx += x[i];
    sy += y[i];
  }
  final mx = sx / n, my = sy / n;
  var num = 0.0, dx2 = 0.0, dy2 = 0.0;
  for (var i = 0; i < n; i++) {
    final ax = x[i] - mx, ay = y[i] - my;
    num += ax * ay;
    dx2 += ax * ax;
    dy2 += ay * ay;
  }
  final den = dx2 * dy2;
  return den == 0 ? 0.0 : num / math.sqrt(den);
}

/// All twenty-four keys ranked by how well [pitchClassWeights] (a length-12
/// distribution, index 0 = C … 11 = B; any non-negative units — note counts or
/// summed durations) correlate with their profiles, best first.
///
/// Throws [ArgumentError] if the list is not length 12 or is entirely zero.
List<KeyEstimate> rankKeys(List<num> pitchClassWeights) {
  if (pitchClassWeights.length != 12) {
    throw ArgumentError.value(pitchClassWeights, 'pitchClassWeights',
        'must have exactly 12 entries (one per pitch class)');
  }
  final x = [for (final w in pitchClassWeights) w.toDouble()];
  if (x.every((w) => w == 0)) {
    throw ArgumentError.value(
        pitchClassWeights, 'pitchClassWeights', 'must not be all zero');
  }

  final estimates = <KeyEstimate>[];
  for (var tonic = 0; tonic < 12; tonic++) {
    for (final isMajor in const [true, false]) {
      final profile = isMajor ? _majorProfile : _minorProfile;
      final rotated = [
        for (var pc = 0; pc < 12; pc++) profile[(pc - tonic) % 12]
      ];
      estimates.add(KeyEstimate(_keyFor(tonic, isMajor), _pearson(x, rotated)));
    }
  }
  estimates.sort((a, b) => b.correlation.compareTo(a.correlation));
  return estimates;
}

/// The single most likely key of [pitchClassWeights] (the top of [rankKeys]).
KeyEstimate estimateKey(List<num> pitchClassWeights) =>
    rankKeys(pitchClassWeights).first;

/// The most likely key of a bare list of [pitches] (each counted once, octave
/// and spelling ignored). Throws [ArgumentError] on an empty list.
KeyEstimate estimateKeyFromPitches(Iterable<Pitch> pitches) {
  final weights = List<num>.filled(12, 0);
  var any = false;
  for (final p in pitches) {
    weights[p.midiNumber % 12] += 1;
    any = true;
  }
  if (!any) {
    throw ArgumentError.value(pitches, 'pitches', 'must not be empty');
  }
  return estimateKey(weights);
}
