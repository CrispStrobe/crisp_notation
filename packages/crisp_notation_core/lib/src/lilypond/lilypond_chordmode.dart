/// LilyPond `\chordmode` modifiers (`m7`, `7.9-`, `maj9`, `9^7`, `13.11`)
/// and the chord they build, shared by the reader (which plays and names
/// them) and the writer (which spells a [ChordSymbol] in them).
library;

import '../model/element.dart';

/// The chord a `\chordmode` modifier string builds, as LilyPond 2.24 builds
/// it: chord degrees (1 for the root, 3 for the third, ...) with their
/// semitones above the root.
///
/// The first number is how far the chord reaches: thirds stacked up to it,
/// plus the number itself (`3` is root and third, `4` adds a fourth to them,
/// `6` a sixth to the triad, `9` stacks 7 and 9 on it); `5` alone is root
/// and fifth (a power chord) and `1` the root alone. Every later number adds
/// its degree (`.9`), `+`/`-` raise or lower it, and `^` removes the degrees
/// after it. `m` lowers the third, `maj` raises the seventh, `dim` and `aug`
/// alter the fifth (and `dim` the seventh), `sus`/`sus4`/`sus2` replace the
/// third.
///
/// ⚠️ A thirteenth leaves its eleventh out, but only over a MAJOR third
/// (`c:13`; `c:m13` and `c:13sus4` keep it) and only when the eleventh is
/// not written (`c:11`, `c:13.11` keep it). Each rule here follows
/// LilyPond 2.24's `chord-entry.scm` and was checked against its MIDI.
Map<int, int> lilyChordModeSteps(String mods) {
  final parts = mods.split('^');
  final steps = <int, int>{1: 0, 3: 4, 5: 7};
  var minor = false, maj = false, dim = false, aug = false;
  int? sus;
  int? first;
  final explicit = <int>{};
  final altered = <int, int>{};
  for (final m in RegExp(r'(m(?:aj|in)?|dim|aug|sus)|(\d+)([+-]*)')
      .allMatches(parts.first)) {
    if (m[1] case final word?) {
      switch (word) {
        case 'm' || 'min':
          minor = true;
        case 'maj':
          maj = true;
        case 'dim':
          dim = true;
        case 'aug':
          aug = true;
        case 'sus':
          sus = 4;
      }
      continue;
    }
    final n = int.parse(m[2]!);
    final shift = '+'.allMatches(m[3]!).length - '-'.allMatches(m[3]!).length;
    // `sus2`/`sus4`: the number belongs to the suspension, and counts as the
    // first, so the `9` of `sus4.9` adds a ninth alone (no seventh).
    if ((n == 2 || n == 4) &&
        parts.first.substring(0, m.start).endsWith('sus')) {
      sus = n;
      first ??= n;
      continue;
    }
    if (n > 13) continue;
    if (first == null) {
      first = n;
      if (n == 5) {
        steps.remove(3);
      } else if (n < 7) {
        steps.removeWhere((s, _) => s > n);
        steps[n] = chordDegreeSemitones[n]!;
      } else {
        for (var s = 7; s <= n; s += 2) {
          steps[s] = chordDegreeSemitones[s]!;
        }
      }
    } else {
      steps[n] = chordDegreeSemitones[n]!;
      explicit.add(n);
    }
    if (shift != 0) altered[n] = shift;
  }
  // A bare `maj` is a major seventh chord, a bare `dim7` diminished.
  if (maj) steps[7] = 11;
  if (minor && steps.containsKey(3)) steps[3] = 3;
  if (dim) {
    if (steps.containsKey(3)) steps[3] = 3;
    steps[5] = 6;
    if (steps.containsKey(7)) steps[7] = 9;
  }
  if (aug) steps[5] = 8;
  if (sus case final s?) {
    steps.remove(3);
    steps[s] = chordDegreeSemitones[s]!;
  }
  altered.forEach((s, shift) {
    if (steps.containsKey(s)) steps[s] = chordDegreeSemitones[s]! + shift;
  });
  // LilyPond's chord-entry.scm: a natural eleventh over a natural (major)
  // third is dropped unless it was written.
  if (first != 11 &&
      !explicit.contains(11) &&
      steps[11] == 17 &&
      steps[3] == 4) {
    steps.remove(11);
  }
  if (parts.length > 1) {
    for (final m in RegExp(r'\d+').allMatches(parts.sublist(1).join('.'))) {
      steps.remove(int.parse(m[0]!));
    }
  }
  return steps;
}

/// [chord]'s quality and degrees as `\chordmode` modifiers (without the
/// colon), or the empty string for a plain major triad: `m7`, `7.9-`,
/// `maj9.11+`, `sus4.9`, `6.9`.
///
/// The kind's own modifier comes first; each degree whose tone differs from
/// what that builds is added after it (`.9-`) and each one it lacks is
/// removed (`^5`). The result is checked against [lilyChordModeSteps], and
/// where the keyword rules would undo a degree (`maj` re-raises any seventh,
/// `dim` re-lowers the fifth) every tone is spelled out from the root
/// instead (`1.3.5-.7`), which LilyPond builds exactly.
///
/// ⚠️ [ChordSymbolKind.none] has no modifiers; the writer writes it as a
/// rest (`r`), which LilyPond's chord names print as "N.C.".
String lilyChordMods(ChordSymbol chord) {
  final target = chord.tones;
  final base = _baseMods[chord.quality] ?? '';
  if (base.isNotEmpty || chord.degrees.isNotEmpty) {
    final built = lilyChordModeSteps(base);
    final adds = <String>[];
    final removes = <int>[];
    final values = {...built.keys, ...target.keys}.toList()..sort();
    var spellable = true;
    for (final v in values) {
      final want = target[v];
      if (want == null) {
        removes.add(v);
      } else if (built[v] != want) {
        final natural = chordDegreeSemitones[v];
        if (natural == null) {
          spellable = false;
          break;
        }
        adds.add('.$v${_shift(want - natural)}');
      }
    }
    if (spellable) {
      // A bare `.9` or `^5` needs a chord in front of it.
      final head = base.isEmpty ? '3.5' : base;
      final mods = '$head${adds.join()}'
          '${removes.isEmpty ? '' : '^${removes.join('.')}'}';
      if (_sameSteps(lilyChordModeSteps(mods), target)) return mods;
    }
  }
  if (_sameSteps(lilyChordModeSteps(base), target)) return base;
  // Every tone from the root up.
  final values = target.keys.where((v) => v != 1).toList()..sort();
  return [
    '1',
    for (final v in values)
      if (chordDegreeSemitones[v] case final natural?)
        '$v${_shift(target[v]! - natural)}',
  ].join('.');
}

String _shift(int by) => by > 0 ? '+' * by : '-' * -by;

bool _sameSteps(Map<int, int> a, Map<int, int> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

/// Each kind in LilyPond's own modifier spelling. `maj` already MEANS a
/// major seventh in LilyPond, so a plain triad takes no modifier at all, and
/// `7+` is its raised seventh — hence `m7+` for minor-major. The functional
/// kinds are spelled by their tones: an Italian sixth is a major third and
/// an augmented sixth (`6+^5`).
const Map<ChordSymbolKind, String> _baseMods = {
  ChordSymbolKind.major: '',
  ChordSymbolKind.minor: 'm',
  ChordSymbolKind.diminished: 'dim',
  ChordSymbolKind.augmented: 'aug',
  ChordSymbolKind.dominantSeventh: '7',
  ChordSymbolKind.majorSeventh: 'maj7',
  ChordSymbolKind.minorSeventh: 'm7',
  ChordSymbolKind.halfDiminishedSeventh: 'm7.5-',
  ChordSymbolKind.diminishedSeventh: 'dim7',
  ChordSymbolKind.minorMajorSeventh: 'm7+',
  ChordSymbolKind.sixth: '6',
  ChordSymbolKind.minorSixth: 'm6',
  ChordSymbolKind.dominantNinth: '9',
  ChordSymbolKind.suspendedFourth: 'sus4',
  ChordSymbolKind.suspendedSecond: 'sus2',
  ChordSymbolKind.majorNinth: 'maj9',
  ChordSymbolKind.minorNinth: 'm9',
  ChordSymbolKind.dominantEleventh: '11',
  ChordSymbolKind.majorEleventh: 'maj11',
  ChordSymbolKind.minorEleventh: 'm11',
  ChordSymbolKind.dominantThirteenth: '13',
  ChordSymbolKind.majorThirteenth: 'maj13',
  ChordSymbolKind.minorThirteenth: 'm13',
  ChordSymbolKind.augmentedSeventh: 'aug7',
  ChordSymbolKind.neapolitan: '',
  ChordSymbolKind.italian: '6+^5',
  ChordSymbolKind.french: '6+.4+^5',
  ChordSymbolKind.german: '6+',
  ChordSymbolKind.tristan: '1.4+.6+.9+',
  ChordSymbolKind.pedal: '1',
  ChordSymbolKind.power: '5',
  ChordSymbolKind.other: '1',
};
