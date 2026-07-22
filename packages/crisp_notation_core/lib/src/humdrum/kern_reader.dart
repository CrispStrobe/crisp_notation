/// Humdrum `**kern` import (subset): a `**kern` document → [Score]. Reads the
/// subset the writer emits — per spine: clef (with mid-score changes),
/// key/time signatures (incl. common/cut and additive), measures,
/// notes/chords, rests, durations (breve…64th with dots), ties, articulations,
/// ornaments and tuplets (reciprocal durations → `TupletSpan`s). Unsupported
/// records are ignored. Pickup is detected from a short first measure.
///
/// A single spine parses to a [Score]; two spines to a [GrandStaff]
/// ([grandStaffFromKern]); any number to a [StaffSystem] ([staffSystemFromKern]).
/// Pure Dart.
library;

import '../layout/grand_staff.dart';
import '../layout/multi_part.dart';
import '../layout/staff_system.dart';
import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/tempo.dart';
import '../theory/time_signature.dart';

/// `**dynam` token → the model dynamic level (the inverse of `level.name`).
final _dynamLevels = {for (final l in DynamicLevel.values) l.name: l};

/// `!!nav:` comment value → the model navigation mark (inverse of `.name`).
final _navMarks = {for (final n in NavigationMark.values) n.name: n};

const _recipBases = {
  '0': DurationBase.breve,
  // Humdrum `00` = long, `000` = maxima (Renaissance polyphony). The model's
  // longest value is `breve`, so these are approximated to it — a slightly short
  // long/maxima beats rejecting the whole score (they appear in early-music kern).
  '00': DurationBase.breve,
  '000': DurationBase.breve,
  '1': DurationBase.whole,
  '2': DurationBase.half,
  '4': DurationBase.quarter,
  '8': DurationBase.eighth,
  '16': DurationBase.sixteenth,
  '32': DurationBase.thirtySecond,
  '64': DurationBase.sixtyFourth,
};

/// Parses a `**kern` document into a single-staff [Score]. The first `**kern`
/// spine is read; other spines are ignored.
///
/// Throws [FormatException] on documents this subset cannot represent.
Score scoreFromKern(String kern) {
  final lines = kern.split('\n');
  final cols = _kernSpineColumns(lines);
  if (cols.isEmpty) throw const FormatException('not a **kern document');
  return _KernReader(lines, _spineLayout(lines), staffIndex: 0).read();
}

/// Parses a two-spine `**kern` document into a [GrandStaff]. The two `**kern`
/// spines are assigned to the upper and lower staves by their leading clef
/// (treble family → upper, bass family → lower); when the clefs don't
/// disambiguate, the right-hand (higher-numbered) column is taken as the upper
/// staff, matching the Humdrum convention that spines run low-to-high left to
/// right. Element ids are unique across both staves.
///
/// This is the shape optical music recognition produces for piano/grand-staff
/// scores (see `omr/omr.dart`). Throws [FormatException] if the document does
/// not hold at least two `**kern` spines.
GrandStaff grandStaffFromKern(String kern) {
  final lines = kern.split('\n');
  final cols = _kernSpineColumns(lines);
  if (cols.length < 2) {
    throw const FormatException('grand staff needs two **kern spines');
  }
  final layout = _spineLayout(lines);
  final a = _spineScore(lines, layout, 0);
  final b = _spineScore(lines, layout, 1);
  final aUpper = _isUpperClef(a.clef);
  final bUpper = _isUpperClef(b.clef);
  // Clef-based assignment; fall back to column order (rightmost = upper).
  final upperIsA = aUpper == bUpper ? false : aUpper;
  return GrandStaff(
    upper: upperIsA ? a : b,
    lower: upperIsA ? b : a,
  );
}

/// Imports Humdrum `**kern` straight into a paginating [MultiPartScore] — its
/// spines line-break together into aligned systems and paginate (feed it to
/// `layoutMultiPartPages` / `MultiPartView`).
MultiPartScore multiPartScoreFromKern(String kern) =>
    MultiPartScore.fromStaffSystem(staffSystemFromKern(kern));

/// Parses every `**kern` spine into a [StaffSystem], ordered top to bottom
/// (rightmost Humdrum spine — the highest-sounding part — on top). Element ids
/// are unique across staves. Throws [FormatException] if there are no spines.
StaffSystem staffSystemFromKern(String kern) {
  final lines = kern.split('\n');
  final cols = _kernSpineColumns(lines);
  if (cols.isEmpty) throw const FormatException('not a **kern document');
  final layout = _spineLayout(lines);
  // Kern staves are tagged 0..N-1 left to right; the rightmost (highest tag) is
  // the highest-sounding part, so it goes on top.
  final staves = [
    for (var s = cols.length - 1; s >= 0; s--) _spineScore(lines, layout, s)
  ];
  return StaffSystem(staves);
}

/// Reads one kern staff (by its 0-based index) into a [Score], giving its
/// element ids a staff-specific prefix so they stay unique across staves.
Score _spineScore(List<String> lines, List<List<int>> layout, int staffIndex) =>
    _KernReader(lines, layout,
            staffIndex: staffIndex, idPrefix: 's${staffIndex}e')
        .read();

/// Per line, the original **kern staff index for each tab column (or -1 for a
/// non-kern spine such as `**dynam`). Follows Humdrum spine manipulators — `*^`
/// (split into two sub-spines), `*v` (merge adjacent sub-spines), `*-`
/// (terminate) — so a staff can be located in its *current* columns even after
/// a spine to its **left** splits (which shifts everything right of it).
List<List<int>> _spineLayout(List<String> lines) {
  var spines = <int>[];
  var kernNext = 0;
  final perLine = <List<int>>[];
  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.isEmpty || line.startsWith('!')) {
      perLine.add(List.of(spines));
      continue;
    }
    final cols = line.split('\t');
    if (cols.any((t) => t.startsWith('**'))) {
      spines = [for (final t in cols) _isKernSpine(t) ? kernNext++ : -1];
      perLine.add(List.of(spines));
      continue;
    }
    if (cols.length == spines.length &&
        cols.every((t) => t.startsWith('*')) &&
        cols.any((t) => t == '*^' || t == '*v' || t == '*-')) {
      final next = <int>[];
      for (var i = 0; i < cols.length; i++) {
        switch (cols[i]) {
          case '*^': // split: two sub-spines keep the parent's staff tag
            next.add(spines[i]);
            next.add(spines[i]);
          case '*-': // terminate: drop this column
            break;
          case '*v': // merge this and following *v columns into one
            next.add(spines[i]);
            while (i + 1 < cols.length && cols[i + 1] == '*v') {
              i++;
            }
          default:
            next.add(spines[i]);
        }
      }
      spines = next;
      perLine.add(List.of(spines));
      continue;
    }
    perLine.add(List.of(spines));
  }
  return perLine;
}

/// Whether [interp] is a kern-family exclusive interpretation — plain `**kern`
/// or extended `**ekern` (the encoding SMT optical music recognition emits,
/// e.g. `**ekern_1.0`).
bool _isKernSpine(String interp) =>
    interp == '**kern' || interp.startsWith('**ekern');

/// The tab-column indices that carry a kern-family exclusive interpretation,
/// taken from the first record that declares any. Empty when the document has
/// none.
List<int> _kernSpineColumns(List<String> lines) {
  for (final raw in lines) {
    final cols = raw.trimRight().split('\t');
    if (!cols.any(_isKernSpine)) continue;
    return [
      for (var i = 0; i < cols.length; i++)
        if (_isKernSpine(cols[i])) i,
    ];
  }
  return const [];
}

/// Whether [clef] belongs to the treble (upper-staff) family.
bool _isUpperClef(Clef clef) => switch (clef) {
      Clef.treble ||
      Clef.treble8va ||
      Clef.treble8vb ||
      Clef.frenchViolin ||
      Clef.soprano ||
      Clef.mezzoSoprano =>
        true,
      _ => false,
    };

class _KernReader {
  final List<String> lines;
  // Per-line staff tag for each tab column (from `_spineLayout`).
  final List<List<int>> layout;
  // Which kern staff this reader extracts (its columns are those tagged with
  // this index in [layout]; the first is voice 1, a second is voice 2).
  final int staffIndex;
  final String idPrefix;
  _KernReader(this.lines, this.layout,
      {required this.staffIndex, this.idPrefix = 'e'});

  int _nextId = 0;
  bool _started = false;
  // A `|:` on a barline marks the NEXT measure as a repeat start.
  bool _pendingStartRepeat = false;
  // A `*>N` section label / `!!nav:` comment marks the measure it precedes.
  int? _pendingVolta;
  NavigationMark? _pendingNav;
  // Column indices of parallel `**text` lyric spines, in verse order.
  final _textCols = <int>[];
  // Column index of a parallel `**dynam` spine, if any.
  int? _dynamCol;
  // Lyrics gathered from the `**text` spines, anchored to their note's id.
  final _lyrics = <Lyric>[];
  // Dynamics gathered from the `**dynam` spine.
  final _dynamics = <DynamicMarking>[];

  /// Reads this row's parallel `**text`/`**dynam` columns as [note]'s syllables
  /// (one per verse) and its dynamic. A trailing `-` on a syllable marks a word
  /// that continues onto the next note; leading/trailing hyphens are stripped.
  void _readMarkings(List<String> cols, MusicElement note) {
    if (note is! NoteElement || note.id == null) return;
    for (var v = 0; v < _textCols.length; v++) {
      final c = _textCols[v];
      if (c >= cols.length) continue;
      final raw = cols[c];
      if (raw == '.' || raw.isEmpty || raw.startsWith('*') || raw == '=') {
        continue;
      }
      final hyphen = raw.endsWith('-');
      final text = raw.replaceAll(RegExp(r'^-+|-+$'), '');
      if (text.isNotEmpty) {
        _lyrics.add(Lyric(note.id!, text, verse: v + 1, hyphenToNext: hyphen));
      }
    }
    final dc = _dynamCol;
    if (dc != null && dc < cols.length) {
      final level = _dynamLevels[cols[dc].trim()];
      if (level != null) _dynamics.add(DynamicMarking(note.id!, level));
    }
  }

  Clef _clef = Clef.treble;
  KeySignature _key = const KeySignature(0);
  TimeSignature? _time;

  final _measures = <Measure>[];
  var _current = <MusicElement>[];
  // Grace notes (`q`/`qq`) awaiting attachment to the next principal note.
  var _pendingGraces = <Pitch>[];
  var _pendingGraceStyle = GraceStyle.acciaccatura;
  // Voices 2-4 — the extra sub-spines after `*^` split(s) of this staff.
  var _extraVoices = [<MusicElement>[], <MusicElement>[], <MusicElement>[]];
  // Per-element tuplet ratio (null = not a tuplet), aligned with [_current].
  var _currentRatios = <({int actual, int normal})?>[];
  final _slurs = <Slur>[];
  String? _openSlur; // element id of the current unclosed slur start
  Clef? _pendingClef;
  KeySignature? _pendingKey;
  TimeSignature? _pendingTime;

  String _newId() => '$idPrefix${_nextId++}';

  Score read() {
    for (var li = 0; li < lines.length; li++) {
      final line = lines[li].trimRight();
      if (line.isEmpty) continue;
      if (line.startsWith('!')) {
        if (line.startsWith('!!!')) {
          _reference(line);
        } else if (line.startsWith('!!nav:')) {
          // Navigation has no standard kern token; carried as a local comment.
          _pendingNav = _navMarks[line.substring(6).trim()];
        }
        continue; // reference records handled; other comments skipped
      }
      final cols = line.split('\t');
      // Detect parallel `**text` (lyric) and `**dynam` spines once, at the
      // exclusive-interp header (the paired writer keeps their columns fixed).
      if (_textCols.isEmpty && cols.contains('**text')) {
        for (var c = 0; c < cols.length; c++) {
          if (cols[c] == '**text') _textCols.add(c);
        }
      }
      if (_dynamCol == null && cols.contains('**dynam')) {
        _dynamCol = cols.indexOf('**dynam');
      }
      // This staff's columns on this line — first is voice 1, a second (from a
      // `*^` split) is voice 2. Spine splits in *other* staves shift columns;
      // the layout tracks that so we always read the right ones.
      final tags = li < layout.length ? layout[li] : const <int>[];
      final myCols = [
        for (var c = 0; c < cols.length && c < tags.length; c++)
          if (tags[c] == staffIndex) c,
      ];
      if (myCols.isEmpty) continue;
      String at(int c) => c < cols.length ? cols[c] : cols.last;
      final token = at(myCols.first);
      if (token.startsWith('**')) continue; // exclusive-interpretation header
      if (token == '*-') continue; // this staff's spine terminates
      if (token == '*^' || token == '*v') continue; // splits: handled by layout
      if (token.startsWith('=')) {
        // Repeat barlines: `:|` ends a repeat (on the measure just closed),
        // `|:` starts one (on the measure about to begin). A leading start-
        // repeat barline (no measure yet accumulated) only stages the flag.
        final endRep = token.contains(':|');
        if (_current.isNotEmpty || _extraVoices.any((v) => v.isNotEmpty)) {
          _finishMeasure(endRepeat: endRep);
        } else if (endRep && _measures.isNotEmpty) {
          _measures[_measures.length - 1] =
              _measures.last.copyWith(endRepeat: true);
        }
        _pendingStartRepeat = token.contains('|:');
      } else if (token.startsWith('*>')) {
        // A `*>N` section label marks the coming measure as volta N.
        _pendingVolta = int.tryParse(token.substring(2).trim());
      } else if (token.startsWith('*')) {
        _interpretation(token);
      } else if (!token.startsWith('.')) {
        // `.` and its null-token variants (`..`, `./`, `.\`) carry no event.
        // Grace note (`q` acciaccatura / `qq` appoggiatura): accumulate for the
        // next principal note rather than adding a timed element.
        MusicElement? el;
        try {
          if (token.contains('q')) {
            final parsed = _element(token.replaceAll('q', ''));
            if (parsed is NoteElement) {
              _pendingGraces.addAll(parsed.pitches);
              _pendingGraceStyle = token.contains('qq')
                  ? GraceStyle.appoggiatura
                  : GraceStyle.acciaccatura;
            }
          } else {
            _started = true;
            el = _element(token,
                graceNotes: _pendingGraces, graceStyle: _pendingGraceStyle);
          }
        } on FormatException {
          // A single unparseable token (exotic/editorial marker, unmeasured
          // chant note without a duration): skip it rather than reject the
          // whole score. Robustness for large real-world corpora.
          el = null;
        }
        if (el != null) {
          _current.add(el);
          _currentRatios.add(_tupletRatioOf(token.split(' ').first));
          _trackSlur(token, el.id);
          _readMarkings(cols, el);
          _pendingGraces = [];
          _pendingGraceStyle = GraceStyle.acciaccatura;
        }
      }
      // Extra sub-spines → voices 2-4 (the model holds four; tuplets/slurs stay
      // on voice 1). Data tokens only; skip nulls and control tokens.
      for (var v = 1; v < myCols.length && v <= 3; v++) {
        final tv = at(myCols[v]);
        if (!tv.startsWith('.') &&
            !tv.startsWith('*') &&
            !tv.startsWith('=') &&
            !tv.startsWith('!')) {
          try {
            _extraVoices[v - 1].add(_element(tv));
          } on FormatException {
            // skip an unparseable voice token (see above)
          }
        }
      }
    }
    if (_current.isNotEmpty || _extraVoices.any((v) => v.isNotEmpty)) {
      _finishMeasure();
    }
    return Score(
      clef: _leadingClef,
      keySignature: _leadingKey,
      timeSignature: _leadingTime,
      measures: withDetectedPickup(_measures, _leadingTime),
      slurs: _slurs,
      lyrics: _lyrics,
      dynamics: _dynamics,
      tempo: _tempo,
      metadata: ScoreMetadata(
        title: _title,
        composer: _composer,
        lyricist: _lyricist,
        copyright: _copyright,
        instrument: _instrument,
      ),
    );
  }

  String? _title, _composer, _lyricist, _copyright, _instrument;
  Tempo? _tempo;

  /// Parses a `!!!KEY: value` bibliographic reference record.
  void _reference(String line) {
    final match = RegExp(r'^!!!([A-Za-z0-9]+):\s?(.*)$').firstMatch(line);
    if (match == null) return;
    final value = match[2]!.trim();
    if (value.isEmpty) return;
    switch (match[1]) {
      case 'OTL':
        _title = value;
      case 'COM':
        _composer = value;
      case 'LYR':
        _lyricist = value;
      case 'YEC':
        _copyright = value;
    }
  }

  // Leading (document-initial) signatures, captured before the first note.
  Clef _leadingClef = Clef.treble;
  KeySignature _leadingKey = const KeySignature(0);
  TimeSignature? _leadingTime;

  /// Records kern slur markers: `(` opens a slur on [id], `)` closes the open
  /// one, ending at [id]. Single-level (nested `&(`/`&)` are read as plain).
  void _trackSlur(String token, String? id) {
    if (id == null) return;
    if (token.contains('(')) _openSlur = id;
    if (token.contains(')') && _openSlur != null) {
      _slurs.add(Slur(_openSlur!, id));
      _openSlur = null;
    }
  }

  void _finishMeasure({bool endRepeat = false}) {
    _measures.add(Measure(
      _current,
      voice2: _extraVoices[0],
      voice3: _extraVoices[1],
      voice4: _extraVoices[2],
      clefChange: _pendingClef,
      keyChange: _pendingKey,
      timeChange: _pendingTime,
      tuplets: _tupletSpansOf(_currentRatios),
      startRepeat: _pendingStartRepeat,
      endRepeat: endRepeat,
      volta: _pendingVolta,
      navigation: _pendingNav,
    ));
    _pendingStartRepeat = false;
    _pendingVolta = null;
    _pendingNav = null;
    _current = <MusicElement>[];
    _extraVoices = [<MusicElement>[], <MusicElement>[], <MusicElement>[]];
    _currentRatios = <({int actual, int normal})?>[];
    _pendingClef = null;
    _pendingKey = null;
    _pendingTime = null;
  }

  /// The tuplet ratio of a kern reciprocal (e.g. `6` → 3:2, `12` → 3:2), or null
  /// for a power-of-two (non-tuplet) value. The written note value is the
  /// largest power-of-two reciprocal ≤ N (see [_durationOf]); the ratio scales
  /// it — a note of reciprocal N sounds `p/N` of that written value.
  static ({int actual, int normal})? _tupletRatioOf(String subtoken) {
    final m = RegExp(r'(\d+)').firstMatch(subtoken);
    if (m == null) return null;
    final n = int.tryParse(m[1]!);
    if (n == null || n <= 0 || _recipBases.containsKey('$n')) return null;
    var p = 1;
    while (p * 2 <= n && p < 64) {
      p *= 2;
    }
    final g = _gcd(n, p);
    final actual = n ~/ g;
    final normal = p ~/ g;
    return actual >= 2 ? (actual: actual, normal: normal) : null;
  }

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  /// Groups the per-element tuplet ratios into [TupletSpan]s: each maximal run
  /// of same-ratio elements is chunked into groups of `actual` elements. Uniform
  /// tuplets (the common case) round-trip exactly; a trailing partial group
  /// keeps the ratio.
  static List<TupletSpan> _tupletSpansOf(
      List<({int actual, int normal})?> ratios) {
    final spans = <TupletSpan>[];
    var i = 0;
    while (i < ratios.length) {
      final r = ratios[i];
      if (r == null) {
        i++;
        continue;
      }
      var j = i;
      while (j < ratios.length && ratios[j] == r) {
        j++;
      }
      for (var start = i; start < j; start += r.actual) {
        final end = (start + r.actual - 1) < j ? start + r.actual - 1 : j - 1;
        if (end > start) {
          spans.add(TupletSpan(start, end, actual: r.actual, normal: r.normal));
        }
      }
      i = j;
    }
    return spans;
  }

  void _interpretation(String token) {
    if (token.startsWith('*clef')) {
      final clef = _clefOf(token.substring(5));
      _apply(clef: clef);
    } else if (token.startsWith('*k[')) {
      final end = token.indexOf(']');
      if (end < 0) return;
      _apply(key: _keyOf(token.substring(3, end)));
    } else if (token.startsWith('*M') && RegExp(r'^\*M\d').hasMatch(token)) {
      _apply(time: _meterOf(token.substring(2)));
    } else if (token.startsWith('*met(')) {
      _apply(symbol: token.contains('C|') ? TimeSymbol.cut : TimeSymbol.common);
    } else if (token.startsWith('*I"')) {
      final name = token.substring(3).trim();
      if (name.isNotEmpty) _instrument = name;
    } else if (token.startsWith('*MM')) {
      final bpm = double.tryParse(token.substring(3));
      if (bpm != null) _tempo ??= Tempo(bpm);
    }
  }

  void _apply(
      {Clef? clef,
      KeySignature? key,
      TimeSignature? time,
      TimeSymbol? symbol}) {
    if (!_started && _measures.isEmpty && _current.isEmpty) {
      // Leading signatures.
      if (clef != null) _leadingClef = _clef = clef;
      if (key != null) _leadingKey = _key = key;
      if (time != null) _leadingTime = _time = time;
      if (symbol != null && _leadingTime != null) {
        _leadingTime = _withSymbol(_leadingTime!, symbol);
        _time = _leadingTime;
      }
      return;
    }
    // Mid-score changes, attached to the measure being built.
    if (clef != null && clef != _clef) {
      _pendingClef = clef;
      _clef = clef;
    }
    if (key != null && key != _key) {
      _pendingKey = key;
      _key = key;
    }
    if (time != null && time != _time) {
      _pendingTime = time;
      _time = time;
    }
    if (symbol != null && _pendingTime != null) {
      _pendingTime = _withSymbol(_pendingTime!, symbol);
      _time = _pendingTime;
    }
  }

  static TimeSignature _withSymbol(TimeSignature t, TimeSymbol symbol) =>
      TimeSignature(t.beats, t.beatUnit,
          symbol: symbol, components: t.components);

  MusicElement _element(String token,
      {List<Pitch> graceNotes = const [],
      GraceStyle graceStyle = GraceStyle.acciaccatura}) {
    final subtokens = token.split(' ').where((s) => s.isNotEmpty).toList();
    if (subtokens.isEmpty) {
      throw const FormatException('Empty **kern data token');
    }
    if (subtokens.length == 1 && subtokens.first.contains('r')) {
      return RestElement(_durationOf(subtokens.first), id: _newId());
    }
    final pitches = <Pitch>[];
    var tie = false;
    var showAccidental = false;
    for (final sub in subtokens) {
      if (sub.contains('[') || sub.contains('_')) tie = true;
      final (pitch, forced) = _pitchOf(sub);
      if (pitch == null) continue;
      if (forced) showAccidental = true;
      pitches.add(pitch);
    }
    if (pitches.isEmpty) {
      return RestElement(_durationOf(subtokens.first), id: _newId());
    }
    return NoteElement(
      pitches: pitches,
      duration: _durationOf(subtokens.first),
      tieToNext: tie,
      showAccidental: showAccidental ? true : null,
      articulations: _articOf(subtokens.first),
      ornament: _ornamentOf(subtokens.first),
      graceNotes: graceNotes,
      graceStyle: graceStyle,
      id: _newId(),
    );
  }

  /// Humdrum ornament signifier on a note token (one ornament per note).
  static Ornament? _ornamentOf(String token) {
    if (token.contains('T')) return Ornament.trill;
    if (token.contains('m')) return Ornament.shortTrill;
    if (token.contains('M')) return Ornament.mordent;
    if (token.contains(r'$')) return Ornament.invertedTurn;
    if (token.contains('S')) return Ornament.turn;
    return null;
  }

  /// Humdrum articulation signifiers on a note token.
  static Set<Articulation> _articOf(String token) {
    final result = <Articulation>{};
    if (token.contains("'")) result.add(Articulation.staccato);
    if (token.contains('~')) result.add(Articulation.tenuto);
    if (token.contains('^^')) {
      result.add(Articulation.marcato);
    } else if (token.contains('^')) {
      result.add(Articulation.accent);
    }
    if (token.contains(';')) result.add(Articulation.fermata);
    return result;
  }

  NoteDuration _durationOf(String subtoken) {
    final match = RegExp(r'(\d+)(\.*)').firstMatch(subtoken);
    if (match == null) throw FormatException('bad kern duration: "$subtoken"');
    final recip = match[1]!;
    final dots = match[2]!.length.clamp(0, 2);
    final base = _recipBases[recip];
    if (base != null) return NoteDuration(base, dots: dots);
    // Tuplet reciprocal (not a power of two, e.g. 6 = quarter-note triplet).
    // The written note value is the largest power-of-two reciprocal ≤ N; the
    // tuplet ratio is captured separately by [_tupletRatioOf] and attached to
    // the measure as a [TupletSpan], so the sounding rhythm is preserved.
    final n = int.tryParse(recip);
    if (n != null && n > 0) {
      var p = 1;
      while (p * 2 <= n && p < 64) {
        p *= 2;
      }
      final approx = _recipBases['$p'];
      if (approx != null) return NoteDuration(approx, dots: dots);
    }
    throw FormatException('bad kern duration: "$subtoken"');
  }

  static (Pitch?, bool) _pitchOf(String subtoken) {
    // Strip duration, tie and articulation markers; keep the pitch letters +
    // accidentals.
    final match = RegExp(r'([a-gA-G]+)(#+|-+|n)?').firstMatch(subtoken);
    if (match == null) return (null, false);
    final letters = match[1]!;
    final step = Step.values.asNameMap()[letters[0].toLowerCase()];
    if (step == null) return (null, false);
    final lower = letters[0] == letters[0].toLowerCase();
    final octave = lower ? 3 + letters.length : 4 - letters.length;
    final accid = match[2];
    final alter = accid == null
        ? 0
        : accid.startsWith('#')
            ? accid.length
            : accid.startsWith('-')
                ? -accid.length
                : 0; // 'n'
    return (Pitch(step, alter: alter, octave: octave), accid == 'n');
  }

  static Clef _clefOf(String code) {
    if (code.startsWith('X')) return Clef.percussion;
    final match = RegExp(r'([GFC])(v|\^)?(\d)').firstMatch(code);
    if (match == null) return Clef.treble;
    final shape = match[1];
    final mod = match[2];
    final line = int.parse(match[3]!);
    return switch (shape) {
      'G' when line == 1 => Clef.frenchViolin,
      'G' when mod == '^' => Clef.treble8va,
      'G' when mod == 'v' => Clef.treble8vb,
      'G' => Clef.treble,
      'F' when line == 5 => Clef.subbass,
      'F' when line == 3 => Clef.baritone,
      'F' when mod == 'v' => Clef.bass8vb,
      'F' => Clef.bass,
      'C' when line == 1 => Clef.soprano,
      'C' when line == 2 => Clef.mezzoSoprano,
      'C' when line == 4 => Clef.tenor,
      'C' => Clef.alto,
      _ => Clef.treble,
    };
  }

  static KeySignature _keyOf(String content) {
    final sharps = '#'.allMatches(content).length;
    final flats = '-'.allMatches(content).length;
    final fifths = sharps > 0 ? sharps : -flats;
    return KeySignature(fifths.clamp(-7, 7));
  }

  static TimeSignature? _meterOf(String spec) {
    final match = RegExp(r'^([\d+]+)/(\d+)$').firstMatch(spec);
    if (match == null) return null;
    final count = match[1]!;
    final unit = int.parse(match[2]!);
    if (count.contains('+')) {
      return TimeSignature.additive(
          count.split('+').map(int.parse).toList(), unit);
    }
    // A non-power-of-2 denominator (e.g. `*M3/3`, `*M2/21`) is a non-standard /
    // exotic meter that appears in some early-music kern. Skip the meter change
    // rather than reject the whole score (the MIDI reader degrades the same way);
    // the caller (`*M` branch) applies null as a no-op.
    return TimeSignature.tryParse(int.parse(count), unit);
  }
}
