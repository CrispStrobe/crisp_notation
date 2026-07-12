/// Chord identification — the inverse of [Triad]: name a set of pitches.
///
/// Given the notes of a chord, [identifyChord] finds the root, quality and
/// inversion by matching the pitch-class set against the common triad, seventh
/// and sixth templates, and spells the result from the input pitches. Pure
/// theory (no rendering); pairs with the pedagogy core.
library;

import 'pitch.dart';

/// The chord qualities [identifyChord] recognizes.
enum ChordType {
  /// Major triad.
  major('', {0, 4, 7}),

  /// Minor triad.
  minor('m', {0, 3, 7}),

  /// Diminished triad.
  diminished('dim', {0, 3, 6}),

  /// Augmented triad.
  augmented('aug', {0, 4, 8}),

  /// Suspended second.
  sus2('sus2', {0, 2, 7}),

  /// Suspended fourth.
  sus4('sus4', {0, 5, 7}),

  /// Dominant seventh.
  dominantSeventh('7', {0, 4, 7, 10}),

  /// Major seventh.
  majorSeventh('maj7', {0, 4, 7, 11}),

  /// Minor seventh.
  minorSeventh('m7', {0, 3, 7, 10}),

  /// Diminished seventh.
  diminishedSeventh('dim7', {0, 3, 6, 9}),

  /// Half-diminished seventh (m7♭5).
  halfDiminishedSeventh('m7b5', {0, 3, 6, 10}),

  /// Minor–major seventh.
  minorMajorSeventh('m(maj7)', {0, 3, 7, 11}),

  /// Augmented seventh (7♯5).
  augmentedSeventh('7#5', {0, 4, 8, 10}),

  /// Major sixth.
  majorSixth('6', {0, 4, 7, 9}),

  /// Minor sixth.
  minorSixth('m6', {0, 3, 7, 9});

  const ChordType(this.suffix, this.intervals);

  /// The chord-symbol suffix after the root (e.g. `m7`, `maj7`, `sus4`).
  final String suffix;

  /// Semitone intervals above the root, in stacked-thirds order.
  final Set<int> intervals;
}

/// A named chord: [root]/[type]/[inversion], spelled from the input, with the
/// lowest note as [bass].
class ChordAnalysis {
  /// The chord root (spelled from an input pitch of the root's pitch class).
  final Pitch root;

  /// The recognized quality.
  final ChordType type;

  /// Inversion: 0 root position, 1 = third in the bass, 2 = fifth, …
  final int inversion;

  /// The lowest sounding pitch.
  final Pitch bass;

  /// Creates a chord analysis result.
  const ChordAnalysis(this.root, this.type, this.inversion, this.bass);

  /// The chord symbol, e.g. `C`, `Am7`, `G7`, `F#dim`, or a slash chord for an
  /// inversion, `C/E`.
  String get symbol {
    final base = '${_name(root)}${type.suffix}';
    return inversion == 0 ? base : '$base/${_name(bass)}';
  }

  @override
  bool operator ==(Object other) =>
      other is ChordAnalysis &&
      other.root == root &&
      other.type == type &&
      other.inversion == inversion &&
      other.bass == bass;

  @override
  int get hashCode => Object.hash(root, type, inversion, bass);

  @override
  String toString() => 'ChordAnalysis($symbol)';
}

/// Identifies the chord formed by [pitches], or null if no template matches
/// (fewer than three distinct pitch classes, or an unrecognized sonority).
///
/// When two roots both fit (e.g. C6 vs Am7 for C–E–G–A), the reading with the
/// **bass** as the root wins, so voicing drives the spelling.
ChordAnalysis? identifyChord(List<Pitch> pitches) {
  if (pitches.length < 3) return null;
  final bass = pitches.reduce((a, b) => a.midiNumber <= b.midiNumber ? a : b);
  final pcs = {for (final p in pitches) p.midiNumber % 12};
  if (pcs.length < 3) return null;
  final bassPc = bass.midiNumber % 12;

  ChordAnalysis? match(int rootPc) {
    final intervals = {for (final pc in pcs) (pc - rootPc + 12) % 12};
    for (final type in ChordType.values) {
      if (_setEquals(intervals, type.intervals)) {
        final root = _spell(pitches, rootPc);
        final bassInterval = (bassPc - rootPc + 12) % 12;
        final order = type.intervals.toList()..sort();
        final inversion =
            order.indexOf(bassInterval).clamp(0, order.length - 1);
        return ChordAnalysis(root, type, inversion, bass);
      }
    }
    return null;
  }

  // Prefer the interpretation rooted on the bass (root position).
  final rooted = match(bassPc);
  if (rooted != null) return rooted;
  for (final pc in pcs) {
    if (pc == bassPc) continue;
    final found = match(pc);
    if (found != null) return found;
  }
  return null;
}

/// The chord symbol for [pitches] (shorthand for `identifyChord(...)?.symbol`).
String? chordSymbolFor(List<Pitch> pitches) => identifyChord(pitches)?.symbol;

bool _setEquals(Set<int> a, Set<int> b) =>
    a.length == b.length && a.containsAll(b);

/// A pitch of pitch class [pc] taken from [pitches] (to keep its spelling), or
/// a default sharp spelling if none is present.
Pitch _spell(List<Pitch> pitches, int pc) {
  for (final p in pitches) {
    if (p.midiNumber % 12 == pc) return p;
  }
  const table = [
    (Step.c, 0), (Step.c, 1), (Step.d, 0), (Step.d, 1), //
    (Step.e, 0), (Step.f, 0), (Step.f, 1), (Step.g, 0),
    (Step.g, 1), (Step.a, 0), (Step.a, 1), (Step.b, 0),
  ];
  final (step, alter) = table[pc % 12];
  return Pitch(step, alter: alter, octave: 4);
}

String _name(Pitch pitch) {
  final letter = pitch.step.name.toUpperCase();
  final accidental = switch (pitch.alter) {
    0 => '',
    2 => '##',
    -2 => 'bb',
    _ => pitch.alter > 0 ? '#' * pitch.alter : 'b' * -pitch.alter,
  };
  return '$letter$accidental';
}
