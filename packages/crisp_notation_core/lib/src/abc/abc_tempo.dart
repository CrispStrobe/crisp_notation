/// ABC `Q:` tempo — the one place its two renderings live.
///
/// A `Q:` carries BOTH a metronome mark, which the model holds as [Tempo], and
/// an optional text label ("Allegro"), which it cannot. The reader needs the
/// display string, the writer needs the field; deriving them in two places is
/// how the duration tables in this repo drifted apart, so they live together.
library;

import '../theory/duration.dart';
import '../theory/tempo.dart';

/// The metronome mark and label in a `Q:` value.
///
/// `Q:"Allegro" 1/4=120` → both; `Q:1/4=120` → mark only; bare `Q:120` → a
/// quarter at 120, which is what a bare number means in ABC.
({Tempo? tempo, String? label}) parseAbcTempo(String value) {
  final v = value.trim();
  if (v.isEmpty) return (tempo: null, label: null);
  final quoted = RegExp(r'"([^"]*)"').firstMatch(v);
  final label = quoted?[1]?.trim();

  final beat = RegExp(r'(\d+)\s*/\s*(\d+)\s*=\s*(\d+(?:\.\d+)?)').firstMatch(v);
  if (beat != null) {
    final bpm = double.tryParse(beat[3]!);
    final unit = _unitOf(int.parse(beat[1]!), int.parse(beat[2]!));
    if (bpm != null && bpm > 0 && unit != null) {
      return (
        tempo: Tempo(bpm, beatUnit: unit.$1, dots: unit.$2),
        label: label?.isEmpty ?? true ? null : label,
      );
    }
    return (tempo: null, label: label?.isEmpty ?? true ? null : label);
  }
  final plain = RegExp(r'=\s*(\d+(?:\.\d+)?)').firstMatch(v)?.group(1) ??
      RegExp(r'^\s*(\d+(?:\.\d+)?)\s*$').firstMatch(v)?.group(1);
  final bpm = plain == null ? null : double.tryParse(plain);
  return (
    tempo: bpm == null || bpm <= 0 ? null : Tempo(bpm),
    label: label?.isEmpty ?? true ? null : label,
  );
}

/// A `num/den`-of-a-whole beat as a duration base plus dots, or null when it is
/// not a value the model can name.
///
/// A dotted note is 3/2 of its base, so `3/8` is a DOTTED QUARTER — reading it
/// as three eighths would be a beat unit the model has no way to hold.
(DurationBase, int)? _unitOf(int num, int den) {
  for (final base in DurationBase.values) {
    for (var dots = 0; dots <= 2; dots++) {
      final f = NoteDuration(base, dots: dots).toFraction();
      if (f.numerator * den == f.denominator * num) return (base, dots);
    }
  }
  return null;
}

/// The `Q:` field value for [tempo] (with an optional text [label]).
String abcTempoField(Tempo tempo, {String? label}) {
  final f = NoteDuration(tempo.beatUnit, dots: tempo.dots).toFraction();
  final bpm = tempo.bpm == tempo.bpm.roundToDouble()
      ? tempo.bpm.round().toString()
      : tempo.bpm.toString();
  final prefix = label == null || label.isEmpty ? '' : '"$label" ';
  return '$prefix${f.numerator}/${f.denominator}=$bpm';
}

/// How a `Q:` is rendered above the staff — the text the reader files as an
/// annotation, since nothing in the layout draws [Tempo] itself.
String abcTempoDisplay(Tempo tempo, {String? label}) {
  final f = NoteDuration(tempo.beatUnit, dots: tempo.dots).toFraction();
  final bpm = tempo.bpm == tempo.bpm.roundToDouble()
      ? tempo.bpm.round().toString()
      : tempo.bpm.toString();
  final head = label == null || label.isEmpty ? '' : '$label ';
  return '$head${abcTempoNote(f.numerator, f.denominator)} = $bpm';
}

/// A note symbol for a `num/den`-of-a-whole beat unit in a metronome mark,
/// falling back to the raw fraction for units without a simple glyph.
String abcTempoNote(int num, int den) {
  if (num == 1 && den == 4) return '♩'; // quarter
  if (num == 1 && den == 8) return '♪'; // eighth
  if (num == 3 && den == 8) return '♩.'; // dotted quarter
  return '$num/$den';
}
