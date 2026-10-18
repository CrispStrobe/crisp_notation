/// Ending (volta) helpers shared by the format readers and writers — not
/// exported from the package entrypoint.
library;

import '../model/measure.dart';

/// Every pass an ending label names, in order: "1., 2." and "1.2.3." list
/// theirs, "1-3" and "1.–3." are ranges, and "Fine" names none.
List<int> voltaNumbersIn(String label) {
  final out = <int>[];
  for (final m in RegExp(r'(\d+)\.?(?:\s*[-–]\s*(\d+))?').allMatches(label)) {
    final from = int.parse(m[1]!);
    final to = m[2] == null ? from : int.parse(m[2]!);
    for (var n = from; n <= to && n - from < 64; n++) {
      if (n >= 1 && !out.contains(n)) out.add(n);
    }
  }
  return out;
}

/// Whether bar [i] of [measures] is the last bar of its ending: the bracket
/// does not carry on into the next bar.
bool voltaEndsAt(List<Measure> measures, int i) =>
    measures[i].volta != null &&
    (i == measures.length - 1 ||
        !measures[i].voltaContinuesInto(measures[i + 1]));

/// Whether bar [i] of [measures] is the first bar of its ending.
bool voltaStartsAt(List<Measure> measures, int i) =>
    measures[i].volta != null &&
    (i == 0 || !measures[i - 1].voltaContinuesInto(measures[i]));

/// The pass a text-only ending ("Fine", "last time") is taken on, for a format
/// that states no passes for it: the one after the latest pass of the endings
/// just before it in the same repeat, else 1.
int nextVoltaPass(List<Measure> before) {
  var pass = 0;
  for (var i = before.length - 1; i >= 0; i--) {
    final m = before[i];
    if (m.volta == null) break;
    for (final p in m.voltaPasses) {
      if (p > pass) pass = p;
    }
    if (m.startRepeat) break;
  }
  return pass + 1;
}

/// Whether the ending whose last bar is [last] has a closing hook, for a
/// format that states none (LilyPond, ABC): only where that bar ends at a
/// repeat sign or the final barline. Any other bar line leaves the bracket
/// open, as on a usual last ending.
bool voltaHookedByBarline(List<Measure> measures, int last) {
  final m = measures[last];
  return m.endRepeat ||
      m.barline == BarlineStyle.finalBar ||
      (last + 1 < measures.length && measures[last + 1].startRepeat);
}

/// Sets [Measure.voltaOpenEnd] on the last bar of each ending in [measures]
/// for which [openAt] (given that bar's index) says so, clearing it
/// elsewhere.
List<Measure> withVoltaOpenEnds(
    List<Measure> measures, bool Function(int last) openAt) {
  return [
    for (var i = 0; i < measures.length; i++)
      if (measures[i].volta == null)
        measures[i]
      else if (voltaEndsAt(measures, i))
        measures[i].copyWith(voltaOpenEnd: openAt(i))
      else
        measures[i].voltaOpenEnd
            ? measures[i].copyWith(voltaOpenEnd: false)
            : measures[i],
  ];
}
