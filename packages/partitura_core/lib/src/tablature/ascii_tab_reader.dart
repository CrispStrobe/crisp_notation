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
}) {
  final tune = tuning ?? Tuning.standardGuitar;
  final n = tune.stringCount;
  final blocks = _blocks(text.split(RegExp(r'\r?\n')), n);

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
      placed.add((_pitchFromMidi(open.midiNumber + fret), stringIndex));
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

/// Whether [line] looks like a tab string line: after its label, it is made
/// only of tab characters (dashes, frets, techniques, barlines) and has at
/// least two dashes — enough to reject ordinary prose.
bool _isTabLine(String line) {
  final body = _stripLabel(line);
  if ('-'.allMatches(body).length < 2) return false;
  return RegExp(r'''^[-0-9hpbxXsHP~/\\|() \t.]+$''').hasMatch(body);
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
        var end = c;
        while (end < line.length && _isDigit(line[end])) {
          end++;
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
