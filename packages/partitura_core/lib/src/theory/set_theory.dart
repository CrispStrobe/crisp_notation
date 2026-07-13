/// Post-tonal (pitch-class set) theory (Phase 4.5).
///
/// Normal order, Forte prime form, the interval-class vector, the Z-relation and
/// the Forte set-class *number* for a pitch-class set (integers 0–11). Pure
/// theory (no rendering); the analysis toolkit for atonal music. The prime form
/// is the canonical identifier; [forteNumber] adds the familiar `3-11` naming
/// (hexachords excepted — see there).
library;

import 'pitch.dart';

/// The pitch classes (0–11) sounding in [pitches], de-duplicated.
Set<int> pitchClassSet(Iterable<Pitch> pitches) =>
    {for (final p in pitches) p.midiNumber % 12};

/// [pcs] transposed by [n] semitones (mod 12).
Set<int> transposeSet(Set<int> pcs, int n) =>
    {for (final p in pcs) (p + n) % 12};

/// [pcs] inverted about pitch class 0 (`p → −p mod 12`).
Set<int> invertSet(Set<int> pcs) => {for (final p in pcs) (12 - p) % 12};

/// The **normal order** of [pcs]: the rotation packed most tightly (smallest
/// span, ties broken from the outside in, then by the lowest starting pitch
/// class). Returns the actual pitch classes in that order.
List<int> normalForm(Set<int> pcs) {
  final s = pcs.toList()..sort();
  final n = s.length;
  if (n <= 1) return s;
  var bestStart = 0;
  List<int>? bestShape;
  for (var i = 0; i < n; i++) {
    // Ascending intervals above this rotation's starting note.
    final shape = [
      for (var k = 0; k < n; k++) (s[(i + k) % n] - s[i] + 12) % 12
    ];
    if (bestShape == null || _moreCompact(shape, bestShape)) {
      bestShape = shape;
      bestStart = i;
    }
  }
  return [for (var k = 0; k < n; k++) s[(bestStart + k) % n]];
}

/// The **Forte prime form** of [pcs]: the more left-packed of the set's and its
/// inversion's normal orders, transposed to start on 0.
List<int> primeForm(Set<int> pcs) {
  if (pcs.isEmpty) return [];
  final zeroed = _zeroed(normalForm(pcs));
  final invZeroed = _zeroed(normalForm(invertSet(pcs)));
  return _lexLess(invZeroed, zeroed) ? invZeroed : zeroed;
}

/// The **interval-class vector** of [pcs]: counts of interval classes 1–6
/// (`[ic1, ic2, ic3, ic4, ic5, ic6]`) across every unordered pair.
List<int> intervalClassVector(Set<int> pcs) {
  final v = List<int>.filled(6, 0);
  final s = pcs.toList();
  for (var i = 0; i < s.length; i++) {
    for (var j = i + 1; j < s.length; j++) {
      final d = ((s[i] - s[j]).abs()) % 12;
      final ic = d > 6 ? 12 - d : d;
      if (ic >= 1) v[ic - 1]++;
    }
  }
  return v;
}

/// Whether [a] and [b] are **Z-related**: the same interval-class vector but
/// different prime forms (not transpositions/inversions of each other).
bool zRelated(Set<int> a, Set<int> b) =>
    _listEq(intervalClassVector(a), intervalClassVector(b)) &&
    !_listEq(primeForm(a), primeForm(b));

/// The **Forte set-class number** of [pcs] (e.g. a minor triad → `3-11`, a
/// dominant seventh → `4-27`, the major scale → `7-35`), or null if it has no
/// Forte number (the empty set, or — for now — a hexachord, whose catalogue is
/// not yet transcribed; the [primeForm] remains the canonical identifier).
///
/// Trichords through pentachords (and dyads) come from the catalogue; septachords
/// through decachords are derived from their complement, which Forte numbered
/// with the same ordinal (`7-35` is the complement of `5-35`). A `Z` marks a
/// Z-related class (`4-Z15`).
String? forteNumber(Set<int> pcs) {
  final card = pcs.length;
  if (card == 0 || card > 12) return null;
  if (card == 1) return '1-1';
  if (card == 11) return '11-1';
  if (card == 12) return '12-1';
  final direct = _forteByCard[card];
  if (direct != null) return direct[_pfKey(primeForm(pcs))];
  // Larger sets (7–10) share their complement's ordinal (Forte's convention).
  if (card >= 7 && card <= 10) {
    final complement = {for (var p = 0; p < 12; p++) p}.difference(pcs);
    final compNumber = forteNumber(complement);
    if (compNumber == null) return null;
    return '$card${compNumber.substring(compNumber.indexOf('-'))}';
  }
  return null; // hexachords: not yet catalogued
}

// A prime form as a compact key: pitch classes 0–9, then T (10), E (11).
String _pfKey(List<int> primeForm) =>
    [for (final p in primeForm) '0123456789TE'[p]].join();

// Forte prime forms → numbers, by cardinality (2–5). Complementary cardinalities
// (7–10) reuse these via [forteNumber]; 1/11/12 are handled directly there.
const Map<int, Map<String, String>> _forteByCard = {
  2: {
    '01': '2-1',
    '02': '2-2',
    '03': '2-3',
    '04': '2-4',
    '05': '2-5',
    '06': '2-6'
  },
  3: {
    '012': '3-1',
    '013': '3-2',
    '014': '3-3',
    '015': '3-4',
    '016': '3-5',
    '024': '3-6',
    '025': '3-7',
    '026': '3-8',
    '027': '3-9',
    '036': '3-10',
    '037': '3-11',
    '048': '3-12',
  },
  4: {
    '0123': '4-1',
    '0124': '4-2',
    '0134': '4-3',
    '0125': '4-4',
    '0126': '4-5',
    '0127': '4-6',
    '0145': '4-7',
    '0156': '4-8',
    '0167': '4-9',
    '0235': '4-10',
    '0135': '4-11',
    '0236': '4-12',
    '0136': '4-13',
    '0237': '4-14',
    '0146': '4-Z15',
    '0157': '4-16',
    '0347': '4-17',
    '0147': '4-18',
    '0148': '4-19',
    '0158': '4-20',
    '0246': '4-21',
    '0247': '4-22',
    '0257': '4-23',
    '0248': '4-24',
    '0268': '4-25',
    '0358': '4-26',
    '0258': '4-27',
    '0369': '4-28',
    '0137': '4-Z29',
  },
  5: {
    '01234': '5-1',
    '01235': '5-2',
    '01245': '5-3',
    '01236': '5-4',
    '01237': '5-5',
    '01256': '5-6',
    '01267': '5-7',
    '02346': '5-8',
    '01246': '5-9',
    '01346': '5-10',
    '02347': '5-11',
    '01356': '5-Z12',
    '01248': '5-13',
    '01257': '5-14',
    '01268': '5-15',
    '01347': '5-16',
    '01348': '5-Z17',
    '01457': '5-Z18',
    '01367': '5-19',
    '01568': '5-20',
    '01458': '5-21',
    '01478': '5-22',
    '02357': '5-23',
    '01357': '5-24',
    '02358': '5-25',
    '02458': '5-26',
    '01358': '5-27',
    '02368': '5-28',
    '01368': '5-29',
    '01468': '5-30',
    '01369': '5-31',
    '01469': '5-32',
    '02468': '5-33',
    '02469': '5-34',
    '02479': '5-35',
    '01247': '5-Z36',
    '03458': '5-Z37',
    '01258': '5-Z38',
  },
};

// The interval shape of [order] shifted to begin on 0.
List<int> _zeroed(List<int> order) =>
    [for (final p in order) (p - order.first + 12) % 12];

// Compactness for normal order: smaller span (last interval) wins, ties broken
// by the next interval inward, and so on.
bool _moreCompact(List<int> a, List<int> b) {
  for (var k = a.length - 1; k >= 1; k--) {
    if (a[k] != b[k]) return a[k] < b[k];
  }
  return false;
}

// Lexicographic "more packed to the left" (both start on 0).
bool _lexLess(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return false;
}

bool _listEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
