/// Bar capacities and rest filling, shared by the document-level edits
/// (linked parts, ossia and divisi staves) that have to invent bars.
library;

import '../model/element.dart';
import '../model/score.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/time_signature.dart';

/// Each bar's capacity in [score]: its explicit length, else the meter in
/// force there.
List<Fraction> barCapacities(Score score) {
  var meter = score.timeSignature ?? const TimeSignature(4, 4);
  final out = <Fraction>[];
  for (final m in score.measures) {
    if (m.timeChange != null) meter = m.timeChange!;
    out.add(m.actualDuration ?? Fraction(meter.beats, meter.beatUnit));
  }
  return out;
}

/// Rests that fill [capacity] exactly, longest first, with ids
/// `<idPrefix>.<n>`.
List<MusicElement> restsFilling(Fraction capacity, String idPrefix) {
  final values = <NoteDuration>[
    for (final base in DurationBase.values)
      for (final dots in const [2, 1, 0]) NoteDuration(base, dots: dots),
  ]..sort((a, b) => b.toFraction().compareTo(a.toFraction()));
  final out = <MusicElement>[];
  var left = capacity;
  while (left > Fraction.zero && out.length < 16) {
    final d = values.firstWhere((v) => !(v.toFraction() > left),
        orElse: () => values.last);
    out.add(RestElement(d, id: '$idPrefix.${out.length}'));
    left = left - d.toFraction();
  }
  return out;
}
