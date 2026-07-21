/// Plain-text ("ASCII") guitar/bass tablature import → [Score].
///
/// ASCII tab is the informal notation shared on the web for decades: N string
/// lines of dashes with fret numbers, e.g.
///
/// ```text
/// e|-----0-----|
/// B|---1-------|
/// G|-0-----2h4-|
/// D|-----------|
/// A|-----------|
/// E|-----------|
/// ```
///
/// It has **no formal spec and no reliable rhythm** — horizontal spacing is
/// cosmetic — so this is a lossy reconstruction: every event gets the same
/// [duration], barlines come from `|` columns, and pitches are recovered from
/// each `(string, fret)` via the [Tuning]. Recognized techniques: `h`/`p`
/// (hammer-on / pull-off → a slur), `/`/`\` (slide → a glissando), `b` (bend),
/// `~` (vibrato) and `x` (dead/muted note); they apply to single-note events.
/// The result is a normal pitched [Score] — render it as notation or, with the
/// same tuning, as tab (which uses canonical lowest-fret placement, so an
/// unusual voicing may relocate).
library;

import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/pitch.dart';
import '../theory/tuning.dart';

/// A fret token on one string line: its column, fret value (`null` = a dead
/// `x`), and the technique character immediately after it (or `null`).
class _Tok {
  final int col;
  final int? fret;
  final String? suffix;
  _Tok(this.col, this.fret, this.suffix);
}

/// One time-column event: the tokens sharing a start column, per string.
class _Event {
  final int col;
  final tokens = <int, _Tok>{}; // stringIndex -> token
  _Event(this.col);
}

/// Parses plain-text tablature [text] into a [Score] for [tuning]
/// (default [Tuning.standardGuitar]).
///
/// By default every event takes [duration] (default an eighth). With
/// [inferRhythm] the durations are instead *interpreted from the horizontal
/// spacing* — the smallest gap between successive events is taken as an eighth
/// and wider gaps scale up (2× → quarter, 3× → dotted quarter, 4× → half, …).
/// This is a heuristic reading of well-spaced tabs; badly spaced tabs give
/// arbitrary rhythm. See the library doc for the techniques and lossiness.
/// Returns a single-measure whole-rest score if no tab lines are found.
Score asciiTabToScore(
  String text, {
  Tuning? tuning,
  NoteDuration duration = NoteDuration.eighth,
  bool inferRhythm = false,
  bool applyStatedCapo = false,
}) {
  final lines = text.split(RegExp(r'\r?\n'));
  // ClassTab writes frets RELATIVE to the capo and states it in prose ("capo on
  // the 2nd fret"); the sounding pitch is open + capo + fret. This is OFF by
  // default — the tab's own MIDIs are inconsistent about whether they bake the
  // capo in, so applying it is a caller choice (sounding vs written pitch), not
  // a fix. When on, the written (string, fret) still stays capo-relative.
  final capo = applyStatedCapo ? _capoFromText(lines) : 0;
  // When the caller doesn't force a tuning, read it from the tab itself instead
  // of blindly assuming 6-string standard. The string LABELS (`e B G D A E`)
  // name the tuning — matching them against a known tuning fixes silent pitch
  // corruption (a Drop-D tab read as standard is two semitones flat on the low
  // string). Falling back on the string COUNT stops a 4-line bass tab parsing
  // to nothing, or a 7-string tab dropping its 7th string.
  final tune = tuning ??
      _tuningFromMetadata(lines) ??
      _tuningFromLabels(_labelLetters(lines)) ??
      _defaultForCount(_firstBlockCount(lines)) ??
      Tuning.standardGuitar;
  final n = tune.stringCount;
  final blocks = _blocks(lines, n);

  // Flatten the stacked blocks into one left-to-right event stream, keeping a
  // global column so spacing (and barlines) read continuously across wraps.
  final events = <_Event>[];
  final barCols = <int>[];
  var blockOffset = 0;
  for (final block in blocks) {
    final width =
        block.fold<int>(0, (w, line) => line.length > w ? line.length : w);
    for (final event in _events(block, n)) {
      events.add(_Event(blockOffset + event.col)..tokens.addAll(event.tokens));
    }
    for (final bc in _barlineColumns(block, n)) {
      barCols.add(blockOffset + bc);
    }
    blockOffset += width + 1;
  }
  events.sort((a, b) => a.col.compareTo(b.col));
  barCols.sort();

  final durations = inferRhythm
      ? _inferDurations(events)
      : List.filled(events.length, duration);

  final measures = <Measure>[];
  final slurs = <Slur>[];
  final glissandos = <Glissando>[];
  final bends = <Bend>[];
  final vibratos = <Vibrato>[];
  final deadNotes = <TabNoteMark>[];
  final voicings = <TabVoicing>[];

  var current = <MusicElement>[];
  var id = 0;
  // Per string: the id of the previous single-note event, and its pending
  // technique linking it to the next note on that string.
  final prevIdOnString = List<String?>.filled(n, null);
  final pendingLink = List<String?>.filled(n, null);
  var barPtr = 0;

  void closeMeasure() {
    if (current.isNotEmpty) {
      measures.add(Measure(current));
      current = <MusicElement>[];
    }
  }

  for (var e = 0; e < events.length; e++) {
    final event = events[e];
    while (barPtr < barCols.length && barCols[barPtr] <= event.col) {
      closeMeasure();
      barPtr++;
    }

    // Collect (pitch, string) so the note renders on the written strings.
    final placed = <(Pitch, int)>[];
    final singleString = event.tokens.length == 1;
    int? soloString;
    var soloDead = false;
    event.tokens.forEach((stringIndex, tok) {
      final open = tune.strings[stringIndex];
      final fret = tok.fret ?? 0; // a dead note sits at the open string
      placed.add((_pitchFromMidi(open.midiNumber + fret + capo), stringIndex));
      if (singleString) {
        soloString = stringIndex;
        soloDead = tok.fret == null;
      }
    });
    if (placed.isEmpty) continue;
    placed.sort((a, b) => a.$1.midiNumber.compareTo(b.$1.midiNumber));
    final pitches = [for (final p in placed) p.$1];

    final noteId = 'e$id';
    id++;
    current
        .add(NoteElement(pitches: pitches, duration: durations[e], id: noteId));
    voicings.add(TabVoicing(noteId, [for (final p in placed) p.$2]));
    if (soloDead) deadNotes.add(TabNoteMark(noteId, TabNoteStyle.dead));

    // Resolve a pending same-string technique from the previous note.
    event.tokens.forEach((stringIndex, tok) {
      final link = pendingLink[stringIndex];
      final from = prevIdOnString[stringIndex];
      if (link != null && from != null) {
        switch (link) {
          case 'h':
          case 'p':
            slurs.add(Slur(from, noteId));
          case '/':
          case r'\':
            glissandos.add(Glissando(from, noteId));
        }
      }
      pendingLink[stringIndex] = null;
    });

    // Record this note's own suffix technique for the single-note case.
    if (singleString && soloString != null) {
      final suffix = event.tokens[soloString!]!.suffix;
      switch (suffix) {
        case 'b':
          bends.add(Bend(noteId));
        case '~':
          vibratos.add(Vibrato(noteId));
        case 'h':
        case 'p':
        case '/':
        case r'\':
          pendingLink[soloString!] = suffix;
      }
      prevIdOnString[soloString!] = noteId;
    } else {
      // A chord breaks per-string technique chains.
      for (var s = 0; s < n; s++) {
        if (event.tokens.containsKey(s)) prevIdOnString[s] = null;
      }
    }
  }
  closeMeasure();

  if (measures.isEmpty) {
    measures.add(Measure([RestElement(NoteDuration.whole, id: 'e0')]));
  }

  return Score(
    clef: Clef.treble,
    measures: measures,
    slurs: slurs,
    glissandos: glissandos,
    bends: bends,
    vibratos: vibratos,
    tabNoteMarks: deadNotes,
    tabVoicings: voicings,
  );
}

/// Interprets note durations from the horizontal spacing of [events]: the
/// smallest inter-event gap is an eighth, and each wider gap scales from
/// there, snapping to the nearest plain-or-dotted note value.
List<NoteDuration> _inferDurations(List<_Event> events) {
  if (events.length <= 1) {
    return List.filled(events.length, NoteDuration.eighth);
  }
  final gaps = <int>[
    for (var i = 0; i + 1 < events.length; i++)
      events[i + 1].col - events[i].col,
  ];
  final base =
      gaps.where((g) => g > 0).fold<int>(gaps.first, (m, g) => g < m ? g : m);
  final unit = base < 1 ? 1 : base;
  gaps.add(gaps.last); // the final note reuses the previous gap
  return [for (final g in gaps) _durationForEighths((g / unit).round())];
}

/// A note value [eighths] eighth-notes long, snapped down to the nearest
/// plain-or-dotted value (1 = eighth … 8 = whole).
NoteDuration _durationForEighths(int eighths) {
  if (eighths >= 8) return NoteDuration.whole;
  if (eighths >= 6) return const NoteDuration(DurationBase.half, dots: 1);
  if (eighths >= 4) return NoteDuration.half;
  if (eighths >= 3) return const NoteDuration(DurationBase.quarter, dots: 1);
  if (eighths >= 2) return NoteDuration.quarter;
  return NoteDuration.eighth;
}

/// Groups tab lines into blocks of [n] consecutive string lines.
List<List<String>> _blocks(List<String> lines, int n) {
  final result = <List<String>>[];
  var run = <String>[];
  void flush() {
    for (var i = 0; i + n <= run.length; i += n) {
      result.add(run.sublist(i, i + n).map(_stripLabel).toList());
    }
    run = <String>[];
  }

  for (final line in lines) {
    if (_isTabLine(line)) {
      run.add(line);
    } else {
      flush();
    }
  }
  flush();
  return result;
}

/// Known tunings to match ASCII-tab string labels against. Their letter
/// sequences are distinct, so a match is unambiguous — and using the matched
/// tuning supplies the octaves that bare labels omit.
final _knownTunings = <Tuning>[
  Tuning.standardGuitar,
  Tuning.dropDGuitar,
  Tuning.dadgadGuitar,
  Tuning.openGGuitar,
  Tuning.sevenStringGuitar,
  Tuning.eightStringGuitar,
  Tuning.standardBass,
  Tuning.fiveStringBass,
  Tuning.banjoOpenG,
  Tuning.ukulele,
  Tuning.mandolin,
];

/// A tuning-string's note letter + accidental, no octave (`E`, `A#`, `Eb`) —
/// the form an ASCII-tab label is written in.
String _pitchLetter(Pitch p) {
  final acc = p.alter > 0 ? '#' : (p.alter < 0 ? 'b' : '');
  return '${p.step.name.toUpperCase()}$acc';
}

/// The leading note letters of the first block of tab lines, top string first
/// (`['E','B','G','D','A','E']`), or empty if the lines carry no letter labels.
List<String> _labelLetters(List<String> lines) {
  final labels = <String>[];
  for (final line in lines) {
    if (!_isTabLine(line)) {
      if (labels.isNotEmpty) break; // past the first block
      continue;
    }
    final m = RegExp(r'^[ \t]*([A-Ga-g])([#b]?)').firstMatch(line);
    if (m == null) return const []; // an unlabelled tab line — can't infer
    labels.add('${m.group(1)!.toUpperCase()}${m.group(2)}');
  }
  return labels;
}

/// The capo position stated in prose (`capo on the 2nd fret`, `capo 3`,
/// `capo: 5`), or 0. A `no capo` / `without capo` line is skipped so it does
/// not match a stray number. Clamped to a sane 1-12.
int _capoFromText(List<String> lines) {
  for (final line in lines) {
    final low = line.toLowerCase();
    if (low.contains('no capo') ||
        low.contains('without capo') ||
        low.contains('capo not')) {
      continue;
    }
    final m =
        RegExp(r'capo\s*:?\s*(?:on\s+)?(?:the\s+)?(\d{1,2})').firstMatch(low);
    if (m != null) {
      final v = int.parse(m.group(1)!);
      if (v >= 1 && v <= 12) return v;
    }
  }
  return 0;
}

/// A tuning read from an explicit `tuning: …` metadata line (`tuning: DADGBE`,
/// `tuning: D A D G B E`, `standard tuning: E A D G B E`). This is authoritative
/// where the visual string LABELS are not: a Drop-D tab often labels its low
/// string by its nominal name `E` while the tuning line correctly says `D`.
///
/// Tuning lines are written low string → high; our tunings list high → low, so
/// the note sequence is reversed before matching against the known tunings.
Tuning? _tuningFromMetadata(List<String> lines) {
  for (final line in lines) {
    // Accept `tuning:`, `tuning -`, or `tuning ` — the separator varies.
    final m = RegExp(r'tuning\s*[-:]?\s*([A-Ga-g][#b]?(?:[ A-Ga-g#b]*))',
            caseSensitive: false)
        .firstMatch(line);
    if (m == null) continue;
    final notes = [
      for (final x in RegExp(r'[A-Ga-g][#b]?').allMatches(m.group(1)!))
        '${x.group(0)![0].toUpperCase()}${x.group(0)!.substring(1)}',
    ];
    if (notes.length < 4 || notes.length > 12) continue;
    // A known named tuning gives exact octaves; otherwise build the tuning from
    // the note names (a scordatura like `E A D F# B E` that no named tuning
    // matches) by stacking octaves upward from the lowest string.
    final labels = notes.reversed.toList();
    final t = _tuningFromLabels(labels) ?? _buildTuning(notes);
    if (t != null) return t;
  }
  return null;
}

/// Pitch class (0–11) of a note name like `E`, `F#`, `Bb`, or null.
int? _noteToPc(String note) {
  const base = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  final pc = base[note[0].toUpperCase()];
  if (pc == null) return null;
  final acc = note.length > 1 ? note[1] : '';
  return ((pc + (acc == '#' ? 1 : (acc == 'b' ? -1 : 0))) % 12 + 12) % 12;
}

/// Builds a tuning from note names given LOW string → high, by anchoring the
/// lowest string in the guitar low-string octave (~octave 2) and stacking each
/// higher string to the nearest same-named pitch above the previous. Returns a
/// high-string-first [Tuning], or null on an unparseable name.
Tuning? _buildTuning(List<String> notesLowToHigh) {
  final midis = <int>[];
  int? prev;
  for (final note in notesLowToHigh) {
    final pc = _noteToPc(note);
    if (pc == null) return null;
    int midi;
    if (prev == null) {
      midi = 36 + pc; // octave 2 (C2 = 36); E2 = 40, D2 = 38
    } else {
      midi = prev + ((pc - prev % 12) % 12 + 12) % 12;
      if (midi <= prev) midi += 12; // strictly ascending strings
    }
    midis.add(midi);
    prev = midi;
  }
  return Tuning([for (final m in midis.reversed) _pitchFromMidi(m)]);
}

/// The known tuning whose string letters match [labels] exactly, or null.
Tuning? _tuningFromLabels(List<String> labels) {
  if (labels.isEmpty) return null;
  for (final t in _knownTunings) {
    if (t.strings.length != labels.length) continue;
    var match = true;
    for (var i = 0; i < labels.length; i++) {
      if (_pitchLetter(t.strings[i]) != labels[i]) {
        match = false;
        break;
      }
    }
    if (match) return t;
  }
  return null;
}

/// The count of tab lines in the first contiguous block.
int _firstBlockCount(List<String> lines) {
  var count = 0;
  for (final line in lines) {
    if (_isTabLine(line)) {
      count++;
    } else if (count > 0) {
      break;
    }
  }
  return count;
}

/// A default tuning for a bare string [count] when the labels named no known
/// tuning — so an unlabelled 4/7/8-line tab still parses at the right width.
Tuning? _defaultForCount(int count) => switch (count) {
      4 => Tuning.standardBass,
      6 => Tuning.standardGuitar,
      7 => Tuning.sevenStringGuitar,
      8 => Tuning.eightStringGuitar,
      _ => null,
    };

/// Whether [line] looks like a tab string line: after its label, it is made
/// only of tab characters (dashes, frets, techniques, barlines) and has at
/// least two dashes — enough to reject ordinary prose.
bool _isTabLine(String line) {
  final body = _stripLabel(line);
  // `=` is a held-note sustain line — horizontal fill just like `-`. Count them
  // together, or a string line that is mostly one sustained note (`-0=====…`,
  // a single dash) is wrongly rejected, which breaks the block: the six strings
  // split into four, and the tuning is then mis-inferred (a guitar read as a
  // bass, an octave low).
  final fill = RegExp('[-=]').allMatches(body).length;
  if (fill < 2) return false;
  // A bar-number / rhythm-reference row (`25 |-3-| |-3-|`, `0 |----|----|`)
  // is dash-dominated and so would pass as a tab line, then get grouped in with
  // the six string lines — throwing off the block alignment and reading the bar
  // number "55" as fret 55 (an impossible pitch). A genuine string line begins
  // with a dash, a `|`, or a fret digit run followed by more tab content; it
  // never begins with a number followed by WHITESPACE. That leading
  // "number then space" is the reliable tell of a counting row.
  if (RegExp(r'^\s*\d+[ \t]').hasMatch(body)) return false;
  // A real tab line is DASH-DOMINATED; prose is letter-dominated. Rather than
  // demand every character be on an allowlist — which let a single stray marker
  // (a let-ring `L`, an inline annotation) reject the whole line and drop the
  // block to nothing — count only the "foreign" characters and tolerate a few.
  // The tab glyphs (digits, `-`, techniques, `=` sustain, `*` repeat, `<>`
  // slides, `:` repeat/separator, barlines, parens, spacing) are free; anything
  // else is foreign. This is the robustness of grepping digits from any labelled
  // line, without admitting a letter-heavy prose line as tab.
  final foreign =
      body.replaceAll(RegExp(r'''[-0-9hpbxXsHP~/\\|()=*<>: \t.]'''), '').length;
  return foreign <= 1 + fill ~/ 6;
}

/// Strips a leading string label like `e|`, `B|`, `E |` or `g` from a line.
String _stripLabel(String line) {
  final m = RegExp(r'^[ \t]*[A-Ga-g][#b]?[ \t]*\|?').firstMatch(line);
  if (m == null) return line;
  // Only strip if what follows still looks like tab content.
  final rest = line.substring(m.end);
  return rest.contains('-') ? rest : line;
}

/// Reads the fret tokens of a [block] into column-aligned [_Event]s.
List<_Event> _events(List<String> block, int n) {
  final byCol = <int, _Event>{};
  for (var s = 0; s < block.length && s < n; s++) {
    final line = block[s];
    var c = 0;
    while (c < line.length) {
      final ch = line[c];
      if (_isDigit(ch)) {
        // A fret is at most two digits, and no guitar fret exceeds ~24. So read
        // up to two digits, but if that pair is >24 it cannot be one fret —
        // it is two adjacent single-digit frets written without a separator
        // (`797` = 7,9,7; `575` = 5,7,5), so back off to a single digit. This
        // also fixes an int overflow on a long garbage digit run.
        var end = c + 1;
        if (end < line.length && _isDigit(line[end])) {
          if (int.parse(line.substring(c, end + 1)) <= 24) end++;
        }
        final fret = int.parse(line.substring(c, end));
        final suffix = end < line.length ? line[end] : null;
        (byCol[c] ??= _Event(c)).tokens[s] =
            _Tok(c, fret, _isTechnique(suffix) ? suffix : null);
        c = end;
      } else if (ch == 'x' || ch == 'X') {
        (byCol[c] ??= _Event(c)).tokens[s] = _Tok(c, null, null);
        c++;
      } else {
        c++;
      }
    }
  }
  final events = byCol.values.toList()..sort((a, b) => a.col.compareTo(b.col));
  return events;
}

/// The columns at which a majority of string lines carry a barline `|`.
List<int> _barlineColumns(List<String> block, int n) {
  final counts = <int, int>{};
  for (final line in block) {
    for (var c = 0; c < line.length; c++) {
      if (line[c] == '|') counts[c] = (counts[c] ?? 0) + 1;
    }
  }
  final cols = [
    for (final entry in counts.entries)
      if (entry.value * 2 >= n) entry.key,
  ]..sort();
  return cols;
}

bool _isDigit(String ch) {
  final c = ch.codeUnitAt(0);
  return c >= 0x30 && c <= 0x39;
}

bool _isTechnique(String? ch) =>
    ch == 'h' || ch == 'p' || ch == 'b' || ch == '~' || ch == '/' || ch == r'\';

/// Spells a MIDI key as a [Pitch] using sharps (matching the MIDI importer).
Pitch _pitchFromMidi(int key) {
  const table = [
    (Step.c, 0), (Step.c, 1), (Step.d, 0), (Step.d, 1), //
    (Step.e, 0), (Step.f, 0), (Step.f, 1), (Step.g, 0),
    (Step.g, 1), (Step.a, 0), (Step.a, 1), (Step.b, 0),
  ];
  final (step, alter) = table[key % 12];
  return Pitch(step, alter: alter, octave: key ~/ 12 - 1);
}
