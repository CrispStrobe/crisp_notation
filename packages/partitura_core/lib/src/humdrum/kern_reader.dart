/// Humdrum `**kern` import (subset): a `**kern` document → [Score]. Reads the
/// subset the writer emits — a single spine: clef (with mid-score changes),
/// key/time signatures (incl. common/cut and additive), measures,
/// notes/chords, rests, durations (breve…64th with dots), ties, articulations
/// and ornaments. Multiple
/// spines beyond the first, and unsupported records, are ignored. Pickup is
/// detected from a short first measure. Pure Dart.
library;

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
  if (!lines.any((l) => l.trimRight().split('\t').contains('**kern'))) {
    throw const FormatException('not a **kern document');
  }
  return _KernReader(lines).read();
}

class _KernReader {
  final List<String> lines;
  _KernReader(this.lines);

  int _nextId = 0;
  int _spine = 0; // which tab-column holds the **kern data
  bool _started = false;
  Clef _clef = Clef.treble;
  KeySignature _key = const KeySignature(0);
  TimeSignature? _time;

  final _measures = <Measure>[];
  var _current = <MusicElement>[];
  Clef? _pendingClef;
  KeySignature? _pendingKey;
  TimeSignature? _pendingTime;

  String _newId() => 'e${_nextId++}';

  Score read() {
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;
      if (line.startsWith('!')) {
        if (line.startsWith('!!!')) _reference(line);
        continue; // reference records handled; other comments skipped
      }
      final token = line.split('\t')[_columnFor(line)];
      if (token == '**kern') {
        _spine = line.split('\t').indexOf('**kern');
        continue;
      }
      if (token == '*-') break; // spine terminator
      if (token.startsWith('=')) {
        _finishMeasure();
      } else if (token.startsWith('*')) {
        _interpretation(token);
      } else if (token != '.') {
        _started = true;
        _current.add(_element(token));
      }
    }
    if (_current.isNotEmpty) _finishMeasure();
    return Score(
      clef: _leadingClef,
      keySignature: _leadingKey,
      timeSignature: _leadingTime,
      measures: withDetectedPickup(_measures, _leadingTime),
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

  int _columnFor(String line) {
    final cols = line.split('\t');
    return _spine < cols.length ? _spine : 0;
  }

  void _finishMeasure() {
    _measures.add(Measure(
      _current,
      clefChange: _pendingClef,
      keyChange: _pendingKey,
      timeChange: _pendingTime,
    ));
    _current = <MusicElement>[];
    _pendingClef = null;
    _pendingKey = null;
    _pendingTime = null;
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

  MusicElement _element(String token) {
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
    final base = match == null ? null : _recipBases[match[1]];
    if (base == null) throw FormatException('bad kern duration: "$subtoken"');
    return NoteDuration(base, dots: match![2]!.length.clamp(0, 2));
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
