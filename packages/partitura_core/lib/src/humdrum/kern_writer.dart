/// Humdrum `**kern` export: [Score] → a `**kern` spine, a **subset** codec
/// that round-trips through `scoreFromKern`.
///
/// Humdrum is the open, documented representation used in computational
/// musicology (the format spec is public; no toolkit code is used here).
/// Covered subset: a single voice/spine — clef (with mid-score changes),
/// key/time signatures (incl. common/cut and additive), measures,
/// notes/chords, rests, durations (breve…64th with dots), ties, articulations
/// and ornaments, and tuplets (as reciprocal durations). Two voices and
/// lyrics are out of scope. Pure
/// Dart.
library;

import '../model/element.dart';
import '../model/measure.dart';
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
  final meta = score.metadata;
  final slurStarts = {for (final s in score.slurs) s.startId};
  final slurEnds = {for (final s in score.slurs) s.endId};
  final lines = <String>[];
  // Bibliographic reference records precede the spine.
  for (final (key, value) in [
    ('OTL', meta.title),
    ('COM', meta.composer),
    ('LYR', meta.lyricist),
    ('YEC', meta.copyright),
  ]) {
    if (value != null) lines.add('!!!$key: $value');
  }
  lines.add('**kern');
  lines.add('*clef${_clefCodes[score.clef]}');
  if (meta.instrument != null) lines.add('*I"${meta.instrument}');
  lines.add('*k[${kernKeyContent(score.keySignature)}]');
  if (score.timeSignature != null) {
    lines.addAll(_meterLines(score.timeSignature!));
  }
  final t = score.tempo;
  if (t != null) {
    // kern *MM is quarter-notes per minute; store the quarter-equivalent.
    final f = NoteDuration(t.beatUnit, dots: t.dots).toFraction();
    final quarters = t.bpm * f.numerator * 4 / f.denominator;
    final s = quarters == quarters.roundToDouble()
        ? quarters.round().toString()
        : quarters.toString();
    lines.add('*MM$s');
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
    for (var i = 0; i < measure.elements.length; i++) {
      final element = measure.elements[i];
      lines.add(_token(element, prevTie, _tupletRatioAt(measure, i),
          slurStart: element.id != null && slurStarts.contains(element.id),
          slurEnd: element.id != null && slurEnds.contains(element.id)));
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

/// The tuplet ratio covering element [i] of [measure], or null.
({int actual, int normal})? _tupletRatioAt(Measure measure, int i) {
  for (final t in measure.tuplets) {
    if (i >= t.startIndex && i <= t.endIndex) {
      return (actual: t.actual, normal: t.normal);
    }
  }
  return null;
}

/// The kern reciprocal for [dur], scaled to the tuplet [ratio] when present: a
/// written value with reciprocal `w` in an `actual:normal` tuplet sounds
/// `normal/actual` of `w`, so it is notated with reciprocal `w·actual/normal`
/// (e.g. a quarter, `4`, in a 3:2 triplet → `6`). Falls back to the plain
/// reciprocal when the scaled value is not an integer.
String _durString(NoteDuration dur, ({int actual, int normal})? ratio) {
  final baseRecip = _durRecip[dur.base];
  final dots = '.' * dur.dots;
  if (ratio != null && baseRecip != null) {
    final w = int.tryParse(baseRecip);
    if (w != null && w > 0 && (w * ratio.actual) % ratio.normal == 0) {
      return '${w * ratio.actual ~/ ratio.normal}$dots';
    }
  }
  return '$baseRecip$dots';
}

String _token(
    MusicElement element, bool tiedFromPrev, ({int actual, int normal})? ratio,
    {bool slurStart = false, bool slurEnd = false}) {
  final durStr = _durString(element.duration, ratio);
  final slurOpen = slurStart ? '(' : '';
  final slurClose = slurEnd ? ')' : '';
  if (element is RestElement) return '$slurOpen${durStr}r$slurClose';

  final note = element as NoteElement;
  final tiedToNext = note.tieToNext;
  final prefix = tiedToNext && !tiedFromPrev ? '[' : '';
  final suffix = tiedFromPrev ? (tiedToNext ? '_' : ']') : '';
  final marks =
      '${_kernArtic(note.articulations)}${_kernOrnament(note.ornament)}';
  final body = note.pitches
      .map((p) =>
          '$prefix$durStr${_kernPitch(p, note.showAccidental)}$marks$suffix')
      .join(' ');
  return '$slurOpen$body$slurClose';
}

/// Humdrum ornament signifier for [ornament].
String _kernOrnament(Ornament? ornament) => switch (ornament) {
      Ornament.trill => 'T',
      Ornament.shortTrill => 'm',
      Ornament.mordent => 'M',
      Ornament.turn => 'S',
      Ornament.invertedTurn => r'$',
      // kern has no trill-with-accidental token; fall back to a plain trill.
      Ornament.trillSharp || Ornament.trillFlat || Ornament.trillNatural => 'T',
      null => '',
    };

/// Humdrum articulation signifiers appended to a note (marcato `^^` wins over
/// accent `^` when both are present).
String _kernArtic(Set<Articulation> a) {
  final b = StringBuffer();
  if (a.contains(Articulation.staccato)) b.write("'");
  if (a.contains(Articulation.tenuto)) b.write('~');
  if (a.contains(Articulation.marcato)) {
    b.write('^^');
  } else if (a.contains(Articulation.accent)) {
    b.write('^');
  }
  if (a.contains(Articulation.fermata)) b.write(';');
  return b.toString();
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
