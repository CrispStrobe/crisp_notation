/// ABC notation import.
///
/// ABC is a plain-text music format widespread for folk and traditional tunes.
/// This reads a broad slice of ABC 2.1 into a crisp_notation [Score] (pure Dart,
/// web-safe): the `M`/`L`/`K` header, then a tune body of pitched notes
/// (accidentals from the key + in-measure state, octave marks, `L`-relative and
/// fractional lengths), rests, chords, broken rhythm (`>`/`<`), ties, tuplets,
/// slurs, grace notes (incl. `{/…}`), decorations (`!…!` and shorthand
/// `. ~ H T M P u v` → articulations / ornaments / dynamics / bowing), navigation
/// (`!segno!`/`!D.C.!`/`!D.S.!`/`!fine!`…), quoted `"C"`/positioned `"^…"`
/// annotations, bar lines (repeats, double/final, variant endings `|1`/`[2`),
/// multi-measure rests (`Z`), inline fields (`[K:…]`/`[M:…]`/`[L:…]`), `w:`
/// lyrics and `s:` symbol lines (chord symbols / dynamics / decorations aligned
/// to the notes), `Q:` tempo and `P:` part labels (as annotations), and line
/// continuation (`\`).
///
/// Multi-voice tunes (`V:`) import each voice as its own staff via
/// [staffSystemFromAbc] (one aligned system); [scoreFromAbc] takes the first
/// voice. `Q:`/`P:` and unmodeled decorations are skipped so real tunes still
/// import. PLAN.md tracks the full ABC coverage toward abcjs parity.
library;

import '../layout/multi_part.dart';
import '../layout/staff_system.dart';
import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/time_signature.dart';

/// Parses an ABC tune [abc] into a [Score] (the first tune, first voice if
/// several). For multi-voice tunes rendered as a system, see
/// [staffSystemFromAbc].
///
/// Throws [FormatException] if no tune body / `K:` field is found.
Score scoreFromAbc(String abc) {
  final tune = _collectTune(abc);
  return tune.buildScore(tune.order.first);
}

/// Parses an ABC tune [abc] into a [StaffSystem] — one notation staff per `V:`
/// voice, top to bottom in declaration order, aligned as a system. A
/// single-voice tune yields a one-staff system. Each voice keeps its own clef
/// (from `V:… clef=…` or the `K:` header) and lyrics; element ids are prefixed
/// per voice so they stay unique across staves.
///
/// Voices with fewer bars than the longest (an imperfect encoding) are padded
/// with trailing full-measure rests so the system still aligns and renders
/// rather than failing.
///
/// Throws [FormatException] if no tune body / `K:` field is found.
StaffSystem staffSystemFromAbc(String abc) {
  final tune = _collectTune(abc);
  final scores = [for (final id in tune.order) tune.buildScore(id)];
  var maxBars = 0;
  for (final score in scores) {
    if (score.measures.length > maxBars) maxBars = score.measures.length;
  }
  return StaffSystem([
    for (var i = 0; i < scores.length; i++) _padToBars(scores[i], maxBars, i),
  ]);
}

/// Imports an ABC tune straight into a paginating [MultiPartScore] — its voices
/// line-break together into aligned systems and paginate (feed it to
/// `layoutMultiPartPages` / `MultiPartView`).
MultiPartScore multiPartScoreFromAbc(String abc) =>
    MultiPartScore.fromStaffSystem(staffSystemFromAbc(abc));

/// [score] extended to [bars] measures with trailing full-measure (whole) rests
/// (ids prefixed for voice [voiceIndex]), or unchanged if already long enough.
Score _padToBars(Score score, int bars, int voiceIndex) {
  if (score.measures.length >= bars) return score;
  final measures = [
    ...score.measures,
    for (var p = score.measures.length; p < bars; p++)
      Measure([RestElement(NoteDuration.whole, id: 'v${voiceIndex}pad$p')]),
  ];
  return Score(
    clef: score.clef,
    keySignature: score.keySignature,
    timeSignature: score.timeSignature,
    measures: measures,
    annotations: score.annotations,
    slurs: score.slurs,
    dynamics: score.dynamics,
    lyrics: score.lyrics,
  );
}

/// Accumulates a tune's shared header (`M`/`L`/`K`) and its per-voice bodies,
/// clefs, and lyric lines, so both [scoreFromAbc] and [staffSystemFromAbc] can
/// build [Score]s from the same parse.
class _Tune {
  final TimeSignature? meter;
  final Fraction unit;
  final KeySignature key;
  final Clef headerClef;

  /// Header `Q:` tempo, rendered above the first note of the top voice.
  final String? tempo;

  /// Voice ids in declaration order (at least one — an implicit voice when the
  /// tune has no `V:` field at all).
  final List<String> order;
  final Map<String, Clef> clefs;
  final Map<String, StringBuffer> bodies;
  final Map<String, List<String>> lyrics;

  /// Per-voice `s:` symbol lines (decorations / chord symbols aligned to notes).
  final Map<String, List<String>> symbols;

  _Tune(this.meter, this.unit, this.key, this.headerClef, this.tempo,
      this.order, this.clefs, this.bodies, this.lyrics, this.symbols);

  /// Builds the [Score] for one voice [id].
  Score buildScore(String id) {
    final clef = clefs[id] ?? headerClef;
    // Prefix ids per voice so a multi-voice system keeps them unique.
    final prefix = order.length > 1 ? 'v${order.indexOf(id)}e' : 'e';
    final parser = _AbcBody(bodies[id]!.toString(), unit, key, idPrefix: prefix)
      ..parse();
    final measures = parser.measures.isEmpty
        ? [
            Measure([RestElement(NoteDuration.whole, id: '${prefix}0')])
          ]
        : withDetectedPickup(parser.measures, meter);
    final voiceLyrics = _alignLyrics(lyrics[id] ?? const [], parser.noteOrder);

    // The header tempo sits above the first note of the top staff.
    var annotations = parser.annotations;
    if (tempo != null && id == order.first) {
      final firstNote =
          parser.noteOrder.firstWhere((s) => s != '|', orElse: () => '');
      if (firstNote.isNotEmpty) {
        annotations = [Annotation(firstNote, tempo!), ...annotations];
      }
    }

    // `s:` symbol lines: decorations / chord symbols aligned to the notes.
    var finalMeasures = measures;
    var finalDynamics = parser.dynamics;
    final sLines = symbols[id] ?? const [];
    if (sLines.isNotEmpty) {
      final applied = _applySymbols(sLines, parser.noteOrder, measures);
      finalMeasures = applied.measures;
      annotations = [...annotations, ...applied.annotations];
      finalDynamics = [...parser.dynamics, ...applied.dynamics];
    }

    return Score(
      clef: clef,
      keySignature: key,
      timeSignature: meter,
      measures: finalMeasures,
      annotations: annotations,
      slurs: parser.slurs,
      dynamics: finalDynamics,
      lyrics: voiceLyrics,
    );
  }
}

_Tune _collectTune(String abc) {
  TimeSignature? meter;
  Fraction? unitLen;
  var key = const KeySignature(0);
  var headerClef = Clef.treble;
  String? tempo;
  var sawKey = false;

  final order = <String>[];
  final clefs = <String, Clef>{};
  final bodies = <String, StringBuffer>{};
  final lyrics = <String, List<String>>{};
  final symbols = <String, List<String>>{};
  String? current; // the voice body lines are currently attributed to

  void ensure(String id) {
    if (bodies.containsKey(id)) return;
    order.add(id);
    bodies[id] = StringBuffer();
    lyrics[id] = <String>[];
    symbols[id] = <String>[];
  }

  // Resolve the voice to attribute body content / lyrics to.
  String active() {
    if (current != null) return current!;
    if (order.isNotEmpty) return current = order.first;
    ensure('');
    return current = '';
  }

  // Declares/updates a voice from a `V:` value ("1 clef=bass name=…").
  void declareVoice(String value, {bool switchTo = false}) {
    final (id, clef) = _parseVoiceHeader(value);
    ensure(id);
    if (clef != null) clefs[id] = clef;
    if (switchTo) current = id;
  }

  for (final raw in abc.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('%')) continue;
    final isField =
        line.length >= 2 && line[1] == ':' && _isFieldLetter(line[0]);

    if (!sawKey && isField) {
      final value = line.substring(2).trim();
      switch (line[0]) {
        case 'M':
          meter = _parseMeter(value);
        case 'L':
          unitLen = _parseUnitLength(value);
        case 'V':
          declareVoice(value); // header declaration; body switches later
        case 'Q':
          tempo = _parseTempo(value);
        case 'K':
          final parsed = _parseKey(value);
          key = parsed.$1;
          headerClef = parsed.$2 ?? headerClef;
          sawKey = true; // the K field ends the header; the body follows
      }
      continue;
    }
    if (!sawKey) continue;

    if (isField) {
      final value = line.substring(2).trim();
      if (line[0] == 'w') {
        lyrics[active()]!.add(value);
      } else if (line[0] == 's') {
        symbols[active()]!.add(value);
      } else if (line[0] == 'V') {
        declareVoice(value, switchTo: true);
      } else if (line[0] == 'P' && value.isNotEmpty) {
        // A part label ("P:A") → an above-note annotation on the next note.
        bodies[active()]!.write('"^$value" ');
      } else if (line[0] == 'Q') {
        // A mid-tune tempo change → an above-note annotation.
        final t = _parseTempo(value);
        if (t != null) bodies[active()]!.write('"^$t" ');
      }
      continue; // mid-tune field line
    }

    // A body line. An inline `[V:x]` prefix switches the active voice.
    var noComment = line.split('%').first;
    final voiceMatch = RegExp(r'^\[V:\s*([^\]]+)\]').firstMatch(noComment);
    if (voiceMatch != null) {
      declareVoice(voiceMatch[1]!, switchTo: true);
      noComment = noComment.substring(voiceMatch.end);
    }
    // A trailing `\` continues the line; newlines are already token separators,
    // so dropping it is enough to join the lines.
    noComment = noComment.replaceFirst(RegExp(r'\\\s*$'), '');
    final buffer = bodies[active()]!;
    buffer.write(noComment);
    buffer.write('\n');
  }

  if (!sawKey) throw const FormatException('no ABC tune (missing K: field)');
  if (order.isEmpty) ensure(''); // a tune with a K: but no body content

  // Default note length: 1/8, or 1/16 when the meter is "short" (< 3/4).
  final unit = unitLen ??
      ((meter != null && meter.beats / meter.beatUnit < 0.75)
          ? Fraction(1, 16)
          : Fraction(1, 8));

  return _Tune(meter, unit, key, headerClef, tempo, order, clefs, bodies,
      lyrics, symbols);
}

/// Parses a `Q:` value into readable tempo text — an optional quoted label and
/// a `beat=bpm` metronome mark (e.g. `Q:"Allegro" 1/4=120` → `Allegro ♩ = 120`,
/// `Q:1/4=120` → `♩ = 120`, bare `Q:120` → `♩ = 120`). Returns null if empty.
String? _parseTempo(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  final buf = StringBuffer();
  final quoted = RegExp(r'"([^"]*)"').firstMatch(v);
  if (quoted != null) buf.write(quoted[1]!.trim());

  final beat = RegExp(r'(\d+)\s*/\s*(\d+)\s*=\s*(\d+)').firstMatch(v);
  String? metro;
  if (beat != null) {
    final sym = _tempoNote(int.parse(beat[1]!), int.parse(beat[2]!));
    metro = '$sym = ${beat[3]}';
  } else {
    final bpm = RegExp(r'=\s*(\d+)').firstMatch(v)?.group(1) ??
        RegExp(r'^\s*(\d+)\s*$').firstMatch(v)?.group(1);
    if (bpm != null) metro = '${_tempoNote(1, 4)} = $bpm';
  }
  if (metro != null) {
    if (buf.isNotEmpty) buf.write(' ');
    buf.write(metro);
  }
  final out = buf.toString().trim();
  return out.isEmpty ? null : out;
}

/// A note symbol for a `num/den`-of-a-whole beat unit in a metronome mark,
/// falling back to the raw fraction for units without a simple glyph.
String _tempoNote(int num, int den) {
  if (num == 1 && den == 4) return '♩'; // ♩ quarter
  if (num == 1 && den == 8) return '♪'; // ♪ eighth
  if (num == 3 && den == 8) return '♩.'; // dotted quarter
  return '$num/$den';
}

/// Parses a `V:` value ("1 clef=bass name=…") into its id and optional clef.
(String, Clef?) _parseVoiceHeader(String value) {
  final id = value.trim().split(RegExp(r'\s')).first;
  Clef? clef;
  final cm = RegExp(r'clef\s*=\s*"?([A-Za-z]+)').firstMatch(value);
  if (cm != null) {
    final c = cm[1]!.toLowerCase();
    if (c.startsWith('bass')) {
      clef = Clef.bass;
    } else if (c.startsWith('alto')) {
      clef = Clef.alto;
    } else if (c.startsWith('tenor')) {
      clef = Clef.tenor;
    } else if (c.startsWith('treble')) {
      clef = Clef.treble;
    } else if (c.startsWith('perc')) {
      clef = Clef.percussion;
    }
  }
  return (id, clef);
}

bool _isFieldLetter(String c) {
  final u = c.toUpperCase().codeUnitAt(0);
  return u >= 0x41 && u <= 0x5A;
}

TimeSignature? _parseMeter(String value) {
  final v = value.trim();
  if (v == 'C') return TimeSignature.commonTime;
  if (v == 'C|') return TimeSignature.cutTime;
  // Additive meter: "3+2/8" or "(3+2)/8".
  final add =
      RegExp(r'^\(?\s*(\d+(?:\s*\+\s*\d+)+)\s*\)?\s*/\s*(\d+)').firstMatch(v);
  if (add != null) {
    final groups = add[1]!.split('+').map((g) => int.parse(g.trim())).toList();
    return TimeSignature.additive(groups, int.parse(add[2]!));
  }
  final m = RegExp(r'^(\d+)\s*/\s*(\d+)').firstMatch(v);
  if (m == null) return null;
  return TimeSignature.tryParse(int.parse(m[1]!), int.parse(m[2]!));
}

Fraction? _parseUnitLength(String value) {
  final m = RegExp(r'^(\d+)\s*/\s*(\d+)').firstMatch(value.trim());
  if (m == null) return null;
  return Fraction(int.parse(m[1]!), int.parse(m[2]!));
}

/// Parses a `K:` value (tonic + mode, e.g. `G`, `Em`, `Ador`, `Bb mix`) plus an
/// optional `clef=`/mode-named clef.
(KeySignature, Clef?) _parseKey(String value) {
  final v = value.trim();
  Clef? clef;
  final low = v.toLowerCase();
  if (low.contains('bass')) clef = Clef.bass;
  if (low.contains('alto')) clef = Clef.alto;
  if (low.contains('tenor')) clef = Clef.tenor;
  if (low.contains('perc')) clef = Clef.percussion;

  // "none" and the bagpipe keys (Hp/HP) carry no standard signature.
  if (low.startsWith('none') || low.startsWith('hp')) {
    return (const KeySignature(0), clef);
  }
  final m = RegExp(r'^([A-Ga-g])([#b]?)\s*([A-Za-z]*)').firstMatch(v);
  if (m == null) return (const KeySignature(0), clef);
  final tonic = '${m[1]!.toUpperCase()}${m[2]}';
  final base = _tonicFifths[tonic] ?? 0;
  var fifths = base + _modeAdjust(m[3]!.toLowerCase());
  if (fifths > 7) fifths -= 12;
  if (fifths < -7) fifths += 12;
  return (KeySignature(fifths), clef);
}

const _tonicFifths = {
  'C': 0, 'G': 1, 'D': 2, 'A': 3, 'E': 4, 'B': 5, 'F#': 6, 'C#': 7, //
  'F': -1, 'Bb': -2, 'Eb': -3, 'Ab': -4, 'Db': -5, 'Gb': -6, 'Cb': -7,
  'G#': -4, 'D#': -3, 'A#': -2,
};

int _modeAdjust(String mode) {
  if (mode.isEmpty) return 0;
  final m = mode.length >= 3 ? mode.substring(0, 3) : mode;
  return switch (m) {
    'maj' || 'ion' => 0,
    'min' || 'aeo' || 'm' => -3,
    'dor' => -2,
    'phr' => -4,
    'lyd' => 1,
    'mix' => -1,
    'loc' => -5,
    _ => mode == 'm' ? -3 : 0,
  };
}

/// One parsed note/rest/chord, accumulated so broken rhythm and tuplets can
/// adjust durations before the immutable elements are built.
class _Rec {
  List<Pitch>? pitches; // null = rest
  Fraction dur;
  bool tie = false;
  final Set<Articulation> articulations;
  final List<Pitch> grace;
  final GraceStyle graceStyle;
  final Ornament? ornament;
  final String id;
  _Rec(this.pitches, this.dur, this.id,
      {Set<Articulation>? articulations,
      List<Pitch>? grace,
      this.graceStyle = GraceStyle.acciaccatura,
      this.ornament})
      : articulations = articulations ?? {},
        grace = grace ?? [];
}

/// Tokenizes an ABC tune body into measures + spans.
class _AbcBody {
  final String src;
  // Mutable so inline fields ([L:…], [K:…]) can change them mid-tune.
  Fraction unit;
  KeySignature key;
  final String _idPfx;
  int _pos = 0;
  int _id = 0;

  final List<Measure> measures = [];
  final List<Annotation> annotations = [];
  final List<Slur> slurs = [];

  /// Element ids in performance order (for lyric alignment) — with a `|` marker
  /// string for each barline so `w:` bar breaks can be honored.
  final List<String> noteOrder = [];

  _AbcBody(this.src, this.unit, this.key, {String idPrefix = 'e'})
      : _idPfx = idPrefix;

  List<_Rec> _recs = [];
  // Overlay voices (`&`) already completed in the current measure. Voice 1 is
  // the live [_recs]; each `&` pushes the current recs here and starts a fresh
  // voice. Flushed into a Measure's voice2/3/4 at the barline.
  final List<List<_Rec>> _overlayRecs = [];
  final List<TupletSpan> _tuplets = [];
  bool _nextStartRepeat = false;
  bool _nextBarDotted = false;
  int? _nextVolta;
  KeySignature? _pendingKeyChange;
  TimeSignature? _pendingTimeChange;
  Clef? _pendingClefChange;
  NavigationMark? _pendingNavigation;
  int? _pendingMultiRest;

  String? _pendingChordSymbol;
  final Set<Articulation> _pendingArtic = {};
  final List<Pitch> _pendingGrace = [];
  GraceStyle _pendingGraceStyle = GraceStyle.acciaccatura;
  Ornament? _pendingOrnament;
  DynamicLevel? _pendingDynamic;
  final List<DynamicMarking> dynamics = [];
  final Map<String, int> _measureAccidentals = {};

  // Broken rhythm: multiply the next note's duration by this, once.
  Fraction? _brokenNext;
  // Slur open note ids awaiting a ')'.
  final List<String> _openSlurs = [];
  // Tuplet in progress: notes remaining, and its ratio.
  int _tupletLeft = 0;
  int _tupletActual = 0;
  int _tupletNormal = 0;
  int _tupletStart = 0;

  void parse() {
    while (_pos < src.length) {
      final c = src[_pos];
      if (c == ' ' || c == '\t' || c == '\n') {
        _pos++;
      } else if (c == '"') {
        _readChordSymbol();
      } else if (c == '|' || c == ':' && _atRepeatBar() || _atLeftBar()) {
        _readBarline();
      } else if (c == '(' && _atTuplet()) {
        _readTuplet();
      } else if (c == '(') {
        _pos++;
        _openSlurs.add('$_idPfx$_id'); // slur starts on the next note
      } else if (c == ')') {
        _pos++;
        _closeSlur();
      } else if (c == '&') {
        // Voice overlay: finalize the current voice and start the next one in
        // this same bar. Tuplet/broken state is per-voice; measure accidentals
        // persist across the staff's overlaid voices.
        _pos++;
        _overlayRecs.add(_recs);
        _recs = [];
        _tupletLeft = 0;
        _brokenNext = null;
        // The writer states each overlay voice's accidentals from scratch, so
        // reset the measure accidental state here — otherwise voice 1's
        // accidentals would wrongly carry into voice 2.
        _measureAccidentals.clear();
      } else if (c == '-') {
        _pos++;
        if (_recs.isNotEmpty) _recs.last.tie = true;
      } else if (c == '{') {
        _readGrace();
      } else if (c == '!') {
        _pos++;
        _readDecoration();
      } else if (c == '.' && _pos + 1 < src.length && src[_pos + 1] == '|') {
        _pos++; // ".|" — the following barline is drawn dotted
        _nextBarDotted = true;
      } else if (c == '.') {
        _pos++;
        _pendingArtic.add(Articulation.staccato);
      } else if (c == '>' || c == '<') {
        _readBroken();
      } else if (c == '[' && _peekIsDigit()) {
        _pos++; // '[' of a variant ending "[1", "[2"
        _readVoltaNumber();
      } else if (c == '[' && _peekIsInlineField()) {
        _readInlineField();
      } else if (c == '[') {
        _readChord();
      } else if (c == 'Z') {
        _pos++; // multi-measure rest "Z" / "Zn"
        _pendingMultiRest = _readInt(1);
      } else if (c == 'z' || c == 'x') {
        _readRest();
      } else if ('~HTMPuv'.contains(c)) {
        _pos++;
        _applyShorthand(c);
      } else if (_isNoteStart(c)) {
        _readNote();
      } else {
        _pos++; // unknown token (emphasis L, y spacer, …)
      }
    }
    _closeMeasure(BarlineStyle.normal, endRepeat: false);
  }

  bool _atRepeatBar() => _pos + 1 < src.length && src[_pos + 1] == '|'; // ":|"

  bool _atLeftBar() => src[_pos] == '[' && _peekIsBar(); // "[|"

  bool _peekIsBar() => _pos + 1 < src.length && src[_pos + 1] == '|';

  bool _peekIsDigit() => _pos + 1 < src.length && _isDigit(src[_pos + 1]);

  /// True for an inline field like `[K:D]`, `[M:3/4]`, `[L:1/8]`, `[V:2]`.
  bool _peekIsInlineField() =>
      _pos + 2 < src.length &&
      _isFieldLetter(src[_pos + 1]) &&
      src[_pos + 2] == ':';

  /// Applies a mid-tune inline field: `[K:…]` (key/clef change), `[M:…]`
  /// (meter), `[L:…]` (unit length); others are ignored. The change takes
  /// effect from the current measure.
  void _readInlineField() {
    _pos++; // '['
    final field = src[_pos];
    _pos += 2; // letter + ':'
    final start = _pos;
    while (_pos < src.length && src[_pos] != ']' && src[_pos] != '\n') {
      _pos++;
    }
    final value = src.substring(start, _pos).trim();
    if (_pos < src.length && src[_pos] == ']') _pos++;
    switch (field) {
      case 'K':
        final parsed = _parseKey(value);
        key = parsed.$1;
        _pendingKeyChange = key;
        if (parsed.$2 != null) _pendingClefChange = parsed.$2;
      case 'M':
        final m = _parseMeter(value);
        if (m != null) _pendingTimeChange = m;
      case 'L':
        final l = _parseUnitLength(value);
        if (l != null) unit = l;
    }
  }

  bool _atTuplet() =>
      _pos + 1 < src.length && _isDigit(src[_pos + 1]); // "(3" etc

  bool _isNoteStart(String c) {
    final u = c.codeUnitAt(0);
    return c == '^' ||
        c == '_' ||
        c == '=' ||
        (u >= 0x41 && u <= 0x47) ||
        (u >= 0x61 && u <= 0x67);
  }

  void _readChordSymbol() {
    _pos++;
    final start = _pos;
    while (_pos < src.length && src[_pos] != '"') {
      _pos++;
    }
    var text = src.substring(start, _pos);
    if (_pos < src.length) _pos++;
    // A leading position marker (`^` above, `_` below, `<`/`>` left/right,
    // `@` free) makes it a text annotation rather than a chord symbol; strip
    // it (crisp_notation annotations carry no ABC position). `@x,y` drops coords.
    if (text.isNotEmpty && '^_<>@'.contains(text[0])) {
      text = text.substring(1);
      if (text.startsWith(RegExp(r'-?\d'))) {
        text =
            text.replaceFirst(RegExp(r'^-?\d+(\.\d+)?,-?\d+(\.\d+)?\s*'), '');
      }
    }
    if (text.isNotEmpty) _pendingChordSymbol = text;
  }

  void _readDecoration() {
    final start = _pos;
    while (_pos < src.length && src[_pos] != '!' && src[_pos] != '\n') {
      _pos++;
    }
    final name = src.substring(start, _pos);
    if (_pos < src.length && src[_pos] == '!') _pos++; // closing '!'
    _applyDecoration(name);
  }

  /// Maps an ABC decoration name (from `!…!`) to a pending articulation,
  /// ornament or dynamic on the next note. Unknown names are ignored.
  void _applyDecoration(String name) {
    final artic = switch (name) {
      'fermata' || 'invertedfermata' => Articulation.fermata,
      'accent' || '>' || 'emphasis' => Articulation.accent,
      'tenuto' => Articulation.tenuto,
      'marcato' || '^' => Articulation.marcato,
      'staccato' || '.' => Articulation.staccato,
      'upbow' || 'u' => Articulation.upBow,
      'downbow' || 'v' => Articulation.downBow,
      _ => null,
    };
    if (artic != null) {
      _pendingArtic.add(artic);
      return;
    }
    final ornament = switch (name) {
      'trill' || 'tr' => Ornament.trill,
      'mordent' || 'lowermordent' => Ornament.mordent,
      'uppermordent' || 'pralltriller' => Ornament.shortTrill,
      'turn' || 'turnx' => Ornament.turn,
      'invertedturn' || 'invertedturnx' => Ornament.invertedTurn,
      _ => null,
    };
    if (ornament != null) {
      _pendingOrnament = ornament;
      return;
    }
    final nav =
        switch (name.toLowerCase().replaceAll('.', '').replaceAll(' ', '')) {
      'segno' => NavigationMark.segno,
      'coda' => NavigationMark.coda,
      'dacoda' || 'tocoda' => NavigationMark.toCoda,
      'dacapo' || 'dc' => NavigationMark.daCapo,
      'dacapoalfine' || 'dcalfine' => NavigationMark.daCapoAlFine,
      'dacapoalcoda' || 'dcalcoda' => NavigationMark.daCapoAlCoda,
      'dalsegno' || 'ds' => NavigationMark.dalSegno,
      'dalsegnoalfine' || 'dsalfine' => NavigationMark.dalSegnoAlFine,
      'dalsegnoalcoda' || 'dsalcoda' => NavigationMark.dalSegnoAlCoda,
      'fine' => NavigationMark.fine,
      _ => null,
    };
    if (nav != null) {
      _pendingNavigation = nav;
      return;
    }
    _pendingDynamic ??= DynamicLevel.values.asNameMap()[name];
  }

  /// The legacy single-character decorations: `~` roll, `H` fermata, `T` trill,
  /// `M` mordent, `P` upper mordent, and `u`/`v` up-/down-bow.
  void _applyShorthand(String c) {
    switch (c) {
      case '~':
        _pendingOrnament = Ornament.turn; // general ornament / roll
      case 'H':
        _pendingArtic.add(Articulation.fermata);
      case 'T':
        _pendingOrnament = Ornament.trill;
      case 'M':
        _pendingOrnament = Ornament.mordent;
      case 'P':
        _pendingOrnament = Ornament.shortTrill;
      case 'u':
        _pendingArtic.add(Articulation.upBow);
      case 'v':
        _pendingArtic.add(Articulation.downBow);
    }
  }

  void _readGrace() {
    _pos++; // '{'
    if (_pos < src.length && src[_pos] == '/') {
      _pos++; // acciaccatura "{/…}"
      _pendingGraceStyle = GraceStyle.acciaccatura;
    } else {
      _pendingGraceStyle = GraceStyle.appoggiatura; // plain "{…}"
    }
    while (_pos < src.length && src[_pos] != '}') {
      if (_isNoteStart(src[_pos])) {
        final p = _readPitch();
        _readDuration(); // grace durations are ignored
        if (p != null) _pendingGrace.add(p);
      } else {
        _pos++;
      }
    }
    if (_pos < src.length) _pos++; // '}'
  }

  void _readBroken() {
    var count = 0;
    final ch = src[_pos];
    while (_pos < src.length && src[_pos] == ch) {
      count++;
      _pos++;
    }
    // a>b : a *= (2 - 2^-n); b *= 2^-n. '<' swaps the two.
    final small = Fraction(1, 1 << count);
    final big = Fraction((1 << (count + 1)) - 1, 1 << count);
    final (firstF, nextF) = ch == '>' ? (big, small) : (small, big);
    if (_recs.isNotEmpty) _recs.last.dur = _recs.last.dur * firstF;
    _brokenNext = nextF;
  }

  void _readBarline() {
    final start = _pos;
    // A leading '[' only as part of "[|"; then a run of '|'/':'; then a
    // trailing ']' as part of "|]" — so an adjacent "[chord" is not eaten.
    if (src[_pos] == '[' && _peekIsBar()) _pos++;
    while (_pos < src.length && (src[_pos] == '|' || src[_pos] == ':')) {
      _pos++;
    }
    if (_pos < src.length && src[_pos] == ']') _pos++;
    final t = src.substring(start, _pos);
    final endRepeat = t.replaceAll('[', '').startsWith(':');
    final startRepeat = t.endsWith(':');
    var style = t.contains(']')
        ? BarlineStyle.finalBar
        : (t.replaceAll(RegExp('[:\\[]'), '') == '||'
            ? BarlineStyle.doubleBar
            : BarlineStyle.normal);
    if (_nextBarDotted && style == BarlineStyle.normal) {
      style = BarlineStyle.dotted;
    }
    _nextBarDotted = false;
    _closeMeasure(style, endRepeat: endRepeat);
    _nextStartRepeat = startRepeat;
    noteOrder.add('|');
    // A variant-ending number may follow the bar directly ("|1", ":|2").
    _readVoltaNumber();
  }

  /// Reads a variant-ending number (e.g. `1`, `2`, or a `1,3` / `1-2` list —
  /// only the first is kept, since a measure carries a single volta) and marks
  /// it on the next measure.
  void _readVoltaNumber() {
    final start = _pos;
    while (_pos < src.length &&
        (_isDigit(src[_pos]) || src[_pos] == ',' || src[_pos] == '-')) {
      _pos++;
    }
    if (_pos == start) return;
    final first = RegExp(r'\d+').firstMatch(src.substring(start, _pos));
    if (first != null) _nextVolta = int.parse(first[0]!);
  }

  void _closeMeasure(BarlineStyle style, {required bool endRepeat}) {
    _measureAccidentals.clear();
    // A multi-measure rest ("Z" / "Zn") is its own empty measure.
    if (_pendingMultiRest != null && _recs.isEmpty) {
      final count = _pendingMultiRest!;
      _pendingMultiRest = null;
      measures.add(count >= 2
          ? Measure(const [], multiRest: count, barline: style)
          : Measure([RestElement(NoteDuration.whole, id: '$_idPfx${_id++}')],
              barline: style));
      _nextStartRepeat = false;
      _nextVolta = null;
      return;
    }
    final empty = _recs.isEmpty && _overlayRecs.isEmpty;
    if (empty && measures.isEmpty) return;
    if (empty && !endRepeat && style == BarlineStyle.normal) return;
    // Voice 1 is the first overlay (or the live recs if there was no `&`);
    // voices 2–4 follow. The model holds up to four voices per measure.
    final voices = [..._overlayRecs, _recs];
    List<MusicElement> build(List<_Rec> recs) => [
          for (final r in recs)
            if (r.pitches == null)
              RestElement(_durationOf(r.dur), id: r.id)
            else
              NoteElement(
                pitches: r.pitches!,
                duration: _durationOf(r.dur),
                tieToNext: r.tie,
                articulations: r.articulations,
                graceNotes: r.grace,
                graceStyle: r.graceStyle,
                ornament: r.ornament,
                id: r.id,
              ),
        ];
    measures.add(Measure(
      build(voices[0]),
      voice2: voices.length > 1 ? build(voices[1]) : const [],
      voice3: voices.length > 2 ? build(voices[2]) : const [],
      voice4: voices.length > 3 ? build(voices[3]) : const [],
      tuplets: List.of(_tuplets),
      clefChange: _pendingClefChange,
      keyChange: _pendingKeyChange,
      timeChange: _pendingTimeChange,
      startRepeat: _nextStartRepeat,
      endRepeat: endRepeat,
      volta: _nextVolta,
      navigation: _pendingNavigation,
      barline: style,
    ));
    _recs = [];
    _overlayRecs.clear();
    _tuplets.clear();
    _nextStartRepeat = false;
    _nextVolta = null;
    _pendingKeyChange = null;
    _pendingTimeChange = null;
    _pendingClefChange = null;
    _pendingNavigation = null;
  }

  void _readTuplet() {
    _pos++; // '('
    final numStart = _pos;
    while (_pos < src.length && _isDigit(src[_pos])) {
      _pos++;
    }
    final p = int.parse(src.substring(numStart, _pos));
    var q = switch (p) { 2 => 3, 3 => 2, 4 => 3, 6 => 2, 8 => 3, _ => 2 };
    var r = p;
    // Optional :q:r.
    if (_pos < src.length && src[_pos] == ':') {
      _pos++;
      q = _readInt(q);
      if (_pos < src.length && src[_pos] == ':') {
        _pos++;
        r = _readInt(r);
      }
    }
    _tupletActual = p;
    _tupletNormal = q;
    _tupletLeft = r;
    _tupletStart = _recs.length;
  }

  int _readInt(int fallback) {
    final start = _pos;
    while (_pos < src.length && _isDigit(src[_pos])) {
      _pos++;
    }
    return _pos > start ? int.parse(src.substring(start, _pos)) : fallback;
  }

  void _readRest() {
    _pos++;
    final dur = _applyPending(_readDuration());
    _add(_Rec(null, dur, '$_idPfx${_id++}'));
  }

  void _readChord() {
    _pos++; // '['
    final pitches = <Pitch>[];
    while (_pos < src.length && src[_pos] != ']') {
      if (_isNoteStart(src[_pos])) {
        final p = _readPitch();
        _readDuration();
        if (p != null) pitches.add(p);
      } else {
        _pos++;
      }
    }
    if (_pos < src.length) _pos++;
    final dur = _applyPending(_readDuration());
    if (pitches.isEmpty) return;
    pitches.sort((a, b) => a.midiNumber.compareTo(b.midiNumber));
    _add(_makeRec(pitches, dur));
  }

  void _readNote() {
    final pitch = _readPitch();
    if (pitch == null) return;
    final dur = _applyPending(_readDuration());
    _add(_makeRec([pitch], dur));
  }

  _Rec _makeRec(List<Pitch> pitches, Fraction dur) {
    final rec = _Rec(pitches, dur, '$_idPfx${_id++}',
        articulations: _pendingArtic.isEmpty ? null : Set.of(_pendingArtic),
        grace: _pendingGrace.isEmpty ? null : List.of(_pendingGrace),
        graceStyle: _pendingGraceStyle,
        ornament: _pendingOrnament);
    _pendingArtic.clear();
    _pendingGrace.clear();
    _pendingOrnament = null;
    if (_pendingDynamic != null) {
      dynamics.add(DynamicMarking(rec.id, _pendingDynamic!));
      _pendingDynamic = null;
    }
    if (_pendingChordSymbol != null) {
      annotations.add(Annotation(rec.id, _pendingChordSymbol!));
      _pendingChordSymbol = null;
    }
    return rec;
  }

  void _add(_Rec rec) {
    _recs.add(rec);
    // Only notes take `w:` syllables — a rest is skipped in the lyric stream
    // (ABC aligns syllables to notes, not rests). Including rests here would
    // shift every following syllable and attach some to rests. Overlay voices
    // (after a `&`) never take lyrics — only voice 1 does.
    if (rec.pitches != null && _overlayRecs.isEmpty) noteOrder.add(rec.id);
    // Tuplet span accounting.
    if (_tupletLeft > 0) {
      _tupletLeft--;
      if (_tupletLeft == 0) {
        _tuplets.add(TupletSpan(
          _tupletStart,
          _recs.length - 1,
          actual: _tupletActual,
          normal: _tupletNormal,
        ));
      }
    }
  }

  Fraction _applyPending(Fraction dur) {
    if (_brokenNext != null) {
      dur = dur * _brokenNext!;
      _brokenNext = null;
    }
    return dur;
  }

  void _closeSlur() {
    if (_openSlurs.isEmpty || _recs.isEmpty) return;
    final startId = _openSlurs.removeLast();
    final endId = _recs.last.id;
    if (startId != endId) slurs.add(Slur(startId, endId));
  }

  Pitch? _readPitch() {
    var alter = 0;
    var explicit = false;
    while (_pos < src.length && '^_='.contains(src[_pos])) {
      explicit = true;
      alter += switch (src[_pos]) { '^' => 1, '_' => -1, _ => -alter };
      _pos++;
    }
    if (_pos >= src.length) return null;
    final letter = src[_pos];
    final code = letter.codeUnitAt(0);
    final isLower = code >= 0x61 && code <= 0x67;
    final isUpper = code >= 0x41 && code <= 0x47;
    if (!isLower && !isUpper) return null;
    _pos++;

    var octave = isLower ? 5 : 4;
    while (_pos < src.length && (src[_pos] == ',' || src[_pos] == "'")) {
      octave += src[_pos] == "'" ? 1 : -1;
      _pos++;
    }
    final step = _stepOf(letter.toUpperCase());
    final upper = letter.toUpperCase();
    if (explicit) {
      _measureAccidentals[upper] = alter;
    } else if (_measureAccidentals.containsKey(upper)) {
      alter = _measureAccidentals[upper]!;
    } else {
      alter = _keyAlter(step);
    }
    return Pitch(step, alter: alter, octave: octave);
  }

  int _keyAlter(Step step) {
    if (!key.alteredSteps.contains(step)) return 0;
    return key.fifths >= 0 ? 1 : -1;
  }

  Fraction _readDuration() {
    var num = 1;
    var den = 1;
    final numStart = _pos;
    while (_pos < src.length && _isDigit(src[_pos])) {
      _pos++;
    }
    if (_pos > numStart) num = int.parse(src.substring(numStart, _pos));
    while (_pos < src.length && src[_pos] == '/') {
      _pos++;
      final dStart = _pos;
      while (_pos < src.length && _isDigit(src[_pos])) {
        _pos++;
      }
      den *= _pos > dStart ? int.parse(src.substring(dStart, _pos)) : 2;
    }
    return unit * Fraction(num, den);
  }

  bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
}

/// Aligns `w:` syllable lines to the note ids in [noteOrder] (which contains
/// `|` markers at barlines, matching the `|` advance in `w:`).
/// Applies `s:` symbol lines to a voice: aligns whitespace-separated tokens to
/// the notes in [noteOrder] (as `w:` aligns syllables — `*` skips a note, `|`
/// syncs to a barline), classifies each token, and returns the (possibly
/// rebuilt) [measures] plus the new annotations / dynamics. `"…"` tokens become
/// chord-symbol / text [Annotation]s, `!p!`…`!fff!` become [DynamicMarking]s,
/// and articulation / ornament decorations (`!trill!`, `.`, `~`, `H`…) merge
/// onto their aligned note.
({
  List<Measure> measures,
  List<Annotation> annotations,
  List<DynamicMarking> dynamics,
}) _applySymbols(
    List<String> sLines, List<String> noteOrder, List<Measure> measures) {
  final tokens = <String>[];
  for (final line in sLines) {
    tokens.addAll(_splitSymbolTokens(line));
  }
  final annotations = <Annotation>[];
  final dynamics = <DynamicMarking>[];
  final decoById = <String, ({Set<Articulation> artic, Ornament? ornament})>{};

  var ti = 0;
  for (final id in noteOrder) {
    if (ti >= tokens.length) break;
    if (id == '|') {
      while (ti < tokens.length && tokens[ti] == '|') {
        ti++;
      }
      continue;
    }
    var tok = tokens[ti];
    while (tok == '|' && ti + 1 < tokens.length) {
      ti++;
      tok = tokens[ti];
    }
    ti++;
    if (tok == '*' || tok == '|') continue; // skip this note
    final sym = _symbolOf(tok);
    if (sym == null) continue;
    if (sym.annotation != null) {
      annotations.add(Annotation(id, sym.annotation!));
    }
    if (sym.dynamic != null) dynamics.add(DynamicMarking(id, sym.dynamic!));
    if (sym.artic.isNotEmpty || sym.ornament != null) {
      final prev = decoById[id];
      decoById[id] = (
        artic: {...?prev?.artic, ...sym.artic},
        ornament: sym.ornament ?? prev?.ornament,
      );
    }
  }

  final outMeasures =
      decoById.isEmpty ? measures : _mergeDecorations(measures, decoById);
  return (measures: outMeasures, annotations: annotations, dynamics: dynamics);
}

/// Splits an `s:` line into tokens on whitespace, keeping a quoted `"…"` chord
/// symbol or a `!…!` decoration (which may contain spaces) as one token.
List<String> _splitSymbolTokens(String line) {
  final tokens = <String>[];
  var i = 0;
  while (i < line.length) {
    final c = line[i];
    if (c == ' ' || c == '\t') {
      i++;
      continue;
    }
    if (c == '"' || c == '!') {
      final close = line.indexOf(c, i + 1);
      if (close < 0) {
        tokens.add(line.substring(i));
        break;
      }
      tokens.add(line.substring(i, close + 1));
      i = close + 1;
    } else {
      var j = i;
      while (j < line.length && line[j] != ' ' && line[j] != '\t') {
        j++;
      }
      tokens.add(line.substring(i, j));
      i = j;
    }
  }
  return tokens;
}

/// Classifies one `s:` token into its chord-symbol/text annotation, dynamic
/// level, and/or articulation + ornament, or null when it carries none.
({
  String? annotation,
  DynamicLevel? dynamic,
  Set<Articulation> artic,
  Ornament? ornament,
})? _symbolOf(String tok) {
  if (tok.isEmpty) return null;
  // "…" chord symbol / text (drop a leading position marker ^_<>@).
  if (tok.startsWith('"')) {
    var text =
        tok.substring(1, tok.endsWith('"') ? tok.length - 1 : tok.length);
    if (text.isNotEmpty && '^_<>@'.contains(text[0])) {
      text = text.substring(1);
    }
    text = text.trim();
    return text.isEmpty
        ? null
        : (annotation: text, dynamic: null, artic: const {}, ornament: null);
  }
  // !name! decoration, or a bare shorthand character (. ~ H T M P u v > ^).
  final name = tok.startsWith('!')
      ? tok.substring(1, tok.endsWith('!') ? tok.length - 1 : tok.length)
      : tok;
  final dyn = DynamicLevel.values.asNameMap()[name];
  final artic = _symbolArtic(name);
  final orn = _symbolOrnament(name);
  if (dyn == null && artic == null && orn == null) return null;
  return (
    annotation: null,
    dynamic: dyn,
    artic: artic == null ? const {} : {artic},
    ornament: orn,
  );
}

/// The articulation for an `s:` decoration name or shorthand char (mirrors the
/// inline `!…!` / shorthand mapping).
Articulation? _symbolArtic(String s) => switch (s) {
      'fermata' || 'invertedfermata' || 'H' => Articulation.fermata,
      'accent' || 'emphasis' || '>' => Articulation.accent,
      'tenuto' => Articulation.tenuto,
      'marcato' || '^' => Articulation.marcato,
      'staccato' || '.' => Articulation.staccato,
      'upbow' || 'u' => Articulation.upBow,
      'downbow' || 'v' => Articulation.downBow,
      _ => null,
    };

/// The ornament for an `s:` decoration name or shorthand char.
Ornament? _symbolOrnament(String s) => switch (s) {
      'trill' || 'tr' || 'T' => Ornament.trill,
      'mordent' || 'lowermordent' || 'M' => Ornament.mordent,
      'uppermordent' || 'pralltriller' || 'P' => Ornament.shortTrill,
      'turn' || 'turnx' || '~' => Ornament.turn,
      'invertedturn' || 'invertedturnx' => Ornament.invertedTurn,
      _ => null,
    };

/// Rebuilds the notes named in [byId] with their `s:` articulations / ornament
/// merged in (other elements and measure fields are untouched).
List<Measure> _mergeDecorations(List<Measure> measures,
    Map<String, ({Set<Articulation> artic, Ornament? ornament})> byId) {
  MusicElement rebuild(MusicElement e) {
    if (e is! NoteElement || e.id == null) return e;
    final deco = byId[e.id];
    if (deco == null) return e;
    return NoteElement(
      pitches: e.pitches,
      duration: e.duration,
      showAccidental: e.showAccidental,
      tieToNext: e.tieToNext,
      articulations: {...e.articulations, ...deco.artic},
      graceNotes: e.graceNotes,
      graceStyle: e.graceStyle,
      ornament: deco.ornament ?? e.ornament,
      fingerings: e.fingerings,
      arpeggio: e.arpeggio,
      tremolo: e.tremolo,
      notehead: e.notehead,
      id: e.id,
    );
  }

  return [
    for (final m in measures)
      m.copyWith(
        elements: [for (final e in m.elements) rebuild(e)],
        voice2: [for (final e in m.voice2) rebuild(e)],
      ),
  ];
}

List<Lyric> _alignLyrics(List<String> lines, List<String> noteOrder) {
  if (lines.isEmpty) return const [];
  // Flatten every w: line into a stream of syllable tokens.
  final tokens = <String>[];
  for (final line in lines) {
    for (final t in _splitSyllables(line)) {
      tokens.add(t);
    }
  }
  final lyrics = <Lyric>[];
  var ti = 0;
  for (final id in noteOrder) {
    if (ti >= tokens.length) break;
    if (id == '|') {
      // Advance syllables to the next '|' only if the token stream uses them.
      while (ti < tokens.length && tokens[ti] == '|') {
        ti++;
      }
      continue;
    }
    var tok = tokens[ti];
    while (tok == '|' && ti + 1 < tokens.length) {
      ti++;
      tok = tokens[ti];
    }
    ti++;
    if (tok == '*' || tok == '|' || tok.isEmpty) continue; // skip this note
    final hyphen = tok.endsWith('-');
    final text = (hyphen ? tok.substring(0, tok.length - 1) : tok)
        .replaceAll('~', ' ')
        .replaceAll(r'\-', '-');
    if (text.isEmpty) continue;
    lyrics.add(Lyric(id, text, hyphenToNext: hyphen));
  }
  return lyrics;
}

Iterable<String> _splitSyllables(String line) sync* {
  final buf = StringBuffer();
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == ' ') {
      if (buf.isNotEmpty) {
        yield buf.toString();
        buf.clear();
      }
    } else if (c == '-') {
      buf.write('-');
      yield buf.toString();
      buf.clear();
    } else if (c == '|') {
      if (buf.isNotEmpty) {
        yield buf.toString();
        buf.clear();
      }
      yield '|';
    } else {
      buf.write(c);
    }
  }
  if (buf.isNotEmpty) yield buf.toString();
}

Step _stepOf(String letter) => switch (letter) {
      'C' => Step.c,
      'D' => Step.d,
      'E' => Step.e,
      'F' => Step.f,
      'G' => Step.g,
      'A' => Step.a,
      _ => Step.b,
    };

/// Maps a whole-note [fraction] to the nearest notated duration (base + dots).
NoteDuration _durationOf(Fraction fraction) {
  const bases = [
    (DurationBase.breve, 2.0),
    (DurationBase.whole, 1.0),
    (DurationBase.half, 0.5),
    (DurationBase.quarter, 0.25),
    (DurationBase.eighth, 0.125),
    (DurationBase.sixteenth, 0.0625),
    (DurationBase.thirtySecond, 0.03125),
    (DurationBase.sixtyFourth, 0.015625),
  ];
  const dotMul = [1.0, 1.5, 1.75];
  final target = fraction.numerator / fraction.denominator;
  for (var dots = 0; dots < dotMul.length; dots++) {
    for (final (base, value) in bases) {
      if ((value * dotMul[dots] - target).abs() < 1e-9) {
        return NoteDuration(base, dots: dots);
      }
    }
  }
  var best = bases.first;
  var bestDiff = double.infinity;
  for (final b in bases) {
    final d = (b.$2 - target).abs();
    if (d < bestDiff) {
      bestDiff = d;
      best = b;
    }
  }
  return NoteDuration(best.$1);
}
