/// String tunings for fretted-instrument tablature.
library;

import 'pitch.dart';

/// The open-string pitches of a fretted instrument, plus fret assignment.
///
/// [strings] lists the open pitches from the **top tab line to the bottom** —
/// i.e. string 1 (the highest-sounding string) first. Standard six-string
/// guitar is `[E4, B3, G3, D3, A2, E2]`.
class Tuning {
  /// Open pitches, top tab line (string 1) first.
  final List<Pitch> strings;

  /// A human label (e.g. "Drop D"), or null.
  final String? name;

  /// Creates a tuning from its open-string [strings] (top line first).
  const Tuning(this.strings, {this.name});

  /// Number of strings / tab lines.
  int get stringCount => strings.length;

  /// Standard six-string guitar tuning (E A D G B E), top line = high E4.
  static final Tuning standardGuitar = Tuning(
    [
      Pitch.parse('e4'),
      Pitch.parse('b3'),
      Pitch.parse('g3'),
      Pitch.parse('d3'),
      Pitch.parse('a2'),
      Pitch.parse('e2'),
    ],
    name: 'Standard',
  );

  /// Drop-D guitar tuning (low E → D).
  static final Tuning dropDGuitar = Tuning(
    [
      Pitch.parse('e4'),
      Pitch.parse('b3'),
      Pitch.parse('g3'),
      Pitch.parse('d3'),
      Pitch.parse('a2'),
      Pitch.parse('d2'),
    ],
    name: 'Drop D',
  );

  /// Standard four-string bass tuning (E A D G), top line = G2.
  static final Tuning standardBass = Tuning(
    [
      Pitch.parse('g2'),
      Pitch.parse('d2'),
      Pitch.parse('a1'),
      Pitch.parse('e1'),
    ],
    name: 'Bass',
  );

  /// The lowest-fret (string, fret) that plays [pitch] on this tuning, or
  /// null if it is unreachable within [maxFret]. String index 0 = top line.
  (int string, int fret)? fretFor(Pitch pitch, {int maxFret = 24}) {
    (int, int)? best;
    for (var i = 0; i < strings.length; i++) {
      final fret = pitch.midiNumber - strings[i].midiNumber;
      if (fret < 0 || fret > maxFret) continue;
      if (best == null || fret < best.$2) best = (i, fret);
    }
    return best;
  }

  @override
  bool operator ==(Object other) =>
      other is Tuning &&
      other.name == name &&
      _listEquals(other.strings, strings);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(strings));

  @override
  String toString() =>
      'Tuning(${name ?? '?'}: ${strings.map((p) => p.toString()).join(' ')})';

  static bool _listEquals(List<Pitch> a, List<Pitch> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
