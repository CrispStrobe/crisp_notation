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
import '../model/slur_levels.dart';
import '../theory/chord_name.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/tempo.dart';
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
  // Humdrum extends the reciprocal series downward with zeros:
  // 0 = breve, 00 = longa.
  DurationBase.long: '00',
  DurationBase.breve: '0',
  DurationBase.whole: '1',
  DurationBase.half: '2',
  DurationBase.quarter: '4',
  DurationBase.eighth: '8',
  DurationBase.sixteenth: '16',
  DurationBase.thirtySecond: '32',
  DurationBase.sixtyFourth: '64',
  // Absent, these fell through to the null-coalescing-free interpolation below
  // and wrote the literal text "null" as the duration.
  DurationBase.oneHundredTwentyEighth: '128',
  DurationBase.twoHundredFiftySixth: '256',
  DurationBase.fiveHundredTwelfth: '512',
  DurationBase.oneThousandTwentyFourth: '1024',
};

/// Metadata flattened to a single line.
///
/// A `!!!` reference record and a `*I"` instrument tag both occupy exactly one
/// line, so an embedded newline does not extend them — it ENDS them and leaves
/// the remaining text sitting in the spine, where the reader parses it as
/// music. A CPDL source whose LYR field ran over four lines put a bare `C1` in
/// the data column, and it read back as a phantom C3 whole note ahead of the
/// first real one. Corpus metadata carries line breaks routinely.
/// Flattens a value onto ONE line, without touching its spacing.
///
/// ⚠️ Only the characters that would BREAK the format are replaced: a newline
/// ends a `!!!` record and a tab separates spines, so both must go. A run of
/// ordinary SPACES is content — hymn texts are full of them for alignment —
/// and collapsing it was silent corruption of every third-party lyric line.
String _oneLine(String value) =>
    value.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();

/// [value] made safe as a DATA token in a spine.
///
/// Humdrum decides a record's kind from its first character: `*` is an
/// interpretation, `!` a comment, `=` a barline. A syllable starting with one
/// does not merely get lost — it changes the row's meaning, and `*-` in
/// particular TERMINATES the spine mid-data, so the file stops being valid
/// Humdrum at all. A leading backslash keeps it a data token; the reader strips
/// it back off.
String _spineToken(String value) =>
    value.isNotEmpty && '*!='.contains(value[0]) ? '\\$value' : value;

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

/// The slur markers each element id carries, as kern's `(`/`)` with one `&`
/// per nesting level (`&(`, `&&(` …). See [slurLevels] for why levels exist.
({Map<String, String> opens, Map<String, String> closes}) _slurMarks(
    Score score) {
  final levels = slurLevels(score);
  final opens = <String, String>{};
  final closes = <String, String>{};
  for (var i = 0; i < score.slurs.length; i++) {
    final s = score.slurs[i];
    final mark = '&' * levels[i];
    opens[s.startId] = '${opens[s.startId] ?? ''}$mark(';
    closes[s.endId] = '${closes[s.endId] ?? ''}$mark)';
  }
  return (opens: opens, closes: closes);
}

/// Serializes [score] as a single-spine `**kern` document.
String scoreToKern(Score score) {
  final meta = score.metadata;
  final marks = _slurMarks(score);
  final slurStarts = marks.opens;
  final slurEnds = marks.closes;
  final lines = <String>[];
  // Bibliographic reference records precede the spine.
  for (final (key, value) in [
    ('OTL', meta.title),
    ('COM', meta.composer),
    ('LYR', meta.lyricist),
    ('YEC', meta.copyright),
  ]) {
    if (value != null) lines.add('!!!$key: ${_oneLine(value)}');
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
  final hasChords = score.chordSymbols.isNotEmpty;
  final hasFigures = score.figuredBass.isNotEmpty;
  if ((verseCount > 0 || hasDyn || hasChords || hasFigures) && !multiVoice) {
    return _kernWithExtraSpines(lines, score, verseCount, hasDyn, hasChords,
        hasFigures, slurStarts, slurEnds);
  }

  lines.add('**kern');
  lines.add('*clef${_clefCodes[score.clef]}');
  if (meta.instrument != null) lines.add('*I"${_oneLine(meta.instrument!)}');
  lines.add('*k[${kernKeyContent(score.keySignature)}]');
  if (score.timeSignature != null) {
    lines.addAll(_meterLines(score.timeSignature!));
  }
  if (score.tempo != null) lines.add(_mmLine(score.tempo!));
  // Text marks ride LOCAL COMMENTS (`!text`), which Humdrum attaches to the
  // next data record in that spine — so kern needs no extra spine for them.
  // It was the only codec of six carrying no annotations at all.
  final annById = _annotationsById(score);

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
        final bar = _repeatBar(score.measures[m - 1].endRepeat,
            measure.startRepeat, score.measures[m - 1].barline);
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
    lines.add(dup(lastEnd ? '=:|!' : _closingBar(score)));
    lines.add(dup('*v')); // merge the sub-spines back into one
    lines.add('*-');
    return '${lines.join('\n')}\n';
  }

  // Element-level ties need to know the previous note's tie state.
  var prevTie = false;
  for (var m = 0; m < score.measures.length; m++) {
    final measure = score.measures[m];
    if (m > 0) {
      lines.add(_repeatBar(score.measures[m - 1].endRepeat, measure.startRepeat,
          score.measures[m - 1].barline));
      if (measure.clefChange != null) {
        lines.add('*clef${_clefCodes[measure.clefChange!]}');
      }
      if (measure.keyChange != null) {
        lines.add('*k[${kernKeyContent(measure.keyChange!)}]');
      }
      if (measure.timeChange != null) {
        lines.addAll(_meterLines(measure.timeChange!));
      }
      // A mid-score tempo change is another `*MM` interpretation, exactly like
      // the initial one — only the score-level tempo was ever written.
      if (measure.tempoChange != null) lines.add(_mmLine(measure.tempoChange!));
    } else if (measure.startRepeat) {
      lines.add('=!|:'); // a repeat that starts at the very beginning
    }
    lines.addAll(_marksFor(measure, 0));
    // A MID-BAR clef is a `*clefX` interpretation at its own onset, not one at
    // the barline — kern places it between data records like any other.
    var elapsedAt = Fraction.zero;
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
      for (final ic in measure.inlineClefs) {
        if (ic.onset == elapsedAt) {
          lines.add('*clef${_clefCodes[ic.clef]}');
        }
      }
      elapsedAt = elapsedAt + element.duration.toFraction();
      for (final text in annById[element.id] ?? const <String>[]) {
        lines.add(_localComment(text));
      }
      lines.add(_token(element, prevTie, _tupletRatioAt(measure, i),
          slurStart: slurStarts[element.id] ?? '',
          slurEnd: slurEnds[element.id] ?? ''));
      prevTie = element is NoteElement && element.tieToNext;
    }
  }

  lines.add(score.measures.isNotEmpty && score.measures.last.endRepeat
      ? '=:|!'
      : _closingBar(score));
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
String _repeatBar(bool endPrev, bool startCur,
        [BarlineStyle style = BarlineStyle.normal]) =>
    endPrev && startCur
        ? '=:|!|:'
        : endPrev
            ? '=:|!'
            : startCur
                ? '=!|:'
                // A repeat token wins the slot: it says more than the style,
                // and kern has one token for both.
                : (_kernBarline[style] ?? '=');

/// Single-voice `**kern` paired with optional parallel spines: a `**dynam`
/// spine when [hasDyn], then [verseCount] `**text` spines for lyric verses.
/// [lines] already holds the leading `!!!` reference records. A syllable that
/// continues its word (hyphenToNext) is written with a trailing `-`; a note
/// with no marking in a spine gets a null token (`.`).
String _kernWithExtraSpines(
    List<String> lines,
    Score score,
    int verseCount,
    bool hasDyn,
    bool hasChords,
    bool hasFigures,
    Map<String, String> slurStarts,
    Map<String, String> slurEnds) {
  final meta = score.metadata;
  final dynById = {for (final d in score.dynamics) d.elementId: d.level.name};
  // Harmony rides a `**mxhm` spine, Humdrum's MusicXML-harmony representation.
  // Its tokens are chord LABELS, so they go out through the shared canonical
  // formatter — the same text ABC and MEI carry.
  final chordById = {
    for (final c in score.chordSymbols) c.elementId: _spineToken(chordName(c)),
  };
  // Figured bass rides a `**fb` spine — Humdrum's thoroughbass representation.
  // Its token stacks the figures of one bass note on a space.
  final figuresById = {
    for (final f in score.figuredBass)
      f.noteId: _spineToken(f.figures.join(' ')),
  };
  final annById = _annotationsById(score);
  final syl = <String, String>{}; // (noteId, verse) → the `**text` token
  for (final l in score.lyrics) {
    // A `**text` token occupies one TAB-separated cell on one line, so a
    // syllable carrying a newline or a tab does not extend it — it ends the row
    // and the remainder is read as a new one, i.e. as MUSIC. Same constraint as
    // the `!!!` records above, and `*-` inside a syllable would close the spine
    // outright; `_oneLine` flattens the whitespace that carries it there.
    final text = _spineToken(_oneLine(l.text));
    syl['${l.elementId}#${l.verse}'] =
        l.hyphenToNext ? '$text-' : (text.isEmpty ? '.' : text);
  }
  final extraCount = (hasChords ? 1 : 0) +
      (hasFigures ? 1 : 0) +
      (hasDyn ? 1 : 0) +
      verseCount;
  // A row whose extra spines all carry the same filler (interps `*`, a shared
  // barline token, terminators `*-`).
  String across(String kern, String filler) =>
      '$kern${'\t$filler' * extraCount}';
  // A note row: its dynamic (if any) then its syllable per verse, else `.`.
  String dataRow(String kern, String? id) {
    final cols = [
      kern,
      if (hasChords) (id == null ? '.' : chordById[id] ?? '.'),
      if (hasFigures) (id == null ? '.' : figuresById[id] ?? '.'),
      if (hasDyn) (id == null ? '.' : dynById[id] ?? '.'),
      for (var v = 1; v <= verseCount; v++)
        (id == null ? '.' : syl['$id#$v'] ?? '.'),
    ];
    return cols.join('\t');
  }

  lines.add([
    '**kern',
    if (hasChords) '**mxhm',
    if (hasFigures) '**fb',
    if (hasDyn) '**dynam',
    for (var v = 0; v < verseCount; v++) '**text',
  ].join('\t'));
  lines.add(across('*clef${_clefCodes[score.clef]}', '*'));
  if (meta.instrument != null) {
    lines.add(across('*I"${_oneLine(meta.instrument!)}', '*'));
  }
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
      final bar = _repeatBar(score.measures[m - 1].endRepeat,
          measure.startRepeat, score.measures[m - 1].barline);
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
      if (measure.tempoChange != null) {
        lines.add(across(_mmLine(measure.tempoChange!), '*'));
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
          slurStart: slurStarts[element.id] ?? '',
          slurEnd: slurEnds[element.id] ?? '');
      // A local comment line carries the SAME token in every spine — it is a
      // full record, not a cell — so the parallel spines get `!` too.
      for (final text in annById[element.id] ?? const <String>[]) {
        lines.add(across(_localComment(text), '!'));
      }
      lines.add(dataRow(tok, element is NoteElement ? element.id : null));
      prevTie = element is NoteElement && element.tieToNext;
    }
  }
  final lastEnd = score.measures.isNotEmpty && score.measures.last.endRepeat;
  final fbar = lastEnd ? '=:|!' : _closingBar(score);
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
    Map<String, String> slurStarts, Map<String, String> slurEnds) {
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
            slurStart: slurStarts[e.id] ?? '', slurEnd: slurEnds[e.id] ?? '')
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
(List<({Fraction at, String tok})>, bool) _kernEvents(
    Measure measure,
    bool tiedFromPrev,
    Map<String, String> slurStarts,
    Map<String, String> slurEnds) {
  var t = Fraction(0, 1);
  var prevTie = tiedFromPrev;
  final out = <({Fraction at, String tok})>[];
  for (var i = 0; i < measure.elements.length; i++) {
    final e = measure.elements[i];
    out.add((
      at: t,
      tok: _token(e, prevTie, _tupletRatioAt(measure, i),
          slurStart: slurStarts[e.id] ?? '', slurEnd: slurEnds[e.id] ?? ''),
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
  // Levels are assigned PER PART: each part is its own spine, so its slurs
  // only ever have to be distinguishable from that part's others.
  final partMarks = [for (final p in parts) _slurMarks(p)];
  final slurStarts = [for (final m in partMarks) m.opens];
  final slurEnds = [for (final m in partMarks) m.closes];
  final lead = parts.first;
  final meta = lead.metadata;
  final lines = <String>[];
  for (final (key, value) in [
    ('OTL', meta.title),
    ('COM', meta.composer),
    ('LYR', meta.lyricist),
    ('YEC', meta.copyright),
  ]) {
    if (value != null) lines.add('!!!$key: ${_oneLine(value)}');
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
    lines.add(row((p) => '*I"${_oneLine(nameOf(p))}'));
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
  final fbar = lastEnd ? '=:|!' : _closingBar(lead);
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

/// The tuplet ratio covering element [i] of voice 1 of [measure], or null.
///
/// This is the single-voice path (the one that pairs `**dynam`/`**text`
/// spines), so only voice 1's spans apply; an inner voice's span addresses a
/// different element list and would re-time the wrong notes.
({int actual, int normal})? _tupletRatioAt(Measure measure, int i) {
  for (final t in measure.tupletsForVoice(0)) {
    if (i >= t.startIndex && i <= t.endIndex) {
      return (actual: t.actual, normal: t.normal);
    }
  }
  return null;
}

/// The kern reciprocal for [dur], scaled to the tuplet [ratio] when present.
///
/// `**kern` records only how long a note SOUNDS — there is no tuplet bracket in
/// the format — so this writes the sounding duration exactly and lets the reader
/// re-derive a bracket from it. A written value with reciprocal `w` in an
/// `actual:normal` tuplet sounds `normal/actual` of `w`, so a quarter (`4`) in a
/// 3:2 triplet is `6`.
///
/// It used to fall back to the PLAIN reciprocal whenever that scaling was not an
/// integer, which silently discarded the tuplet and changed the music: a 2:3
/// duplet quarter sounds 3/8 of a whole and was written `4`, i.e. 1/4. Two
/// exact forms cover every case:
///  * a dotted note value, which is what a duplet or quadruplet actually is
///    (2:3 quarter = `4.`, 4:3 quarter = `8.`) — and the conventional spelling;
///  * Humdrum's rational reciprocal `N%M`, a duration of `M/N` whole notes, for
///    ratios no dotted value reaches (7:8 quarter = 2/7 of a whole = `7%2`).
String _durString(NoteDuration dur, ({int actual, int normal})? ratio) {
  var sounding = dur.toFraction();
  if (ratio != null && ratio.actual > 0) {
    sounding = Fraction(
      sounding.numerator * ratio.normal,
      sounding.denominator * ratio.actual,
    );
  }
  // Prefer a plain or dotted note value whenever one sounds exactly this long.
  // Dots first so 3/8 comes out as the conventional `4.` and not `8%3`.
  for (var dots = 0; dots <= 2; dots++) {
    for (final entry in _durRecip.entries) {
      if (NoteDuration(entry.key, dots: dots)
              .toFraction()
              .compareTo(sounding) ==
          0) {
        return '${entry.value}${'.' * dots}';
      }
    }
  }
  if (sounding.numerator == 1) return '${sounding.denominator}';
  return '${sounding.denominator}%${sounding.numerator}';
}

String _token(
    MusicElement element, bool tiedFromPrev, ({int actual, int normal})? ratio,
    {String slurStart = '', String slurEnd = ''}) {
  final durStr = _durString(element.duration, ratio);
  // Kern's convention: `(` prefixes the token, `)` suffixes it. A note that
  // both closes and opens is `(4c)`, which is unambiguous because the reader
  // takes every CLOSE in a token before any OPEN.
  final slurOpen = slurStart;
  final slurClose = slurEnd;
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
  // Humdrum signifiers verified against the corpus, not assumed: a backtick is
  // staccatissimo (20 of 800 sampled `.krn`) and a comma a breath mark (469).
  // `^^` is already marcato here, so it was not available.
  if (a.contains(Articulation.staccatissimo)) b.write('`');
  if (a.contains(Articulation.breath)) b.write(',');
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

/// The model's barline styles as kern tokens. Only the three Humdrum actually
/// spells get one; the rest fall back to a plain `=` rather than inventing a
/// token no other tool would read.
const Map<BarlineStyle, String?> _kernBarline = {
  BarlineStyle.doubleBar: '=||',
  BarlineStyle.finalBar: '==',
  BarlineStyle.none: '=-',
};

/// The token closing the last measure.
///
/// ⚠️ This used to be a hard-coded `==` on every export — Humdrum's convention,
/// since a piece conventionally ends with a final barline. But `==` IS a final
/// barline, so reading it back set `finalBar` on scores that never had one, and
/// `normal` in came out `finalBar`. The model decides it now; `=` is a perfectly
/// ordinary way for a kern file to end.
String _closingBar(Score score) =>
    _kernBarline[score.measures.isEmpty
        ? BarlineStyle.normal
        : score.measures.last.barline] ??
    '=';

/// A kern `*MM` line for [t]. `*MM` is QUARTER-notes per minute, so a dotted or
/// non-quarter beat unit is normalised rather than written as-is.
String _mmLine(Tempo t) {
  final q = t.quarterBpm;
  return '*MM${q == q.roundToDouble() ? q.round() : q}';
}

/// A score's annotations grouped by the element they sit on.
///
/// A note may carry SEVERAL, so this is a list per id — the same lesson the
/// ABC writer learned when a note with both a tempo mark and a direction on it
/// kept only the last.
/// A text mark as a Humdrum local comment.
///
/// ⚠️ A SPACE after the `!` when the text would otherwise read as a structured
/// directive (`Note: play softly` looks exactly like `!LO:`). No real directive
/// carries one, so the space is what tells the two apart on the way back.
String _localComment(String text) {
  final flat = _oneLine(text);
  return RegExp(r'^[A-Za-z]{1,8}:').hasMatch(flat) ? '! $flat' : '!$flat';
}

Map<String?, List<String>> _annotationsById(Score score) {
  final out = <String?, List<String>>{};
  for (final a in score.annotations) {
    (out[a.elementId] ??= []).add(a.text);
  }
  return out;
}
