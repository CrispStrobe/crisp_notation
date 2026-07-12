/// Humdrum `**kern` export: [Score] → a `**kern` spine, a **subset** codec
/// that round-trips through `scoreFromKern`.
///
/// Humdrum is the open, documented representation used in computational
/// musicology (the format spec is public; no toolkit code is used here).
/// Covered subset: a single voice/spine — clef (with mid-score changes),
/// key/time signatures (incl. common/cut and additive), measures,
/// notes/chords, rests, durations (breve…64th with dots) and ties. Two voices,
/// slurs, tuplets, articulations and lyrics are out of scope. Pure Dart.
library;

import '../model/element.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/time_signature.dart';

const _clefCodes = {
  Clef.treble: 'G2',
  Clef.bass: 'F4',
  Clef.alto: 'C3',
  Clef.tenor: 'C4',
  Clef.treble8va: 'G^2',
  Clef.treble8vb: 'Gv2',
  Clef.bass8vb: 'Fv4',
  Clef.frenchViolin: 'G1',
  Clef.soprano: 'C1',
  Clef.mezzoSoprano: 'C2',
  Clef.baritone: 'F3',
  Clef.subbass: 'F5',
  Clef.percussion: 'X',
};

/// Reciprocal duration value per [DurationBase] (kern: 4 = quarter, 0 = breve).
const _durRecip = {
  DurationBase.breve: '0',
  DurationBase.whole: '1',
  DurationBase.half: '2',
  DurationBase.quarter: '4',
  DurationBase.eighth: '8',
  DurationBase.sixteenth: '16',
  DurationBase.thirtySecond: '32',
  DurationBase.sixtyFourth: '64',
};

/// The `*k[...]` content for [key]: sharps `f#c#…`, flats `b-e-…`, order as
/// written on the staff.
String kernKeyContent(KeySignature key) {
  const sharps = ['f', 'c', 'g', 'd', 'a', 'e', 'b'];
  const flats = ['b', 'e', 'a', 'd', 'g', 'c', 'f'];
  if (key.fifths > 0) {
    return [for (var i = 0; i < key.fifths; i++) '${sharps[i]}#'].join();
  }
  if (key.fifths < 0) {
    return [for (var i = 0; i < -key.fifths; i++) '${flats[i]}-'].join();
  }
  return '';
}

/// Serializes [score] as a single-spine `**kern` document.
String scoreToKern(Score score) {
  final lines = <String>['**kern'];
  lines.add('*clef${_clefCodes[score.clef]}');
  lines.add('*k[${kernKeyContent(score.keySignature)}]');
  if (score.timeSignature != null) {
    lines.addAll(_meterLines(score.timeSignature!));
  }

  // Element-level ties need to know the previous note's tie state.
  var prevTie = false;
  for (var m = 0; m < score.measures.length; m++) {
    final measure = score.measures[m];
    if (m > 0) {
      lines.add('=');
      if (measure.clefChange != null) {
        lines.add('*clef${_clefCodes[measure.clefChange!]}');
      }
      if (measure.keyChange != null) {
        lines.add('*k[${kernKeyContent(measure.keyChange!)}]');
      }
      if (measure.timeChange != null) {
        lines.addAll(_meterLines(measure.timeChange!));
      }
    }
    for (final element in measure.elements) {
      lines.add(_token(element, prevTie));
      prevTie = element is NoteElement && element.tieToNext;
    }
  }

  lines.add('==');
  lines.add('*-');
  return '${lines.join('\n')}\n';
}

List<String> _meterLines(TimeSignature time) {
  final count = time.components?.join('+') ?? '${time.beats}';
  final lines = <String>['*M$count/${time.beatUnit}'];
  if (time.symbol == TimeSymbol.common) lines.add('*met(C)');
  if (time.symbol == TimeSymbol.cut) lines.add('*met(C|)');
  return lines;
}

String _token(MusicElement element, bool tiedFromPrev) {
  final durStr =
      '${_durRecip[element.duration.base]}${'.' * element.duration.dots}';
  if (element is RestElement) return '${durStr}r';

  final note = element as NoteElement;
  final tiedToNext = note.tieToNext;
  final prefix = tiedToNext && !tiedFromPrev ? '[' : '';
  final suffix = tiedFromPrev ? (tiedToNext ? '_' : ']') : '';
  return note.pitches
      .map((p) => '$prefix$durStr${_kernPitch(p, note.showAccidental)}$suffix')
      .join(' ');
}

String _kernPitch(Pitch pitch, bool? showAccidental) {
  final letter = pitch.step.name;
  final repeated = pitch.octave >= 4
      ? letter * (pitch.octave - 3)
      : letter.toUpperCase() * (4 - pitch.octave);
  final accid = pitch.alter > 0
      ? '#' * pitch.alter
      : pitch.alter < 0
          ? '-' * -pitch.alter
          : (showAccidental == true ? 'n' : '');
  return '$repeated$accid';
}
