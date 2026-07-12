/// Keys and functional harmony (Tonika, Subdominante, Dominante).
library;

import 'interval.dart';
import 'key_signature.dart';
import 'pitch.dart';
import 'triad.dart';

/// The three primary harmonic functions of functional harmony — the
/// pedagogy target for cadence and accompaniment games.
enum HarmonicFunction {
  /// The home chord, built on scale degree 1 (Tonika).
  tonic,

  /// Built on scale degree 4 (Subdominante).
  subdominant,

  /// Built on scale degree 5 (Dominante).
  dominant,
}

/// A major or minor key: a [tonic] pitch plus mode.
class Key {
  /// The key's tonic. Its octave anchors the pitches of triads built with
  /// [triadFor].
  final Pitch tonic;

  /// True for major (Dur), false for minor (Moll).
  final bool isMajor;

  /// Creates a major key on [tonic].
  const Key.major(this.tonic) : isMajor = true;

  /// Creates a minor key on [tonic].
  const Key.minor(this.tonic) : isMajor = false;

  /// Position of each step's major key on the circle of fifths (C = 0).
  static const List<int> _majorFifths = [0, 2, 4, -1, 1, 3, 5];

  /// The key signature: C major/A minor = 0, G major/E minor = +1,
  /// F major/D minor = -1, …
  ///
  /// Throws an [ArgumentError] for keys with no standard signature
  /// (more than 7 sharps/flats), e.g. G♯ major.
  KeySignature get signature {
    final fifths =
        _majorFifths[tonic.step.index] + 7 * tonic.alter - (isMajor ? 0 : 3);
    if (fifths < -7 || fifths > 7) {
      throw ArgumentError(
        '$this has no standard key signature ($fifths fifths)',
      );
    }
    return KeySignature(fifths);
  }

  /// The primary triad for harmonic function [f] in this key.
  ///
  /// In major, all three are major triads (C major: T = C, S = F, D = G).
  /// In minor, tonic and subdominant are minor; the dominant is a **major**
  /// triad, following the harmonic-minor convention of functional harmony
  /// (A minor: t = Am, s = Dm, D = E major).
  Triad triadFor(HarmonicFunction f) {
    final minorQuality = isMajor ? ChordQuality.major : ChordQuality.minor;
    return switch (f) {
      HarmonicFunction.tonic => Triad(tonic, minorQuality),
      HarmonicFunction.subdominant =>
        Triad(tonic.transposeBy(Interval.perfectFourth), minorQuality),
      HarmonicFunction.dominant =>
        Triad(tonic.transposeBy(Interval.perfectFifth), ChordQuality.major),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is Key && other.tonic == tonic && other.isMajor == isMajor;

  @override
  int get hashCode => Object.hash(tonic, isMajor);

  @override
  String toString() => 'Key($tonic ${isMajor ? 'major' : 'minor'})';
}
