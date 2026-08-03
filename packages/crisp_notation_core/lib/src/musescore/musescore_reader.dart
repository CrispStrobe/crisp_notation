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
import '../theory/fraction.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/tempo.dart';
import '../theory/time_signature.dart';

/// MuseScore `<durationType>` name → [DurationBase].
const _durationBases = {
  'long': DurationBase.long,
  'breve': DurationBase.breve,
  'whole': DurationBase.whole,
  'half': DurationBase.half,
  'quarter': DurationBase.quarter,
  'eighth': DurationBase.eighth,
  '16th': DurationBase.sixteenth,
  '32nd': DurationBase.thirtySecond,
  '64th': DurationBase.sixtyFourth,
  '128th': DurationBase.oneHundredTwentyEighth,
  '256th': DurationBase.twoHundredFiftySixth,
  '512th': DurationBase.fiveHundredTwelfth,
  '1024th': DurationBase.oneThousandTwentyFourth,
};

/// MuseScore duration names shorter than a 64th (128th, 256th, 512th, 1024th).
/// No [DurationBase] represents them; the reader clamps them to a 64th.
final _tooShort = RegExp(r'^(128|256|512|1024)th$');

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
  // MuseScore 2.x+ wraps everything in <Score>; MuseScore 1.x hangs <Part>/
  // <Staff> directly under <museScore>. Fall back to the root so both parse.
  final scoreNode = root.child('Score') ?? root;
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
  // MuseScore 2.x+ wraps everything in <Score>; MuseScore 1.x hangs <Part>/
  // <Staff> directly under <museScore>. Fall back to the root so both parse.
  final scoreNode = root.child('Score') ?? root;
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
  int? midiProgram;
  var isPercussion = false;
  if (id != null) {
    for (final part in scoreNode.childrenNamed('Part')) {
      if (part.childrenNamed('Staff').any((s) => s.attributes['id'] == id)) {
        track = part.childText('trackName');
        // The GM voice: `<Instrument>`'s `<Channel><program value="N"/>` (0-based
        // GM in MuseScore) and `<useDrumset>1` → percussion.
        final inst = part.child('Instrument');
        if (inst != null) {
          // Percussion: an explicit `<useDrumset>1`, or a `<Drum>` map (older
          // files omit useDrumset but list drums — matching `_drumsetFor`).
          if (inst.childText('useDrumset') == '1' ||
              inst.childrenNamed('Drum').isNotEmpty) {
            isPercussion = true;
          }
          final value =
              inst.child('Channel')?.child('program')?.attributes['value'];
          final p = int.tryParse(value ?? '');
          if (p != null) midiProgram = p.clamp(0, 127);
        }
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
    midiProgram: midiProgram,
    isPercussion: isPercussion,
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
  /// Chord symbols collected from `<Harmony>` elements.
  final List<ChordSymbol> _chordSymbols = [];

  /// Reads a `<Harmony>`, or null when its quality cannot be established.
  ///
  /// 🔴 **A chord is OMITTED rather than guessed.** MuseScore 1.x — which most of
  /// the corpus is — writes the quality as an integer `<extension>` indexing a
  /// chord-description list, not as a name. Across a 40-file sample four values
  /// cover 533 of 534 harmonies (1×412, 64×74, 16×47, 177×1), and only `1`, the
  /// plain-triad default, can be justified from the material: `joy-world.mscz`
  /// gives root 14 and root 15 under "Joy to the World", i.e. C and G major.
  /// Mapping `64` and `16` on a hunch would emit confident, wrong chords for
  /// roughly a quarter of them — so they are skipped until someone establishes
  /// the mapping. Newer files write `<name>`, which IS read.
  ({Pitch root, ChordSymbolKind kind, Pitch? bass})? _harmonyOf(XmlNode node) {
    final rootTpc = int.tryParse(node.childText('root') ?? '');
    if (rootTpc == null) return null;
    final root = _pitchFromTpc(rootTpc);
    final baseTpc = int.tryParse(node.childText('base') ?? '');
    final bass = baseTpc == null ? null : _pitchFromTpc(baseTpc);

    final name = node.childText('name');
    if (name != null && name.trim().isNotEmpty) {
      return (root: root, kind: _kindFromName(name.trim()), bass: bass);
    }
    // ⚠️ MuseScore writes NEITHER `<name>` nor `<extension>` for a plain major
    // triad — the commonest chord there is. Treating "no quality stated" as
    // unknown dropped every one of them, from our own output and from real
    // MuseScore files alike. "Absent" and "present but unrecognised" are
    // different answers: only the second is a quality we cannot establish.
    final extText = node.childText('extension');
    if (extText == null || extText.trim().isEmpty) {
      return (root: root, kind: ChordSymbolKind.major, bass: bass);
    }
    final kind = _kindFromExtension(int.tryParse(extText));
    if (kind == null) return null; // unknown quality — say nothing
    return (root: root, kind: kind, bass: bass);
  }

  /// MuseScore's tonal pitch class → a spelled [Pitch]. TPC walks the line of
  /// fifths from F, so 13 = F, 14 = C, 15 = G, 20 = F♯, 6 = F♭.
  ///
  /// ⚠️ Getting this wrong yields plausible but WRONG roots — every chord would
  /// still look like a chord — so it has its own test.
  static Pitch _pitchFromTpc(int tpc) {
    const order = [Step.f, Step.c, Step.g, Step.d, Step.a, Step.e, Step.b];
    final idx = ((tpc + 1) % 7 + 7) % 7;
    final alter = ((tpc + 1) / 7).floor() - 2;
    return Pitch(order[idx], alter: alter);
  }

  /// MuseScore 1.x's integer chord id → a quality, or null when unknown.
  ///
  /// 📊 **INFERRED FROM THE MUSIC, not from documentation — and the evidence is
  /// recorded because the mapping is an inference.** 1.x indexes a
  /// chord-description list we cannot resolve, so the interval each value's
  /// melody actually plays above its own root was aggregated over 132 corpus
  /// files (one-chord bars only, so attribution is unambiguous):
  ///
  /// | ext | n | top intervals |
  /// |---|---|---|
  /// | 1 | 1920 | 1 · 5 · **3** (25.4%) — no ♭3 in the top six |
  /// | 64 | 356 | 5 · 1 · **♭7** (17.4%) · 3 |
  /// | 16 | 138 | 1 · 5 · **♭3** (23.2%) — no major 3 in the top six |
  ///
  /// The separation is unambiguous: major, dominant seventh, minor. `1` is
  /// corroborated independently — `joy-world.mscz` gives roots 14 and 15 under
  /// "Joy to the World", i.e. C and G major.
  ///
  /// ⚠️ Values outside this table still return null rather than a guess. If real
  /// documentation ever contradicts the above, trust it over this — but replace
  /// the table, do not extend it by pattern-matching.
  static ChordSymbolKind? _kindFromExtension(int? ext) => switch (ext) {
        1 => ChordSymbolKind.major,
        16 => ChordSymbolKind.minor,
        64 => ChordSymbolKind.dominantSeventh,
        _ => null,
      };

  static ChordSymbolKind _kindFromName(String raw) {
    final n = raw.toLowerCase().replaceAll(' ', '');
    return switch (n) {
      'm' || 'min' || 'minor' || '-' => ChordSymbolKind.minor,
      'm7' || 'min7' || '-7' => ChordSymbolKind.minorSeventh,
      '7' || 'dom7' => ChordSymbolKind.dominantSeventh,
      'maj7' || 'ma7' || 'major7' => ChordSymbolKind.majorSeventh,
      '6' => ChordSymbolKind.sixth,
      'm6' || 'min6' => ChordSymbolKind.minorSixth,
      '9' => ChordSymbolKind.dominantNinth,
      'dim' => ChordSymbolKind.diminished,
      'dim7' => ChordSymbolKind.diminishedSeventh,
      'aug' || '+' => ChordSymbolKind.augmented,
      'sus4' || 'sus' => ChordSymbolKind.suspendedFourth,
      'sus2' => ChordSymbolKind.suspendedSecond,
      'm7b5' || 'ø' => ChordSymbolKind.halfDiminishedSeventh,
      'mmaj7' || 'minmaj7' || 'mmajor7' => ChordSymbolKind.minorMajorSeventh,
      '' || 'maj' || 'major' => ChordSymbolKind.major,
      _ => ChordSymbolKind.major,
    };
  }

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

  /// The `<fractions>` distance each slur start declares to its end.
  ///
  /// ⚠️ MuseScore STATES where a spanner ends, and pairing starts to ends by
  /// document position instead threw that away — which crosses nested slurs
  /// (`e0-e3` inside `e1-e2` paired as `e0-e2` and `e1-e3`) and collapses a
  /// chain sharing a boundary note. Parallel to [_slurStartIds] by index.
  final _slurStartDeltas = <Fraction?>[];
  // Hairpins ride the SAME `<Spanner>` mechanism, so they are paired the same
  // way: endpoints in document order. 81% of the corpus `.mscx` carry one.
  final _annotations = <Annotation>[];
  final _hairpinStartIds = <String>[];
  final _hairpinEndIds = <String>[];
  final _hairpinTypes = <HairpinType>[];
  // Pedal (1,284 of 4,000 sampled `.mscx`) and Ottava (586). Both were already
  // in the model and already read from MusicXML, so this was a pure codec gap.
  final _pedalStartIds = <String>[];
  final _pedalEndIds = <String>[];
  final _glissStartIds = <String>[];
  final _glissEndIds = <String>[];
  final _cueNoteIds = <String>[];
  final _figuredBass = <FiguredBass>[];
  final _portStartIds = <String>[];
  final _portEndIds = <String>[];
  final _trillStartIds = <String>[];
  final _trillEndIds = <String>[];
  final _ottavaStartIds = <String>[];
  final _ottavaEndIds = <String>[];
  final _ottavaDown = <bool>[];
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
      // A melisma is `<ticks>` (with `<ticks_f>` alongside): the DURATION the
      // syllable is held over. The model records only the FACT of an extender,
      // which is the part every other format agrees on — MusicXML's `<extend/>`
      // and LilyPond's `__` carry no length either. 895 of 1,500 sampled
      // `.mscx` have one and we were dropping every single one.
      final melisma = lyric.child('ticks') != null;
      _lyrics.add(Lyric(
        id,
        text,
        verse: no + 1,
        hyphenToNext: syllabic == 'begin' || syllabic == 'middle',
        extender: melisma,
      ));
    }
  }

  String _newId() => '$idPrefix${_nextId++}';

  Score read() {
    for (final measureNode in staff.childrenNamed('Measure')) {
      _readMeasure(measureNode);
    }
    return Score(
      chordSymbols: _chordSymbols,
      clef: _leadingClef,
      keySignature: _leadingKey ?? const KeySignature(0),
      timeSignature: _leadingTime,
      measures: _measures,
      slurs: _pairSlurs(),
      annotations: _annotations,
      hairpins: [
        for (var i = 0;
            i < _hairpinStartIds.length && i < _hairpinEndIds.length;
            i++)
          Hairpin(
              _hairpinStartIds[i],
              _hairpinEndIds[i],
              i < _hairpinTypes.length
                  ? _hairpinTypes[i]
                  : HairpinType.crescendo),
      ],
      pedals: [
        for (var i = 0;
            i < _pedalStartIds.length && i < _pedalEndIds.length;
            i++)
          Pedal(_pedalStartIds[i], _pedalEndIds[i]),
      ],
      glissandos: [
        for (var i = 0;
            i < _glissStartIds.length && i < _glissEndIds.length;
            i++)
          Glissando(_glissStartIds[i], _glissEndIds[i]),
      ],
      cueNoteIds: _cueNoteIds,
      figuredBass: _figuredBass,
      portamentos: [
        for (var i = 0; i < _portStartIds.length && i < _portEndIds.length; i++)
          Portamento(_portStartIds[i], _portEndIds[i]),
      ],
      trillExtensions: [
        for (var i = 0;
            i < _trillStartIds.length && i < _trillEndIds.length;
            i++)
          TrillExtension(_trillStartIds[i], _trillEndIds[i]),
      ],
      ottavas: [
        for (var i = 0;
            i < _ottavaStartIds.length && i < _ottavaEndIds.length;
            i++)
          Ottava(_ottavaStartIds[i], _ottavaEndIds[i],
              down: i < _ottavaDown.length && _ottavaDown[i]),
      ],
      dynamics: _dynamics,
      lyrics: _lyrics,
      tempo: _tempo,
      metadata: metadata,
    );
  }

  /// The `<fractions>` inside a `<next>`/`<prev>` location, if it states one.
  ///
  /// `<measures>` is deliberately NOT folded in: it would need each start's
  /// measure and the lengths that follow, and a location carrying it always
  /// carries the remainder here too. Absent means "fall back to position".
  Fraction? _locationDelta(XmlNode? side) {
    final text = side?.child('location')?.childText('fractions');
    if (text == null) return null;
    final parts = text.split('/');
    if (parts.length != 2) return null;
    final n = int.tryParse(parts[0]);
    final d = int.tryParse(parts[1]);
    if (n == null || d == null || d == 0) return null;
    return Fraction(n, d);
  }

  /// Pairs slur starts with ends by the DISTANCE each start declares.
  ///
  /// Falls back to positional pairing for any start whose declared end is not
  /// found — third-party files use `<measures>` too, and an unmatched start is
  /// better placed approximately than dropped.
  List<Slur> _pairSlurs() {
    final onset = <String, Fraction>{};
    var measureStart = Fraction.zero;
    for (final m in _measures) {
      var acc = measureStart;
      for (final e in m.elements) {
        if (e.id != null) onset[e.id!] = acc;
        acc = acc + e.duration.toFraction();
      }
      final measureEnd = acc;
      for (final voice in [m.voice2, m.voice3, m.voice4]) {
        var vacc = measureStart;
        for (final e in voice) {
          if (e.id != null) onset[e.id!] = vacc;
          vacc = vacc + e.duration.toFraction();
        }
      }
      measureStart = measureEnd;
    }
    final ends = List<String?>.from(_slurEndIds);
    final out = <Slur>[];
    final unresolved = <int>[];
    for (var i = 0; i < _slurStartIds.length; i++) {
      final start = _slurStartIds[i];
      final delta = i < _slurStartDeltas.length ? _slurStartDeltas[i] : null;
      final from = onset[start];
      var matched = false;
      if (delta != null && from != null) {
        final target = from + delta;
        for (var j = 0; j < ends.length; j++) {
          final end = ends[j];
          if (end != null && onset[end] == target) {
            out.add(Slur(start, end));
            ends[j] = null;
            matched = true;
            break;
          }
        }
      }
      if (!matched) unresolved.add(i);
    }
    final leftovers = [
      for (final e in ends)
        if (e != null) e
    ];
    for (var k = 0; k < unresolved.length && k < leftovers.length; k++) {
      out.add(Slur(_slurStartIds[unresolved[k]], leftovers[k]));
    }
    return out;
  }

  /// Records a chord's slur endpoints from its `<Spanner type="Slur">` children.
  void _trackChordSlur(XmlNode chord, String? id) {
    if (id == null) return;
    for (final s in chord.childrenNamed('Spanner')) {
      switch (s.attributes['type']) {
        case 'Slur':
          if (s.child('next') != null) {
            _slurStartIds.add(id);
            _slurStartDeltas.add(_locationDelta(s.child('next')));
          }
          if (s.child('prev') != null) _slurEndIds.add(id);
        case 'HairPin':
          if (s.child('next') != null) {
            _hairpinStartIds.add(id);
            // `<subtype>` 0 is a crescendo and 1 a diminuendo — read off real
            // MuseScore files, not assumed. Anything else defaults to
            // crescendo rather than dropping the hairpin.
            final sub = s.child('HairPin')?.childText('subtype')?.trim();
            _hairpinTypes.add(
                sub == '1' ? HairpinType.diminuendo : HairpinType.crescendo);
          }
          if (s.child('prev') != null) _hairpinEndIds.add(id);
      }
    }
  }

  void _readMeasure(XmlNode measureNode) {
    final pickup = measureNode.attributes.containsKey('len');
    Clef? clefChange;
    KeySignature? keyChange;
    Tempo? measureTempo;
    final inlineClefs = <InlineClefChange>[];
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
      final pendingHarmonies =
          <({Pitch root, ChordSymbolKind kind, Pitch? bass})>[];
      var pendingGraceStyle = GraceStyle.acciaccatura;
      // A <Dynamic> applies to the next principal chord.
      String? pendingDynamic;
      // (isStart, type) of a voice-level hairpin spanner awaiting its chord.
      // ⚠️ A LIST, not one slot. A note that ENDS one hairpin and STARTS the
      // next — an ordinary `<` then `>` phrase — carries two `<Spanner>`
      // siblings, and a single pending slot kept only the second: the first
      // hairpin vanished.
      final pendingHairpins = <(bool, HairpinType)>[];
      bool? pendingPedal; // true = start, false = end
      bool? pendingGliss;
      var pendingGlissPort = false;
      List<String>? pendingFigures;
      bool? pendingTrill;
      (bool, bool)? pendingOttava; // (isStart, down)
      String? pendingStaffText;

      /// Attaches a voice-level spanner waiting for its anchor element.
      ///
      /// ⚠️ Pedals and ottavas anchor to a REST as readily as to a chord — a
      /// pedal is held through rests by definition, and the corpus file that
      /// surfaced this opens its pedal on one. Attaching only on `<Chord>`, as
      /// the hairpin work did, reads every one we wrote and none of theirs.
      void attachPendingSpanners(String? id) {
        if (id == null) return;
        if (pendingPedal != null) {
          (pendingPedal! ? _pedalStartIds : _pedalEndIds).add(id);
          pendingPedal = null;
        }
        if (pendingGliss != null) {
          if (pendingGliss!) {
            (pendingGlissPort ? _portStartIds : _glissStartIds).add(id);
          } else {
            // A stop closes whichever kind is still open.
            if (_portStartIds.length > _portEndIds.length) {
              _portEndIds.add(id);
            } else {
              _glissEndIds.add(id);
            }
          }
          pendingGliss = null;
        }
        if (pendingTrill != null) {
          (pendingTrill! ? _trillStartIds : _trillEndIds).add(id);
          pendingTrill = null;
        }
        if (pendingOttava != null) {
          if (pendingOttava!.$1) {
            _ottavaStartIds.add(id);
            _ottavaDown.add(pendingOttava!.$2);
          } else {
            _ottavaEndIds.add(id);
          }
          pendingOttava = null;
        }
      }

      for (final node in voices[v].children) {
        switch (node.name) {
          case 'Clef':
            // Clefs/signatures live in the first voice.
            final clef = _clefOf(node);
            if (clef == null) break;
            // ⚠️ POSITION decides, and it decides FIRST. A `<Clef>` after
            // notes have already been read is a MID-BAR change at that onset,
            // whatever measure it is in — `_leadingSet` stays false for the
            // whole of measure 0, so testing it first swallowed a mid-bar clef
            // there as the score's opening clef.
            var at = Fraction.zero;
            for (final e in elements) {
              at = at + e.duration.toFraction();
            }
            if (at > Fraction.zero) {
              if (clef != _clef) {
                inlineClefs.add(InlineClefChange(at, clef));
                _clef = clef;
              }
            } else if (!_leadingSet) {
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
            // Attach any harmonies waiting for a note. Several can precede one
            // chord (MuseScore gives each its own <tick>), so they are spread
            // over the following notes rather than collapsed — dropping a chord
            // leaves a hole in the chart, which is worse than a small shift.
            if (chord.id != null && pendingHarmonies.isNotEmpty) {
              _chordSymbols.add(
                ChordSymbol(
                  chord.id!,
                  pendingHarmonies.first.root,
                  pendingHarmonies.first.kind,
                  bass: pendingHarmonies.first.bass,
                ),
              );
              pendingHarmonies.removeAt(0);
            }
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
            // A voice-level `<Spanner type="HairPin">` sits BEFORE the chord it
            // applies to, so it is held and attached when that chord arrives —
            // the same shape as `<Harmony>` and `<Dynamic>` above.
            final figs = pendingFigures;
            if (figs != null && chord.id != null) {
              if (figs.isNotEmpty) {
                _figuredBass.add(FiguredBass(chord.id!, figs));
              }
              pendingFigures = null;
            }
            if (pendingHairpins.isNotEmpty && chord.id != null) {
              for (final p in pendingHairpins) {
                if (p.$1) {
                  _hairpinStartIds.add(chord.id!);
                  _hairpinTypes.add(p.$2);
                } else {
                  _hairpinEndIds.add(chord.id!);
                }
              }
              pendingHairpins.clear();
            }
            attachPendingSpanners(chord.id);
            if (pendingStaffText != null && chord.id != null) {
              _annotations.add(Annotation(chord.id!, pendingStaffText));
              pendingStaffText = null;
            }
          case 'Spanner':
            // ⚠️ A HairPin spanner is a SIBLING of `<Chord>` in real MuseScore
            // files, not a child of it the way a Slur is. Reading it only from
            // inside a chord — which is where our own writer put it — found
            // every hairpin we wrote and none of the 6,807 corpus files'.
            final isStart = node.child('next') != null;
            final isEnd = node.child('prev') != null;
            switch (node.attributes['type']) {
              case 'HairPin':
                final sub = node.child('HairPin')?.childText('subtype')?.trim();
                final type =
                    sub == '1' ? HairpinType.diminuendo : HairpinType.crescendo;
                if (isStart) {
                  pendingHairpins.add((true, type));
                } else if (isEnd) {
                  pendingHairpins.add((false, type));
                }
              case 'Pedal':
                if (isStart) {
                  pendingPedal = true;
                } else if (isEnd) {
                  pendingPedal = false;
                }
              case 'Glissando':
                // subtype 0 is the straight line — a portamento; 1 the wavy
                // one, a glissando. One spanner, two concepts.
                final gsub =
                    node.child('Glissando')?.childText('subtype')?.trim();
                if (isStart) {
                  pendingGliss = true;
                  pendingGlissPort = gsub == '0';
                } else if (isEnd) {
                  pendingGliss = false;
                }
              case 'Trill':
                if (isStart) {
                  pendingTrill = true;
                } else if (isEnd) {
                  pendingTrill = false;
                }
              case 'Ottava':
                // `<subtype>` is the printed name: 8va/15ma sound HIGHER than
                // written, 8vb/15mb lower. The model's `down` follows the
                // MusicXML sense — MusicXML "down" writes the notes lower, an
                // 8va bracket ABOVE — so a `…b` subtype maps to down: false.
                final sub =
                    node.child('Ottava')?.childText('subtype')?.trim() ?? '';
                final down = !sub.endsWith('b');
                if (isStart) {
                  pendingOttava = (true, down);
                } else if (isEnd) {
                  pendingOttava = (false, down);
                }
            }
          case 'FiguredBass':
            pendingFigures = [
              for (final item in node.childrenNamed('FiguredBassItem'))
                if ((item.childText('digit') ?? '').trim().isNotEmpty)
                  item.childText('digit')!.trim(),
            ];
          case 'Harmony':
            // A chord symbol. It precedes the note it sits over, so it is held
            // and attached when that note arrives.
            final h = _harmonyOf(node);
            if (h != null) pendingHarmonies.add(h);
          case 'StaffText':
            // Precedes the chord it belongs to, like `<Harmony>` and
            // `<Dynamic>`, so it is held until that chord arrives.
            final txt = node.childText('text')?.trim();
            if (txt != null && txt.isNotEmpty) pendingStaffText = txt;
          case 'Breath':
            // A `<Breath>` FOLLOWS the chord it belongs to — you breathe after
            // the note — so it attaches BACKWARDS to the last element, unlike
            // the spanners above which are held for the element that follows.
            if (elements.isNotEmpty) {
              final last = elements.last;
              if (last is NoteElement) {
                elements[elements.length - 1] = last.copyWith(
                  articulations: {...last.articulations, Articulation.breath},
                );
              }
            }
          case 'Rest':
            final rest = RestElement(_durationOf(node), id: _newId());
            elements.add(rest);
            attachPendingSpanners(rest.id);
          case 'Tempo':
            // <tempo> is quarter-notes per second → bpm. ⚠️ POSITION decides
            // which it is, not order: a piece whose only marking is a
            // mid-score change has no earlier <Tempo>, so "is this the first?"
            // would file it as the score tempo.
            final t = double.tryParse(node.childText('tempo') ?? '');
            if (t != null) {
              if (_measures.isEmpty && elements.isEmpty) {
                _tempo ??= Tempo(t * 60);
              } else {
                measureTempo = Tempo(t * 60);
              }
            }
          case 'Tuplet':
            tupStart = elements.length;
            tupActual = int.tryParse(node.childText('actualNotes') ?? '');
            tupNormal = int.tryParse(node.childText('normalNotes') ?? '');
          case 'endTuplet':
            // TupletSpan carries the voice it addresses, so an inner voice's
            // tuplet is representable. The old `v == 0` gate here was written
            // against a model that had no such field, and it silently
            // un-tripleted every tuplet below voice 1.
            if (v < 4 &&
                tupStart != null &&
                tupActual != null &&
                tupActual >= 2 &&
                tupNormal != null &&
                elements.length - 1 >= tupStart) {
              tuplets.add(TupletSpan(tupStart, elements.length - 1,
                  actual: tupActual, normal: tupNormal, voice: v));
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
      inlineClefs: inlineClefs,
      keyChange: keyChange,
      timeChange: timeChange,
      tempoChange: measureTempo,
      tuplets: tuplets,
      pickup: pickup,
      startRepeat: measureNode.child('startRepeat') != null,
      endRepeat: measureNode.child('endRepeat') != null,
      barline: _mscxBarlineOf(measureNode),
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
      // An explicit `<head>` on the note. Only the drumset filled this before,
      // so a notehead shape on an ordinary staff was read by nothing — and
      // written by nothing either.
      if (notehead == NoteheadShape.normal) {
        notehead = switch (note.childText('head')?.trim()) {
          'cross' => NoteheadShape.x,
          'diamond' => NoteheadShape.diamond,
          'triangle' => NoteheadShape.triangleUp,
          'slash' => NoteheadShape.slash,
          'xcircle' => NoteheadShape.circleX,
          _ => NoteheadShape.normal,
        };
      }
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
      fingerings: _fingeringsOf(chord),
      arpeggio: _arpeggioOf(chord),
      tremolo: _tremoloOf(chord),
      notehead: notehead,
      graceNotes: graceNotes,
      graceStyle: graceStyle,
      id: _cueOrId(chord),
    );
  }

  /// The chord's new id, remembering it when `<small>` marks it a CUE note —
  /// the model holds those on the score, not on the element.
  String _cueOrId(XmlNode chord) {
    final id = _newId();
    if (chord.childText('small')?.trim() == '1') _cueNoteIds.add(id);
    return id;
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
    'articStaccatissimoAbove': Articulation.staccatissimo,
    'articStaccatissimoBelow': Articulation.staccatissimo,
    'articStaccatissimoWedgeAbove': Articulation.staccatissimo,
    'articStaccatissimoWedgeBelow': Articulation.staccatissimo,
    'staccatissimo': Articulation.staccatissimo,
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

  /// The chord's `<Arpeggio><subtype>`. MuseScore's type 2 is the downward
  /// roll; 0 and 1 are both upward, 0 being the plain one the corpus uses.
  static Arpeggio? _arpeggioOf(XmlNode chord) {
    final a = chord.child('Arpeggio');
    if (a == null) return null;
    return a.childText('subtype')?.trim() == '2' ? Arpeggio.down : Arpeggio.up;
  }

  /// Finger numbers from a chord's `<Note><Fingering><text>` children.
  static List<int> _fingeringsOf(XmlNode chord) {
    final out = <int>[];
    for (final note in chord.childrenNamed('Note')) {
      for (final f in note.childrenNamed('Fingering')) {
        final n = int.tryParse(f.childText('text')?.trim() ?? '');
        if (n != null) out.add(n);
      }
    }
    return out;
  }

  TimeSignature? _timeOf(XmlNode node) {
    // MuseScore 2.x+: <sigN>/<sigD>.  MuseScore 1.x: <nom1> (or <nom>) / <den>.
    final n = int.tryParse(node.childText('sigN') ??
        node.childText('nom1') ??
        node.childText('nom') ??
        '');
    final d =
        int.tryParse(node.childText('sigD') ?? node.childText('den') ?? '');
    if (n == null || d == null) return null;
    // ⚠️ `<subtype>` on a 1.x `<TimeSig>` is a PACKED value with no sigN/sigD
    // beside it, which is why this is read only when the numbers were found.
    final symbol = switch (node.childText('subtype')) {
      '1' => TimeSymbol.common,
      '2' => TimeSymbol.cut,
      _ => TimeSymbol.numeric,
    };
    return TimeSignature.tryParse(n, d, symbol: symbol);
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
      // Durations shorter than a 64th (128th/256th/…) have no [DurationBase] —
      // they are vanishingly rare (a fast tremolo/ornament). Clamp them to a
      // 64th so the whole score still loads, rather than throwing it away; the
      // clamped note reads slightly long. Anything else is genuinely unknown.
      if (type != null && _tooShort.hasMatch(type)) {
        return NoteDuration(DurationBase.sixtyFourth, dots: dots);
      }
      throw FormatException('Unsupported durationType: "$type"');
    }
    return NoteDuration(base, dots: dots);
  }

  /// The [NoteDuration] whose whole-note value equals [n]/[d], or null when no
  /// single base(+dots) matches (e.g. an additive 5/4 measure rest).
  static NoteDuration? _durationForFraction(int n, int d) {
    for (final base in DurationBase.values) {
      final (bn, bd) = base.wholeValue;
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

/// The `<BarLine><subtype>` anywhere in [measureNode]'s voices, as a style.
///
/// MuseScore puts the barline inside a `<voice>` rather than on the measure,
/// so it is searched for rather than read off an attribute.
BarlineStyle _mscxBarlineOf(XmlNode measureNode) {
  for (final voice in measureNode.childrenNamed('voice')) {
    for (final bar in voice.childrenNamed('BarLine')) {
      final sub = bar.childText('subtype')?.trim();
      final style = switch (sub) {
        'double' => BarlineStyle.doubleBar,
        'end' => BarlineStyle.finalBar,
        'heavy' => BarlineStyle.heavy,
        'dashed' => BarlineStyle.dashed,
        'dotted' => BarlineStyle.dotted,
        'reverse-end' => BarlineStyle.reverseFinal,
        'none' => BarlineStyle.none,
        _ => null,
      };
      if (style != null) return style;
    }
  }
  return BarlineStyle.normal;
}
