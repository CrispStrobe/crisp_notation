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

/// Whether [line] is a version-restart header: an explicit `version` marker, or
/// a full preamble carrying two or more distinct metadata fields (`Time: 6/8
/// Standard Tuning …`). A single field on its own (a mid-piece `Time: 3/4`
/// change) is NOT a version boundary.
bool _isVersionHeader(String line) {
  final low = line.toLowerCase();
  if (RegExp(r'\bversion\b').hasMatch(low)) return true;
  var markers = 0;
  for (final k in ['tuning', 'time', 'key', 'tempo', 'capo']) {
    if (RegExp('\\b$k\\b').hasMatch(low)) markers++;
  }
  return markers >= 2;
}

/// Splits a plain-text tab that packs several ARRANGEMENTS of the same piece
/// (a ClassTab habit — "1st version … in C", "2nd version … in E") into one text
/// per version, so each parses to one clean [Score] instead of mixing keys and
/// tunings into garbage. A boundary is a [_isVersionHeader] restart after tab
/// has begun, a string-label-format change (`E|` vs `E |`, a different tabber),
/// or the piece TITLE restated above the next arrangement (ClassTab reprints it
/// before each version). An ordinary single-version tab returns one element (so
/// callers can always take the first); a runaway split (>6) is treated as
/// single.
List<String> splitTabVersions(String text) {
  final lines = text.split(RegExp(r'\r?\n'));
  // The title-restatement boundary only applies when the file actually CLAIMS
  // several arrangements ("1st version …", "2 versions …") — otherwise an
  // incidental title mention mid-piece would fragment a single-version tab.
  final titleWords =
      _enumeratesVersions(text) ? _titleWords(lines) : const <String>[];

  var segs = _segment(lines, titleWords);
  // If reprinted titles push the count past the cap, they are noise on top of a
  // file that already splits cleanly on its own headers — fall back to the
  // header-only split rather than giving up and merging everything.
  if (segs.length > 6 && titleWords.isNotEmpty) {
    segs = _segment(lines, const <String>[]);
  }
  // A genuine multi-version file has a handful of arrangements. A large count
  // means the label format merely alternates block-to-block within one
  // arrangement (a cascade of false boundaries) — treat the file as single.
  // Cap on the count of tab-BEARING segments, BEFORE dropping rest-only ones, so
  // a runaway split can never be un-capped just because some of its false
  // segments happen to be empty of frets.
  final tabbed = segs.where((s) => s.any(_isTabLine)).toList();
  if (tabbed.isEmpty || tabbed.length > 6) return [text];
  // Emit only segments with a real fret (a digit) — an all-rests block (a
  // leading empty intro a boundary split off) parses to a zero-note version,
  // which is worse than not splitting at all.
  final out = [
    for (final s in tabbed)
      if (s.any((l) => _isTabLine(l) && RegExp(r'\d').hasMatch(l)))
        s.join('\n'),
  ];
  return out.isEmpty ? [text] : out;
}

/// One segmentation pass: splits [lines] into raw segments at each version
/// boundary. A boundary is a [_isVersionHeader] restart or a [_restatesTitle]
/// line (both only after tab has begun), or a string-label-format change.
/// [titleWords] empty disables the title-restatement boundary.
List<List<String>> _segment(List<String> lines, List<String> titleWords) {
  final segs = <List<String>>[];
  var cur = <String>[];
  var sawTab = false;
  String? fmt; // 'sp' (E |) or 'ns' (E|), the established label format

  for (final line in lines) {
    final isTab = _isTabLine(line);
    String? lf;
    if (isTab) {
      final m = RegExp(r'^[ \t]*[A-Ga-g][#b]?([ \t]*)\|').firstMatch(line);
      lf = (m?.group(1)?.isNotEmpty ?? false) ? 'sp' : 'ns';
    }
    final restart = sawTab &&
        !isTab &&
        (_isVersionHeader(line) || _restatesTitle(line, titleWords));
    final formatChange =
        isTab && sawTab && fmt != null && lf != null && lf != fmt;
    if (restart || formatChange) {
      segs.add(cur);
      cur = <String>[];
      sawTab = false;
      fmt = null;
    }
    cur.add(line);
    if (isTab) {
      sawTab = true;
      fmt ??= lf;
    }
  }
  if (cur.isNotEmpty) segs.add(cur);
  return segs;
}

/// Whether the tab's header CLAIMS several arrangements — "1st version …",
/// "version 2", "3 versions", "another version". The signal that a reprinted
/// title later in the file is a real version boundary, not an incidental
/// mention.
bool _enumeratesVersions(String text) => RegExp(
      r'\b(\d+(?:st|nd|rd|th)? version|version \d|\d+ versions|another version)\b',
      caseSensitive: false,
    ).hasMatch(text);

/// The distinctive words of the piece TITLE — the first prose line before the
/// staff (skipping blank lines and `#…#` licence boxes). Words of four or more
/// letters, lowercased; empty if there is no such line or it is too generic to
/// match on. Used to spot the title reprinted above a later arrangement.
List<String> _titleWords(List<String> lines) {
  for (final l in lines) {
    final t = l.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    if (_isTabLine(l)) break; // reached the staff without a title line
    final words = <String>{
      for (final m in RegExp(r'[a-z]{4,}').allMatches(t.toLowerCase()))
        m.group(0)!,
    };
    if (words.length >= 3) return words.toList();
    return const []; // a short/generic first line — don't match on it
  }
  return const [];
}

/// Whether [line] reprints the piece title (shares most of its distinctive
/// [titleWords]) — the header ClassTab places above each arrangement. Guarded to
/// short, title-like lines so a prose sentence mentioning the title isn't taken
/// for a version boundary.
bool _restatesTitle(String line, List<String> titleWords) {
  if (titleWords.length < 3) return false;
  final t = line.trim();
  if (t.length > 70) return false; // a title line is short, not a sentence
  final low = t.toLowerCase();
  final hits = titleWords.where(low.contains).length;
  return hits >= 3 && hits * 2 >= titleWords.length;
}

/// Parses every arrangement in a multi-version tab to its own [Score] (see
/// [splitTabVersions]). A single-version tab yields a one-element list. A split
/// segment that parses to no notes is dropped, so a caller never receives an
/// empty version; if every segment is empty the whole text is parsed as one.
List<Score> asciiTabVersions(
  String text, {
  Tuning? tuning,
  NoteDuration duration = NoteDuration.eighth,
  bool inferRhythm = false,
  bool applyStatedCapo = false,
}) {
  Score parse(String t) => asciiTabToScore(t,
      tuning: tuning,
      duration: duration,
      inferRhythm: inferRhythm,
      applyStatedCapo: applyStatedCapo);
  bool hasNotes(Score s) =>
      s.measures.expand((m) => m.elements).whereType<NoteElement>().isNotEmpty;
  final scores = [
    for (final seg in splitTabVersions(text)) parse(seg),
  ].where(hasNotes).toList();
  return scores.isEmpty ? [parse(text)] : scores;
}

/// Parses plain-text tablature [text] into a single [Score] — see the top-level
/// doc for [tuning] inference, techniques, rhythm and lossiness. For a file that
/// packs several arrangements, split first with [splitTabVersions].
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
  final head = _preamble(lines);
  final tune = tuning ??
      _tuningFromMetadata(head) ??
      _tuningFromProse(head) ??
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
  // Common guitar scordaturas that no named Tuning covers, matched by their
  // exact label sequence. Building a tuning from ANY unrecognised label run was
  // too eager — a single-line block or a typo'd label ("E A G D A E") produced
  // a bogus tuning and scrambled the pitches — so only these curated, exact
  // spellings qualify; anything else falls through to the standard default.
  // (A lute tuning `E A D F# B E` was tried too, but it falsely matched lute
  // tablature whose real tuning is uncertain, so it was dropped.)
  _buildTuning(['D', 'G', 'D', 'G', 'B', 'E'])!, // barrios: E B G D G D
  _buildTuning(['C', 'G', 'D', 'G', 'B', 'E'])!, // williams: E B G D G C
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

/// A tuning named in prose rather than spelled out — "Drop D", "6th string in
/// D", "Open D", "Open G", "DADGAD". Only the unambiguous common ones; anything
/// else falls through to the label / count inference.
Tuning? _tuningFromProse(List<String> lines) {
  final text = lines.join(' ').toLowerCase();
  // Drop-D: the 6th (lowest) string lowered to D — one canonical result.
  if (RegExp(r'\bdrop[ -]?d\b').hasMatch(text) ||
      RegExp(r'\b(6th|sixth)\b[^a-z]{0,20}\bin d\b').hasMatch(text) ||
      RegExp(r'\b(6th|sixth)[ -]?string\b[^a-z]{0,14}\bd\b').hasMatch(text)) {
    return Tuning.dropDGuitar;
  }
  if (text.contains('dadgad')) return Tuning.dadgadGuitar;
  // "Open D/G" is dangerous: on its own it almost always names the open 4th/3rd
  // STRING ("the open D on beat 3", "open D, 4th string"), not the tuning. Only
  // treat it as a tuning when the word "tuning" sits right beside it.
  if (RegExp(r'\bopen[ -]?d\b[^a-z]{0,12}tun|\btun\w*[^a-z]{0,12}open[ -]?d\b')
      .hasMatch(text)) {
    return _buildTuning(['D', 'A', 'D', 'F#', 'A', 'D']);
  }
  if (RegExp(r'\bopen[ -]?g\b[^a-z]{0,12}tun|\btun\w*[^a-z]{0,12}open[ -]?g\b')
      .hasMatch(text)) {
    return _buildTuning(['D', 'G', 'D', 'G', 'B', 'D']);
  }
  return null;
}

/// The header lines before the first tab line. A tuning stated in prose
/// ("Drop D", "Tuning: D A D G B E") belongs to this preamble; the SAME words
/// appearing later are per-note performance remarks ("the open D on beat 3"),
/// not a file-global retuning — scoping here stops those from misfiring.
List<String> _preamble(List<String> lines) {
  // The header ends where the STAFF begins — the first LABELLED string line (a
  // note-letter label on a tab line). Decorative dash rows that appear earlier
  // (an ASCII `#-----#` box, a `-----` rule, a Roman-numeral position marker)
  // are not the staff, so they must not cut the header short and hide the
  // tuning declaration that follows them. Only when a tab carries no labels at
  // all do we fall back to the first tab line of any kind.
  bool labelled(String l) =>
      RegExp(r'^[ \t]*[A-Ga-g][#b]?').hasMatch(l) && _isTabLine(l);
  var i = lines.indexWhere(labelled);
  // Unlabelled tab (`|---0-2-4-|`, no note letters): end at the first line that
  // BEGINS a block — two consecutive tab lines — so a lone `#-----#` box border
  // in the header (pure dashes, which reads as a tab line) doesn't end it early.
  if (i < 0) {
    for (var k = 0; k + 1 < lines.length; k++) {
      if (_isTabLine(lines[k]) && _isTabLine(lines[k + 1])) {
        i = k;
        break;
      }
    }
  }
  if (i < 0) i = lines.indexWhere(_isTabLine);
  return i < 0 ? lines : lines.sublist(0, i);
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
  // A real string line is DASH-dominated. Two decorative rows otherwise slip
  // through and get miscounted as strings — a Roman-numeral left-hand POSITION
  // marker above the staff (`            VII  V------------|`) and a FINGERING
  // row below it (`   1-1 4 2    3     1`). Both float their few glyphs in wide
  // whitespace, so they are SPACE-dominated. Counting either as a string
  // inflates the line count to seven, which picks a 7-string tuning and drops
  // every note a fret (a low E read as B1) — so reject any space-dominated row.
  final spaces = RegExp(r'[ \t]').allMatches(body).length;
  if (spaces > fill) return false;
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
  // else is foreign. A `t` that PREFIXES a fret is a tremolo/tap marker (`t12
  // t12 t12`, El Último Trémolo) — free it first, or a whole tremolo string line
  // is rejected and every tremolo note dropped; but a bare `t` (an annotation
  // word) stays foreign, so prose lines are still rejected. This is the
  // robustness of grepping digits from any labelled line, without admitting a
  // letter-heavy prose line as tab.
  final foreign = body
      .replaceAll(RegExp(r't(?=\d)'), '')
      .replaceAll(RegExp(r'''[-0-9hpbxXsHP~/\\|()=*<>: \t.]'''), '')
      .length;
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
