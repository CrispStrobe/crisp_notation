/// Screen-reader / accessibility labels for score elements (Phase 3.9).
///
/// These turn the score into spoken descriptions so an interactive player can
/// expose a note-by-note navigable, accessible score — a genuine gap across
/// notation renderers. crisp_notation makes no sound; the app decides how to speak
/// or sonify these.
library;

import '../theory/duration.dart';
import '../theory/pitch.dart';
import 'element.dart';
import 'score.dart';

/// A spoken, screen-reader-friendly label for [element] — pitch names spelled
/// out and the duration named. E.g. `"C sharp 4 quarter note"`,
/// `"C 4, E 4, G 4 chord, half note"`, `"quarter rest"`.
String semanticLabel(MusicElement element) {
  final dur = _durationWords(element.duration);
  switch (element) {
    case NoteElement(:final pitches):
      if (pitches.isEmpty) return '$dur note';
      if (pitches.length == 1) return '${_pitchWords(pitches.first)} $dur note';
      return '${pitches.map(_pitchWords).join(', ')} chord, $dur note';
    case RestElement():
      return '$dur rest';
  }
}

/// Every identified element in [score] mapped to its [semanticLabel] (every
/// voice), for driving per-element `Semantics` / a navigable list.
Map<String, String> semanticLabels(Score score) {
  final out = <String, String>{};
  for (final measure in score.measures) {
    for (final voice in [
      measure.elements,
      measure.voice2,
      measure.voice3,
      measure.voice4,
    ]) {
      for (final element in voice) {
        final id = element.id;
        if (id != null) out[id] = semanticLabel(element);
      }
    }
  }
  return out;
}

String _pitchWords(Pitch p) {
  const alter = {
    -2: ' double flat',
    -1: ' flat',
    0: '',
    1: ' sharp',
    2: ' double sharp',
  };
  const micro = {
    MicrotonalAccidental.halfFlat: ' half flat',
    MicrotonalAccidental.halfSharp: ' half sharp',
    MicrotonalAccidental.sesquiFlat: ' sesquiflat',
    MicrotonalAccidental.sesquiSharp: ' sesquisharp',
  };
  final acc =
      p.microtone != null ? (micro[p.microtone] ?? '') : (alter[p.alter] ?? '');
  return '${p.step.name.toUpperCase()}$acc ${p.octave}';
}

String _durationWords(NoteDuration d) {
  const names = {
    DurationBase.maxima: 'maxima',
    DurationBase.long: 'longa',
    DurationBase.breve: 'double whole',
    DurationBase.whole: 'whole',
    DurationBase.half: 'half',
    DurationBase.quarter: 'quarter',
    DurationBase.eighth: 'eighth',
    DurationBase.sixteenth: 'sixteenth',
    DurationBase.thirtySecond: 'thirty-second',
    DurationBase.sixtyFourth: 'sixty-fourth',
  };
  final dots = switch (d.dots) {
    1 => 'dotted ',
    2 => 'double-dotted ',
    _ => '',
  };
  return '$dots${names[d.base]}';
}
