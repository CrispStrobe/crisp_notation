/// Humdrum `**kern` export: [Score] → a `**kern` spine, a **subset** codec
/// that round-trips through `scoreFromKern`.
///
/// Humdrum is the open, documented representation used in computational
/// musicology (the format spec is public; no toolkit code is used here).
/// Covered subset: a single voice/spine — clef (with mid-score changes),
/// key/time signatures (incl. common/cut and additive), measures,
/// notes/chords, rests, durations (breve…64th with dots), ties, articulations
/// and ornaments, and tuplets (as reciprocal durations). Repeats ride the
/// barline signs (`:|`/`|:`); single-voice dynamics and lyrics ride parallel
/// `**dynam` / `**text` spines. Pure Dart.
library;

import '../layout/multi_part.dart';
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

  // The number of voices to write (1–4) = the highest voice used anywhere.
  var voiceCount = 1;
  for (final m in score.measures) {
    if (m.voice2.isNotEmpty && voiceCount < 2) voiceCount = 2;
    if (m.voice3.isNotEmpty && voiceCount < 3) voiceCount = 3;
    if (m.voice4.isNotEmpty) {
      voiceCount = 4;
      break;
    }
  }
  final multiVoice = voiceCount > 1;
  // Dynamics ride a `**dynam` spine, lyrics parallel `**text` spines (one per
  // verse). Only the single-voice path is paired; a multi-voice score keeps
  // both out of scope. Emitting the extra spines ONLY when a marking exists
  // keeps every other score byte-identical.
  final verseCount =
      score.lyrics.fold<int>(0, (mx, l) => l.verse > mx ? l.verse : mx);
  final hasDyn = score.dynamics.isNotEmpty;
  if ((verseCount > 0 || hasDyn) && !multiVoice) {
    return _kernWithExtraSpines(
        lines, score, verseCount, hasDyn, slurStarts, slurEnds);
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

  // Multi-voice: split the spine into `voiceCount` sub-spines (one per voice,
  // time-merged), then merge them back. Control lines are copied across every
  // sub-spine; `dup` builds the tab-joined columns.
  if (multiVoice) {
    String dup(String x) => List.filled(voiceCount, x).join('\t');
    // Split 1 → voiceCount, one voice per line (splitting the last sub-spine),
    // so the columns stay in voice order (v1, v2, …).
    lines.add('*^'); // 1 → 2
    for (var k = 3; k <= voiceCount; k++) {
      lines.add([...List.filled(k - 2, '*'), '*^'].join('\t'));
    }
    for (var m = 0; m < score.measures.length; m++) {
      final measure = score.measures[m];
      if (m > 0) {
        final bar =
            _repeatBar(score.measures[m - 1].endRepeat, measure.startRepeat);
        lines.add(dup(bar));
        if (measure.clefChange != null) {
          lines.add(dup('*clef${_clefCodes[measure.clefChange!]}'));
        }
        if (measure.keyChange != null) {
          lines.add(dup('*k[${kernKeyContent(measure.keyChange!)}]'));
        }
        if (measure.timeChange != null) {
          for (final l in _meterLines(measure.timeChange!)) {
            lines.add(dup(l));
          }
        }
      } else if (measure.startRepeat) {
        lines.add(dup('=!|:'));
      }
      lines.addAll(_marksFor(measure, voiceCount - 1));
      lines.addAll(_multiVoiceRows(measure, voiceCount, slurStarts, slurEnds));
    }
    final lastEnd = score.measures.isNotEmpty && score.measures.last.endRepeat;
    lines.add(dup(lastEnd ? '=:|!' : '=='));
    lines.add(dup('*v')); // merge the sub-spines back into one
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
    lines.addAll(_marksFor(measure, 0));
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

/// Volta / navigation records for [measure], to emit just after its opening
/// barline. A volta is a `*>N` section label (spanning the kern column + its
/// [extraSpines] parallel spines); navigation — which has no standard kern
/// token — rides a `!!nav:` global comment (a single line, all spines).
List<String> _marksFor(Measure measure, int extraSpines) => [
      if (measure.volta != null)
        '*>${measure.volta}${'\t*>${measure.volta}' * extraSpines}',
      if (measure.navigation != null) '!!nav:${measure.navigation!.name}',
    ];

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

/// Single-voice `**kern` paired with optional parallel spines: a `**dynam`
/// spine when [hasDyn], then [verseCount] `**text` spines for lyric verses.
/// [lines] already holds the leading `!!!` reference records. A syllable that
/// continues its word (hyphenToNext) is written with a trailing `-`; a note
/// with no marking in a spine gets a null token (`.`).
String _kernWithExtraSpines(List<String> lines, Score score, int verseCount,
    bool hasDyn, Set<String> slurStarts, Set<String> slurEnds) {
  final meta = score.metadata;
  final dynById = {for (final d in score.dynamics) d.elementId: d.level.name};
  final syl = <String, String>{}; // (noteId, verse) → the `**text` token
  for (final l in score.lyrics) {
    syl['${l.elementId}#${l.verse}'] = l.hyphenToNext ? '${l.text}-' : l.text;
  }
  final extraCount = (hasDyn ? 1 : 0) + verseCount;
  // A row whose extra spines all carry the same filler (interps `*`, a shared
  // barline token, terminators `*-`).
  String across(String kern, String filler) =>
      '$kern${'\t$filler' * extraCount}';
  // A note row: its dynamic (if any) then its syllable per verse, else `.`.
  String dataRow(String kern, String? id) {
    final cols = [
      kern,
      if (hasDyn) (id == null ? '.' : dynById[id] ?? '.'),
      for (var v = 1; v <= verseCount; v++)
        (id == null ? '.' : syl['$id#$v'] ?? '.'),
    ];
    return cols.join('\t');
  }

  lines.add([
    '**kern',
    if (hasDyn) '**dynam',
    for (var v = 0; v < verseCount; v++) '**text',
  ].join('\t'));
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
    lines.addAll(_marksFor(measure, extraCount));
    for (var i = 0; i < measure.elements.length; i++) {
      final element = measure.elements[i];
      if (element is NoteElement && element.graceNotes.isNotEmpty) {
        final mark = element.graceStyle == GraceStyle.appoggiatura ? 'qq' : 'q';
        for (final pitch in element.graceNotes) {
          lines.add(dataRow('8${_kernPitch(pitch, null)}$mark', null));
        }
      }
      final tok = _token(element, prevTie, _tupletRatioAt(measure, i),
          slurStart: element.id != null && slurStarts.contains(element.id),
          slurEnd: element.id != null && slurEnds.contains(element.id));
      lines.add(dataRow(tok, element is NoteElement ? element.id : null));
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
List<String> _multiVoiceRows(Measure measure, int voiceCount,
    Set<String> slurStarts, Set<String> slurEnds) {
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

  // Fill an absent sub-spine with rests aligned to voice 1's rhythm, matching
  // its (tuplet-scaled) reciprocals so the sub-spines stay consistent.
  List<({Fraction at, String tok})> restFill() {
    var t = Fraction(0, 1);
    final filled = <({Fraction at, String tok})>[];
    for (var i = 0; i < measure.elements.length; i++) {
      filled.add((
        at: t,
        tok: '${_durString(measure.elements[i].duration, ratioAt(0, i))}r',
      ));
      t = t + measure.effectiveDurationAt(i);
    }
    return filled;
  }

  // One event list per sub-spine (voice), rest-filling voices absent here.
  final voices = <List<({Fraction at, String tok})>>[];
  for (var vi = 0; vi < voiceCount; vi++) {
    final v = measure.voiceAt(vi);
    voices.add(vi > 0 && v.isEmpty ? restFill() : events(vi));
  }

  // Merged, sorted set of onsets across every voice; each row is one token per
  // sub-spine (`.` where a voice has no event at that onset).
  final onsets = <Fraction>{
    for (final v in voices)
      for (final e in v) e.at,
  }.toList()
    ..sort((a, b) => (a - b).numerator.sign);
  return [
    for (final t in onsets)
      voices
          .map((v) => v
              .firstWhere((e) => e.at == t, orElse: () => (at: t, tok: '.'))
              .tok)
          .join('\t'),
  ];
}

/// A part's voice-1 events for one [measure] as `(onset, token)` pairs plus the
/// tie state to carry into the next measure. Onsets are tuplet-scaled so a
/// triplet stays aligned across the merged spines.
(List<({Fraction at, String tok})>, bool) _kernEvents(Measure measure,
    bool tiedFromPrev, Set<String> slurStarts, Set<String> slurEnds) {
  var t = Fraction(0, 1);
  var prevTie = tiedFromPrev;
  final out = <({Fraction at, String tok})>[];
  for (var i = 0; i < measure.elements.length; i++) {
    final e = measure.elements[i];
    out.add((
      at: t,
      tok: _token(e, prevTie, _tupletRatioAt(measure, i),
          slurStart: e.id != null && slurStarts.contains(e.id),
          slurEnd: e.id != null && slurEnds.contains(e.id)),
    ));
    t = t + measure.effectiveDurationAt(i);
    prevTie = e is NoteElement && e.tieToNext;
  }
  return (out, prevTie);
}

/// Expands every part that uses voices 2-4 into one single-voice part per voice,
/// so a downstream one-voice-per-part writer keeps all notes. Measure-level
/// signature/repeat/barline changes ride the first flattened voice only.
MultiPartScore _flattenPartVoices(MultiPartScore mp) {
  final flat = <Score>[];
  for (final p in mp.parts) {
    var maxV = 1;
    for (final m in p.measures) {
      if (m.voice4.isNotEmpty) {
        maxV = 4;
        break;
      }
      if (m.voice3.isNotEmpty && maxV < 3) maxV = 3;
      if (m.voice2.isNotEmpty && maxV < 2) maxV = 2;
    }
    if (maxV == 1) {
      flat.add(p);
      continue;
    }
    for (var v = 0; v < maxV; v++) {
      flat.add(Score(
        clef: p.clef,
        keySignature: p.keySignature,
        timeSignature: p.timeSignature,
        tempo: p.tempo,
        metadata: p.metadata,
        measures: [
          for (final m in p.measures)
            Measure(
              m.voiceAt(v),
              clefChange: v == 0 ? m.clefChange : null,
              keyChange: v == 0 ? m.keyChange : null,
              timeChange: v == 0 ? m.timeChange : null,
              startRepeat: v == 0 && m.startRepeat,
              endRepeat: v == 0 && m.endRepeat,
              barline: m.barline,
            ),
        ],
      ));
    }
  }
  return MultiPartScore(flat.isEmpty ? mp.parts : flat);
}

/// A [multiPart] score → a multi-spine `**kern` document: one `**kern` spine per
/// part, the parts' events **time-merged** row by row (a spine sustaining across
/// another's onset gets a null token `.`), so an orchestral score keeps EVERY
/// part (unlike [scoreToKern]'s single spine). Round-trips through
/// `staffSystemFromKern`. Each part keeps its own clef/key; meter, tempo and
/// repeats follow the lead part (they are document-global in this subset).
String multiPartToKern(MultiPartScore multiPart, {List<String>? partNames}) {
  // Each part's row here carries only ONE voice (voice 1) — so a part that uses
  // voices 2-4 (e.g. a Chopin grand-staff hand with divisi) would lose them.
  // Flatten every multi-voice part into one single-voice part per voice first,
  // so the per-part row-merge below keeps EVERY note. (Single-voice parts pass
  // through unchanged; `scoreToKern` already handles the one-part multi-voice
  // case via `*^` splits.)
  multiPart = _flattenPartVoices(multiPart);
  final parts = multiPart.parts;
  if (parts.isEmpty) {
    return scoreToKern(Score(clef: Clef.treble, measures: const []));
  }
  if (parts.length == 1) return scoreToKern(parts.first);

  final n = parts.length;
  final slurStarts = [
    for (final p in parts) {for (final s in p.slurs) s.startId}
  ];
  final slurEnds = [
    for (final p in parts) {for (final s in p.slurs) s.endId}
  ];
  final lead = parts.first;
  final meta = lead.metadata;
  final lines = <String>[];
  for (final (key, value) in [
    ('OTL', meta.title),
    ('COM', meta.composer),
    ('LYR', meta.lyricist),
    ('YEC', meta.copyright),
  ]) {
    if (value != null) lines.add('!!!$key: $value');
  }
  String row(String Function(int p) cell) =>
      [for (var p = 0; p < n; p++) cell(p)].join('\t');
  String nameOf(int p) =>
      (partNames != null && p < partNames.length ? partNames[p] : null) ??
      parts[p].metadata.instrument ??
      'Part ${p + 1}';

  lines.add(row((_) => '**kern'));
  lines.add(row((p) => '*clef${_clefCodes[parts[p].clef]}'));
  if (partNames != null || parts.any((p) => p.metadata.instrument != null)) {
    lines.add(row((p) => '*I"${nameOf(p)}'));
  }
  lines.add(row((p) => '*k[${kernKeyContent(parts[p].keySignature)}]'));
  if (lead.timeSignature != null) {
    for (final l in _meterLines(lead.timeSignature!)) {
      lines.add(row((_) => l));
    }
  }
  final t = lead.tempo;
  if (t != null) {
    final f = NoteDuration(t.beatUnit, dots: t.dots).toFraction();
    final quarters = t.bpm * f.numerator * 4 / f.denominator;
    final s = quarters == quarters.roundToDouble()
        ? quarters.round().toString()
        : quarters.toString();
    lines.add(row((_) => '*MM$s'));
  }

  Measure? measureOf(int p, int m) =>
      m < parts[p].measures.length ? parts[p].measures[m] : null;
  final measureCount =
      parts.map((p) => p.measures.length).reduce((a, b) => a > b ? a : b);
  final endTie = List<bool>.filled(n, false);

  for (var m = 0; m < measureCount; m++) {
    if (m > 0) {
      final bar = _repeatBar(measureOf(0, m - 1)?.endRepeat ?? false,
          measureOf(0, m)?.startRepeat ?? false);
      lines.add(row((_) => bar));
      if (parts
          .any((p) => measureOf(parts.indexOf(p), m)?.clefChange != null)) {
        lines.add(row((p) {
          final c = measureOf(p, m)?.clefChange;
          return c == null ? '*' : '*clef${_clefCodes[c]}';
        }));
      }
      if (parts.any((p) => measureOf(parts.indexOf(p), m)?.keyChange != null)) {
        lines.add(row((p) {
          final k = measureOf(p, m)?.keyChange;
          return k == null ? '*' : '*k[${kernKeyContent(k)}]';
        }));
      }
      final timeChange = measureOf(0, m)?.timeChange;
      if (timeChange != null) {
        for (final l in _meterLines(timeChange)) {
          lines.add(row((_) => l));
        }
      }
    } else if (measureOf(0, 0)?.startRepeat ?? false) {
      lines.add(row((_) => '=!|:'));
    }

    final perPart = <List<({Fraction at, String tok})>>[];
    for (var p = 0; p < n; p++) {
      final measure = measureOf(p, m);
      if (measure == null) {
        perPart.add([(at: Fraction(0, 1), tok: '1r')]);
        endTie[p] = false;
      } else {
        final (evs, tie) =
            _kernEvents(measure, endTie[p], slurStarts[p], slurEnds[p]);
        perPart.add(evs);
        endTie[p] = tie;
      }
    }
    final onsets = <Fraction>{
      for (final evs in perPart)
        for (final e in evs) e.at
    }.toList()
      ..sort((a, b) => (a - b).numerator.sign);
    for (final onset in onsets) {
      lines.add(row((p) => perPart[p]
          .firstWhere((e) => e.at == onset, orElse: () => (at: onset, tok: '.'))
          .tok));
    }
  }

  final lastEnd = lead.measures.isNotEmpty && lead.measures.last.endRepeat;
  final fbar = lastEnd ? '=:|!' : '==';
  lines.add(row((_) => fbar));
  lines.add(row((_) => '*-'));
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
