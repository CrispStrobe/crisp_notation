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
import '../theory/time_signature.dart';

const _recipBases = {
  '0': DurationBase.breve,
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
    _KernReader(lines, layout, staffIndex: staffIndex, idPrefix: 's${staffIndex}e')
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
  Clef _clef = Clef.treble;
  KeySignature _key = const KeySignature(0);
  TimeSignature? _time;

  final _measures = <Measure>[];
  var _current = <MusicElement>[];
  // Grace notes (`q`/`qq`) awaiting attachment to the next principal note.
  var _pendingGraces = <Pitch>[];
  var _pendingGraceStyle = GraceStyle.acciaccatura;
  // Voice 2 — the second sub-spine after a `*^` split (intra-staff overlay).
  var _current2 = <MusicElement>[];
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
        if (line.startsWith('!!!')) _reference(line);
        continue; // reference records handled; other comments skipped
      }
      final cols = line.split('\t');
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
        _finishMeasure();
      } else if (token.startsWith('*')) {
        _interpretation(token);
      } else if (token != '.') {
        // Grace note (`q` acciaccatura / `qq` appoggiatura): accumulate for the
        // next principal note rather than adding a timed element.
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
          final el = _element(token,
              graceNotes: _pendingGraces, graceStyle: _pendingGraceStyle);
          _current.add(el);
          _currentRatios.add(_tupletRatioOf(token.split(' ').first));
          _trackSlur(token, el.id);
          _pendingGraces = [];
          _pendingGraceStyle = GraceStyle.acciaccatura;
        }
      }
      // Second sub-spine → voice 2 (no tuplets/slurs tracked; the model carries
      // those on voice 1 only). Data tokens only; skip nulls and control tokens.
      if (myCols.length > 1) {
        final t2 = at(myCols[1]);
        if (t2 != '.' &&
            !t2.startsWith('*') &&
            !t2.startsWith('=') &&
            !t2.startsWith('!')) {
          _current2.add(_element(t2));
        }
      }
    }
    if (_current.isNotEmpty || _current2.isNotEmpty) _finishMeasure();
    return Score(
      clef: _leadingClef,
      keySignature: _leadingKey,
      timeSignature: _leadingTime,
      measures: withDetectedPickup(_measures, _leadingTime),
      slurs: _slurs,
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

  void _finishMeasure() {
    _measures.add(Measure(
      _current,
      voice2: _current2,
      clefChange: _pendingClef,
      keyChange: _pendingKey,
      timeChange: _pendingTime,
      tuplets: _tupletSpansOf(_currentRatios),
    ));
    _current = <MusicElement>[];
    _current2 = <MusicElement>[];
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
          spans.add(
              TupletSpan(start, end, actual: r.actual, normal: r.normal));
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
    return TimeSignature(int.parse(count), unit);
  }
}
