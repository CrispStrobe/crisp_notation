/// MEI (Music Encoding Initiative) import (subset): an `<mei>` document →
/// [Score]. Reads the subset the writer emits — clef (with mid-score changes
/// as inline `<clef>`/`<keySig>`/`<meterSig>`), key/time signatures, measures,
/// notes/chords, rests, durations (breve…64th with dots), two voices (layers),
/// ties, pickup measures, articulations (`@artic`/`@fermata`) and ornaments
/// (`<trill>`/`<mordent>`/`<turn>` control events). Pitch spelling is recovered
/// from `@accid.ges`
/// (falling back to written `@accid`). Unsupported markup is ignored. Pure
/// Dart (web-safe).
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

const _durBases = {
  'breve': DurationBase.breve,
  '1': DurationBase.whole,
  '2': DurationBase.half,
  '4': DurationBase.quarter,
  '8': DurationBase.eighth,
  '16': DurationBase.sixteenth,
  '32': DurationBase.thirtySecond,
  '64': DurationBase.sixtyFourth,
};

const _accidAlters = {
  'x': 2,
  'ss': 2,
  's': 1,
  'n': 0,
  'f': -1,
  'ff': -2,
  'fff': -2,
};

/// Parses an MEI document into a single-staff [Score].
///
/// Throws [FormatException] on documents this subset cannot represent.
Score scoreFromMei(String mei) {
  final root = parseXml(mei);
  if (root.name != 'mei') {
    throw FormatException('Expected <mei>, got <${root.name}>');
  }
  final score =
      root.child('music')?.child('body')?.child('mdiv')?.child('score');
  if (score == null) throw const FormatException('No <score> in MEI document');
  return _MeiReader(score, _headMetadata(root)).read();
}

/// The default title the writer emits when none is set; nulled on read so
/// empty metadata round-trips.
const _defaultTitle = 'Music';

/// Reads `<meiHead>` title / composer / lyricist / copyright (instrument comes
/// from the staffDef label, added in [_MeiReader.read]).
ScoreMetadata _headMetadata(XmlNode root) {
  final fileDesc = root.child('meiHead')?.child('fileDesc');
  final titleStmt = fileDesc?.child('titleStmt');
  final title = titleStmt?.childText('title');
  String? composer;
  String? lyricist;
  for (final p in titleStmt?.child('respStmt')?.childrenNamed('persName') ??
      const <XmlNode>[]) {
    if (p.attributes['role'] == 'composer') composer = p.text;
    if (p.attributes['role'] == 'lyricist') lyricist = p.text;
  }
  final copyright = fileDesc?.child('pubStmt')?.child('availability')?.text;
  return ScoreMetadata(
    title: (title == '' || title == _defaultTitle) ? null : title,
    composer: composer == '' ? null : composer,
    lyricist: lyricist == '' ? null : lyricist,
    copyright: copyright == '' ? null : copyright,
  );
}

class _MeiReader {
  final XmlNode score;
  final ScoreMetadata headMeta;
  _MeiReader(this.score, this.headMeta);

  int _nextId = 0;
  Clef _clef = Clef.treble;
  KeySignature _key = const KeySignature(0);
  TimeSignature? _time;

  String _newId() => 'e${_nextId++}';

  Score read() {
    final scoreDef = score.child('scoreDef');
    final staffDef = scoreDef?.child('staffGrp')?.child('staffDef') ??
        scoreDef?.child('staffDef');
    if (staffDef != null) {
      _clef = _clefFrom(staffDef, 'clef.shape', 'clef.line', 'clef.dis',
              'clef.dis.place') ??
          _clef;
    }
    if (scoreDef != null) {
      _key = _keyFrom(scoreDef.attributes['keysig']) ?? _key;
      _time = _meterFrom(scoreDef, 'meter.count', 'meter.unit', 'meter.sym') ??
          _time;
    }
    final leadingClef = _clef;
    final leadingKey = _key;
    final leadingTime = _time;

    final measures = <Measure>[];
    final section = score.child('section');
    if (section != null) {
      for (final node in section.childrenNamed('measure')) {
        measures.add(_readMeasure(node));
      }
    }

    final instrument = staffDef?.attributes['label'];
    Tempo? tempo;
    final mm = double.tryParse(scoreDef?.attributes['mm'] ?? '');
    if (mm != null) {
      tempo = Tempo(mm,
          beatUnit: _durBases[scoreDef!.attributes['mm.unit'] ?? '4'] ??
              DurationBase.quarter,
          dots: (int.tryParse(scoreDef.attributes['mm.dots'] ?? '0') ?? 0)
              .clamp(0, 2));
    }
    return Score(
      clef: leadingClef,
      keySignature: leadingKey,
      timeSignature: leadingTime,
      measures: measures,
      slurs: [
        for (final s in _slurs)
          Slur(_xmlIdToId[s.startId] ?? s.startId,
              _xmlIdToId[s.endId] ?? s.endId),
      ],
      tempo: tempo,
      metadata: ScoreMetadata(
        title: headMeta.title,
        composer: headMeta.composer,
        lyricist: headMeta.lyricist,
        copyright: headMeta.copyright,
        instrument: instrument == '' ? null : instrument,
      ),
    );
  }

  // Ornament control events for the current measure, keyed by note xml:id.
  var _ornaments = <String, Ornament>{};
  // Slur control events (by source xml:id) accumulated across the document.
  final _slurs = <Slur>[];
  // Source xml:id → the regenerated element id, so slurs can be re-anchored.
  final _xmlIdToId = <String, String>{};

  /// A fresh element id, recording the source [xmlId] → new-id mapping so slur
  /// control events (which reference the source ids) can be re-anchored.
  String _idFor(String? xmlId) {
    final id = _newId();
    if (xmlId != null) _xmlIdToId[xmlId] = id;
    return id;
  }

  Measure _readMeasure(XmlNode measureNode) {
    final pickup = measureNode.attributes['metcon'] == 'false';
    _ornaments = {};
    for (final node in measureNode.children) {
      final ornament = switch (node.name) {
        'trill' => Ornament.trill,
        'mordent' => node.attributes['form'] == 'upper'
            ? Ornament.shortTrill
            : Ornament.mordent,
        'turn' => Ornament.turn,
        _ => null,
      };
      final startid = node.attributes['startid'];
      if (ornament != null && startid != null) {
        _ornaments[startid.replaceFirst('#', '')] = ornament;
      }
      if (node.name == 'slur') {
        final endid = node.attributes['endid'];
        if (startid != null && endid != null) {
          _slurs.add(Slur(
              startid.replaceFirst('#', ''), endid.replaceFirst('#', '')));
        }
      }
    }
    final staff = measureNode.child('staff');
    final layers = staff?.childrenNamed('layer').toList() ?? const <XmlNode>[];

    Clef? clefChange;
    KeySignature? keyChange;
    TimeSignature? timeChange;
    final byLayer = <List<MusicElement>>[];

    for (var l = 0; l < layers.length; l++) {
      final elements = <MusicElement>[];
      for (final node in layers[l].children) {
        switch (node.name) {
          case 'clef':
            final clef = _clefFrom(node, 'shape', 'line', 'dis', 'dis.place');
            if (clef != null && clef != _clef) {
              clefChange = clef;
              _clef = clef;
            }
          case 'keySig':
            final key = _keyFrom(node.attributes['sig']);
            if (key != null && key != _key) {
              keyChange = key;
              _key = key;
            }
          case 'meterSig':
            final time = _meterFrom(node, 'count', 'unit', 'sym');
            if (time != null && time != _time) {
              timeChange = time;
              _time = time;
            }
          case 'note':
            elements.add(_noteFrom(node));
          case 'chord':
            elements.add(_chordFrom(node));
          case 'rest':
          case 'mRest':
            elements.add(RestElement(_durationFrom(node),
                id: _idFor(node.attributes['xml:id'])));
          default:
            break; // beam, tuplet, dynam, slur, …: ignored
        }
      }
      byLayer.add(elements);
    }

    return Measure(
      byLayer.isEmpty ? const [] : byLayer[0],
      voice2: byLayer.length > 1 ? byLayer[1] : const [],
      voice3: byLayer.length > 2 ? byLayer[2] : const [],
      voice4: byLayer.length > 3 ? byLayer[3] : const [],
      clefChange: clefChange,
      keyChange: keyChange,
      timeChange: timeChange,
      pickup: pickup,
    );
  }

  NoteElement _noteFrom(XmlNode note) => NoteElement(
        pitches: [_pitchFrom(note)],
        duration: _durationFrom(note),
        showAccidental: note.attributes.containsKey('accid') ? true : null,
        tieToNext: _isTieStart(note.attributes['tie']),
        articulations: _articOf(note),
        ornament: _ornaments[note.attributes['xml:id']],
        id: _idFor(note.attributes['xml:id']),
      );

  NoteElement _chordFrom(XmlNode chord) {
    final notes = chord.childrenNamed('note').toList();
    return NoteElement(
      pitches: [for (final n in notes) _pitchFrom(n)],
      duration: _durationFrom(chord),
      showAccidental:
          notes.any((n) => n.attributes.containsKey('accid')) ? true : null,
      tieToNext: _isTieStart(chord.attributes['tie']),
      articulations: _articOf(chord),
      ornament: _ornaments[chord.attributes['xml:id']],
      id: _idFor(chord.attributes['xml:id']),
    );
  }

  static const _articMap = {
    'stacc': Articulation.staccato,
    'ten': Articulation.tenuto,
    'acc': Articulation.accent,
    'marc': Articulation.marcato,
    'upbow': Articulation.upBow,
    'dnbow': Articulation.downBow,
  };

  static Set<Articulation> _articOf(XmlNode node) {
    final result = <Articulation>{};
    final artic = node.attributes['artic'];
    if (artic != null) {
      for (final token in artic.split(RegExp(r'\s+'))) {
        final a = _articMap[token];
        if (a != null) result.add(a);
      }
    }
    if (node.attributes.containsKey('fermata')) {
      result.add(Articulation.fermata);
    }
    return result;
  }

  static bool _isTieStart(String? tie) => tie == 'i' || tie == 'm';

  static Pitch _pitchFrom(XmlNode note) {
    final step = Step.values.asNameMap()[note.attributes['pname']] ?? Step.c;
    final oct = int.tryParse(note.attributes['oct'] ?? '4') ?? 4;
    final accid = note.attributes['accid.ges'] ?? note.attributes['accid'];
    final alter = accid == null ? 0 : (_accidAlters[accid] ?? 0);
    return Pitch(step, alter: alter, octave: oct);
  }

  NoteDuration _durationFrom(XmlNode node) {
    final base = _durBases[node.attributes['dur']];
    if (base == null) {
      // A full-measure rest (@dur absent) falls back to the running meter.
      final f = (_time ?? TimeSignature.fourFour).toFraction();
      return _durationForFraction(f.numerator, f.denominator) ??
          NoteDuration.whole;
    }
    final dots =
        (int.tryParse(node.attributes['dots'] ?? '0') ?? 0).clamp(0, 2);
    return NoteDuration(base, dots: dots);
  }

  static NoteDuration? _durationForFraction(int n, int d) {
    for (final base in DurationBase.values) {
      final (bn, bd) =
          base == DurationBase.breve ? (2, 1) : (1, base.denominator);
      for (var dots = 0; dots <= 2; dots++) {
        final mulN = (1 << (dots + 1)) - 1;
        final mulD = 1 << dots;
        if (bn * mulN * d == n * bd * mulD) {
          return NoteDuration(base, dots: dots);
        }
      }
    }
    return null;
  }

  static Clef? _clefFrom(XmlNode node, String shapeAttr, String lineAttr,
      String disAttr, String disPlaceAttr) {
    final shape = node.attributes[shapeAttr];
    if (shape == null) return null;
    if (shape == 'perc') return Clef.percussion;
    final line = int.tryParse(node.attributes[lineAttr] ?? '');
    final dis = node.attributes[disAttr];
    final place = node.attributes[disPlaceAttr];
    return switch (shape) {
      'G' when line == 1 => Clef.frenchViolin,
      'G' when dis == '8' && place == 'above' => Clef.treble8va,
      'G' when dis == '8' && place == 'below' => Clef.treble8vb,
      'G' => Clef.treble,
      'F' when line == 5 => Clef.subbass,
      'F' when line == 3 => Clef.baritone,
      'F' when dis == '8' && place == 'below' => Clef.bass8vb,
      'F' => Clef.bass,
      'C' when line == 1 => Clef.soprano,
      'C' when line == 2 => Clef.mezzoSoprano,
      'C' when line == 4 => Clef.tenor,
      'C' => Clef.alto,
      _ => Clef.treble,
    };
  }

  static KeySignature? _keyFrom(String? sig) {
    if (sig == null) return null;
    if (sig == '0') return const KeySignature(0);
    final match = RegExp(r'^(\d+)([sf])$').firstMatch(sig);
    if (match == null) return null;
    final n = int.parse(match[1]!);
    final fifths = match[2] == 's' ? n : -n;
    if (fifths < -7 || fifths > 7) return null;
    return KeySignature(fifths);
  }

  static TimeSignature? _meterFrom(
      XmlNode node, String countAttr, String unitAttr, String symAttr) {
    final count = node.attributes[countAttr];
    final unit = int.tryParse(node.attributes[unitAttr] ?? '');
    if (count == null || unit == null) return null;
    final symbol = switch (node.attributes[symAttr]) {
      'common' => TimeSymbol.common,
      'cut' => TimeSymbol.cut,
      _ => TimeSymbol.numeric,
    };
    if (count.contains('+')) {
      return TimeSignature.additive(
          count.split('+').map(int.parse).toList(), unit);
    }
    return TimeSignature(int.parse(count), unit, symbol: symbol);
  }
}
