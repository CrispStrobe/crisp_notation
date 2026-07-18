/// MuseScore import (subset): a `.mscx` (MuseScore XML) document → [Score].
///
/// Reads the same shared subset the writer emits — clef (with mid-score
/// changes), key/time signatures, measures, notes/chords, rests, durations
/// (breve…64th with dots), two voices, ties, pickup measures, articulations
/// and ornaments — plus the common shapes real MuseScore 3/4 files use for
/// those (e.g. `<KeySig>` stored as `concertKey`, `accidental` or `subtype`;
/// whole-measure rests as `durationType>measure`; MuseScore-3 articulation
/// names). Unsupported markup (slurs, tuplets, lyrics, dynamics, beams,
/// spanners) is ignored. Pure Dart (web-safe); the
/// `.mscz` ZIP container is unwrapped in `crisp_notation_cli`.
library;

import '../layout/multi_part.dart';
import '../layout/staff_system.dart';
import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../musicxml/xml_reader.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/tempo.dart';
import '../theory/time_signature.dart';

/// MuseScore `<durationType>` name → [DurationBase].
const _durationBases = {
  'breve': DurationBase.breve,
  'whole': DurationBase.whole,
  'half': DurationBase.half,
  'quarter': DurationBase.quarter,
  'eighth': DurationBase.eighth,
  '16th': DurationBase.sixteenth,
  '32nd': DurationBase.thirtySecond,
  '64th': DurationBase.sixtyFourth,
};

/// MuseScore concert clef-type code → crisp_notation [Clef]. Octave-doubled and
/// old-style treble variants fold onto their nearest supported clef.
const _clefs = {
  'G': Clef.treble,
  'G8va': Clef.treble8va,
  'G15ma': Clef.treble8va,
  'G8vb': Clef.treble8vb,
  'G8vbo': Clef.treble8vb,
  'G8vbp': Clef.treble8vb,
  'G15mb': Clef.treble8vb,
  'G1': Clef.frenchViolin,
  'F': Clef.bass,
  'F8vb': Clef.bass8vb,
  'F15mb': Clef.bass8vb,
  'F_B': Clef.baritone,
  'F_C': Clef.subbass,
  'C1': Clef.soprano,
  'C2': Clef.mezzoSoprano,
  'C3': Clef.alto,
  'C4': Clef.tenor,
  'C5': Clef.baritone,
  'PERC': Clef.percussion,
  'PERC2': Clef.percussion,
};

/// Parses a MuseScore `.mscx` document into a single-staff [Score], reading
/// staff [staffIndex] (default: the first staff that holds measures).
///
/// Throws [FormatException] on documents this subset cannot represent.
Score scoreFromMscx(String mscx, {int staffIndex = 0}) {
  final root = parseXml(mscx);
  if (root.name != 'museScore') {
    throw FormatException('Expected <museScore>, got <${root.name}>');
  }
  final scoreNode = root.child('Score');
  if (scoreNode == null) throw const FormatException('No <Score> in document');
  // The staff-with-measures nodes (a <Part>'s <Staff> holds no measures).
  final staves = scoreNode
      .childrenNamed('Staff')
      .where((s) => s.child('Measure') != null)
      .toList();
  if (staves.isEmpty) throw const FormatException('No <Staff> with measures');
  if (staffIndex < 0 || staffIndex >= staves.length) {
    throw FormatException('Staff $staffIndex not found (${staves.length})');
  }
  return _StaffReader(staves[staffIndex], _metadataOf(scoreNode),
          drumset: _drumsetFor(scoreNode, staves[staffIndex]))
      .read();
}

/// Parses a MuseScore `.mscx` document into a [StaffSystem] — one staff per
/// `<Staff>`-with-measures, top to bottom. Element ids are staff-prefixed so
/// they stay unique across parts. Throws [FormatException] if there are none.
StaffSystem staffSystemFromMscx(String mscx) {
  final root = parseXml(mscx);
  if (root.name != 'museScore') {
    throw FormatException('Expected <museScore>, got <${root.name}>');
  }
  final scoreNode = root.child('Score');
  if (scoreNode == null) throw const FormatException('No <Score> in document');
  final staves = scoreNode
      .childrenNamed('Staff')
      .where((s) => s.child('Measure') != null)
      .toList();
  if (staves.isEmpty) throw const FormatException('No <Staff> with measures');
  final base = _metadataOf(scoreNode);
  return StaffSystem([
    for (var i = 0; i < staves.length; i++)
      _StaffReader(
        staves[i],
        _staffMetadata(scoreNode, staves[i], base),
        drumset: _drumsetFor(scoreNode, staves[i]),
        idPrefix: 's${i}e',
      ).read(),
  ]);
}

/// A MuseScore `.mscx` document → a paginating [MultiPartScore], one part per
/// staff — so a multi-instrument file keeps EVERY part (unlike [scoreFromMscx],
/// which reads a single staff).
MultiPartScore multiPartScoreFromMscx(String mscx) =>
    MultiPartScore.fromStaffSystem(staffSystemFromMscx(mscx));

/// [base] score metadata with the instrument taken from the `<Part>` that owns
/// [staffNode] (matched by `<Staff id>`), so each part keeps its own name.
ScoreMetadata _staffMetadata(
    XmlNode scoreNode, XmlNode staffNode, ScoreMetadata base) {
  final id = staffNode.attributes['id'];
  String? track;
  if (id != null) {
    for (final part in scoreNode.childrenNamed('Part')) {
      if (part.childrenNamed('Staff').any((s) => s.attributes['id'] == id)) {
        track = part.childText('trackName');
        break;
      }
    }
  }
  final instrument =
      (track == null || track.isEmpty || track == 'Music') ? null : track;
  return ScoreMetadata(
    title: base.title,
    composer: base.composer,
    lyricist: base.lyricist,
    copyright: base.copyright,
    instrument: instrument,
  );
}

/// One entry of a MuseScore drumset: the staff [line] (MuseScore convention —
/// top line is 0, increasing downward by a half-space) and notehead [head] a
/// drum pitch is drawn with.
typedef _Drum = ({int line, NoteheadShape head});

/// The `<Drum pitch="…">` map for the [staffNode]'s part, or null when the
/// staff is not a drum staff. Matches the `<Part>` whose `<Staff id>` equals the
/// music staff's id (falling back to the sole drum part), then reads its
/// `<Instrument>`'s drum definitions (pitch → line + notehead).
Map<int, _Drum>? _drumsetFor(XmlNode scoreNode, XmlNode staffNode) {
  final id = staffNode.attributes['id'];
  final parts = scoreNode.childrenNamed('Part').toList();
  XmlNode? instrument;
  for (final part in parts) {
    final inst = part.child('Instrument');
    if (inst == null || inst.childrenNamed('Drum').isEmpty) continue;
    final owns = id != null &&
        part.childrenNamed('Staff').any((s) => s.attributes['id'] == id);
    if (owns) {
      instrument = inst;
      break;
    }
    instrument ??= inst; // fallback: the first drum part
  }
  if (instrument == null) return null;
  final map = <int, _Drum>{};
  for (final drum in instrument.childrenNamed('Drum')) {
    final pitch = int.tryParse(drum.attributes['pitch'] ?? '');
    if (pitch == null) continue;
    map[pitch] = (
      line: int.tryParse(drum.childText('line') ?? '') ?? 0,
      head: _noteheadOf(drum.childText('head')),
    );
  }
  return map.isEmpty ? null : map;
}

/// MuseScore drum `<head>` group → [NoteheadShape] (unknown / absent → normal).
NoteheadShape _noteheadOf(String? head) => switch (head) {
      'cross' || 'x' => NoteheadShape.x,
      'diamond' => NoteheadShape.diamond,
      'triangle' || 'triangle-up' || 'triangleUp' => NoteheadShape.triangleUp,
      'slash' || 'slashed' => NoteheadShape.slash,
      'xcircle' || 'circled' || 'circledlarge' => NoteheadShape.circleX,
      _ => NoteheadShape.normal,
    };

/// Reads MuseScore `<metaTag>`s and the part `<trackName>` into metadata; the
/// default track name ("Music") maps to a null instrument.
ScoreMetadata _metadataOf(XmlNode scoreNode) {
  String? tag(String name) {
    for (final t in scoreNode.childrenNamed('metaTag')) {
      if (t.attributes['name'] == name && t.text.isNotEmpty) return t.text;
    }
    return null;
  }

  final track = scoreNode.child('Part')?.childText('trackName');
  return ScoreMetadata(
    title: tag('workTitle'),
    composer: tag('composer'),
    lyricist: tag('lyricist'),
    copyright: tag('copyright'),
    instrument:
        (track == null || track.isEmpty || track == 'Music') ? null : track,
  );
}

class _StaffReader {
  final XmlNode staff;
  final ScoreMetadata metadata;

  /// The part's drumset (pitch → line + notehead), or null for a pitched staff.
  final Map<int, _Drum>? drumset;

  _StaffReader(this.staff, this.metadata, {this.drumset, this.idPrefix = 'e'});

  /// Element-id prefix, made staff-specific when reading a multi-staff document
  /// so ids stay unique across parts.
  final String idPrefix;

  int _nextId = 0;
  bool _leadingSet = false;
  Clef? _clef;
  Clef _leadingClef = Clef.treble;
  KeySignature? _key; // running key; _leadingKey holds the score's initial
  KeySignature? _leadingKey;
  TimeSignature? _time; // running meter; _leadingTime holds the score's initial
  TimeSignature? _leadingTime;
  Tempo? _tempo;

  final _measures = <Measure>[];
  // Slur endpoints in document order: a `<Spanner type="Slur">` with `<next>`
  // marks a start, `<prev>` an end. Paired positionally (non-nested slurs).
  final _slurStartIds = <String>[];
  final _slurEndIds = <String>[];
  final _dynamics = <DynamicMarking>[];
  final _lyrics = <Lyric>[];

  /// Reads a chord's `<Lyrics>` children into [_lyrics], anchored to [id].
  /// `<no>` is the 0-based verse; `syllabic` begin/middle → hyphen to next.
  void _collectLyrics(XmlNode chord, String? id) {
    if (id == null) return;
    for (final lyric in chord.childrenNamed('Lyrics')) {
      final text = lyric.childText('text');
      if (text == null || text.isEmpty) continue;
      final no = int.tryParse(lyric.childText('no') ?? '0') ?? 0;
      final syllabic = lyric.childText('syllabic');
      _lyrics.add(Lyric(
        id,
        text,
        verse: no + 1,
        hyphenToNext: syllabic == 'begin' || syllabic == 'middle',
      ));
    }
  }

  String _newId() => '$idPrefix${_nextId++}';

  Score read() {
    for (final measureNode in staff.childrenNamed('Measure')) {
      _readMeasure(measureNode);
    }
    return Score(
      clef: _leadingClef,
      keySignature: _leadingKey ?? const KeySignature(0),
      timeSignature: _leadingTime,
      measures: _measures,
      slurs: [
        for (var i = 0; i < _slurStartIds.length && i < _slurEndIds.length; i++)
          Slur(_slurStartIds[i], _slurEndIds[i]),
      ],
      dynamics: _dynamics,
      lyrics: _lyrics,
      tempo: _tempo,
      metadata: metadata,
    );
  }

  /// Records a chord's slur endpoints from its `<Spanner type="Slur">` children.
  void _trackChordSlur(XmlNode chord, String? id) {
    if (id == null) return;
    for (final s in chord.childrenNamed('Spanner')) {
      if (s.attributes['type'] != 'Slur') continue;
      if (s.child('next') != null) _slurStartIds.add(id);
      if (s.child('prev') != null) _slurEndIds.add(id);
    }
  }

  void _readMeasure(XmlNode measureNode) {
    final pickup = measureNode.attributes.containsKey('len');
    Clef? clefChange;
    KeySignature? keyChange;
    TimeSignature? timeChange;

    // Voices are <voice> children; a bare measure counts as one voice.
    final voiceNodes = measureNode.childrenNamed('voice').toList();
    final voices = voiceNodes.isEmpty ? [measureNode] : voiceNodes;

    final byVoice = <List<MusicElement>>[];
    final tuplets = <TupletSpan>[];
    for (var v = 0; v < voices.length; v++) {
      final elements = <MusicElement>[];
      int? tupStart, tupActual, tupNormal;
      // Grace <Chord>s accumulate until the next principal chord adopts them.
      var pendingGraces = <Pitch>[];
      var pendingGraceStyle = GraceStyle.acciaccatura;
      // A <Dynamic> applies to the next principal chord.
      String? pendingDynamic;
      for (final node in voices[v].children) {
        switch (node.name) {
          case 'Clef':
            // Clefs/signatures live in the first voice.
            final clef = _clefOf(node);
            if (clef == null) break;
            if (!_leadingSet) {
              _clef = clef;
              _leadingClef = clef;
            } else if (clef != _clef) {
              clefChange = clef;
              _clef = clef;
            }
          case 'KeySig':
            final key = _keyOf(node);
            if (key == null) break;
            if (!_leadingSet) {
              _key = key;
              _leadingKey = key;
            } else if (key != (_key ?? const KeySignature(0))) {
              keyChange = key;
              _key = key; // advance the running key (mirrors _clef)
            }
          case 'TimeSig':
            final time = _timeOf(node);
            if (time == null) break;
            if (!_leadingSet) {
              _time = time;
              _leadingTime = time;
            } else if (time != _time) {
              timeChange = time;
              _time = time; // advance the running meter (mirrors _clef)
            }
          case 'Chord':
            final graceStyle = _graceStyleOf(node);
            if (graceStyle != null) {
              // A grace chord: hold its pitches for the next principal note.
              pendingGraces.addAll(_chordOf(node).pitches);
              pendingGraceStyle = graceStyle;
              break;
            }
            final chord = _chordOf(node,
                graceNotes: pendingGraces, graceStyle: pendingGraceStyle);
            pendingGraces = [];
            pendingGraceStyle = GraceStyle.acciaccatura;
            elements.add(chord);
            _collectLyrics(node, chord.id);
            if (pendingDynamic != null && chord.id != null) {
              final level = _dynamicLevels[pendingDynamic];
              if (level != null) {
                _dynamics.add(DynamicMarking(chord.id!, level));
              }
              pendingDynamic = null;
            }
            // Slurs are tracked in every voice (each <voice> is a contiguous
            // block, so positional pairing stays correct per voice) — a slur in
            // voice 2/3/4 used to be ignored and dropped.
            _trackChordSlur(node, chord.id);
          case 'Rest':
            elements.add(RestElement(_durationOf(node), id: _newId()));
          case 'Tempo':
            // <tempo> is quarter-notes per second → bpm.
            final t = double.tryParse(node.childText('tempo') ?? '');
            if (t != null) _tempo ??= Tempo(t * 60);
          case 'Tuplet':
            tupStart = elements.length;
            tupActual = int.tryParse(node.childText('actualNotes') ?? '');
            tupNormal = int.tryParse(node.childText('normalNotes') ?? '');
          case 'endTuplet':
            // Tuplets are voice-1 only in the model.
            if (v == 0 &&
                tupStart != null &&
                tupActual != null &&
                tupActual >= 2 &&
                tupNormal != null &&
                elements.length - 1 >= tupStart) {
              tuplets.add(TupletSpan(tupStart, elements.length - 1,
                  actual: tupActual, normal: tupNormal));
            }
            tupStart = null;
          case 'Dynamic':
            pendingDynamic = node.childText('subtype');
          default:
            break; // Beam, Spanner, StaffText, …: ignored
        }
      }
      byVoice.add(elements);
    }

    _leadingSet = true;
    _measures.add(Measure(
      byVoice.isEmpty ? const [] : byVoice[0],
      voice2: byVoice.length > 1 ? byVoice[1] : const [],
      voice3: byVoice.length > 2 ? byVoice[2] : const [],
      voice4: byVoice.length > 3 ? byVoice[3] : const [],
      clefChange: clefChange,
      keyChange: keyChange,
      timeChange: timeChange,
      tuplets: tuplets,
      pickup: pickup,
      startRepeat: measureNode.child('startRepeat') != null,
      endRepeat: measureNode.child('endRepeat') != null,
      navigation:
          _navMarks[measureNode.child('Marker')?.childText('subtype') ?? ''],
      volta:
          int.tryParse(measureNode.child('Volta')?.childText('endings') ?? ''),
    ));
  }

  static final _navMarks = {for (final n in NavigationMark.values) n.name: n};

  /// The grace style of a `<Chord>` (`<acciaccatura/>`/`<appoggiatura/>` or the
  /// `<grace…>` family), or null if it is a principal (non-grace) chord.
  static GraceStyle? _graceStyleOf(XmlNode chord) {
    for (final child in chord.children) {
      final n = child.name;
      if (n == 'appoggiatura' || n.startsWith('grace') && !n.contains('acc')) {
        return GraceStyle.appoggiatura;
      }
      if (n == 'acciaccatura') return GraceStyle.acciaccatura;
    }
    return null;
  }

  NoteElement _chordOf(XmlNode chord,
      {List<Pitch> graceNotes = const [],
      GraceStyle graceStyle = GraceStyle.acciaccatura}) {
    final duration = _durationOf(chord);
    var tie = false;
    final pitches = <Pitch>[];
    // On a drum staff, each hit is placed on its drumset line and drawn with
    // the drumset notehead (taken from the first mapped hit of the chord).
    NoteheadShape notehead = NoteheadShape.normal;
    for (final note in chord.childrenNamed('Note')) {
      final spanner = note
          .childrenNamed('Spanner')
          .any((s) => s.attributes['type'] == 'Tie' && s.child('next') != null);
      if (spanner) tie = true;
      final midi = int.tryParse(note.childText('pitch') ?? '');
      if (midi == null) continue;
      final drum = drumset?[midi];
      if (drum != null) {
        // MuseScore line: top line 0, increasing downward; our staffPosition:
        // bottom line 0, increasing upward → position = 8 - line.
        pitches.add(Clef.percussion.pitchAt(8 - drum.line));
        if (notehead == NoteheadShape.normal) notehead = drum.head;
      } else {
        final tpc = int.tryParse(note.childText('tpc') ?? '');
        pitches.add(_pitchOf(tpc, midi));
      }
    }
    if (pitches.isEmpty) {
      // A chord with no readable pitch degrades to a rest of its duration.
      return NoteElement.note(const Pitch(Step.c), duration, id: _newId());
    }
    return NoteElement(
      pitches: pitches,
      duration: duration,
      tieToNext: tie,
      articulations: _articOf(chord),
      ornament: _ornamentOf(chord),
      tremolo: _tremoloOf(chord),
      notehead: notehead,
      graceNotes: graceNotes,
      graceStyle: graceStyle,
      id: _newId(),
    );
  }

  /// The tremolo slash count from `<Tremolo><subtype>rN</subtype>` (r8→1,
  /// r16→2, r32→3…), or null.
  static int? _tremoloOf(XmlNode chord) {
    final sub = chord.child('Tremolo')?.childText('subtype');
    if (sub == null || !sub.startsWith('r')) return null;
    final r = int.tryParse(sub.substring(1));
    if (r == null || r < 8) return null;
    var n = 0, v = r;
    while (v > 8) {
      v ~/= 2;
      n++;
    }
    return n + 1; // r8→1, r16→2, …
  }

  static final _dynamicLevels = {
    for (final l in DynamicLevel.values) l.name: l
  };

  static const _ornamentMap = {
    'ornamentTrill': Ornament.trill,
    'trill': Ornament.trill,
    'ornamentShortTrill': Ornament.shortTrill,
    'prall': Ornament.shortTrill,
    'ornamentMordent': Ornament.mordent,
    'mordent': Ornament.mordent,
    'ornamentTurn': Ornament.turn,
    'turn': Ornament.turn,
    'ornamentTurnInverted': Ornament.invertedTurn,
    'reverseturn': Ornament.invertedTurn,
  };

  static Ornament? _ornamentOf(XmlNode chord) {
    for (final node in chord.childrenNamed('Articulation')) {
      final o = _ornamentMap[node.childText('subtype')];
      if (o != null) return o;
    }
    return null;
  }

  /// MuseScore `<Articulation>` subtypes → articulations. Accepts both the
  /// SMuFL glyph names (MuseScore 4) and the older MuseScore-3 names.
  static const _articMap = {
    'articStaccatoAbove': Articulation.staccato,
    'articStaccatoBelow': Articulation.staccato,
    'staccato': Articulation.staccato,
    'articTenutoAbove': Articulation.tenuto,
    'articTenutoBelow': Articulation.tenuto,
    'tenuto': Articulation.tenuto,
    'articAccentAbove': Articulation.accent,
    'articAccentBelow': Articulation.accent,
    'sforzato': Articulation.accent,
    'articMarcatoAbove': Articulation.marcato,
    'articMarcatoBelow': Articulation.marcato,
    'marcato': Articulation.marcato,
    'fermataAbove': Articulation.fermata,
    'fermataBelow': Articulation.fermata,
    'fermata': Articulation.fermata,
    'stringsUpBow': Articulation.upBow,
    'upbow': Articulation.upBow,
    'stringsDownBow': Articulation.downBow,
    'downbow': Articulation.downBow,
  };

  static Set<Articulation> _articOf(XmlNode chord) {
    final result = <Articulation>{};
    for (final node in chord.childrenNamed('Articulation')) {
      final a = _articMap[node.childText('subtype')];
      if (a != null) result.add(a);
    }
    return result;
  }

  /// The pitch for a MuseScore MIDI [midi] with tonal-pitch-class [tpc]. The
  /// tpc fixes the spelling (step + alter); the octave is recovered so the
  /// pitch sounds at [midi]. Falls back to a sharp spelling of [midi] when the
  /// tpc is missing or implies a triple sharp/flat.
  static Pitch _pitchOf(int? tpc, int midi) {
    if (tpc != null) {
      final f = tpc - 14;
      final alter = _floorDiv(f + 1, 7);
      if (alter >= -2 && alter <= 2) {
        const stepForFifth = {
          -1: Step.f,
          0: Step.c,
          1: Step.g,
          2: Step.d,
          3: Step.a,
          4: Step.e,
          5: Step.b,
        };
        final step = stepForFifth[f - 7 * alter]!;
        final octave = (midi - step.semitonesFromC - alter) ~/ 12 - 1;
        return Pitch(step, alter: alter, octave: octave);
      }
    }
    return _spellFromMidi(midi);
  }

  /// A default (sharp) spelling of MIDI number [midi].
  static Pitch _spellFromMidi(int midi) {
    const table = [
      (Step.c, 0),
      (Step.c, 1),
      (Step.d, 0),
      (Step.d, 1),
      (Step.e, 0),
      (Step.f, 0),
      (Step.f, 1),
      (Step.g, 0),
      (Step.g, 1),
      (Step.a, 0),
      (Step.a, 1),
      (Step.b, 0),
    ];
    final (step, alter) = table[((midi % 12) + 12) % 12];
    final octave = (midi - step.semitonesFromC - alter) ~/ 12 - 1;
    return Pitch(step, alter: alter, octave: octave);
  }

  static int _floorDiv(int a, int b) => (a - ((a % b) + b) % b) ~/ b;

  Clef? _clefOf(XmlNode node) {
    final code = node.childText('concertClefType') ??
        node.childText('clefType') ??
        node.childText('subtype');
    if (code == null) return null;
    return _clefs[code] ?? Clef.treble;
  }

  KeySignature? _keyOf(XmlNode node) {
    final fifths = int.tryParse(node.childText('concertKey') ??
        node.childText('accidental') ??
        node.childText('subtype') ??
        '');
    if (fifths == null || fifths < -7 || fifths > 7) return null;
    return KeySignature(fifths);
  }

  TimeSignature? _timeOf(XmlNode node) {
    final n = int.tryParse(node.childText('sigN') ?? '');
    final d = int.tryParse(node.childText('sigD') ?? '');
    if (n == null || d == null) return null;
    return TimeSignature.tryParse(n, d);
  }

  /// The duration of a `<Chord>`/`<Rest>` from its `<durationType>` + `<dots>`.
  /// A whole-measure rest (`durationType>measure`) is mapped through the
  /// running time signature.
  NoteDuration _durationOf(XmlNode node) {
    final type = node.childText('durationType');
    final dots = (int.tryParse(node.childText('dots') ?? '0') ?? 0).clamp(0, 2);
    if (type == 'measure') {
      final f = (_time ?? TimeSignature.fourFour).toFraction();
      return _durationForFraction(f.numerator, f.denominator) ??
          NoteDuration.whole;
    }
    final base = type == null ? null : _durationBases[type];
    if (base == null) {
      throw FormatException('Unsupported durationType: "$type"');
    }
    return NoteDuration(base, dots: dots);
  }

  /// The [NoteDuration] whose whole-note value equals [n]/[d], or null when no
  /// single base(+dots) matches (e.g. an additive 5/4 measure rest).
  static NoteDuration? _durationForFraction(int n, int d) {
    for (final base in DurationBase.values) {
      final (bn, bd) =
          base == DurationBase.breve ? (2, 1) : (1, base.denominator);
      for (var dots = 0; dots <= 2; dots++) {
        final mulN = (1 << (dots + 1)) - 1; // dotted numerator
        final mulD = 1 << dots;
        // base * (mulN/mulD) == n/d  ⇔  bn*mulN*d == n*bd*mulD
        if (bn * mulN * d == n * bd * mulD) {
          return NoteDuration(base, dots: dots);
        }
      }
    }
    return null;
  }
}
