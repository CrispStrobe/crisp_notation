/// Parsing a written chord NAME ("Ebmaj7", "C#m7b5", "G/B") into the model.
///
/// Every other route into [ChordSymbol] is structural — MusicXML reads
/// `<harmony>` element by element, MuseScore its own XML, LilyPond its colon
/// syntax (`c:maj7`). None of them reads the name a human writes, which is the
/// only thing ABC, lead sheets and chord charts give you.
library;

import '../model/element.dart';
import 'pitch.dart';

/// The result of reading a chord name. [degrees] is what the [kind] does not
/// name (`b9` in `G7b9`), empty for a plain kind.
typedef ParsedChordName = ({
  Pitch root,
  ChordSymbolKind kind,
  Pitch? bass,
  List<ChordDegree> degrees,
});

/// The quality part of a chord name: a kind and its extra degrees.
typedef ChordSpelling = ({ChordSymbolKind kind, List<ChordDegree> degrees});

/// Reads a chord name, or null if [text] is not one.
///
/// **Rejecting non-chords matters more than accepting exotic ones.** This runs
/// over free text — ABC quotes chord symbols and prose annotations with the
/// same delimiter — so "Fine", "D.C. al Coda" and "Allegro" must come back
/// null rather than becoming F, D and A chords. The rule that gets that right
/// is strict: after the root, the ENTIRE remainder must be a suffix the model
/// knows, optionally followed by degrees ([parseChordSuffix]). Anything left
/// over means it was never a chord.
///
/// `N.C.` is "no chord" ([ChordSymbolKind.none]), on a nominal root C.
ParsedChordName? parseChordName(String text) {
  var s = text.trim();
  if (s.isEmpty) return null;
  if (s == 'N.C.' || s == 'N.C') {
    return (
      root: const Pitch(Step.c, octave: 4),
      kind: ChordSymbolKind.none,
      bass: null,
      degrees: const <ChordDegree>[],
    );
  }
  // `C6/9` is a six-nine chord, not C6 over a bass 9.
  s = s.replaceFirst('6/9', '69');

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

  final spelling = parseChordSuffix(rest);
  if (spelling == null) return null;
  return (
    root: root,
    kind: spelling.kind,
    bass: bass,
    degrees: spelling.degrees,
  );
}

/// Reads the part of a chord name after the root (`maj7`, `7(b9)`,
/// `sus4(add9)`, `6/9`), or null if [suffix] is not one.
///
/// A kind spelling comes first (the longest one that leaves only degrees
/// behind), then any degrees: `add9`, `omit3`/`no3`, an altered degree with
/// its accidentals (`b9`, `#11`, `+5`, `-9`) and, inside parentheses only, a
/// bare added degree (`7(9)`). Degrees may be parenthesised and separated by
/// commas or spaces. A stacked suspension (`7sus4`, `9sus4`, `13sus2`) is the
/// suspended kind with the seventh (ninth, thirteenth) added; `69` and `6/9`
/// the sixth with an added ninth.
///
/// ⚠️ A bare number OUTSIDE parentheses is never a degree, or the part
/// labels "A4"/"B2" ABC files are full of would read as chords. An altered
/// degree the kind has is an [ChordDegreeType.alter] (`7b5`), one it lacks
/// an [ChordDegreeType.add] (`7b9`). The degrees come back sorted by value.
ChordSpelling? parseChordSuffix(String suffix) {
  final rest = suffix.trim().replaceFirst('6/9', '69');
  if (rest.isEmpty) {
    return (kind: ChordSymbolKind.major, degrees: const <ChordDegree>[]);
  }
  if (_kindOf(rest) case final kind?) {
    return (kind: kind, degrees: const <ChordDegree>[]);
  }
  final sus = RegExp(r'^(7|9|13)sus([24]?)(.*)$').firstMatch(rest);
  if (sus != null) {
    final kind = sus[2] == '2'
        ? ChordSymbolKind.suspendedSecond
        : ChordSymbolKind.suspendedFourth;
    final top = int.parse(sus[1]!);
    final stack = [
      for (final d in [7, 9, 13])
        if (d <= top) ChordDegree.add(d),
    ];
    return _withDegrees(kind, stack, sus[3]!);
  }
  final sixNine = RegExp(r'^(m|mi|min|-)?69(.*)$').firstMatch(rest);
  if (sixNine != null) {
    final kind =
        sixNine[1] == null ? ChordSymbolKind.sixth : ChordSymbolKind.minorSixth;
    return _withDegrees(kind, const [ChordDegree.add(9)], sixNine[2]!);
  }
  // The longest kind spelling that leaves only degrees behind.
  for (var i = rest.length - 1; i >= 0; i--) {
    final kind = i == 0 ? ChordSymbolKind.major : _kindOf(rest.substring(0, i));
    if (kind == null) continue;
    final spelled = _withDegrees(kind, const [], rest.substring(i));
    if (spelled != null && spelled.degrees.isNotEmpty) return spelled;
  }
  return null;
}

/// [kind] with [stack] and the degrees written in [text], or null when
/// [text] is not all degrees.
ChordSpelling? _withDegrees(
    ChordSymbolKind kind, List<ChordDegree> stack, String text) {
  final tones =
      ChordSymbol('', const Pitch(Step.c), kind, degrees: stack).tones;
  final out = [...stack];
  final item = RegExp(r'(add|Add|ADD|omit|Omit|no|No)?([#b♯♭+\-]*)(\d+)');
  var depth = 0;
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (c == '(') {
      depth++;
      i++;
      continue;
    }
    if (c == ')') {
      if (--depth < 0) return null;
      i++;
      continue;
    }
    if (c == ',' || c == ' ') {
      i++;
      continue;
    }
    final m = item.matchAsPrefix(text, i);
    if (m == null) return null;
    i = m.end;
    final value = int.parse(m[3]!);
    if (!const {2, 3, 4, 5, 6, 7, 9, 11, 13}.contains(value)) return null;
    var alter = 0;
    for (final a in m[2]!.split('')) {
      alter += '#♯+'.contains(a) ? 1 : -1;
    }
    final word = m[1]?.toLowerCase();
    final ChordDegree degree;
    if (word == 'omit' || word == 'no') {
      if (alter != 0 || !tones.containsKey(value)) return null;
      degree = ChordDegree.subtract(value);
    } else if (word == 'add') {
      degree = ChordDegree.add(value, alter: alter);
    } else if (alter != 0) {
      degree = tones.containsKey(value)
          ? ChordDegree.alter(value, alter)
          : ChordDegree.add(value, alter: alter);
    } else if (depth > 0 && !tones.containsKey(value)) {
      // `7(9)`: a bare number names an added degree only in parentheses.
      degree = ChordDegree.add(value);
    } else {
      return null;
    }
    out.add(degree);
    switch (degree.type) {
      case ChordDegreeType.subtract:
        tones.remove(value);
      case ChordDegreeType.add:
        tones[value] = chordDegreeSemitones[value]! + alter;
      case ChordDegreeType.alter:
        tones[value] = tones[value]! + alter;
    }
  }
  if (depth != 0) return null;
  // Stable: two degrees on one value keep their written order.
  final order = {for (final (k, d) in out.indexed) d: k};
  out.sort((a, b) {
    final byValue = a.value.compareTo(b.value);
    return byValue != 0 ? byValue : order[a]!.compareTo(order[b]!);
  });
  return (kind: kind, degrees: out);
}

/// The kind and degrees that spell [tones] — chord degrees with their
/// semitones above the root, as [ChordSymbol.tones] gives them — most
/// simply: the kind needing the fewest degrees, a subtracted degree costing
/// a little more than an added or altered one (`9sus4` is a suspended fourth
/// with a seventh and ninth added, not a ninth without its third and with a
/// fourth). Ties go to the kind listed first.
///
/// Only kinds a stack of degrees names are candidates: never a functional
/// kind (Neapolitan, the augmented sixths, Tristan, which are the same tones
/// as an ordinary chord in other words), [ChordSymbolKind.other] or
/// [ChordSymbolKind.none]. Empty [tones] are [ChordSymbolKind.none].
///
/// By construction the result sounds [tones] exactly, so a reader that knows
/// only the tones (LilyPond's chord mode) keeps the chord it plays.
ChordSpelling chordSpellingOf(Map<int, int> tones) {
  if (tones.isEmpty) {
    return (kind: ChordSymbolKind.none, degrees: const <ChordDegree>[]);
  }
  const functional = {
    ChordSymbolKind.neapolitan,
    ChordSymbolKind.italian,
    ChordSymbolKind.french,
    ChordSymbolKind.german,
    ChordSymbolKind.tristan,
    ChordSymbolKind.other,
    ChordSymbolKind.none,
  };
  ChordSpelling? best;
  var bestCost = double.infinity;
  for (final kind in ChordSymbolKind.values) {
    if (functional.contains(kind)) continue;
    final degrees = <ChordDegree>[];
    var cost = 0.0;
    final values = {...kind.tones.keys, ...tones.keys}.toList()..sort();
    for (final v in values) {
      final has = kind.tones[v];
      final want = tones[v];
      if (want == null) {
        degrees.add(ChordDegree.subtract(v));
        cost += 1.1;
      } else if (has == null) {
        final natural = chordDegreeSemitones[v];
        if (natural == null) {
          cost = double.infinity;
          break;
        }
        degrees.add(ChordDegree.add(v, alter: want - natural));
        cost += 1;
      } else if (has != want) {
        degrees.add(ChordDegree.alter(v, want - has));
        cost += 1;
      }
    }
    if (cost < bestCost) {
      bestCost = cost;
      best = (kind: kind, degrees: degrees);
    }
  }
  return best ?? (kind: ChordSymbolKind.other, degrees: const <ChordDegree>[]);
}

/// Every written spelling we accept, mapped to the kind it means.
///
/// The model's own `suffix` is the canonical one; these are the alternates
/// real chord charts use. Deliberately absent: bare `4`/`2` for sus (they
/// collide with the part labels "A4"/"B2" that ABC files are full of).
/// The power chord's `5` is the model's own suffix, so it is read.
final Map<String, ChordSymbolKind> _aliases = {
  for (final k in ChordSymbolKind.values)
    if (k.suffix.isNotEmpty) k.suffix: k,
  'maj': ChordSymbolKind.major,
  'M': ChordSymbolKind.major,
  'ma': ChordSymbolKind.major,
  'Δ': ChordSymbolKind.major,
  'mi': ChordSymbolKind.minor,
  'min': ChordSymbolKind.minor,
  '-': ChordSymbolKind.minor,
  // ⚠ NO bare 'o' for diminished. It is a real chart spelling, but it turns
  // the direction "Go" into G-diminished, and directions arrive through the
  // same quoted channel as chords. Measured on a 53,312-token corpus the
  // spelling is worth 2 tokens; the false positive is not. `o7` and `°`
  // carry a digit or a symbol, so they stay.
  '°': ChordSymbolKind.diminished,
  '+': ChordSymbolKind.augmented,
  '5+': ChordSymbolKind.augmented,
  '#5': ChordSymbolKind.augmented,
  'dom7': ChordSymbolKind.dominantSeventh,
  'M7': ChordSymbolKind.majorSeventh,
  'Ma7': ChordSymbolKind.majorSeventh,
  'Δ7': ChordSymbolKind.majorSeventh,
  'mi7': ChordSymbolKind.minorSeventh,
  'min7': ChordSymbolKind.minorSeventh,
  '-7': ChordSymbolKind.minorSeventh,
  'ø': ChordSymbolKind.halfDiminishedSeventh,
  'ø7': ChordSymbolKind.halfDiminishedSeventh,
  'mi7b5': ChordSymbolKind.halfDiminishedSeventh,
  'min7b5': ChordSymbolKind.halfDiminishedSeventh,
  'm7-5': ChordSymbolKind.halfDiminishedSeventh,
  '-7b5': ChordSymbolKind.halfDiminishedSeventh,
  'o7': ChordSymbolKind.diminishedSeventh,
  '°7': ChordSymbolKind.diminishedSeventh,
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
  'M9': ChordSymbolKind.majorNinth,
  'Ma9': ChordSymbolKind.majorNinth,
  'Δ9': ChordSymbolKind.majorNinth,
  'mi9': ChordSymbolKind.minorNinth,
  'min9': ChordSymbolKind.minorNinth,
  '-9': ChordSymbolKind.minorNinth,
  'M11': ChordSymbolKind.majorEleventh,
  'Ma11': ChordSymbolKind.majorEleventh,
  'Δ11': ChordSymbolKind.majorEleventh,
  'mi11': ChordSymbolKind.minorEleventh,
  'min11': ChordSymbolKind.minorEleventh,
  '-11': ChordSymbolKind.minorEleventh,
  'M13': ChordSymbolKind.majorThirteenth,
  'Ma13': ChordSymbolKind.majorThirteenth,
  'Δ13': ChordSymbolKind.majorThirteenth,
  'mi13': ChordSymbolKind.minorThirteenth,
  'min13': ChordSymbolKind.minorThirteenth,
  '-13': ChordSymbolKind.minorThirteenth,
  '+7': ChordSymbolKind.augmentedSeventh,
  '7+5': ChordSymbolKind.augmentedSeventh,
  '7#5': ChordSymbolKind.augmentedSeventh,
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
