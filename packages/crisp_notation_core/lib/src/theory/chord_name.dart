/// Parsing a written chord NAME ("Ebmaj7", "C#m7b5", "G/B") into the model.
///
/// Every other route into [ChordSymbol] is structural — MusicXML reads
/// `<harmony>` element by element, MuseScore its own XML, LilyPond its colon
/// syntax (`c:maj7`). None of them reads the name a human writes, which is the
/// only thing ABC, lead sheets and chord charts give you.
library;

import '../model/element.dart';
import 'pitch.dart';

/// The result of reading a chord name.
typedef ParsedChordName = ({Pitch root, ChordSymbolKind kind, Pitch? bass});

/// Reads a chord name, or null if [text] is not one.
///
/// **Rejecting non-chords matters more than accepting exotic ones.** This runs
/// over free text — ABC quotes chord symbols and prose annotations with the
/// same delimiter — so "Fine", "D.C. al Coda" and "Allegro" must come back
/// null rather than becoming F, D and A chords. The rule that gets that right
/// is strict: after the root, the ENTIRE remainder must be a suffix the model
/// knows. Anything left over means it was never a chord.
ParsedChordName? parseChordName(String text) {
  final s = text.trim();
  if (s.isEmpty) return null;

  // A slash bass: "G/B". Only ONE slash, and the tail must be a bare note.
  final slash = s.indexOf('/');
  Pitch? bass;
  var head = s;
  if (slash >= 0) {
    final tail = s.substring(slash + 1).trim();
    if (tail.contains('/')) return null;
    bass = _rootOf(tail)?.$1;
    // A slash with an unreadable tail is not a chord — "and/or" must not become
    // an A chord.
    if (bass == null || _rootOf(tail)!.$2.isNotEmpty) return null;
    head = s.substring(0, slash).trim();
  }

  final parsedRoot = _rootOf(head);
  if (parsedRoot == null) return null;
  final (root, rest) = parsedRoot;

  final kind = _kindOf(rest);
  if (kind == null) return null;
  return (root: root, kind: kind, bass: bass);
}

/// Every written spelling we accept, mapped to the kind it means.
///
/// The model's own `suffix` is the canonical one; these are the alternates
/// real chord charts use. Deliberately absent: bare `4`/`2` for sus (they
/// collide with the part labels "A4"/"B2" that ABC files are full of) and
/// anything needing a kind the model does not have (`5` power chords, 9ths
/// beyond dominant, 11ths, 13ths) — inventing a near-miss kind would be worse
/// than leaving the text alone.
final Map<String, ChordSymbolKind> _aliases = {
  for (final k in ChordSymbolKind.values)
    if (k.suffix.isNotEmpty) k.suffix: k,
  'maj': ChordSymbolKind.major,
  'M': ChordSymbolKind.major,
  'ma': ChordSymbolKind.major,
  '\u0394': ChordSymbolKind.major,
  'mi': ChordSymbolKind.minor,
  'min': ChordSymbolKind.minor,
  '-': ChordSymbolKind.minor,
  // ⚠ NO bare 'o' for diminished. It is a real chart spelling, but it turns
  // the direction "Go" into G-diminished, and directions arrive through the
  // same quoted channel as chords. Measured on a 53,312-token corpus the
  // spelling is worth 2 tokens; the false positive is not. `o7` and `\u00b0`
  // carry a digit or a symbol, so they stay.
  '\u00b0': ChordSymbolKind.diminished,
  '+': ChordSymbolKind.augmented,
  '5+': ChordSymbolKind.augmented,
  '#5': ChordSymbolKind.augmented,
  'dom7': ChordSymbolKind.dominantSeventh,
  'M7': ChordSymbolKind.majorSeventh,
  'Ma7': ChordSymbolKind.majorSeventh,
  '\u03947': ChordSymbolKind.majorSeventh,
  'mi7': ChordSymbolKind.minorSeventh,
  'min7': ChordSymbolKind.minorSeventh,
  '-7': ChordSymbolKind.minorSeventh,
  '\u00f8': ChordSymbolKind.halfDiminishedSeventh,
  '\u00f87': ChordSymbolKind.halfDiminishedSeventh,
  'mi7b5': ChordSymbolKind.halfDiminishedSeventh,
  'min7b5': ChordSymbolKind.halfDiminishedSeventh,
  'm7-5': ChordSymbolKind.halfDiminishedSeventh,
  '-7b5': ChordSymbolKind.halfDiminishedSeventh,
  'o7': ChordSymbolKind.diminishedSeventh,
  '\u00b07': ChordSymbolKind.diminishedSeventh,
  'mM7': ChordSymbolKind.minorMajorSeventh,
  'minMaj7': ChordSymbolKind.minorMajorSeventh,
  '-maj7': ChordSymbolKind.minorMajorSeventh,
  'maj6': ChordSymbolKind.sixth,
  'M6': ChordSymbolKind.sixth,
  'mi6': ChordSymbolKind.minorSixth,
  'min6': ChordSymbolKind.minorSixth,
  '-6': ChordSymbolKind.minorSixth,
  'dom9': ChordSymbolKind.dominantNinth,
  'sus': ChordSymbolKind.suspendedFourth,
};

/// The alternates again, lower-cased — but ONLY where lowering stays
/// unambiguous.
///
/// ⚠ Case carries meaning here: `CM7` is a MAJOR seventh and `Cm7` a MINOR
/// one. Folding case blindly silently turns every major seventh minor, so any
/// spelling that collides once lowered (`M`/`m`, `M7`/`m7`, `M6`/`m6`) is
/// dropped from this map and stays case-sensitive.
final Map<String, ChordSymbolKind> _looseAliases = () {
  final seen = <String, ChordSymbolKind?>{};
  for (final e in _aliases.entries) {
    final k = e.key.toLowerCase();
    seen[k] = seen.containsKey(k) && seen[k] != e.value ? null : e.value;
  }
  return {
    for (final e in seen.entries)
      if (e.value != null) e.key: e.value!,
  };
}();

ChordSymbolKind? _kindOf(String rest) {
  // A bare root is a major triad — but only when nothing follows it.
  if (rest.isEmpty) return ChordSymbolKind.major;
  return _aliases[rest] ?? _looseAliases[rest.toLowerCase()];
}

/// The root note at the start of [s], plus whatever follows it.
///
/// A root is one letter A-G, optionally followed by accidentals. Lower case is
/// accepted because chord charts use it, but the letter must be the FIRST
/// character — "bB" is not a chord.
(Pitch, String)? _rootOf(String s) {
  if (s.isEmpty) return null;
  final step = switch (s[0].toUpperCase()) {
    'A' => Step.a,
    'B' => Step.b,
    'C' => Step.c,
    'D' => Step.d,
    'E' => Step.e,
    'F' => Step.f,
    'G' => Step.g,
    _ => null,
  };
  if (step == null) return null;
  var i = 1;
  var alter = 0;
  // `#`/`b` and the unicode signs; `x` is a double sharp on chord charts.
  while (i < s.length) {
    final c = s[i];
    if (c == '#' || c == '♯') {
      alter++;
    } else if (c == 'b' || c == '♭') {
      // A `b` is only an accidental directly after the letter: "Bb" yes, and
      // in "Bbm" the second b is still the accidental, but the `b` of "b5"
      // inside "m7b5" is part of the SUFFIX, which this loop never reaches
      // because it stops at the first non-accidental.
      alter--;
    } else if (c == 'x') {
      alter += 2;
    } else {
      break;
    }
    i++;
  }
  if (alter < -2 || alter > 2) return null;
  return (Pitch(step, octave: 4, alter: alter), s.substring(i));
}

/// Writes [chord] back as a name a human (and every text-based format) reads.
///
/// The inverse of [parseChordName], and deliberately canonical: it emits the
/// model's own [ChordSymbolKind.suffix], never one of the alternates the
/// parser accepts, so `Ami` and `Amin` both come back as `Am`. Round-tripping
/// the CHORD is the contract; round-tripping the spelling is not.
///
/// It is [ChordSymbol.text] — the printed symbol the layout already draws —
/// rather than a second copy of the same table. This file had one, and a
/// duplicated spelling table is exactly how the duration tables in this repo
/// drifted apart. The alias to it is kept so every codec asks for "the name"
/// through the same door it parses one with.
String chordName(ChordSymbol chord) => chord.text;
