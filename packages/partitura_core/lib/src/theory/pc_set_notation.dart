/// A small text notation for the post-tonal analysis objects — pitch-class
/// sets and twelve-tone rows — so an app or CLI can read and write them as
/// plain strings. Pitch classes are integers 0–11, with the customary `T` = 10
/// and `E` = 11 accepted on input.
///
/// Labels round-trip: `parsePitchClassSet(pitchClassSetLabel(s)) == s` and
/// `parseToneRow(toneRowLabel(r)) == r`.
library;

import 'set_theory.dart';
import 'tone_row.dart';

/// Parses one pitch class from a token: a decimal integer (reduced mod 12) or
/// the single letters `T`/`t`/`A` (10) and `E`/`e`/`B` (11).
int _parsePitchClass(String token) {
  switch (token.toUpperCase()) {
    case 'T':
    case 'A':
      return 10;
    case 'E':
    case 'B':
      return 11;
    default:
      final value = int.tryParse(token);
      if (value == null) {
        throw FormatException('not a pitch class: "$token"');
      }
      return value % 12;
  }
}

List<int> _parsePitchClasses(String source) {
  final inner = source.trim().replaceAll(RegExp(r'^[\[{<(]|[\]}>)]$'), '');
  final tokens =
      inner.split(RegExp(r'[\s,]+')).where((t) => t.isNotEmpty).toList();
  return [for (final t in tokens) _parsePitchClass(t)];
}

/// Parses a pitch-class set from text such as `{0,4,7}`, `[0, 4, 7]`, `0 4 7`
/// or `0 4 7 T E`. Surrounding brackets/braces/angle-brackets are optional;
/// members are separated by commas and/or whitespace. Duplicates and order do
/// not matter (a set is unordered).
///
/// Throws a [FormatException] on an unparseable token.
PitchClassSet parsePitchClassSet(String source) =>
    PitchClassSet(_parsePitchClasses(source));

/// The canonical label for a pitch-class set: its members (ascending) in
/// braces, e.g. `{0, 4, 7}`. Round-trips through [parsePitchClassSet].
String pitchClassSetLabel(PitchClassSet set) =>
    '{${set.pitchClasses.join(', ')}}';

/// A one-line analysis of a pitch-class set: its members, normal order, prime
/// form and interval-class vector — for display and logging (not parsed back).
String pitchClassSetAnalysis(PitchClassSet set) {
  String list(Iterable<int> xs) => '[${xs.join(', ')}]';
  return '${pitchClassSetLabel(set)}  '
      'normal ${list(set.normalOrder)}  '
      'prime ${list(set.primeForm)}  '
      'icv ${list(set.intervalClassVector)}';
}

/// Parses a twelve-tone row from text such as `<0,1,2,3,4,5,6,7,8,9,T,E>` or a
/// bare `0 1 2 3 4 5 6 7 8 9 10 11`. Surrounding angle-brackets/brackets are
/// optional. Throws [FormatException] on a bad token and [ArgumentError] unless
/// the twelve pitch classes each appear once.
ToneRow parseToneRow(String source) => ToneRow(_parsePitchClasses(source));

/// The canonical label for a tone row: its twelve pitch classes in order inside
/// angle brackets, with 10 and 11 written `T` and `E`, e.g.
/// `<0,1,2,3,4,5,6,7,8,9,T,E>`. Round-trips through [parseToneRow].
String toneRowLabel(ToneRow row) {
  String pc(int p) => switch (p) { 10 => 'T', 11 => 'E', _ => '$p' };
  return '<${row.pitchClasses.map(pc).join(', ')}>';
}
