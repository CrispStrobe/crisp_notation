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
import '../theory/chord_name.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/tempo.dart';
import '../theory/time_signature.dart';

const _durBases = {
  'long': DurationBase.long,
  'breve': DurationBase.breve,
  '1': DurationBase.whole,
  '2': DurationBase.half,
  '4': DurationBase.quarter,
  '8': DurationBase.eighth,
  '16': DurationBase.sixteenth,
  '32': DurationBase.thirtySecond,
  '64': DurationBase.sixtyFourth,
  '128': DurationBase.oneHundredTwentyEighth,
  '256': DurationBase.twoHundredFiftySixth,
  '512': DurationBase.fiveHundredTwelfth,
  '1024': DurationBase.oneThousandTwentyFourth,
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

/// MEI `<dynam>` text → the model level (the inverse of `DynamicLevel.name`,
/// which the writer emits as the element's text).
final _dynamicLevels = {for (final l in DynamicLevel.values) l.name: l};

/// MEI `<repeatMark func="…">` value → the model navigation mark (the inverse
/// of `NavigationMark.name`, which the writer emits as `@func`).
final _navMarks = {for (final n in NavigationMark.values) n.name: n};

/// The first `<score>` anywhere in the document.
///
/// MEI does not put it at one fixed depth. `<mdiv>` nests for multi-movement
/// works, a document may hold several `<mdiv>` siblings where only a later one
/// carries music, and part-based encodings wrap it as `<parts><part><score>`.
/// The roots vary too: `<meiCorpus>` holds whole `<mei>` documents, and a
/// fragment may be rooted at `<music>`.
///
/// Walking the single path `music > body > mdiv > score` missed all of those:
/// 42 files in the MEI sample corpus contain notes and reported no score at
/// all, including ones with EIGHT `score` elements in them.
///
/// MEI's PART-BASED encoding replaces `score` with `parts > part` outright, so
/// a `part` is accepted as a score-equivalent — it carries the same `section`
/// children, with its `staffDef` sitting directly inside instead of under a
/// `scoreDef > staffGrp`.
XmlNode? _findScore(XmlNode node) {
  // Prefer a score that actually holds music. A large MEI document opens with
  // front matter — title pages, cast lists — encoded as their own `mdiv`s with
  // empty scores, so taking the first one found returns nothing: `opera.mei`
  // has 18 `mdiv`s and all 402 notes live in the fifth score.
  final all = <XmlNode>[];
  void collect(XmlNode n) {
    if (n.name == 'score') all.add(n);
    for (final c in n.children) {
      collect(c);
    }
  }

  collect(node);
  for (final s in all) {
    if (_hasNote(s)) return s;
  }
  if (all.isNotEmpty) return all.first;
  // Only once the whole tree has been searched for a real `score`: a
  // score-based document must never be read through this fallback.
  return _findPart(node);
}

bool _hasNote(XmlNode node) {
  if (node.name == 'note') return true;
  for (final c in node.children) {
    if (_hasNote(c)) return true;
  }
  return false;
}

XmlNode? _findPart(XmlNode node) {
  if (node.name == 'part') return node;
  for (final c in node.children) {
    final found = _findPart(c);
    if (found != null) return found;
  }
  return null;
}

/// Parses an MEI document into a single-staff [Score].
///
/// Throws [FormatException] on documents this subset cannot represent.
Score scoreFromMei(String mei) {
  final root = parseXml(mei);
  final score = _findScore(root);
  if (score == null) {
    throw FormatException('No <score> in MEI document (root <${root.name}>)');
  }
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
  final score = _findScore(root);
  if (score == null) {
    throw FormatException('No <score> in MEI document (root <${root.name}>)');
  }
  final meta = _headMetadata(root);
  // A part-based encoding has no `scoreDef`; its `staffDef` is a direct child.
  // `_staffDefs` only descends through `staffGrp`, so pointing it at the score
  // itself cannot pick up mid-score staff changes inside a `section`.
  final scoreDef = score.child('scoreDef');
  final staffDefs = _staffDefs(scoreDef ?? score);
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
    // An <ending n="…"> wrapping a measure marks it as that volta; carry the
    // number down to the measures it contains.
    void collect(XmlNode node, int? volta) {
      for (final child in node.children) {
        switch (child.name) {
          case 'measure':
            final m = _readMeasure(child);
            measures.add(volta == null ? m : m.copyWith(volta: volta));
          case 'section':
            collect(child, volta);
          case 'ending':
            collect(child, int.tryParse(child.attributes['n'] ?? '') ?? volta);
        }
      }
    }

    collect(score, null);

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
      dynamics: [
        for (final d in _dynamics)
          DynamicMarking(_xmlIdToId[d.elementId] ?? d.elementId, d.level),
      ],
      annotations: [
        for (final a in _annotations)
          Annotation(_xmlIdToId[a.elementId] ?? a.elementId, a.text,
              placement: a.placement),
      ],
      trillExtensions: [
        for (final t in _trillExtensions)
          TrillExtension(_xmlIdToId[t.startId] ?? t.startId,
              _xmlIdToId[t.endId] ?? t.endId),
      ],
      ottavas: [
        for (final o in _ottavas)
          Ottava(_xmlIdToId[o.startId] ?? o.startId,
              _xmlIdToId[o.endId] ?? o.endId,
              down: o.down),
      ],
      pedals: [
        for (final p in _pedals)
          Pedal(_xmlIdToId[p.startId] ?? p.startId,
              _xmlIdToId[p.endId] ?? p.endId),
      ],
      laissezVibrer: [
        for (final l in _laissezVibrer)
          LaissezVibrer(_xmlIdToId[l.noteId] ?? l.noteId, down: l.down),
      ],
      glissandos: [
        for (final g in _glissandos)
          Glissando(_xmlIdToId[g.startId] ?? g.startId,
              _xmlIdToId[g.endId] ?? g.endId),
      ],
      chordSymbols: [
        for (final c in _chordSymbols)
          ChordSymbol(_xmlIdToId[c.elementId] ?? c.elementId, c.root, c.quality,
              bass: c.bass),
      ],
      hairpins: [
        for (final h in _hairpins)
          Hairpin(_xmlIdToId[h.startId] ?? h.startId,
              _xmlIdToId[h.endId] ?? h.endId, h.type),
      ],
      lyrics: _lyrics,
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
  final _hairpins = <Hairpin>[];
  final _annotations = <Annotation>[];
  final _chordSymbols = <ChordSymbol>[];
  final _glissandos = <Glissando>[];
  final _laissezVibrer = <LaissezVibrer>[];
  final _fingerings = <String, List<int>>{};

  /// Let-ring is `@lv` on the note/chord itself, not a control event.
  void _noteLv(XmlNode node, MusicElement element) {
    if (node.attributes['lv'] != 'true') return;
    final id = element.id;
    if (id != null) _laissezVibrer.add(LaissezVibrer(id));
  }

  /// MEI's `@right` back to a barline style. A repeat end occupies the same
  /// attribute and is already read as `endRepeat`, so it leaves the style
  /// normal rather than being mistaken for one.
  static BarlineStyle _barlineOf(String? right) => switch (right) {
        'dbl' => BarlineStyle.doubleBar,
        'end' => BarlineStyle.finalBar,
        'heavy' => BarlineStyle.heavy,
        'dashed' => BarlineStyle.dashed,
        'dotted' => BarlineStyle.dotted,
        'invis' => BarlineStyle.none,
        _ => BarlineStyle.normal,
      };
  final _ottavas = <Ottava>[];
  final _trillExtensions = <TrillExtension>[];

  /// A `<tempo>` control event found while walking the measure being read.
  Tempo? _measureTempo;
  final _pedals = <Pedal>[];

  /// Note ids carrying a `<breath>` control event.
  ///
  /// MEI has no `@artic` value for a breath — it is a control event — so it is
  /// merged back onto the note here rather than going through the @artic table.
  final _breathIds = <String>{};

  /// This element's `@artic` set, plus a breath if a `<breath>` points at it.
  Set<Articulation> _articsWithBreath(XmlNode node) {
    final base = _articOf(node);
    final id = node.attributes['xml:id'];
    if (id == null || !_breathIds.contains(id)) return base;
    return {...base, Articulation.breath};
  }

  // Dynamic control events (`<dynam>`, by source xml:id) across the document.
  final _dynamics = <DynamicMarking>[];
  // `<verse>/<syl>` lyrics, keyed by the note's regenerated id (collected while
  // the note is read, so no id remap is needed).
  final _lyrics = <Lyric>[];
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
    NavigationMark? navigation;
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
        'turn' => node.attributes['form'] == 'lower'
            ? Ornament.invertedTurn
            : Ornament.turn,
        _ => null,
      };
      final startid = node.attributes['startid'];
      if (ornament != null && startid != null) {
        // A `<trill>` carrying `@endid` is an EXTENDED trill, and the model's
        // canonical form for one is the span ALONE — the same convention the
        // MusicXML reader states for `trill-mark` + `wavy-line`. Recording the
        // ornament as well would make every writer draw the sign twice: once
        // for the ornament and once as the span's own head.
        final end = node.attributes['endid'];
        if (node.name == 'trill' && end != null) {
          _trillExtensions.add(TrillExtension(
            startid.replaceFirst('#', ''),
            end.replaceFirst('#', ''),
          ));
        } else {
          _ornaments[startid.replaceFirst('#', '')] = ornament;
        }
      }
      if (node.name == 'slur') {
        final endid = node.attributes['endid'];
        if (startid != null && endid != null) {
          _slurs.add(
              Slur(startid.replaceFirst('#', ''), endid.replaceFirst('#', '')));
        }
      }
      if (node.name == 'dynam' && startid != null) {
        final level = _dynamicLevels[node.text.trim()];
        if (level != null) {
          _dynamics.add(DynamicMarking(startid.replaceFirst('#', ''), level));
        }
      }
      if (node.name == 'hairpin' && startid != null) {
        final endid = node.attributes['endid'];
        final form = node.attributes['form'];
        if (endid != null) {
          _hairpins.add(Hairpin(
            startid.replaceFirst('#', ''),
            endid.replaceFirst('#', ''),
            form == 'dim' ? HairpinType.diminuendo : HairpinType.crescendo,
          ));
        }
      }
      if (node.name == 'dir' && startid != null) {
        final text = node.text.trim();
        if (text.isNotEmpty) {
          _annotations.add(Annotation(
            startid.replaceFirst('#', ''),
            text,
            placement: node.attributes['place'] == 'below'
                ? AnnotationPlacement.below
                : AnnotationPlacement.above,
          ));
        }
      }
      if (node.name == 'fing' && startid != null) {
        final n = int.tryParse(node.text.trim());
        if (n != null) {
          (_fingerings[startid.replaceFirst('#', '')] ??= []).add(n);
        }
      }
      if (node.name == 'tempo') {
        final mm = double.tryParse(node.attributes['mm'] ?? '');
        if (mm != null) {
          _measureTempo = Tempo(mm,
              beatUnit: _durBases[node.attributes['mm.unit'] ?? '4'] ??
                  DurationBase.quarter,
              dots: (int.tryParse(node.attributes['mm.dots'] ?? '0') ?? 0)
                  .clamp(0, 2));
        }
      }
      if (node.name == 'octave' && startid != null) {
        final end = node.attributes['endid'];
        if (end != null) {
          _ottavas.add(Ottava(
            startid.replaceFirst('#', ''),
            end.replaceFirst('#', ''),
            down: node.attributes['dis.place'] != 'below',
          ));
        }
      }
      if (node.name == 'pedal' && startid != null) {
        final end = node.attributes['endid'];
        if (end != null) {
          _pedals.add(Pedal(
            startid.replaceFirst('#', ''),
            end.replaceFirst('#', ''),
          ));
        }
      }
      if (node.name == 'gliss' && startid != null) {
        final end = node.attributes['endid'];
        if (end != null) {
          _glissandos.add(Glissando(
            startid.replaceFirst('#', ''),
            end.replaceFirst('#', ''),
          ));
        }
      }
      if (node.name == 'harm' && startid != null) {
        // `<harm>` carries a chord LABEL, not structured attributes, so it is
        // read by the same parser that reads ABC's quoted strings. Text that
        // does not name a chord (a figured-bass or roman-numeral <harm>) is
        // left alone rather than forced into a triad.
        final parsed = parseChordName(node.text.trim());
        if (parsed != null) {
          _chordSymbols.add(ChordSymbol(
            startid.replaceFirst('#', ''),
            parsed.root,
            parsed.kind,
            bass: parsed.bass,
          ));
        }
      }
      if (node.name == 'breath' && startid != null) {
        _breathIds.add(startid.replaceFirst('#', ''));
      }
      if (node.name == 'repeatMark') {
        navigation = _navMarks[node.attributes['func'] ?? ''] ?? navigation;
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
    for (var li = 0; li < layers.length; li++) {
      // `<layer n="N">` names the voice, so a staff whose voice 3 is empty
      // still puts its voice 4 in slot 4. Reading by POSITION compacts the gap
      // and moves that part up a voice. Anything without a usable @n keeps its
      // position, which is what a file that omits the attribute means.
      final declared = int.tryParse(layers[li].attributes['n']?.trim() ?? '');
      final l = (declared != null && declared >= 1 && declared <= 4)
          ? declared - 1
          : li;
      final elements = <MusicElement>[];
      // Grace notes (`<note grace="acc|unacc">`) are not full elements — they
      // ornament the following principal note. Accumulate them and attach to the
      // next real note/chord (matching the MusicXML reader), instead of emitting
      // them as full-duration notes that over-fill the measure.
      var pendingGraces = <Pitch>[];
      var pendingGraceStyle = GraceStyle.acciaccatura;
      for (final node in _flattenBeams(layers[li].children)) {
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
            _noteLv(node, elements.last);
            pendingGraces = <Pitch>[];
            pendingGraceStyle = GraceStyle.acciaccatura;
          case 'chord':
            elements.add(_chordFrom(node,
                graceNotes: pendingGraces, graceStyle: pendingGraceStyle));
            _noteLv(node, elements.last);
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
                // Graces occur INSIDE tuplets too. This dispatch duplicates the
                // outer one, and omitting the grace check here turned every
                // such grace into a real note — an extra note, at the grace's
                // own short duration, inserted into the middle of the tuplet.
                case 'note' when child.attributes.containsKey('grace'):
                  pendingGraces.add(_pitchFrom(child));
                  if (child.attributes['grace'] == 'acc') {
                    pendingGraceStyle = GraceStyle.appoggiatura;
                  }
                case 'chord' when child.attributes.containsKey('grace'):
                  for (final n
                      in child.children.where((c) => c.name == 'note')) {
                    pendingGraces.add(_pitchFrom(n));
                  }
                  if (child.attributes['grace'] == 'acc') {
                    pendingGraceStyle = GraceStyle.appoggiatura;
                  }
                case 'note':
                  elements.add(_noteFrom(child,
                      graceNotes: pendingGraces,
                      graceStyle: pendingGraceStyle));
                  pendingGraces = <Pitch>[];
                  pendingGraceStyle = GraceStyle.acciaccatura;
                case 'chord':
                  elements.add(_chordFrom(child,
                      graceNotes: pendingGraces,
                      graceStyle: pendingGraceStyle));
                  pendingGraces = <Pitch>[];
                  pendingGraceStyle = GraceStyle.acciaccatura;
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
      while (byLayer.length <= l) {
        byLayer.add(<MusicElement>[]);
      }
      byLayer[l] = elements;
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
      startRepeat: measureNode.attributes['left'] == 'rptstart',
      endRepeat: measureNode.attributes['right'] == 'rptend',
      barline: _barlineOf(measureNode.attributes['right']),
      tempoChange: _takeMeasureTempo(),
      navigation: navigation,
    );
  }

  /// The `<tempo>` seen while walking this measure, cleared as it is taken so
  /// it cannot leak onto the next one.
  Tempo? _takeMeasureTempo() {
    final t = _measureTempo;
    _measureTempo = null;
    return t;
  }

  NoteElement _noteFrom(XmlNode note,
      {List<Pitch> graceNotes = const [],
      GraceStyle graceStyle = GraceStyle.acciaccatura}) {
    final id = _idFor(note.attributes['xml:id']);
    _collectVerses(note, id);
    return NoteElement(
      pitches: [_pitchFrom(note)],
      duration: _durationFrom(note),
      showAccidental: note.attributes.containsKey('accid') ? true : null,
      tieToNext: _isTieStart(note.attributes['tie']),
      articulations: _articsWithBreath(note),
      ornament: _ornaments[note.attributes['xml:id']],
      fingerings: _fingerings[note.attributes['xml:id']] ?? const [],
      tremolo: _tremoloOf(note),
      graceNotes: graceNotes,
      graceStyle: graceStyle,
      id: id,
    );
  }

  /// The tremolo slash count from `@stem.mod="Nslash"`, or null.
  static int? _tremoloOf(XmlNode node) {
    final mod = node.attributes['stem.mod'];
    if (mod == null || !mod.endsWith('slash')) return null;
    return int.tryParse(mod.substring(0, mod.length - 'slash'.length));
  }

  /// Reads `<verse n="…"><syl con="…">text</syl></verse>` children of a note or
  /// chord into [_lyrics], anchored to the note's regenerated [id]. `@con`
  /// carries the continuation: `d`=hyphen to next, `u`=melisma extender,
  /// `b`=elision into the next syllable.
  void _collectVerses(XmlNode noteOrChord, String id) {
    for (final verse in noteOrChord.childrenNamed('verse')) {
      final n = int.tryParse(verse.attributes['n'] ?? '1') ?? 1;
      for (final syl in verse.childrenNamed('syl')) {
        final con = syl.attributes['con'];
        _lyrics.add(Lyric(
          id,
          syl.text.trim(),
          verse: n < 1 ? 1 : n,
          hyphenToNext: con == 'd',
          extender: con == 'u',
          elidesToNext: con == 'b',
        ));
      }
    }
  }

  NoteElement _chordFrom(XmlNode chord,
      {List<Pitch> graceNotes = const [],
      GraceStyle graceStyle = GraceStyle.acciaccatura}) {
    final notes = chord.childrenNamed('note').toList();
    final id = _idFor(chord.attributes['xml:id']);
    _collectVerses(chord, id);
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
      articulations: _articsWithBreath(chord),
      ornament: _ornaments[chord.attributes['xml:id']],
      fingerings: _fingerings[chord.attributes['xml:id']] ?? const [],
      tremolo: _tremoloOf(chord),
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
    'stacciss': Articulation.staccatissimo,
    'spicc': Articulation.staccatissimo,
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
      final (bn, bd) = base.wholeValue;
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
/// notes), and unwraps MEI's EDITORIAL containers, which nest music one level
/// deeper than a naive walk expects. Grace groups and tremolos are
/// intentionally *not* unwrapped here.
Iterable<XmlNode> _flattenBeams(Iterable<XmlNode> nodes) sync* {
  for (final node in nodes) {
    switch (node.name) {
      case 'beam':
        yield* _flattenBeams(node.children);

      // Critical apparatus: `app` offers ALTERNATIVE readings of the same
      // passage, so exactly one must be taken — they are variants, not
      // successive music. Prefer the editor's lemma, else the first reading.
      // Without this the notes are invisible: they are nested one level deeper
      // than the walker looked.
      case 'app':
        final lem = node.child('lem');
        final rdg = node.childrenNamed('rdg');
        final chosen = lem ?? (rdg.isEmpty ? null : rdg.first);
        if (chosen != null) yield* _flattenBeams(chosen.children);

      // Editorial choice: prefer the corrected/regularised reading over the
      // source's own error or original spelling.
      case 'choice':
        final chosen = node.child('corr') ??
            node.child('reg') ??
            (node.children.isEmpty ? null : node.children.first);
        if (chosen != null) yield* _flattenBeams(chosen.children);

      // Substitution: the added text replaces the deleted one.
      case 'subst':
        final add = node.child('add');
        if (add != null) yield* _flattenBeams(add.children);

      // Deleted material does not sound.
      case 'del':
        break;

      // Transparent editorial wrappers — the music inside them is the music.
      case 'supplied':
      case 'unclear':
      case 'add':
      case 'corr':
      case 'reg':
      case 'orig':
      case 'sic':
      case 'lem':
      case 'rdg':
        yield* _flattenBeams(node.children);

      default:
        yield node;
    }
  }
}
