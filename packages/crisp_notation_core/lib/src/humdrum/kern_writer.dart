/// Humdrum `**kern` export: [Score] → a `**kern` spine, a **subset** codec
/// that round-trips through `scoreFromKern`.
///
/// Humdrum is the open, documented representation used in computational
/// musicology (the format spec is public; no toolkit code is used here).
/// Covered subset: a single voice/spine — clef (with mid-score changes),
/// key/time signatures (incl. common/cut and additive), measures,
/// notes/chords, rests, durations (breve…64th with dots), ties, articulations
/// and ornaments, and tuplets (as reciprocal durations). Repeats ride the
/// barline signs (`:|`/`|:`); single-voice lyrics ride parallel `**text`
/// spines. Pure Dart.
library;

import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
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

  final multiVoice = score.measures.any((m) => m.voice2.isNotEmpty);
  // Lyrics ride parallel `**text` spines (one per verse). Only the single-voice
  // path is paired; a multi-voice score keeps lyrics out of scope. Emitting the
  // extra spine ONLY when lyrics exist keeps every other score byte-identical.
  final verseCount =
      score.lyrics.fold<int>(0, (mx, l) => l.verse > mx ? l.verse : mx);
  if (verseCount > 0 && !multiVoice) {
    return _kernWithLyrics(lines, score, verseCount, slurStarts, slurEnds);
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

  // If any measure carries a second voice, emit two sub-spines (`*^` … `*v *v`)
  // with the voices time-merged; otherwise the plain single-spine path.
  if (multiVoice) {
    lines.add('*^'); // split the spine into two sub-spines (voice 1 / voice 2)
    for (var m = 0; m < score.measures.length; m++) {
      final measure = score.measures[m];
      if (m > 0) {
        final bar =
            _repeatBar(score.measures[m - 1].endRepeat, measure.startRepeat);
        lines.add('$bar\t$bar');
        if (measure.clefChange != null) {
          final c = '*clef${_clefCodes[measure.clefChange!]}';
          lines.add('$c\t$c');
        }
        if (measure.keyChange != null) {
          final k = '*k[${kernKeyContent(measure.keyChange!)}]';
          lines.add('$k\t$k');
        }
        if (measure.timeChange != null) {
          for (final l in _meterLines(measure.timeChange!)) {
            lines.add('$l\t$l');
          }
        }
      } else if (measure.startRepeat) {
        lines.add('=!|:\t=!|:');
      }
      lines.addAll(_multiVoiceRows(measure, slurStarts, slurEnds));
    }
    final lastEnd = score.measures.isNotEmpty && score.measures.last.endRepeat;
    lines.add(lastEnd ? '=:|!\t=:|!' : '==\t==');
    lines.add('*v\t*v'); // merge the sub-spines back
    lines.add('*-');
    return '${lines.join('\n')}\n';
  }

  // Element-level ties need to know the previous note's tie state.
  var prevTie = false;
  for (var m = 0; m < score.measures.length; m++) {
    final measure = score.measures[m];
    if (m > 0) {
      lines.add(
          _repeatBar(score.measures[m - 1].endRepeat, measure.startRepeat));
      if (measure.clefChange != null) {
        lines.add('*clef${_clefCodes[measure.clefChange!]}');
      }
      if (measure.keyChange != null) {
        lines.add('*k[${kernKeyContent(measure.keyChange!)}]');
      }
      if (measure.timeChange != null) {
        lines.addAll(_meterLines(measure.timeChange!));
      }
    } else if (measure.startRepeat) {
      lines.add('=!|:'); // a repeat that starts at the very beginning
    }
    for (var i = 0; i < measure.elements.length; i++) {
      final element = measure.elements[i];
      // Grace notes precede the principal, one record each, marked `q`
      // (acciaccatura) or `qq` (appoggiatura). They carry a display duration but
      // no rhythmic time (kern ignores `q` notes when summing the measure).
      if (element is NoteElement && element.graceNotes.isNotEmpty) {
        final mark = element.graceStyle == GraceStyle.appoggiatura ? 'qq' : 'q';
        for (final pitch in element.graceNotes) {
          lines.add('8${_kernPitch(pitch, null)}$mark');
        }
      }
      lines.add(_token(element, prevTie, _tupletRatioAt(measure, i),
          slurStart: element.id != null && slurStarts.contains(element.id),
          slurEnd: element.id != null && slurEnds.contains(element.id)));
      prevTie = element is NoteElement && element.tieToNext;
    }
  }

  lines.add(score.measures.isNotEmpty && score.measures.last.endRepeat
      ? '=:|!'
      : '==');
  lines.add('*-');
  return '${lines.join('\n')}\n';
}

/// A kern barline token carrying repeat signs: `:|` ends a repeat, `|:` starts
/// one. [endPrev] closes the measure before this barline, [startCur] opens the
/// one after it.
String _repeatBar(bool endPrev, bool startCur) => endPrev && startCur
    ? '=:|!|:'
    : endPrev
        ? '=:|!'
        : startCur
            ? '=!|:'
            : '=';

/// Single-voice `**kern` paired with [verseCount] parallel `**text` spines for
/// lyrics. [lines] already holds the leading `!!!` reference records. A
/// syllable that continues its word (hyphenToNext) is written with a trailing
/// `-`; a note with no syllable in a verse gets a null token (`.`).
String _kernWithLyrics(List<String> lines, Score score, int verseCount,
    Set<String> slurStarts, Set<String> slurEnds) {
  final meta = score.metadata;
  // (noteId, verse) → the `**text` token for that syllable.
  final syl = <String, String>{};
  for (final l in score.lyrics) {
    syl['${l.elementId}#${l.verse}'] = l.hyphenToNext ? '${l.text}-' : l.text;
  }
  // Repeat a spine token across the kern column + every text column.
  String across(String kern, String text) => '$kern${'\t$text' * verseCount}';
  // The text columns for a note (its syllable per verse, or `.`), or all `.`
  // for a note-less row (grace/rest).
  String textOf(String? id) {
    final b = StringBuffer();
    for (var v = 1; v <= verseCount; v++) {
      b.write('\t${id == null ? '.' : syl['$id#$v'] ?? '.'}');
    }
    return b.toString();
  }

  lines.add(across('**kern', '**text'));
  lines.add(across('*clef${_clefCodes[score.clef]}', '*'));
  if (meta.instrument != null) lines.add(across('*I"${meta.instrument}', '*'));
  lines.add(across('*k[${kernKeyContent(score.keySignature)}]', '*'));
  if (score.timeSignature != null) {
    for (final l in _meterLines(score.timeSignature!)) {
      lines.add(across(l, '*'));
    }
  }
  final t = score.tempo;
  if (t != null) {
    final f = NoteDuration(t.beatUnit, dots: t.dots).toFraction();
    final quarters = t.bpm * f.numerator * 4 / f.denominator;
    final s = quarters == quarters.roundToDouble()
        ? quarters.round().toString()
        : quarters.toString();
    lines.add(across('*MM$s', '*'));
  }

  var prevTie = false;
  for (var m = 0; m < score.measures.length; m++) {
    final measure = score.measures[m];
    if (m > 0) {
      final bar =
          _repeatBar(score.measures[m - 1].endRepeat, measure.startRepeat);
      lines.add(across(bar, bar));
      if (measure.clefChange != null) {
        lines.add(across('*clef${_clefCodes[measure.clefChange!]}', '*'));
      }
      if (measure.keyChange != null) {
        lines.add(across('*k[${kernKeyContent(measure.keyChange!)}]', '*'));
      }
      if (measure.timeChange != null) {
        for (final l in _meterLines(measure.timeChange!)) {
          lines.add(across(l, '*'));
        }
      }
    } else if (measure.startRepeat) {
      lines.add(across('=!|:', '=!|:'));
    }
    for (var i = 0; i < measure.elements.length; i++) {
      final element = measure.elements[i];
      if (element is NoteElement && element.graceNotes.isNotEmpty) {
        final mark = element.graceStyle == GraceStyle.appoggiatura ? 'qq' : 'q';
        for (final pitch in element.graceNotes) {
          lines.add('8${_kernPitch(pitch, null)}$mark${textOf(null)}');
        }
      }
      final tok = _token(element, prevTie, _tupletRatioAt(measure, i),
          slurStart: element.id != null && slurStarts.contains(element.id),
          slurEnd: element.id != null && slurEnds.contains(element.id));
      lines.add('$tok${textOf(element is NoteElement ? element.id : null)}');
      prevTie = element is NoteElement && element.tieToNext;
    }
  }
  final lastEnd = score.measures.isNotEmpty && score.measures.last.endRepeat;
  final fbar = lastEnd ? '=:|!' : '==';
  lines.add(across(fbar, fbar));
  lines.add(across('*-', '*-'));
  return '${lines.join('\n')}\n';
}

/// Data rows for a two-voice [measure] as `voice1<TAB>voice2` lines, time-merged
/// so a token appears in a sub-spine only where a note/rest starts, and a null
/// token (`.`) marks where that voice is sustaining across the other's event.
/// A measure with no voice 2 fills the second sub-spine with rests aligned to
/// voice 1 (valid for any meter). Voices 3–4, if present, are not yet emitted.
List<String> _multiVoiceRows(
    Measure measure, Set<String> slurStarts, Set<String> slurEnds) {
  // The tuplet ratio covering element [i] of [voiceIndex], or null.
  ({int actual, int normal})? ratioAt(int voiceIndex, int i) {
    for (final t in measure.tupletsForVoice(voiceIndex)) {
      if (i >= t.startIndex && i <= t.endIndex) {
        return (actual: t.actual, normal: t.normal);
      }
    }
    return null;
  }

  // (onset, token) pairs for a voice. Both the reciprocal written into the
  // token and the onset advance are tuplet-scaled — otherwise a triplet in a
  // multi-voice measure exports as a plain note and drifts the sub-spine.
  List<({Fraction at, String tok})> events(int voiceIndex) {
    final voice = measure.voiceAt(voiceIndex);
    var t = Fraction(0, 1);
    final out = <({Fraction at, String tok})>[];
    for (var i = 0; i < voice.length; i++) {
      final e = voice[i];
      out.add((
        at: t,
        tok: _token(e, false, ratioAt(voiceIndex, i),
            slurStart: e.id != null && slurStarts.contains(e.id),
            slurEnd: e.id != null && slurEnds.contains(e.id))
      ));
      t = t + measure.effectiveDurationAt(i, voice: voiceIndex);
    }
    return out;
  }

  final v1 = events(0);

  final List<({Fraction at, String tok})> v2;
  if (measure.voice2.isEmpty) {
    // Fill the second spine with rests aligned to voice 1's rhythm, matching
    // its (tuplet-scaled) reciprocals so the sub-spines stay consistent.
    var t = Fraction(0, 1);
    final filled = <({Fraction at, String tok})>[];
    for (var i = 0; i < measure.elements.length; i++) {
      filled.add((
        at: t,
        tok: '${_durString(measure.elements[i].duration, ratioAt(0, i))}r'
      ));
      t = t + measure.effectiveDurationAt(i);
    }
    v2 = filled;
  } else {
    v2 = events(1);
  }

  // Merged, sorted set of onsets across both voices.
  final onsets = <Fraction>{...v1.map((e) => e.at), ...v2.map((e) => e.at)}
      .toList()
    ..sort((a, b) => (a - b).numerator.sign);
  final rows = <String>[];
  for (final t in onsets) {
    final a = v1.firstWhere((e) => e.at == t, orElse: () => (at: t, tok: '.'));
    final b = v2.firstWhere((e) => e.at == t, orElse: () => (at: t, tok: '.'));
    rows.add('${a.tok}\t${b.tok}');
  }
  return rows;
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
