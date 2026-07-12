/// MuseScore import (subset): a `.mscx` (MuseScore XML) document → [Score].
///
/// Reads the same shared subset the writer emits — clef (with mid-score
/// changes), key/time signatures, measures, notes/chords, rests, durations
/// (breve…64th with dots), two voices, ties and pickup measures — plus the
/// common shapes real MuseScore 3/4 files use for those (e.g. `<KeySig>`
/// stored as `concertKey`, `accidental` or `subtype`; whole-measure rests as
/// `durationType>measure`). Unsupported markup (slurs, tuplets, articulations,
/// lyrics, dynamics, beams, spanners) is ignored. Pure Dart (web-safe); the
/// `.mscz` ZIP container is unwrapped in `partitura_cli`.
library;

import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../musicxml/xml_reader.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
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

/// MuseScore concert clef-type code → partitura [Clef]. Octave-doubled and
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
  return _StaffReader(staves[staffIndex]).read();
}

class _StaffReader {
  final XmlNode staff;
  _StaffReader(this.staff);

  int _nextId = 0;
  bool _leadingSet = false;
  Clef? _clef;
  Clef _leadingClef = Clef.treble;
  KeySignature? _key;
  TimeSignature? _time;

  final _measures = <Measure>[];

  String _newId() => 'e${_nextId++}';

  Score read() {
    for (final measureNode in staff.childrenNamed('Measure')) {
      _readMeasure(measureNode);
    }
    return Score(
      clef: _leadingClef,
      keySignature: _key ?? const KeySignature(0),
      timeSignature: _time,
      measures: _measures,
    );
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
    for (var v = 0; v < voices.length; v++) {
      final elements = <MusicElement>[];
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
            } else if (key != (_key ?? const KeySignature(0))) {
              keyChange = key;
            }
          case 'TimeSig':
            final time = _timeOf(node);
            if (time == null) break;
            if (!_leadingSet) {
              _time = time;
            } else if (time != _time) {
              timeChange = time;
            }
          case 'Chord':
            elements.add(_chordOf(node));
          case 'Rest':
            elements.add(RestElement(_durationOf(node), id: _newId()));
          default:
            break; // Beam, Spanner, StaffText, Dynamic, Tuplet, …: ignored
        }
      }
      byVoice.add(elements);
    }

    _leadingSet = true;
    _measures.add(Measure(
      byVoice.isEmpty ? const [] : byVoice[0],
      voice2: byVoice.length > 1 ? byVoice[1] : const [],
      clefChange: clefChange,
      keyChange: keyChange,
      timeChange: timeChange,
      pickup: pickup,
    ));
  }

  NoteElement _chordOf(XmlNode chord) {
    final duration = _durationOf(chord);
    var tie = false;
    final pitches = <Pitch>[];
    for (final note in chord.childrenNamed('Note')) {
      final spanner = note
          .childrenNamed('Spanner')
          .any((s) => s.attributes['type'] == 'Tie' && s.child('next') != null);
      if (spanner) tie = true;
      final midi = int.tryParse(note.childText('pitch') ?? '');
      if (midi == null) continue;
      final tpc = int.tryParse(note.childText('tpc') ?? '');
      pitches.add(_pitchOf(tpc, midi));
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
      id: _newId(),
    );
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
    return TimeSignature(n, d);
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
