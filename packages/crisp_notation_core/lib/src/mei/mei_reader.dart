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

/// Parses a multi-staff MEI document into a [StaffSystem] — every `<staffDef>`
/// in the `<scoreDef>` (descending through nested `<staffGrp>`s) becomes one
/// aligned staff, read from the matching `<staff n="…">` of each `<measure>`.
/// A `<staffGrp>` with a `@symbol` (`brace`/`bracket`/`line`) becomes the
/// corresponding [StaffBracket]. A single-staff document yields a one-staff
/// system. Element ids are given disjoint spaces per staff.
///
/// Throws [FormatException] on documents this subset cannot represent.
StaffSystem staffSystemFromMei(String mei) {
  final root = parseXml(mei);
  if (root.name != 'mei') {
    throw FormatException('Expected <mei>, got <${root.name}>');
  }
  final score =
      root.child('music')?.child('body')?.child('mdiv')?.child('score');
  if (score == null) throw const FormatException('No <score> in MEI document');
  final meta = _headMetadata(root);
  final scoreDef = score.child('scoreDef');
  final staffDefs = scoreDef == null ? const <XmlNode>[] : _staffDefs(scoreDef);
  final count = staffDefs.isEmpty ? 1 : staffDefs.length;
  final staves = <Score>[
    for (var i = 0; i < count; i++)
      _MeiReader(
        score,
        meta,
        staffN: staffDefs.isEmpty
            ? 1
            : int.tryParse(staffDefs[i].attributes['n'] ?? '') ?? (i + 1),
        idOffset: i * 1000,
      ).read(),
  ];
  return StaffSystem(staves, brackets: _staffGrpBrackets(scoreDef, staffDefs));
}

/// Imports multi-staff MEI straight into a paginating [MultiPartScore] — its
/// staves line-break together into aligned systems and paginate (feed it to
/// `layoutMultiPartPages` / `MultiPartView`).
MultiPartScore multiPartScoreFromMei(String mei) =>
    MultiPartScore.fromStaffSystem(staffSystemFromMei(mei));

/// Every `<staffDef>` under [scoreDef], in document order, descending through
/// nested `<staffGrp>`s.
List<XmlNode> _staffDefs(XmlNode scoreDef) {
  final out = <XmlNode>[];
  void walk(XmlNode node) {
    for (final child in node.children) {
      if (child.name == 'staffDef') {
        out.add(child);
      } else if (child.name == 'staffGrp') {
        walk(child);
      }
    }
  }

  walk(scoreDef);
  return out;
}

/// Brackets from each `<staffGrp @symbol>`: a group is drawn over the staff-
/// index range (positions in [staffDefs]) of the staffDefs it contains. `brace`
/// maps to a brace; `bracket`/`line`/other visible symbols to a square bracket;
/// `none` (or an absent symbol) draws nothing.
List<StaffBracket> _staffGrpBrackets(
    XmlNode? scoreDef, List<XmlNode> staffDefs) {
  if (scoreDef == null) return const [];
  final result = <StaffBracket>[];
  void walk(XmlNode node) {
    for (final child in node.children) {
      if (child.name == 'staffGrp') {
        final symbol = child.attributes['symbol'];
        final inner = _staffDefs(child);
        if (inner.isNotEmpty && symbol != null && symbol != 'none') {
          final first = staffDefs.indexOf(inner.first);
          final last = staffDefs.indexOf(inner.last);
          if (first >= 0 && last >= first) {
            result.add(StaffBracket(first, last,
                kind: symbol == 'brace'
                    ? StaffBracketKind.brace
                    : StaffBracketKind.bracket));
          }
        }
        walk(child);
      }
    }
  }

  walk(scoreDef);
  return result;
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

  /// Which staff of a multi-staff document to read (1-based) — the `@n` on the
  /// `<staffDef>` and the `<staff>` elements. A single-staff document uses 1.
  final int staffN;

  _MeiReader(this.score, this.headMeta, {this.staffN = 1, int idOffset = 0})
      : _nextId = idOffset;

  int _nextId;
  Clef _clef = Clef.treble;
  KeySignature _key = const KeySignature(0);
  TimeSignature? _time;

  String _newId() => 'e${_nextId++}';

  Score read() {
    final scoreDef = score.child('scoreDef');
    // The staffDef for this staff: match `@n`, falling back to the Nth in
    // document order (and to the sole staffDef for a single-staff document).
    final staffDefs =
        scoreDef == null ? const <XmlNode>[] : _staffDefs(scoreDef);
    final XmlNode? staffDef = staffDefs.isEmpty
        ? null
        : staffDefs.firstWhere((d) => d.attributes['n'] == '$staffN',
            orElse: () => staffN <= staffDefs.length
                ? staffDefs[staffN - 1]
                : staffDefs.first);
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

    // Gather measures from *every* <section> (a score commonly has several —
    // one per verse / strophe), descending through nested sections and repeat
    // <ending>s in document order. Reading only the first section dropped every
    // later verse (e.g. a 4-section chorale kept only 4 of 18 measures).
    final measures = <Measure>[];
    void collect(XmlNode node) {
      for (final child in node.children) {
        switch (child.name) {
          case 'measure':
            measures.add(_readMeasure(child));
          case 'section':
          case 'ending':
            collect(child);
        }
      }
    }

    collect(score);

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
    // <tupletSpan startid endid num numbase> — a tuplet expressed as a control
    // event (referencing its first/last note by id) rather than a wrapping
    // <tuplet>. Professionally-encoded MEI uses these heavily; without them the
    // tuplet notes keep their nominal (unscaled) duration.
    final tupletSpans =
        <({String startid, String endid, int num, int numbase})>[];
    for (final node in measureNode.children) {
      if (node.name == 'tupletSpan') {
        final sid = node.attributes['startid']?.replaceFirst('#', '');
        final eid = node.attributes['endid']?.replaceFirst('#', '');
        final num = int.tryParse(node.attributes['num'] ?? '');
        final numbase = int.tryParse(node.attributes['numbase'] ?? '');
        // Don't filter by the span's `@staff` — that's a *draw* hint; the
        // referenced notes can be on another staff. Resolution below only
        // succeeds for spans whose notes this reader actually built, so each
        // span lands on exactly the staff that holds it.
        if (sid != null && eid != null && num != null && numbase != null) {
          tupletSpans
              .add((startid: sid, endid: eid, num: num, numbase: numbase));
        }
      }
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
          _slurs.add(
              Slur(startid.replaceFirst('#', ''), endid.replaceFirst('#', '')));
        }
      }
    }
    // The `<staff>` for this reader's staff. When the `<staff>`s are `@n`-
    // labelled, match `@n` exactly — if this staff is *absent* from the measure,
    // read nothing (an empty bar), rather than falling back to another staff's
    // content (which duplicated it — a chord staff reading the melody, G19).
    // Only unlabelled `<staff>`s (single-staff docs) match by position.
    final staves = measureNode.childrenNamed('staff').toList();
    final XmlNode? staff;
    if (staves.isEmpty) {
      staff = null;
    } else if (staves.any((s) => s.attributes.containsKey('n'))) {
      final matches = staves.where((s) => s.attributes['n'] == '$staffN');
      staff = matches.isEmpty ? null : matches.first;
    } else {
      staff = staffN <= staves.length ? staves[staffN - 1] : staves.first;
    }
    final layers = staff?.childrenNamed('layer').toList() ?? const <XmlNode>[];

    Clef? clefChange;
    KeySignature? keyChange;
    TimeSignature? timeChange;
    final byLayer = <List<MusicElement>>[];

    final tuplets = <TupletSpan>[];
    for (var l = 0; l < layers.length; l++) {
      final elements = <MusicElement>[];
      // Grace notes (`<note grace="acc|unacc">`) are not full elements — they
      // ornament the following principal note. Accumulate them and attach to the
      // next real note/chord (matching the MusicXML reader), instead of emitting
      // them as full-duration notes that over-fill the measure.
      var pendingGraces = <Pitch>[];
      var pendingGraceStyle = GraceStyle.acciaccatura;
      for (final node in _flattenBeams(layers[l].children)) {
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
          case 'note' when node.attributes.containsKey('grace'):
            pendingGraces.add(_pitchFrom(node));
            // MEI grace="acc" = accented (appoggiatura); "unacc" = acciaccatura.
            if (node.attributes['grace'] == 'acc') {
              pendingGraceStyle = GraceStyle.appoggiatura;
            }
          case 'chord' when node.attributes.containsKey('grace'):
            for (final n in node.childrenNamed('note')) {
              pendingGraces.add(_pitchFrom(n));
            }
            if (node.attributes['grace'] == 'acc') {
              pendingGraceStyle = GraceStyle.appoggiatura;
            }
          case 'note':
            elements.add(_noteFrom(node,
                graceNotes: pendingGraces, graceStyle: pendingGraceStyle));
            pendingGraces = <Pitch>[];
            pendingGraceStyle = GraceStyle.acciaccatura;
          case 'chord':
            elements.add(_chordFrom(node,
                graceNotes: pendingGraces, graceStyle: pendingGraceStyle));
            pendingGraces = <Pitch>[];
            pendingGraceStyle = GraceStyle.acciaccatura;
          case 'rest':
          case 'mRest':
            elements.add(RestElement(_durationFrom(node),
                id: _idFor(node.attributes['xml:id'])));
          case 'tuplet':
            final start = elements.length;
            for (final child in _flattenBeams(node.children)) {
              switch (child.name) {
                case 'note':
                  elements.add(_noteFrom(child));
                case 'chord':
                  elements.add(_chordFrom(child));
                case 'rest':
                case 'mRest':
                  elements.add(RestElement(_durationFrom(child),
                      id: _idFor(child.attributes['xml:id'])));
              }
            }
            final actual = int.tryParse(node.attributes['num'] ?? '');
            final normal = int.tryParse(node.attributes['numbase'] ?? '');
            if (actual != null &&
                actual >= 2 &&
                normal != null &&
                elements.length - 1 >= start) {
              tuplets.add(TupletSpan(start, elements.length - 1,
                  actual: actual, normal: normal, voice: l));
            }
          default:
            break; // beam, dynam, slur, …: ignored
        }
      }
      byLayer.add(elements);
    }

    // Resolve <tupletSpan> control events (by note id) to a voice + index range,
    // searching whichever voice holds the referenced notes.
    for (final ts in tupletSpans) {
      final startId = _xmlIdToId[ts.startid];
      final endId = _xmlIdToId[ts.endid];
      if (startId == null || endId == null || ts.num < 2) continue;
      for (var v = 0; v < byLayer.length; v++) {
        final si = byLayer[v].indexWhere((e) => e.id == startId);
        final ei = byLayer[v].indexWhere((e) => e.id == endId);
        if (si >= 0 && ei >= si) {
          tuplets.add(
              TupletSpan(si, ei, actual: ts.num, normal: ts.numbase, voice: v));
          break;
        }
      }
    }

    return Measure(
      byLayer.isEmpty ? const [] : byLayer[0],
      voice2: byLayer.length > 1 ? byLayer[1] : const [],
      voice3: byLayer.length > 2 ? byLayer[2] : const [],
      voice4: byLayer.length > 3 ? byLayer[3] : const [],
      clefChange: clefChange,
      keyChange: keyChange,
      timeChange: timeChange,
      tuplets: tuplets,
      pickup: pickup,
    );
  }

  NoteElement _noteFrom(XmlNode note,
          {List<Pitch> graceNotes = const [],
          GraceStyle graceStyle = GraceStyle.acciaccatura}) =>
      NoteElement(
        pitches: [_pitchFrom(note)],
        duration: _durationFrom(note),
        showAccidental: note.attributes.containsKey('accid') ? true : null,
        tieToNext: _isTieStart(note.attributes['tie']),
        articulations: _articOf(note),
        ornament: _ornaments[note.attributes['xml:id']],
        graceNotes: graceNotes,
        graceStyle: graceStyle,
        id: _idFor(note.attributes['xml:id']),
      );

  NoteElement _chordFrom(XmlNode chord,
      {List<Pitch> graceNotes = const [],
      GraceStyle graceStyle = GraceStyle.acciaccatura}) {
    final notes = chord.childrenNamed('note').toList();
    final id = _idFor(chord.attributes['xml:id']);
    // Map each chord-member note's xml:id to the chord element too, so a control
    // event (tupletSpan, slur, …) anchored to a chord's inner note resolves.
    for (final n in notes) {
      final nid = n.attributes['xml:id'];
      if (nid != null) _xmlIdToId[nid] = id;
    }
    return NoteElement(
      pitches: [for (final n in notes) _pitchFrom(n)],
      duration: _durationFrom(chord),
      showAccidental:
          notes.any((n) => n.attributes.containsKey('accid')) ? true : null,
      tieToNext: _isTieStart(chord.attributes['tie']),
      articulations: _articOf(chord),
      ornament: _ornaments[chord.attributes['xml:id']],
      graceNotes: graceNotes,
      graceStyle: graceStyle,
      id: id,
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
    return TimeSignature.tryParse(int.parse(count), unit, symbol: symbol) ??
        (throw const FormatException('Invalid MEI time signature'));
  }
}

/// Unwraps `<beam>` containers (recursively, since beams nest) so their child
/// notes/chords/rests/tuplets join the sequence in order. In MEI a beam is
/// purely visual grouping — without this, every beamed note is dropped (Baroque
/// scores are almost entirely beamed: e.g. a Brandenburg movement is 92% beamed
/// notes). Non-beam nodes pass through unchanged; grace groups and tremolos are
/// intentionally *not* unwrapped here.
Iterable<XmlNode> _flattenBeams(Iterable<XmlNode> nodes) sync* {
  for (final node in nodes) {
    if (node.name == 'beam') {
      yield* _flattenBeams(node.children);
    } else {
      yield node;
    }
  }
}
