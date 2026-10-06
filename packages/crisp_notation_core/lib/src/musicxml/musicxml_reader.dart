/// MusicXML import (subset): score-partwise → [Score] / [GrandStaff] /
/// [StaffSystem].
///
/// Covers the v0.3/v0.4 feature set: pitches/chords/rests, durations
/// (breve…64th, dots), accidentals, ties, slurs, tuplets, articulations,
/// grace notes, dynamics, hairpin wedges, lyrics, chord symbols
/// (`<harmony>`), key/time/clef with mid-score changes, repeat barlines
/// and voltas, and two voices per staff. Unsupported markup is ignored.
library;

import '../layout/grand_staff.dart';
import '../layout/multi_part.dart';
import '../layout/staff_system.dart';
import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../smufl/glyph_names.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/interval.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/tempo.dart';
import '../theory/time_signature.dart';
import '../theory/transposition.dart';
import 'xml_reader.dart';

/// Parses a `score-partwise` MusicXML document into a single-staff
/// [Score], reading part [partIndex] (default: the first part).
///
/// With [inheritGlobalDirections] (the default), a part other than the first
/// also takes the score-wide tempo from the TOP part: its opening tempo, its
/// tempo changes and the tempo words that go with them ("Allegro molto").
/// Exporters write those once, in the top part, though every part plays at
/// that tempo (#13). Marks the part already has are kept.
///
/// Throws [FormatException] on documents this subset cannot represent.
Score scoreFromMusicXml(String xml,
    {int partIndex = 0, bool inheritGlobalDirections = true}) {
  final root = parseXml(xml);
  final parts = _partsOf(root);
  if (partIndex < 0 || partIndex >= parts.length) {
    throw FormatException('Part $partIndex not found (${parts.length} parts)');
  }
  final score = _PartReader(
    parts[partIndex],
    staff: 1,
    metadata: _metadataOf(root, parts[partIndex]),
    collapseMultiRests: true,
  ).read();
  if (!inheritGlobalDirections || partIndex == 0) return score;
  final top = _PartReader(parts.first, staff: 1);
  return _withGlobalDirections(score, top.read(), top.tempoWords);
}

/// [part] with the score-wide tempo of [top] (the first part, read with
/// every bar kept): the opening tempo, each tempo change, and each tempo
/// word in [topWords], wherever [part] has none of its own. Bars are matched
/// by bar number, so a multi-measure rest in [part] still lines up.
Score _withGlobalDirections(
    Score part, Score top, List<(int, Fraction, String)> topWords) {
  // The first bar number of each of the part's measures.
  final barOf = <int>[];
  var bar = 0;
  for (final m in part.measures) {
    barOf.add(bar);
    bar += m.multiRest ?? 1;
  }
  int? measureAtBar(int b) {
    for (var i = barOf.length - 1; i >= 0; i--) {
      if (barOf[i] <= b) {
        final span = part.measures[i].multiRest ?? 1;
        return b < barOf[i] + span ? i : null;
      }
    }
    return null;
  }

  final measures = [...part.measures];
  for (var b = 1; b < top.measures.length; b++) {
    final change = top.measures[b].tempoChange;
    final i = measureAtBar(b);
    if (change == null || i == null || barOf[i] != b) continue;
    if (measures[i].tempoChange == null) {
      measures[i] = measures[i].copyWith(tempoChange: change);
    }
  }

  final annotations = [...part.annotations];
  var anchorId = 0;
  for (final (b, onset, text) in topWords) {
    final i = measureAtBar(b);
    if (i == null) continue;
    final m = measures[i];
    final ids = {for (final e in m.elements) e.id};
    if (annotations.any(
        (a) => ids.contains(a.elementId) && a.text.trim() == text.trim())) {
      continue; // the part has it already
    }
    // The element sounding at the word's onset (the last one starting at or
    // before it); a multi-rest bar that kept no rest gets one as the anchor.
    String? id;
    var t = Fraction.zero;
    for (var k = 0; k < m.elements.length; k++) {
      if (t > onset) break;
      id = m.elements[k].id;
      t = t + m.effectiveDurationAt(k);
    }
    if (id == null) {
      id = 'tw${anchorId++}';
      measures[i] = Measure(
        [RestElement(NoteDuration.whole, id: id)],
        clefChange: m.clefChange,
        inlineClefs: m.inlineClefs,
        keyChange: m.keyChange,
        timeChange: m.timeChange,
        tempoChange: m.tempoChange,
        startRepeat: m.startRepeat,
        endRepeat: m.endRepeat,
        volta: m.volta,
        multiRest: m.multiRest,
        navigation: m.navigation,
        barline: m.barline,
        pickup: m.pickup,
        actualDuration: m.actualDuration,
      );
    }
    annotations.add(Annotation(id, text));
  }
  return part.copyWith(
    tempo: part.tempo ?? top.tempo,
    measures: measures,
    annotations: annotations,
  );
}

/// The default part-name the writer emits when no instrument is set; the reader
/// maps it back to a null instrument so empty metadata round-trips.
const _defaultPartName = 'Music';

/// Reads `<work>`/`<identification>` and the part's `<part-name>` into
/// [ScoreMetadata]. Some notation programs put title/composer page text only
/// in MusicXML `<credit>` blocks, so those are used as a metadata fallback.
ScoreMetadata _metadataOf(XmlNode root, XmlNode part) {
  final creditTitle = _creditText(root, justify: 'center');
  final title = root.child('work')?.childText('work-title') ??
      root.childText('movement-title') ??
      creditTitle;
  String? composer;
  String? lyricist;
  final identification = root.child('identification');
  if (identification != null) {
    for (final creator in identification.childrenNamed('creator')) {
      switch (creator.attributes['type']) {
        case 'composer':
          composer = creator.text;
        case 'lyricist' || 'poet':
          lyricist = creator.text;
      }
    }
  }
  composer ??= _creditText(root, justify: 'right');
  final copyright = identification?.childText('rights');
  // Part name + GM voice: match the score-part with this part's id. Read its
  // `<midi-instrument>` for a General-MIDI program (`<midi-program>` is 1-based
  // in MusicXML → 0-based here) and percussion (`<midi-channel>10`).
  final partId = part.attributes['id'];
  String? partName;
  int? midiProgram;
  var isPercussion = false;
  for (final sp in root.child('part-list')?.childrenNamed('score-part') ??
      const <XmlNode>[]) {
    if (sp.attributes['id'] != partId) continue;
    partName = sp.childText('part-name');
    final mi = sp.child('midi-instrument');
    if (mi != null) {
      final prog = int.tryParse(mi.childText('midi-program') ?? '');
      if (prog != null) midiProgram = (prog - 1).clamp(0, 127);
      if (int.tryParse(mi.childText('midi-channel') ?? '') == 10) {
        isPercussion = true;
      }
    }
  }
  final instrument =
      partName == _defaultPartName || partName == '' ? null : partName;
  return ScoreMetadata(
    title: title == '' ? null : title,
    composer: composer == '' ? null : composer,
    lyricist: lyricist == '' ? null : lyricist,
    copyright: copyright == '' ? null : copyright,
    instrument: instrument,
    midiProgram: midiProgram,
    isPercussion: isPercussion,
    extras: _extrasOf(identification, partId),
  );
}

/// Separator between a part id and an extras key in a multi-part document (the
/// writer's `_partScopeSeparator`).
const _partScopeSeparator = '/';

/// Reads `<miscellaneous-field>`s back into [ScoreMetadata.extras].
///
/// Extras are per-PART data but MusicXML has one `<identification>` for the
/// whole document, so the writer scopes each key under its part id. A field
/// named for ANOTHER part belongs to that part, not this one — handing it over
/// too is how every part in a multi-part score would end up holding every other
/// part's settings. An unscoped name (what a single-part document writes, and
/// what another program's file would have) belongs to whoever is reading.
Map<String, String> _extrasOf(XmlNode? identification, String? partId) {
  final fields = identification
      ?.child('miscellaneous')
      ?.childrenNamed('miscellaneous-field');
  if (fields == null) return const {};
  final extras = <String, String>{};
  for (final field in fields) {
    final name = field.attributes['name'];
    if (name == null || name.isEmpty) continue;
    final separator = name.indexOf(_partScopeSeparator);
    if (separator <= 0) {
      extras[name] = field.text;
      continue;
    }
    final scope = name.substring(0, separator);
    // A scope that names no part at all is somebody else's key that happens to
    // contain a slash, so it is left whole rather than silently truncated.
    if (scope == partId) {
      extras[name.substring(separator + 1)] = field.text;
    } else if (!_looksLikePartId(scope)) {
      extras[name] = field.text;
    }
  }
  return extras;
}

/// Whether [scope] has the shape of a written part id (`P1`, `P12`).
bool _looksLikePartId(String scope) => RegExp(r'^P\d+$').hasMatch(scope);

String? _creditText(XmlNode root, {required String justify}) {
  final lines = <String>[];
  for (final credit in root.childrenNamed('credit')) {
    final page = credit.attributes['page'];
    if (page != null && page != '1') continue;
    for (final words in credit.childrenNamed('credit-words')) {
      if (words.attributes['justify'] != justify) continue;
      final text = words.text.trim();
      if (text.isEmpty) continue;
      lines.add(text);
    }
  }
  if (lines.isEmpty) return null;
  return lines.join('\n');
}

/// Parses a `score-partwise` document into a [GrandStaff]: either the
/// first part's staves 1+2, or the first two parts.
GrandStaff grandStaffFromMusicXml(String xml) {
  final root = parseXml(xml);
  final parts = _partsOf(root);
  final firstStaves = int.tryParse(
    _firstAttributes(parts.first)?.childText('staves') ?? '1',
  );
  if ((firstStaves ?? 1) >= 2) {
    return GrandStaff(
      upper: _PartReader(
        parts.first,
        staff: 1,
        defaultClef: _defaultClefForStaff(parts.first, 1),
      ).read(),
      lower: _PartReader(
        parts.first,
        staff: 2,
        idOffset: 1000,
        defaultClef: _defaultClefForStaff(parts.first, 2),
      ).read(),
    );
  }
  if (parts.length < 2) {
    throw const FormatException(
      'Grand staff needs a two-staff part or two parts',
    );
  }
  return GrandStaff(
    upper: _PartReader(parts.first, staff: 1).read(),
    lower: _PartReader(parts[1], staff: 1, idOffset: 1000).read(),
  );
}

/// Parses a `score-partwise` document into a [StaffSystem] — every part, and
/// every staff of a multi-staff part, becomes one aligned staff. Multi-staff
/// parts (e.g. piano) are joined by a brace; `<part-group>`s in the
/// `<part-list>` (with a `bracket`/`brace`/`square`/`line` group-symbol)
/// become the corresponding [StaffBracket]s. Element ids are given disjoint
/// spaces per staff so they stay unique across the system.
///
/// Throws [FormatException] on documents this subset cannot represent.
StaffSystem staffSystemFromMusicXml(String xml) {
  final root = parseXml(xml);
  final parts = _partsOf(root);

  final staves = <Score>[];
  final brackets = <StaffBracket>[];
  // Staff index where each part starts, and how many staves it spans.
  final partStart = <int>[];
  final partSpan = <int>[];
  var idBase = 0;
  final systemBreaks = <int>{};
  final partial = <int>{};
  for (final part in parts) {
    final n =
        int.tryParse(_firstAttributes(part)?.childText('staves') ?? '1') ?? 1;
    // `<staff-type>ossia</staff-type>`: a staff drawn only where it has
    // music (see [StaffSystem.partialStaves]).
    if (n == 1 &&
        _firstAttributes(part)
                ?.child('staff-details')
                ?.childText('staff-type') ==
            'ossia') {
      partial.add(staves.length);
    }
    partStart.add(staves.length);
    partSpan.add(n);
    final first = staves.length;
    final metadata = _metadataOf(root, part);
    systemBreaks.addAll(_systemBreaksOf(part));
    for (var s = 1; s <= n; s++) {
      staves.add(
        _PartReader(
          part,
          staff: s,
          idOffset: idBase,
          metadata: metadata,
          defaultClef: _defaultClefForStaff(part, s),
        ).read(),
      );
      idBase += 1000;
    }
    if (n >= 2) {
      // A multi-staff part (piano/organ) is braced together.
      brackets.add(
        StaffBracket(first, staves.length - 1, kind: StaffBracketKind.brace),
      );
    }
  }

  brackets.addAll(_partGroupBrackets(root, partStart, partSpan));
  return StaffSystem(
    staves,
    brackets: brackets,
    barlineGroups: _partGroupBarlines(root, partStart, partSpan),
    systemBreaks: systemBreaks,
    partialStaves: partial,
  );
}

Set<int> _systemBreaksOf(XmlNode part) {
  final breaks = <int>{};
  var index = 0;
  for (final measure in part.childrenNamed('measure')) {
    if (index > 0 &&
        measure
            .childrenNamed('print')
            .any((node) => node.attributes['new-system'] == 'yes')) {
      breaks.add(index);
    }
    index++;
  }
  return breaks;
}

/// Imports multi-part MusicXML straight into a paginating [MultiPartScore] —
/// the N parts line-break together into aligned systems and paginate (feed it
/// to `layoutMultiPartPages` / `MultiPartView`). Any `<part-group>` with
/// `<group-barline>yes</group-barline>` (or `Mensurstrich`) becomes a
/// custom-span barline that connects that section and breaks between sections.
MultiPartScore multiPartScoreFromMusicXml(String xml) =>
    MultiPartScore.fromStaffSystem(staffSystemFromMusicXml(xml));

/// Reads `<part-group>` start/stop pairs from the `<part-list>` and maps each
/// to a [StaffBracket] over the staff range of the `<score-part>`s it wraps.
/// `<score-part>` order matches `<part>` order in the body.
List<StaffBracket> _partGroupBrackets(
  XmlNode root,
  List<int> partStart,
  List<int> partSpan,
) {
  final list = root.child('part-list');
  if (list == null) return const [];
  final result = <StaffBracket>[];
  final openStart = <String, int>{}; // group number -> first staff index
  final openSymbol = <String, String>{};
  var ordinal = 0; // index of the next score-part to be seen
  for (final node in list.children) {
    if (node.name == 'score-part') {
      ordinal++;
    } else if (node.name == 'part-group') {
      final number = node.attributes['number'] ?? '1';
      final type = node.attributes['type'];
      if (type == 'start') {
        if (ordinal < partStart.length) {
          openStart[number] = partStart[ordinal];
          openSymbol[number] = node.childText('group-symbol') ?? 'bracket';
        }
      } else if (type == 'stop') {
        final first = openStart.remove(number);
        final symbol = openSymbol.remove(number);
        final lastPart = ordinal - 1;
        if (first == null || lastPart < 0 || lastPart >= partStart.length) {
          continue;
        }
        final last = partStart[lastPart] + partSpan[lastPart] - 1;
        if (last < first) continue;
        final kind = symbol == 'brace'
            ? StaffBracketKind.brace
            : StaffBracketKind.bracket;
        // `line`/`square`/`bracket` all render as a square bracket; a `none`
        // symbol groups without a visible sign, so we skip it.
        if (symbol == 'none') continue;
        result.add(StaffBracket(first, last, kind: kind));
      }
    }
  }
  return result;
}

/// Reads `<part-group>` pairs whose `<group-barline>` is `yes` (or
/// `Mensurstrich`) and maps each to a [BarlineGroup] over the staff range of
/// the parts it wraps — the sections whose barlines connect. A group with
/// `group-barline` absent contributes nothing (a document with no group-barlines
/// keeps its default single systemic barline). A *symbol-less* `group-barline`
/// of `no`, when no group connects, is the explicit "disconnect" marker crisp
/// writes for a fully-separated layout: each part gets its own barline (so
/// `connectBarlines: false` round-trips instead of falling back to the connected
/// default). A bracketed group with `group-barline=no` keeps the default, so its
/// own behavior is untouched. Mirrors [_partGroupBrackets]; `<score-part>` order
/// matches `<part>` order.
List<BarlineGroup> _partGroupBarlines(
  XmlNode root,
  List<int> partStart,
  List<int> partSpan,
) {
  final list = root.child('part-list');
  if (list == null) return const [];
  final result = <BarlineGroup>[];
  final openStart = <String, int>{}; // group number -> first staff index
  final openConnects = <String, bool>{};
  var sawExplicitDisconnect = false;
  var ordinal = 0; // index of the next score-part to be seen
  for (final node in list.children) {
    if (node.name == 'score-part') {
      ordinal++;
    } else if (node.name == 'part-group') {
      final number = node.attributes['number'] ?? '1';
      final type = node.attributes['type'];
      if (type == 'start') {
        if (ordinal < partStart.length) {
          final barline = node.childText('group-barline');
          final symbol = node.childText('group-symbol');
          openStart[number] = partStart[ordinal];
          openConnects[number] = barline == 'yes' || barline == 'Mensurstrich';
          // A symbol-less group-barline=no is the explicit "disconnect" marker
          // (a bracketed group with barline=no keeps the default so its own
          // documented behavior is untouched).
          if (barline == 'no' && (symbol == null || symbol == 'none')) {
            sawExplicitDisconnect = true;
          }
        }
      } else if (type == 'stop') {
        final first = openStart.remove(number);
        final connects = openConnects.remove(number) ?? false;
        final lastPart = ordinal - 1;
        if (!connects ||
            first == null ||
            lastPart < 0 ||
            lastPart >= partStart.length) {
          continue;
        }
        final last = partStart[lastPart] + partSpan[lastPart] - 1;
        if (last < first) continue;
        result.add(BarlineGroup(first, last));
      }
    }
  }
  // A deliberate full disconnect: give every part its own barline group so the
  // layout stays disconnected rather than defaulting to one systemic barline.
  if (result.isEmpty && sawExplicitDisconnect) {
    return [
      for (var i = 0; i < partStart.length; i++)
        BarlineGroup(partStart[i], partStart[i] + partSpan[i] - 1),
    ];
  }
  return result;
}

List<XmlNode> _partsOf(XmlNode root) {
  if (root.name != 'score-partwise') {
    throw FormatException('Expected <score-partwise>, got <${root.name}>');
  }
  final parts = root.childrenNamed('part').toList();
  if (parts.isEmpty) throw const FormatException('No <part> in document');
  return parts;
}

XmlNode? _firstAttributes(XmlNode part) =>
    part.child('measure')?.child('attributes');

Clef _defaultClefForStaff(XmlNode part, int staff) {
  if (staff == 1) return Clef.treble;

  var measureIndex = 0;
  for (final measure in part.childrenNamed('measure')) {
    var staffOnset = 0;
    for (final node in measure.children) {
      if (node.name == 'attributes') {
        for (final clefNode in node.childrenNamed('clef')) {
          if (_clefNodeStaff(clefNode) != staff) continue;
          final clef = _PartReader._clefOf(clefNode);
          if (measureIndex == 0 && staffOnset == 0) return clef;
          return Clef.treble;
        }
      } else if (node.name == 'note') {
        if (node.child('chord') != null) continue;
        if ((int.tryParse(node.childText('staff') ?? '1') ?? 1) != staff) {
          continue;
        }
        staffOnset += int.tryParse(node.childText('duration') ?? '0') ?? 0;
      }
    }
    measureIndex++;
  }

  return Clef.bass;
}

int _clefNodeStaff(XmlNode clefNode) =>
    int.tryParse(clefNode.attributes['number'] ?? '1') ?? 1;

class _PartReader {
  final XmlNode part;

  /// Which staff of the part to read (1-based; grand staffs use 1 and 2).
  final int staff;

  /// Offset for generated element ids, so two staves of one document
  /// get disjoint id spaces (`e0…` and `e1000…`).
  final int idOffset;

  _PartReader(
    this.part, {
    required this.staff,
    this.idOffset = 0,
    this.metadata = const ScoreMetadata(),
    this.collapseMultiRests = false,
    Clef? defaultClef,
  }) : defaultClef = defaultClef ?? (staff == 2 ? Clef.bass : Clef.treble) {
    _clef = this.defaultClef;
    _leadingClef = this.defaultClef;
  }

  /// Conventional clef when the source omits an initial clef for this staff.
  final Clef defaultClef;

  /// Whether a `<multiple-rest>` becomes ONE [Measure.multiRest] bar standing
  /// for the bars it covers (a single part), or stays as individual rest bars
  /// (a system, whose staves must keep the same bar count).
  final bool collapseMultiRests;

  /// Document-level metadata (title/composer/…) to attach to the built score.
  final ScoreMetadata metadata;

  int _nextId = 0;
  int _divisions = 1;

  Clef? _clef; // running clef (mid-score changes update it)
  Clef? _leadingClef;
  KeySignature? _key; // running key; _leadingKey holds the score's initial
  KeySignature? _leadingKey;
  TimeSignature? _leadingTime;
  Transposition? _transposition;
  Tempo? _tempo;

  static const _beatUnits = {
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

  /// A `<metronome>` (beat-unit + per-minute) into a [Tempo].
  static Tempo? _tempoOf(XmlNode metronome) {
    final base = _beatUnits[metronome.childText('beat-unit')];
    final perMinute = double.tryParse(metronome.childText('per-minute') ?? '');
    if (base == null || perMinute == null) return null;
    final dots = metronome.childrenNamed('beat-unit-dot').length.clamp(0, 2);
    return Tempo(perMinute, beatUnit: base, dots: dots);
  }

  /// The tempo from a `<direction>`'s `<sound tempo="…">` playback attribute.
  ///
  /// This is the OTHER way MusicXML states a tempo, and the two are independent:
  /// `<metronome>` is the mark the score PRINTS, `<sound tempo>` is what a player
  /// should do. A file may carry either, both, or a `<sound>` with no tempo at
  /// all (it also carries dynamics, coda jumps and so on).
  ///
  /// `<sound tempo>` is defined as quarter-notes per minute regardless of the
  /// written beat unit, so it maps to a plain quarter-note [Tempo].
  static Tempo? _soundTempoOf(XmlNode direction) {
    final sound = direction.child('sound');
    if (sound == null) return null;
    final bpm = double.tryParse(sound.attributes['tempo'] ?? '');
    if (bpm == null || bpm <= 0) return null;
    return Tempo(bpm);
  }

  bool _leadingSet = false;

  final _measures = <Measure>[];
  final _slurs = <Slur>[];
  final _glissandos = <Glissando>[];
  final _trillExtensions = <TrillExtension>[];
  final _pedals = <Pedal>[];
  final _dynamics = <DynamicMarking>[];
  final _hairpins = <Hairpin>[];
  final _lyrics = <Lyric>[];
  final _annotations = <Annotation>[];
  final _chordSymbols = <ChordSymbol>[];
  final _jazzMarks = <JazzMark>[];
  final _figuredBass = <FiguredBass>[];
  final _breathMarks = <BreathMark>[];
  final _laissezVibrer = <LaissezVibrer>[];

  // Open spans keyed by MusicXML "number" attribute.
  /// Open slurs by `number`. A null value is a slur opened by a note this
  /// reader does not import (another staff, `print-object="no"`): its number
  /// is taken, so a later stop must not pair with an older start.
  final _openSlurs = <String, String?>{};

  /// Slur numbers started on grace notes: they start at the next principal
  /// note (a grace's slur to its own principal then collapses and is dropped).
  final _graceSlurStarts = <String>[];

  /// A dynamic read in a bar that ended before any note took it: the next
  /// bar's first note gets it (see `_readMeasure`).
  String? _carriedDynamic;
  final _openGliss = <String, String>{};
  final _openPortamento = <String, String>{};
  final _cueNoteIds = <String>[];
  final _portamentos = <Portamento>[];
  final _openTrills = <String, String>{};

  /// Pedals and ottavas awaiting a note, then bound to one with its voice.
  /// Same story as the wedges above: predicting `e{nextId}` can land on a rest,
  /// and "the last note read" jumps voices across a `<backup>`.
  final _pendingPedals = <String>{};
  final _openPedals = <String, (String, int)>{};
  final _pendingOttavas = <String, bool>{};

  /// Wedges whose start has been seen but not yet BOUND to a note.
  ///
  /// ⚠️ The start used to be bound by PREDICTING `e{nextId}` — the id the next
  /// element would take. Two ways that is wrong: the next element may be a
  /// REST (so the hairpin anchored to something the note index does not
  /// contain, and the span read back as `@-1`), and nothing recorded which
  /// VOICE it landed in.
  final _pendingWedges = <String, HairpinType>{};

  /// Wedges bound to a real note, with the voice that note is in.
  final _openWedges = <String, (String, int, HairpinType)>{};

  /// The voice each note id was read into, and the last note read per voice.
  ///
  /// A wedge's stop belongs to the last note IN ITS OWN VOICE. Taking "the last
  /// note read" instead makes the span jump voices in any staff with a
  /// `<backup>` — i.e. every piano score — and our own writer cannot re-emit
  /// such a span, so it is simply lost.
  final _noteVoice = <String, int>{};
  final _lastNoteOfVoice = <int, String>{};
  final _openOttavas = <String, (String, int, bool)>{};
  final _ottavas = <Ottava>[];

  /// MusicXML keeps every bar a `<multiple-rest>N` covers: the style sits on
  /// the first and the N-1 bars after it are still there. The model's
  /// [Measure.multiRest] bar STANDS FOR all N, so keeping both counted the
  /// silence twice (playback ran N-1 bars long, bar numbers drifted). A
  /// single part folds the covered bars into the first; marks on their rests
  /// move to its anchor rest. A staff of a system keeps them as plain bars.
  void _settleMultiRests() {
    if (!_measures.any((m) => m.multiRest != null)) return;
    if (!collapseMultiRests) {
      for (var i = 0; i < _measures.length; i++) {
        if (_measures[i].multiRest != null) {
          _measures[i] = _withMultiRest(_measures[i], null);
        }
      }
      return;
    }
    bool silent(Measure m) => [m.elements, m.voice2, m.voice3, m.voice4]
        .every((v) => v.every((e) => e is RestElement));
    // A bar that can be folded into the run before it: silent and carrying
    // nothing a reader would miss. Its own end repeat or barline may close
    // the run (it moves onto the folded bar), but nothing may open there.
    bool foldable(Measure m) =>
        silent(m) &&
        m.multiRest == null &&
        m.measureRepeat == null &&
        m.timeChange == null &&
        m.keyChange == null &&
        m.clefChange == null &&
        m.tempoChange == null &&
        !m.startRepeat &&
        m.volta == null &&
        m.navigation == null &&
        m.inlineClefs.isEmpty;
    final remap = <String, String>{};
    final out = <Measure>[];
    for (var i = 0; i < _measures.length; i++) {
      final m = _measures[i];
      final want = m.multiRest;
      if (want == null) {
        out.add(m);
        continue;
      }
      final absorbed = <Measure>[];
      var j = i + 1;
      while (absorbed.length < want - 1 &&
          j < _measures.length &&
          foldable(_measures[j])) {
        final next = _measures[j];
        absorbed.add(next);
        j++;
        if (next.endRepeat || next.barline != BarlineStyle.normal) break;
      }
      // No covered bars at all: an encoding that writes the multi-rest as ONE
      // bar (older crisp_notation did), so the declared count stands.
      final covered = absorbed.isEmpty ? want : 1 + absorbed.length;
      var elements = m.elements;
      final anchor = elements.whereType<RestElement>().firstOrNull?.id ??
          absorbed
              .expand((a) => a.elements)
              .whereType<RestElement>()
              .firstOrNull
              ?.id;
      if (elements.isEmpty && anchor != null) {
        elements = [
          absorbed.expand((a) => a.elements).firstWhere((e) => e.id == anchor),
        ];
      }
      for (final a in absorbed) {
        for (final e
            in [a.elements, a.voice2, a.voice3, a.voice4].expand((v) => v)) {
          final id = e.id;
          if (id != null && anchor != null && id != anchor) remap[id] = anchor;
        }
      }
      final last = absorbed.isEmpty ? m : absorbed.last;
      out.add(Measure(
        elements,
        tuplets: m.tuplets,
        clefChange: m.clefChange,
        inlineClefs: m.inlineClefs,
        keyChange: m.keyChange,
        timeChange: m.timeChange,
        tempoChange: m.tempoChange,
        startRepeat: m.startRepeat,
        endRepeat: last.endRepeat,
        volta: m.volta,
        multiRest: covered >= 2 ? covered : null,
        navigation: m.navigation,
        barline: last.barline,
        pickup: m.pickup,
        actualDuration: m.actualDuration,
      ));
      i = j - 1;
    }
    _measures
      ..clear()
      ..addAll(out);
    String to(String id) => remap[id] ?? id;
    for (var k = 0; k < _annotations.length; k++) {
      final a = _annotations[k];
      _annotations[k] =
          Annotation(to(a.elementId), a.text, placement: a.placement);
    }
    for (var k = 0; k < _dynamics.length; k++) {
      final d = _dynamics[k];
      _dynamics[k] = DynamicMarking(to(d.elementId), d.level);
    }
    for (var k = 0; k < _hairpins.length; k++) {
      final h = _hairpins[k];
      _hairpins[k] = Hairpin(to(h.startId), to(h.endId), h.type);
    }
    // A multi-rest keeps its rest only as an anchor: when no mark uses it,
    // it goes, so a plain multi-rest round-trips as the empty bar it was.
    final used = <String>{
      for (final a in _annotations) a.elementId,
      for (final d in _dynamics) d.elementId,
      for (final h in _hairpins) ...[h.startId, h.endId],
      for (final c in _chordSymbols) c.elementId,
    };
    for (var k = 0; k < _measures.length; k++) {
      final m = _measures[k];
      if (m.multiRest == null) continue;
      final kept = [
        for (final e in m.elements)
          if (e.id != null && used.contains(e.id)) e
      ];
      if (kept.length != m.elements.length) {
        _measures[k] = _withElements(m, kept);
      }
    }
  }

  static Measure _withElements(Measure m, List<MusicElement> elements) =>
      Measure(
        elements,
        tuplets: const [],
        clefChange: m.clefChange,
        inlineClefs: m.inlineClefs,
        keyChange: m.keyChange,
        timeChange: m.timeChange,
        tempoChange: m.tempoChange,
        startRepeat: m.startRepeat,
        endRepeat: m.endRepeat,
        volta: m.volta,
        multiRest: m.multiRest,
        navigation: m.navigation,
        barline: m.barline,
        pickup: m.pickup,
        actualDuration: m.actualDuration,
      );

  static Measure _withMultiRest(Measure m, int? multiRest) => Measure(
        m.elements,
        voice2: m.voice2,
        voice3: m.voice3,
        voice4: m.voice4,
        tuplets: m.tuplets,
        clefChange: m.clefChange,
        inlineClefs: m.inlineClefs,
        keyChange: m.keyChange,
        timeChange: m.timeChange,
        tempoChange: m.tempoChange,
        startRepeat: m.startRepeat,
        endRepeat: m.endRepeat,
        volta: m.volta,
        multiRest: multiRest,
        measureRepeat: m.measureRepeat,
        navigation: m.navigation,
        barline: m.barline,
        pickup: m.pickup,
        actualDuration: m.actualDuration,
      );

  void _openSlur(String number, String? id, [XmlNode? slur]) {
    _openSlurs[number] = id;
    _openSlurPlacement[number] =
        slur == null ? SlurPlacement.auto : _slurPlacementOf(slur);
  }

  final _openSlurPlacement = <String, SlurPlacement>{};

  /// A slur's side: `placement` above/below, else `orientation` over/under,
  /// else the sign of the start's `bezier-y` (MusicXML's y grows UP, so a
  /// positive control point bends the slur over the notes). MuseScore writes
  /// only the bezier hints (#8).
  static SlurPlacement _slurPlacementOf(XmlNode slur) {
    switch (slur.attributes['placement'] ?? slur.attributes['orientation']) {
      case 'above' || 'over':
        return SlurPlacement.above;
      case 'below' || 'under':
        return SlurPlacement.below;
    }
    final y = double.tryParse(slur.attributes['bezier-y'] ?? '');
    if (y == null || y == 0) return SlurPlacement.auto;
    return y > 0 ? SlurPlacement.above : SlurPlacement.below;
  }

  SlurPlacement _placementOf(String number) =>
      _openSlurPlacement[number] ?? SlurPlacement.auto;

  String? _closeSlur(String number) => _openSlurs.remove(number);

  Score read() {
    for (final measureNode in part.childrenNamed('measure')) {
      _readMeasure(measureNode);
    }
    _settleMultiRests();
    // Tolerate a slur left open at the end (real files carry imbalances — a
    // number reused across a `type="continue"`, or a `stop` lost across a part
    // boundary): an unclosed slur simply never became a `Slur`, so drop it and
    // read the rest rather than aborting the whole document.
    return Score(
      clef: _leadingClef ?? defaultClef,
      keySignature: _leadingKey ?? const KeySignature(0),
      timeSignature: _leadingTime,
      measures: _measures,
      slurs: _slurs,
      dynamics: _dynamics,
      hairpins: _hairpins,
      lyrics: _lyrics,
      annotations: _annotations,
      chordSymbols: _chordSymbols,
      ottavas: _ottavas,
      glissandos: _glissandos,
      portamentos: _portamentos,
      cueNoteIds: _cueNoteIds,
      trillExtensions: _trillExtensions,
      pedals: _pedals,
      jazzMarks: _jazzMarks,
      figuredBass: _figuredBass,
      breathMarks: _breathMarks,
      laissezVibrer: _laissezVibrer,
      transposition: _transposition,
      metadata: metadata,
      tempo: _tempo,
    );
  }

  /// Parses a `<transpose>` element (`<diatonic>`/`<chromatic>`/
  /// `<octave-change>`, all signed, describing written → sounding) into a
  /// [Transposition]. Returns null for a no-op transpose.
  static Transposition? _transpositionOf(XmlNode transpose) {
    final diatonic = int.tryParse(transpose.childText('diatonic') ?? '0') ?? 0;
    final chromatic =
        int.tryParse(transpose.childText('chromatic') ?? '0') ?? 0;
    final octave =
        int.tryParse(transpose.childText('octave-change') ?? '0') ?? 0;
    if (diatonic == 0 && chromatic == 0 && octave == 0) return null;
    final down = diatonic < 0 || (diatonic == 0 && chromatic < 0) || octave < 0;
    final interval = _intervalFor(diatonic.abs() + 1, chromatic.abs());
    return Transposition(interval, down: down, octaves: octave.abs());
  }

  /// The [Interval] with diatonic [number] (1..8) spanning [semitones],
  /// deriving the quality from the difference to the major/perfect reference.
  static Interval _intervalFor(int number, int semitones) {
    const majorRef = {1: 0, 2: 2, 3: 4, 4: 5, 5: 7, 6: 9, 7: 11, 8: 12};
    final delta = semitones - (majorRef[number] ?? 0);
    final perfectClass =
        number == 1 || number == 4 || number == 5 || number == 8;
    final quality = perfectClass
        ? (delta <= -1
            ? IntervalQuality.diminished
            : delta == 0
                ? IntervalQuality.perfect
                : IntervalQuality.augmented)
        : (delta <= -2
            ? IntervalQuality.diminished
            : delta == -1
                ? IntervalQuality.minor
                : delta == 0
                    ? IntervalQuality.major
                    : IntervalQuality.augmented);
    return Interval(quality, number);
  }

  /// Parses a `<time>` (or its `<interchangeable>` companion) into a
  /// [TimeSignature] — symbol (common/cut), additive `beats` like `3+2`, and,
  /// when [allowAlternate], an interchangeable [TimeSignature.alternate].
  /// Returns null for `<senza-misura/>` — unmetered music has no meter, which
  /// [Score.timeSignature] already models as null.
  TimeSignature? _parseTimeSig(XmlNode time, {bool allowAlternate = true}) {
    // `<time><senza-misura/></time>` is how MusicXML spells "no meter". It is
    // the normal encoding for Renaissance polyphony transcribed without
    // barlines, so throwing here rejected whole repertoires: 35 of the 78
    // unreadable files in a 3,791-score CPDL sweep were Byrd, Gibbons,
    // Palestrina and Padilla, all of them senza misura.
    if (time.child('senza-misura') != null) return null;
    final symbol = switch (time.attributes['symbol']) {
      'common' => TimeSymbol.common,
      'cut' => TimeSymbol.cut,
      _ => TimeSymbol.numeric,
    };
    final beatsText = time.childText('beats');
    final beatTypeText = time.childText('beat-type');
    if (beatsText == null || beatTypeText == null) {
      throw const FormatException('<time> missing <beats>/<beat-type>');
    }
    final beatUnit = int.parse(beatTypeText);
    final groups = beatsText.contains('+')
        ? beatsText.split('+').map(int.parse).toList()
        : null;
    TimeSignature? alt;
    if (allowAlternate) {
      final inter = time.child('interchangeable');
      if (inter != null) alt = _parseTimeSig(inter, allowAlternate: false);
    }
    final beats =
        groups != null ? groups.reduce((a, b) => a + b) : int.parse(beatsText);
    // A meter the model cannot hold — [TimeSignature] caps beatUnit at 16, and
    // layout keys compound-meter beaming off 8/16 — reads as UNMETERED rather
    // than throwing the score away. `3/32` and `16/32` are legal notation and
    // appear in the corpus; losing the meter costs a barline hint, losing the
    // file costs every note in it. Same trade as the duration clamp above.
    if (TimeSignature.tryParse(beats, beatUnit) == null) {
      return null;
    }
    return groups != null
        ? TimeSignature(
            beats,
            beatUnit,
            components: List.unmodifiable(groups),
            alternate: alt,
          )
        : TimeSignature(beats, beatUnit, symbol: symbol, alternate: alt);
  }

  /// Reassembles a `<figure>` element (prefix/number/suffix) into a compact
  /// figure spec string (`#6`, `6`, `4+`) matching the writer's parse.
  static String _figureText(XmlNode figure) {
    const symbol = {'sharp': '#', 'flat': 'b', 'natural': 'n'};
    final prefix = symbol[figure.childText('prefix')] ?? '';
    final number = figure.childText('figure-number') ?? '';
    final suffixRaw = figure.childText('suffix');
    final hasExtend = figure.child('extend') != null;
    // An extend-only figure (no number/accidental) is a held-figure line.
    if (number.isEmpty && prefix.isEmpty && suffixRaw == null && hasExtend) {
      return '_';
    }
    // A slash/back-slash suffix is a slashed (raised) digit → trailing `\`.
    final slash =
        (suffixRaw == 'slash' || suffixRaw == 'back-slash') ? r'\' : '';
    final suffix = symbol[suffixRaw] ?? '';
    return '$prefix$number$suffix$slash';
  }

  String _newId() => 'e${idOffset + _nextId++}';

  /// Tempo words read from this part — `<words>` in a direction that also
  /// sets a tempo (a metronome or `<sound tempo>`) — as (bar index, onset in
  /// the bar, text), so another part can inherit them.
  final tempoWords = <(int, Fraction, String)>[];

  /// Bars still covered by the current `<multiple-rest>` (this one included).
  int _multiRestLeft = 0;
  int _multiRestRestId = 0;

  /// The rests a `<multiple-rest>` covers are folded away (or kept only as an
  /// anchor), so they take ids from their own namespace: the notes after a
  /// multi-rest keep the ids they would have had without it, and a written
  /// multi-rest reads back as the same score.
  String _restIdInMultiRest() => 'mr${idOffset + _multiRestRestId++}';

  void _readMeasure(XmlNode measureNode) {
    // An implicit measure (or the conventional number="0") is a pickup.
    final pickup = measureNode.attributes['implicit'] == 'yes' ||
        measureNode.attributes['number'] == '0';
    final elements = <MusicElement>[];
    final voice2 = <MusicElement>[];
    final voice3 = <MusicElement>[];
    final voice4 = <MusicElement>[];
    final voiceLists = [elements, voice2, voice3, voice4];
    final voiceOnsets = List<Fraction>.filled(4, Fraction.zero);
    final voiceOrder = <String>[]; // distinct voice labels in first-seen order
    final tuplets = <TupletSpan>[];
    final inlineClefs = <InlineClefChange>[];
    Clef? clefChange;
    KeySignature? keyChange;
    TimeSignature? timeChange;
    Tempo? tempoChange;
    var startRepeat = false;
    var endRepeat = false;
    var barline = BarlineStyle.normal;
    int? volta;
    int? multiRest;
    int? measureRepeat;
    NavigationMark? navigation;

    var pendingGraces = <Pitch>[];
    var pendingGraceStyle = GraceStyle.acciaccatura;
    // A dynamic waits for the next NOTE (layout draws dynamics on notes); one
    // written before a rest at a bar's end carries into the next bar instead
    // of being dropped.
    String? pendingDynamic = _carriedDynamic;
    _carriedDynamic = null;
    ({Pitch root, ChordSymbolKind quality, Pitch? bass})? pendingChord;
    // Every text direction before the next note, each with its own
    // placement ("dolce" below and "Allegro" above can share a note).
    final pendingAnnotations = <(String, AnnotationPlacement)>[];
    List<String>? pendingFigures;
    final openTupletStart = List<int?>.filled(4, null);
    final openTupletRatio = List<(int, int)?>.filled(4, null);

    for (final node in measureNode.children) {
      switch (node.name) {
        case 'attributes':
          final divisions = int.tryParse(node.childText('divisions') ?? '');
          if (divisions != null) _divisions = divisions;
          final keyNode = node.child('key');
          KeySignature? key;
          final keySteps =
              keyNode?.childrenNamed('key-step').toList() ?? const [];
          if (keySteps.isNotEmpty) {
            // Non-traditional key signature: key-step/key-alter pairs.
            final keyAlters = keyNode!.childrenNamed('key-alter').toList();
            final accidentals = <KeyAccidental>[];
            for (var i = 0; i < keySteps.length; i++) {
              final step =
                  Step.values.asNameMap()[keySteps[i].text.toLowerCase()];
              final alter = i < keyAlters.length
                  ? int.tryParse(keyAlters[i].text) ?? 0
                  : 0;
              if (step != null) accidentals.add(KeyAccidental(step, alter));
            }
            if (accidentals.isNotEmpty) {
              key = KeySignature.custom(accidentals);
            }
          } else {
            final fifths = int.tryParse(keyNode?.childText('fifths') ?? '');
            if (fifths != null) key = KeySignature(fifths);
          }
          if (key != null) {
            if (!_leadingSet) {
              _key = key;
              _leadingKey = key;
            } else if (key != (_key ?? const KeySignature(0))) {
              keyChange = key;
              _key = key; // advance the running key (mirrors _clef)
            }
          }
          final time = node.child('time');
          if (time != null) {
            final signature = _parseTimeSig(time);
            // A null signature means `<senza-misura/>`: leave the score
            // unmetered rather than inventing a meter for it.
            if (signature != null) {
              if (!_leadingSet) {
                _leadingTime = signature;
              } else {
                // ⚠️ A RESTATED meter is recorded, not suppressed. A file that writes its
                // meter again mid-piece is saying something, and dropping it broke the
                // round trip for ~16% of kern files — the single largest remaining cause
                // in `krn -> lilypond`. The old fear was that redundant exports would draw
                // a meter at every bar; they cannot, because `layout_engine` guards
                // `timeChange != _time` before DRAWING one. Measured first: only 2 of 681
                // MusicXML files and 0 of 25 kern files restate in >50% of bars.
                timeChange = signature;
              }
            }
          }
          final multipleRest =
              node.child('measure-style')?.childText('multiple-rest');
          if (multipleRest != null) {
            multiRest = int.tryParse(multipleRest);
            if (collapseMultiRests && (multiRest ?? 0) >= 2) {
              _multiRestLeft = multiRest!;
            }
          }
          final repeatNode =
              node.child('measure-style')?.child('measure-repeat');
          if (repeatNode != null && repeatNode.attributes['type'] != 'stop') {
            // The model holds 1, 2 or 4 bars. `@slashes` states it; the element
            // text repeats it, and either may be absent.
            measureRepeat = int.tryParse(repeatNode.attributes['slashes'] ??
                    repeatNode.text.trim()) ??
                1;
          }
          for (final clefNode in node.childrenNamed('clef')) {
            final number =
                int.tryParse(clefNode.attributes['number'] ?? '1') ?? 1;
            if (number != staff) continue;
            final clef = _clefOf(clefNode);
            final onset = voiceOnsets.fold<Fraction>(
              Fraction.zero,
              (best, value) => value > best ? value : best,
            );
            if (!_leadingSet && onset == Fraction.zero) {
              _clef = clef;
              _leadingClef = clef;
            } else if (clef != _clef) {
              if (onset == Fraction.zero) {
                clefChange = clef;
              } else {
                inlineClefs.add(InlineClefChange(onset, clef));
              }
              _clef = clef;
            }
          }
          final transpose = node.child('transpose');
          if (transpose != null) {
            _transposition = _transpositionOf(transpose) ?? _transposition;
          }
        case 'barline':
          final repeat = node.child('repeat');
          if (repeat != null) {
            if (repeat.attributes['direction'] == 'forward') {
              startRepeat = true;
            } else if (repeat.attributes['direction'] == 'backward') {
              endRepeat = true;
            }
          }
          final ending = node.child('ending');
          if (ending != null && ending.attributes['type'] == 'start') {
            volta = int.tryParse(
              (ending.attributes['number'] ?? '1').split(',').first.trim(),
            );
          }
          // A styled right barline (double, final, dashed…). Repeat barlines
          // are handled above and take precedence.
          if (repeat == null && node.attributes['location'] != 'left') {
            barline = switch (node.childText('bar-style')) {
              'light-light' => BarlineStyle.doubleBar,
              'light-heavy' => BarlineStyle.finalBar,
              'heavy' => BarlineStyle.heavy,
              'dashed' => BarlineStyle.dashed,
              'dotted' => BarlineStyle.dotted,
              'tick' => BarlineStyle.tick,
              'short' => BarlineStyle.short,
              'heavy-light' => BarlineStyle.reverseFinal,
              'none' => BarlineStyle.none,
              _ => barline,
            };
          }
        case 'direction':
          if (!_isForStaff(node)) break;
          final dynamicsNode = _directionChild(node, 'dynamics');
          if (dynamicsNode != null && dynamicsNode.children.isNotEmpty) {
            pendingDynamic = dynamicsNode.children.first.name;
          }
          final wedge = _directionChild(node, 'wedge');
          if (wedge != null) _handleWedge(wedge, elements, voice2);
          final shift = _directionChild(node, 'octave-shift');
          if (shift != null) _handleOctaveShift(shift);
          final pedal = _directionChild(node, 'pedal');
          if (pedal != null) _handlePedal(pedal);
          final metronome = _directionChild(node, 'metronome');
          // A printed <metronome> wins; <sound tempo="..."> is the fallback.
          // That order matters: when a file carries both they can disagree (a
          // "swing" mark printed as quarter=120 while playback says 96), and the
          // score should read as what it PRINTS. But when there is no printed
          // mark, <sound tempo> is the only tempo in the file — ignoring it, as
          // this did, silently imported those scores with no tempo at all.
          final t =
              metronome != null ? _tempoOf(metronome) : _soundTempoOf(node);
          if (t != null) {
            // A tempo in the FIRST measure is the score's initial tempo; one in
            // any later measure is that measure's tempo change. Keying off
            // "first one ever seen" mislabeled a change in a score with no
            // initial tempo as the initial — relocating it to bar 1 and dropping
            // the change. (`_measures` holds the measures read so far, so it is
            // empty only while reading measure 0.)
            if (_measures.isEmpty) {
              _tempo ??= t;
            } else {
              tempoChange ??= t;
            }
          }
          navigation ??= _navigationOf(node);
          // Plain <words> that are not a navigation label are a text
          // annotation — ALL of the direction's runs, not just the first.
          final words =
              _directionWords(node, aroundMetronome: metronome != null);
          if (words.isNotEmpty && t != null && dynamicsNode == null) {
            tempoWords.add((
              _measures.length,
              voiceOnsets.fold<Fraction>(
                  Fraction.zero, (best, v) => v > best ? v : best),
              words,
            ));
          }
          if (words.isNotEmpty &&
              _navigationOf(node) == null &&
              dynamicsNode == null) {
            pendingAnnotations.add((
              words,
              node.attributes['placement'] == 'below'
                  ? AnnotationPlacement.below
                  : AnnotationPlacement.above,
            ));
          }
        case 'harmony':
          pendingChord = _chordSymbolOf(node);
        case 'figured-bass':
          pendingFigures = [
            for (final fig in node.childrenNamed('figure')) _figureText(fig),
          ];
        case 'note':
          // Every note's slur marks count, imported or not: a stop that was
          // skipped left its start open, and the next stop with that number
          // paired with it, a slur many bars long. ~30% of the quartet
          // corpus's slurs stacked up past the staff (y -65) this way.
          if (!_isForStaff(node) || node.attributes['print-object'] == 'no') {
            _skipSlurMarks(node);
            break;
          }
          final grace = node.child('grace');
          if (grace != null) {
            for (final (type, number) in _slurMarks(node)) {
              if (type == 'start') {
                _graceSlurStarts.add(number);
              } else {
                // A slur INTO a grace note ends at the note before it.
                final start = _closeSlur(number);
                final end = _lastNoteOfVoice[
                    _voiceIndexOf(node.childText('voice') ?? '1', voiceOrder)];
                if (start != null && end != null && start != end) {
                  _slurs.add(Slur(start, end));
                }
              }
            }
            final pitch = _pitchOf(node.child('pitch'));
            if (pitch != null) pendingGraces.add(pitch);
            if (grace.attributes['slash'] == 'no') {
              pendingGraceStyle = GraceStyle.appoggiatura;
            }
            break;
          }
          final voiceLabel = node.childText('voice') ?? '1';
          final voiceIndex = _voiceIndexOf(voiceLabel, voiceOrder);
          final target = voiceLists[voiceIndex];

          if (node.child('chord') != null && target.isNotEmpty) {
            final last = target.last;
            if (last is NoteElement) {
              final pitch = _pitchOf(node.child('pitch'));
              if (pitch != null) {
                target[target.length - 1] = NoteElement(
                  pitches: [...last.pitches, pitch],
                  duration: last.duration,
                  showAccidental: last.showAccidental,
                  tieToNext: last.tieToNext || _startsTie(node),
                  articulations: last.articulations,
                  graceNotes: last.graceNotes,
                  ornament: last.ornament,
                  fingerings: last.fingerings,
                  arpeggio: last.arpeggio,
                  tremolo: last.tremolo,
                  notehead: last.notehead,
                  id: last.id,
                );
                // A chord tone's marks belong to the chord: a slur stop on
                // the second note of a double stop was dropped.
                _readSpans(node, last.id!);
              }
              break;
            }
          }

          final id = _multiRestLeft > 0 && node.child('rest') != null
              ? _restIdInMultiRest()
              : _newId();
          final duration = _durationOf(node);
          // Percussion notes carry <unpitched> (display-step/octave for the
          // staff line) instead of <pitch>. A note that is neither pitched,
          // unpitched, nor a rest keeps its timing as a rest rather than
          // aborting the whole import.
          final pitch = _pitchOf(node.child('pitch')) ??
              _unpitchedOf(node.child('unpitched'));
          if (node.child('rest') != null || pitch == null) {
            target.add(RestElement(duration, id: id));
            // Text before a rest belongs to the rest ("Fine", tempo words
            // over a rest); it lays out there. Carried on to the next note,
            // it moved, or was lost when the bar ended first.
            for (final (text, placement) in pendingAnnotations) {
              _annotations.add(Annotation(id, text, placement: placement));
            }
            pendingAnnotations.clear();
            // So does a dynamic: it lays out under the rest, and consecutive
            // dynamics over rests (a LilyPond Dynamics line) no longer
            // collapse onto the next note.
            final level = pendingDynamic == null
                ? null
                : DynamicLevel.values.asNameMap()[pendingDynamic];
            if (level != null) _dynamics.add(DynamicMarking(id, level));
            pendingDynamic = null;
          } else {
            target.add(
              NoteElement(
                pitches: [pitch],
                duration: duration,
                showAccidental: node.child('accidental') != null ? true : null,
                tieToNext: _startsTie(node),
                articulations: _articulationsOf(node),
                graceNotes: pendingGraces.isEmpty ? const [] : pendingGraces,
                graceStyle: pendingGraceStyle,
                ornament: _ornamentOf(node),
                fingerings: _fingeringsOf(node),
                arpeggio: _arpeggioOf(node),
                tremolo: _tremoloOf(node),
                notehead: _noteheadOf(node),
                id: id,
              ),
            );
            _noteVoice[id] = voiceIndex;
            _lastNoteOfVoice[voiceIndex] = id;
            _bindPendingSpans(id, voiceIndex);
            pendingGraces = <Pitch>[];
            pendingGraceStyle = GraceStyle.acciaccatura;
            if (pendingDynamic != null) {
              final level = DynamicLevel.values.asNameMap()[pendingDynamic];
              if (level != null) _dynamics.add(DynamicMarking(id, level));
              pendingDynamic = null;
            }
            if (pendingChord != null) {
              _chordSymbols.add(
                ChordSymbol(
                  id,
                  pendingChord.root,
                  pendingChord.quality,
                  bass: pendingChord.bass,
                ),
              );
              pendingChord = null;
            }
            for (final (text, placement) in pendingAnnotations) {
              _annotations.add(Annotation(id, text, placement: placement));
            }
            pendingAnnotations.clear();
            if (pendingFigures != null) {
              if (pendingFigures.isNotEmpty) {
                _figuredBass.add(FiguredBass(id, pendingFigures));
              }
              pendingFigures = null;
            }
            // `<cue/>` marks a small-print reference to another part. Without
            // it the note reads as one the player is meant to play.
            if (node.child('cue') != null) _cueNoteIds.add(id);
            _readSpans(node, id);
            _readLyric(node, id);
            final jazz = _jazzOf(node);
            if (jazz != null) _jazzMarks.add(JazzMark(id, jazz));
            final breath = _breathOf(node);
            if (breath != null) _breathMarks.add(BreathMark(id, breath));
            final lv = _laissezVibrerOf(node, id);
            if (lv != null) _laissezVibrer.add(lv);
          }
          voiceOnsets[voiceIndex] =
              voiceOnsets[voiceIndex] + duration.toFraction();

          // ALL the marks, not just the first: a one-note group carries its
          // start AND its stop on the same note, and taking only the first left
          // the span open forever, so it was dropped. Those groups are ordinary
          // — a single note bracketed 6:4 is how a corpus ABC file writes a
          // quarter that sounds where a dotted quarter is written.
          final tupletMarks = _notations(node)
              .expand((n) => n.childrenNamed('tuplet'))
              .toList();
          final modification = node.child('time-modification');
          final hasStart =
              tupletMarks.any((t) => t.attributes['type'] == 'start');
          final hasStop =
              tupletMarks.any((t) => t.attributes['type'] == 'stop');
          if (hasStart && modification != null) {
            openTupletStart[voiceIndex] = target.length - 1;
            openTupletRatio[voiceIndex] = (
              int.parse(modification.childText('actual-notes')!),
              int.parse(modification.childText('normal-notes')!),
            );
          }
          if (hasStop && openTupletStart[voiceIndex] != null) {
            final ratio = openTupletRatio[voiceIndex]!;
            final from = openTupletStart[voiceIndex]!;
            final to = target.length - 1;
            if (ratio.$1 >= 2) {
              tuplets.add(
                TupletSpan(
                  from,
                  to,
                  actual: ratio.$1,
                  normal: ratio.$2,
                  voice: voiceIndex,
                ),
              );
            } else {
              // `<actual-notes>1</actual-notes>` — one note in the time of N.
              // A legal time-modification (a corpus Mass uses 1:4) but NOT a
              // tuplet: `TupletSpan` asserts `actual >= 2`, so building one here
              // makes a Measure the model forbids, and it only survived because
              // `dart run` has assertions off. It is a display device for a
              // LONGER note, so fold the ratio into the written value instead —
              // which is lossless when the result is a real note value, and
              // every 1:N is (1/16 x 4 = a quarter).
              _absorbRatio(target, from, to, ratio.$2, ratio.$1);
            }
            openTupletStart[voiceIndex] = null;
            openTupletRatio[voiceIndex] = null;
          }
        default:
          break; // backup/forward/print/sound…: ignored
      }
    }

    _leadingSet = true;
    if (_multiRestLeft > 0) _multiRestLeft--;
    // `<measure-style><multiple-rest>` is a DISPLAY instruction, and a file can
    // contradict itself: this corpus has a MuseScore export whose measure 52
    // declares a 2-bar multi-rest and then carries two half notes. A bar with
    // music in it is not a multi-measure rest, whatever the markup says, and
    // storing that contradiction makes every consumer defend against it — the
    // ABC writer dropped the notes outright and the layout engine drew a
    // multi-rest instead of them. Normalise here, at the boundary.
    final hasNotes = [elements, voice2, voice3, voice4]
        .any((v) => v.any((e) => e is NoteElement));
    if (multiRest != null && hasNotes) {
      multiRest = null;
    }
    // The bar's whole-measure rest stays: it anchors any text, tempo or
    // dynamic set on the silent stretch (#11 — "Adagio" over bar 1 of a part
    // that opens with eight bars' rest). Dropping it crashed layout.
    _carriedDynamic = pendingDynamic;
    _measures.add(
      Measure(
        elements,
        voice2: voice2,
        voice3: voice3,
        voice4: voice4,
        tuplets: tuplets,
        clefChange: clefChange,
        inlineClefs: inlineClefs,
        keyChange: keyChange,
        timeChange: timeChange,
        tempoChange: tempoChange,
        startRepeat: startRepeat,
        endRepeat: endRepeat,
        volta: volta,
        multiRest: multiRest != null && multiRest >= 2 ? multiRest : null,
        // The model allows 1, 2 or 4 bars and asserts it, so anything else
        // from a third-party file is dropped rather than crashing the import.
        measureRepeat:
            const [1, 2, 4].contains(measureRepeat) ? measureRepeat : null,
        navigation: navigation,
        barline: barline,
        pickup: pickup,
      ),
    );
  }

  /// The first [childName] element under ANY of a `<direction>`'s
  /// `<direction-type>` children, or null.
  ///
  /// One direction routinely splits its content across sibling
  /// `<direction-type>` blocks — tempo text in one, its `<metronome>` in the
  /// next — in whatever order the exporting tool chose. Looking only inside
  /// the first block silently dropped whichever half came second.
  static XmlNode? _directionChild(XmlNode direction, String childName) {
    for (final type in direction.childrenNamed('direction-type')) {
      final match = type.child(childName);
      if (match != null) return match;
    }
    return null;
  }

  /// The text of every `<words>` run in a `<direction>`, in document order,
  /// joined. Exporters split one marking into runs — Finale writes each style
  /// change as its own `<words>` ("Allegro" + italic " con brio"), sometimes
  /// across `<direction-type>` blocks — and reading only the first run kept
  /// half the marking.
  ///
  /// Around a printed metronome ([aroundMetronome]) the runs often only
  /// bracket it — "Andante (" ♩=63 ")" — and the metronome is read as the
  /// tempo, so a dangling bracket and punctuation-only runs are dropped.
  static String _directionWords(XmlNode direction,
      {required bool aroundMetronome}) {
    final runs = <String>[];
    for (final type in direction.childrenNamed('direction-type')) {
      for (final words in type.childrenNamed('words')) {
        var text = words.text.trim();
        if (aroundMetronome) {
          text = text
              .replaceFirst(RegExp(r'\s*[(\[]\s*$'), '')
              .replaceFirst(RegExp(r'^\s*[)\]]\s*'), '');
          if (RegExp(r'^[\s\p{P}]*$', unicode: true).hasMatch(text)) continue;
        }
        if (text.isNotEmpty) runs.add(text);
      }
    }
    final out = StringBuffer();
    for (final run in runs) {
      // No space before a run that starts with closing punctuation.
      if (out.isNotEmpty && !RegExp(r'^[.,;:!?)\]]').hasMatch(run)) {
        out.write(' ');
      }
      out.write(run);
    }
    return out.toString();
  }

  /// A navigation mark from a `<direction>`: a `<segno>`/`<coda>` target, or
  /// an instruction whose `<words>` match a [SmuflGlyph.navigationLabel]
  /// (`D.C.`, `D.S. al Coda`, `Fine`, …). Returns null for other directions.
  static NavigationMark? _navigationOf(XmlNode node) {
    if (_directionChild(node, 'segno') != null) return NavigationMark.segno;
    if (_directionChild(node, 'coda') != null) return NavigationMark.coda;
    final words = _directionChild(node, 'words')?.text.trim();
    if (words == null) return null;
    for (final mark in NavigationMark.values) {
      if (SmuflGlyph.navigationLabel(mark) == words) return mark;
    }
    return null;
  }

  bool _isForStaff(XmlNode node) =>
      (int.tryParse(node.childText('staff') ?? '1') ?? 1) == staff;

  static Clef _clefOf(XmlNode clefNode) {
    final sign = clefNode.childText('sign');
    final line = int.tryParse(clefNode.childText('line') ?? '');
    final octave =
        int.tryParse(clefNode.childText('clef-octave-change') ?? '0') ?? 0;
    return switch ((sign, line, octave)) {
      ('G', _, 1) => Clef.treble8va,
      ('G', _, -1) => Clef.treble8vb,
      ('G', 1, _) => Clef.frenchViolin,
      ('G', _, _) => Clef.treble,
      ('F', 5, _) => Clef.subbass,
      ('F', 3, _) => Clef.baritone,
      ('F', _, -1) => Clef.bass8vb,
      ('F', _, _) => Clef.bass,
      ('C', 1, _) => Clef.soprano,
      ('C', 2, _) => Clef.mezzoSoprano,
      ('C', 4, _) => Clef.tenor,
      ('C', 5, _) => Clef.baritone,
      ('C', _, _) => Clef.alto, // line 3
      ('percussion', _, _) => Clef.percussion,
      ('TAB', _, _) => Clef.treble8vb, // guitar tab staff: read its pitches on
      // the conventional guitar clef (sounds an octave below written).
      // Any other / malformed sign: default to treble rather than abort the
      // whole import — a renderer must never crash on real input.
      _ => Clef.treble,
    };
  }

  // A percussion `<unpitched>` mapped to the staff line it displays on
  // (`display-step` / `display-octave`), so it renders as a normal notehead.
  static Pitch? _unpitchedOf(XmlNode? node) {
    if (node == null) return null;
    final stepText = node.childText('display-step');
    final octText = node.childText('display-octave');
    if (stepText == null || octText == null) return null;
    final step = Step.values.asNameMap()[stepText.toLowerCase()];
    final oct = int.tryParse(octText);
    if (step == null || oct == null) return null;
    return Pitch(step, octave: oct);
  }

  /// Rewrites elements [from]..[to] so each sounds [num]/[den] of its written
  /// value, when that lands on a real note value. Used for a time-modification
  /// that is not a tuplet, where there is no span to carry the ratio.
  static void _absorbRatio(
      List<MusicElement> target, int from, int to, int num, int den) {
    for (var i = from; i <= to && i < target.length; i++) {
      final e = target[i];
      if (e is! NoteElement) continue;
      final want = e.duration.toFraction() * Fraction(num, den);
      NoteDuration? match;
      for (var dots = 0; dots <= 2 && match == null; dots++) {
        for (final base in DurationBase.values) {
          if (NoteDuration(base, dots: dots).toFraction().compareTo(want) ==
              0) {
            match = NoteDuration(base, dots: dots);
            break;
          }
        }
      }
      if (match != null) target[i] = e.copyWith(duration: match);
    }
  }

  /// The model voice slot (0-3) for a `<voice>` label.
  ///
  /// A label of `1`-`4` maps straight to its own slot. First-seen order alone
  /// is not stable across bars: [voiceOrder] is rebuilt per measure, so in a bar
  /// where voice 1 happens to be silent the first label seen is `2`, and its
  /// notes land in voice 1 — the inner part jumps to the outer one for that bar
  /// and back afterwards.
  ///
  /// Labels outside that range (a piano part's second staff conventionally uses
  /// `5` and `6`) keep the first-seen fallback, taking the lowest slot no label
  /// in this measure has already claimed.
  static int _voiceIndexOf(String label, List<String> voiceOrder) {
    final n = int.tryParse(label.trim());
    if (n != null && n >= 1 && n <= 4) return n - 1;
    if (!voiceOrder.contains(label)) voiceOrder.add(label);
    final taken = <int>{
      for (final v in voiceOrder)
        if (int.tryParse(v.trim()) case final k?)
          if (k >= 1 && k <= 4) k - 1,
    };
    var slot = 0;
    for (final v in voiceOrder) {
      final k = int.tryParse(v.trim());
      if (k != null && k >= 1 && k <= 4) continue;
      while (taken.contains(slot)) {
        slot++;
      }
      if (v == label) return slot.clamp(0, 3);
      taken.add(slot);
    }
    return 0;
  }

  static Pitch? _pitchOf(XmlNode? pitchNode) {
    if (pitchNode == null) return null;
    final stepText = pitchNode.childText('step');
    final step = stepText == null
        ? null
        : Step.values.asNameMap()[stepText.toLowerCase()];
    final octave = int.tryParse(pitchNode.childText('octave') ?? '');
    if (step == null || octave == null) return null; // malformed <pitch>
    final alter =
        (double.tryParse(pitchNode.childText('alter') ?? '0') ?? 0).round();
    return Pitch(step, alter: alter, octave: octave);
  }

  NoteDuration _durationOf(XmlNode note) {
    const types = {
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
    final type = note.childText('type');
    final encoded = int.tryParse(note.childText('duration') ?? '');
    if (type != null) {
      var base = types[type];
      // Durations outside DurationBase's range are CLAMPED rather than thrown,
      // mirroring what the MuseScore reader already does for sub-64ths
      // (`1b8efd2`). Rejecting them threw away whole scores over one ornament
      // or one mensural note: a CPDL sweep lost 24 files this way, all early
      // music or fast tremolos.
      //
      // The clamp is lossy in a KNOWN direction, which is why it is safe to
      // ship: a longa/maxima reads SHORT (there is no DurationBase above the
      // breve), a 128th and below reads LONG. Neither loses the note.
      base ??= switch (type) {
        'maxima' || 'long' || 'longa' => DurationBase.breve,
        '128th' || '256th' || '512th' || '1024th' => DurationBase.sixtyFourth,
        _ => null,
      };
      if (base == null) {
        throw FormatException('Unsupported note type: "$type"');
      }
      final dots = note.childrenNamed('dot').length.clamp(0, 2);
      final written = NoteDuration(base, dots: dots);
      if (encoded != null &&
          dots == 0 &&
          note.child('time-modification') == null) {
        final byDuration = _durationFromQuarters(
          encoded / _divisions,
          types,
          snapToNearest: false,
        );
        if (byDuration != null && byDuration != written) {
          return byDuration;
        }
      }
      return written;
    }
    // No <type> (e.g. whole-measure rests): derive from duration/divisions.
    if (encoded == null) {
      throw const FormatException('<note> without <type> or <duration>');
    }
    return _durationFromQuarters(encoded / _divisions, types) ??
        NoteDuration.quarter;
  }

  NoteDuration? _durationFromQuarters(
    double quarters,
    Map<String, DurationBase> types, {
    bool snapToNearest = true,
  }) {
    for (final entry in types.entries) {
      final (bn, bd) = entry.value.wholeValue;
      final value = 4.0 * bn / bd;
      if ((quarters - value).abs() < 1e-6) {
        return NoteDuration(entry.value);
      }
      if ((quarters - value * 1.5).abs() < 1e-6) {
        return NoteDuration(entry.value, dots: 1);
      }
      if ((quarters - value * 1.75).abs() < 1e-6) {
        return NoteDuration(entry.value, dots: 2);
      }
    }
    if (!snapToNearest) return null;
    // No exact match: snap to the nearest representable note value instead of
    // aborting the whole import — real orchestral scores carry odd encoded
    // durations (cue / grace notes at fine divisions, e.g. 85/1024).
    NoteDuration? best;
    var bestErr = double.infinity;
    for (final base in types.values) {
      final value = 4.0 / base.denominator;
      for (var dots = 0; dots <= 2; dots++) {
        final mult = switch (dots) {
          1 => 1.5,
          2 => 1.75,
          _ => 1.0,
        };
        final err = (quarters - value * mult).abs();
        if (err < bestErr) {
          bestErr = err;
          best = NoteDuration(base, dots: dots);
        }
      }
    }
    return best ?? NoteDuration.quarter;
  }

  static bool _startsTie(XmlNode note) =>
      note.childrenNamed('tie').any((tie) => tie.attributes['type'] == 'start');

  Iterable<XmlNode> _notations(XmlNode note) => note.childrenNamed('notations');

  JazzArticulation? _jazzOf(XmlNode note) {
    for (final notations in _notations(note)) {
      final articulations = notations.child('articulations');
      if (articulations == null) continue;
      for (final mark in articulations.children) {
        final jazz = switch (mark.name) {
          'scoop' => JazzArticulation.scoop,
          'plop' => JazzArticulation.plop,
          'doit' => JazzArticulation.doit,
          'falloff' => JazzArticulation.fall,
          _ => null,
        };
        if (jazz != null) return jazz;
      }
    }
    return null;
  }

  BreathSymbol? _breathOf(XmlNode note) {
    for (final notations in _notations(note)) {
      final articulations = notations.child('articulations');
      if (articulations == null) continue;
      for (final mark in articulations.children) {
        if (mark.name == 'breath-mark') return BreathSymbol.comma;
        if (mark.name == 'caesura') return BreathSymbol.caesura;
      }
    }
    return null;
  }

  /// A `<tied type="let-ring"/>` in the note's notations is a laissez-vibrer
  /// tie; its optional `orientation` (under/over) maps to [LaissezVibrer.down].
  LaissezVibrer? _laissezVibrerOf(XmlNode note, String id) {
    for (final notations in _notations(note)) {
      for (final tied in notations.childrenNamed('tied')) {
        if (tied.attributes['type'] == 'let-ring') {
          final o = tied.attributes['orientation'];
          return LaissezVibrer(
            id,
            down: o == 'under'
                ? true
                : o == 'over'
                    ? false
                    : null,
          );
        }
      }
    }
    return null;
  }

  Set<Articulation> _articulationsOf(XmlNode note) {
    final result = <Articulation>{};
    for (final notations in _notations(note)) {
      if (notations.child('fermata') != null) {
        result.add(Articulation.fermata);
      }
      // Up-/down-bow are string techniques, under <technical>.
      final technical = notations.child('technical');
      if (technical != null) {
        if (technical.child('up-bow') != null) result.add(Articulation.upBow);
        if (technical.child('down-bow') != null) {
          result.add(Articulation.downBow);
        }
      }
      final articulations = notations.child('articulations');
      if (articulations == null) continue;
      for (final mark in articulations.children) {
        final articulation = switch (mark.name) {
          'staccato' => Articulation.staccato,
          'tenuto' => Articulation.tenuto,
          'accent' => Articulation.accent,
          'strong-accent' => Articulation.marcato,
          'staccatissimo' => Articulation.staccatissimo,
          'breath-mark' => Articulation.breath,
          _ => null,
        };
        if (articulation != null) result.add(articulation);
      }
    }
    return result.isEmpty ? const {} : result;
  }

  NoteheadShape _noteheadOf(XmlNode note) =>
      switch (note.childText('notehead')) {
        'x' => NoteheadShape.x,
        'diamond' => NoteheadShape.diamond,
        'triangle' => NoteheadShape.triangleUp,
        'slash' => NoteheadShape.slash,
        'circle-x' => NoteheadShape.circleX,
        _ => NoteheadShape.normal,
      };

  int? _tremoloOf(XmlNode note) {
    for (final notations in _notations(note)) {
      final tremolo = notations.child('ornaments')?.child('tremolo');
      if (tremolo != null &&
          (tremolo.attributes['type'] ?? 'single') == 'single') {
        return int.tryParse(tremolo.text.trim());
      }
    }
    return null;
  }

  Arpeggio? _arpeggioOf(XmlNode note) {
    for (final notations in _notations(note)) {
      final arp = notations.child('arpeggiate');
      if (arp != null) {
        return arp.attributes['direction'] == 'down'
            ? Arpeggio.down
            : Arpeggio.up;
      }
    }
    return null;
  }

  List<int> _fingeringsOf(XmlNode note) {
    final result = <int>[];
    for (final notations in _notations(note)) {
      final technical = notations.child('technical');
      if (technical == null) continue;
      for (final mark in technical.childrenNamed('fingering')) {
        final text = mark.text.trim();
        // Editions print the string player's thumb as `T` (or `t`), which is
        // not a digit — <fingering> is free text, so map it to the model's
        // thumb slot rather than dropping the mark.
        if (text == 'T' || text == 't') {
          result.add(kFingeringThumb);
          continue;
        }
        final value = int.tryParse(text);
        if (value != null) result.add(value);
      }
    }
    return result.isEmpty ? const [] : result;
  }

  Ornament? _ornamentOf(XmlNode note) {
    for (final notations in _notations(note)) {
      final ornaments = notations.child('ornaments');
      if (ornaments == null) continue;
      // A trill-mark paired with a wavy-line is an extended trill (handled as a
      // TrillExtension span), so it is not also a single-note trill ornament.
      final hasWavy = ornaments.childrenNamed('wavy-line').isNotEmpty;
      // A trill-mark + accidental-mark is a baroque trill-with-accidental.
      final accMarks = ornaments.childrenNamed('accidental-mark');
      if (!hasWavy &&
          ornaments.childrenNamed('trill-mark').isNotEmpty &&
          accMarks.isNotEmpty) {
        return switch (accMarks.first.text.trim()) {
          'sharp' => Ornament.trillSharp,
          'flat' => Ornament.trillFlat,
          'natural' => Ornament.trillNatural,
          _ => Ornament.trill,
        };
      }
      for (final mark in ornaments.children) {
        final ornament = switch (mark.name) {
          'trill-mark' => hasWavy ? null : Ornament.trill,
          'inverted-mordent' => Ornament.shortTrill,
          'mordent' => Ornament.mordent,
          'turn' => Ornament.turn,
          'inverted-turn' => Ornament.invertedTurn,
          _ => null,
        };
        if (ornament != null) return ornament;
      }
    }
    return null;
  }

  /// The note's `<slur>` marks as `(type, number)`, in document order.
  List<(String, String)> _slurMarks(XmlNode note) => [
        for (final notations in _notations(note))
          for (final slur in notations.childrenNamed('slur'))
            if (slur.attributes['type'] case final type?)
              (type, slur.attributes['number'] ?? '1'),
      ];

  /// Slur bookkeeping for a note that is not imported: its starts take their
  /// numbers, its stops release them.
  void _skipSlurMarks(XmlNode note) {
    for (final (type, number) in _slurMarks(note)) {
      if (type == 'start') {
        _openSlur(number, null);
      } else if (type == 'stop') {
        _closeSlur(number);
      }
    }
  }

  void _readSpans(XmlNode note, String id) {
    for (final number in _graceSlurStarts) {
      _openSlur(number, id);
    }
    _graceSlurStarts.clear();
    for (final notations in _notations(note)) {
      for (final slur in notations.childrenNamed('slur')) {
        final number = slur.attributes['number'] ?? '1';
        switch (slur.attributes['type']) {
          case 'start':
            _openSlur(number, id, slur);
          case 'stop':
            final placement = _placementOf(number);
            final start = _closeSlur(number);
            // A slur that starts and ends on one note (a grace's slur to its
            // own principal) draws nothing.
            // The same slur written more than once over the same notes (an
            // export stacks copies under new numbers: #14 had four) is one
            // slur. Kept, each copy drew as another arc around the first.
            final slur = Slur(start ?? '', id, placement: placement);
            if (start != null && start != id && !_slurs.contains(slur)) {
              _slurs.add(slur);
            }
        }
      }
      // ⚠️ `<glissando>` and `<slide>` are DIFFERENT elements — a glissando
      // steps, a slide is continuous — and the model has both. Only `<slide>`
      // was read, and it was read as a Glissando, so every real `<glissando>`
      // in a third-party file was dropped silently.
      for (final gliss in notations.childrenNamed('glissando')) {
        final number = gliss.attributes['number'] ?? '1';
        switch (gliss.attributes['type']) {
          case 'start':
            _openGliss[number] = id;
          case 'stop':
            final start = _openGliss.remove(number);
            if (start != null) _glissandos.add(Glissando(start, id));
        }
      }
      for (final slide in notations.childrenNamed('slide')) {
        final number = slide.attributes['number'] ?? '1';
        switch (slide.attributes['type']) {
          case 'start':
            _openPortamento[number] = id;
          case 'stop':
            final start = _openPortamento.remove(number);
            if (start != null) _portamentos.add(Portamento(start, id));
        }
      }
      // Extended-trill wavy lines live inside <ornaments>.
      for (final ornaments in notations.childrenNamed('ornaments')) {
        for (final wavy in ornaments.childrenNamed('wavy-line')) {
          final number = wavy.attributes['number'] ?? '1';
          switch (wavy.attributes['type']) {
            case 'start':
              _openTrills[number] = id;
            case 'stop':
              final start = _openTrills.remove(number);
              if (start != null) {
                _trillExtensions.add(TrillExtension(start, id));
              }
          }
        }
      }
    }
  }

  void _handlePedal(XmlNode pedal) {
    final number = pedal.attributes['number'] ?? '1';
    switch (pedal.attributes['type']) {
      case 'start':
        _pendingPedals.add(number);
      case 'stop':
        _pendingPedals.remove(number);
        final start = _openPedals.remove(number);
        if (start != null) {
          _pedals.add(Pedal(start.$1, _lastNoteOfVoice[start.$2] ?? start.$1));
        }
    }
  }

  /// Binds every span still awaiting a note to [id] in [voice].
  void _bindPendingSpans(String id, int voice) {
    for (final e in _pendingWedges.entries) {
      _openWedges[e.key] = (id, voice, e.value);
    }
    _pendingWedges.clear();
    for (final number in _pendingPedals) {
      _openPedals[number] = (id, voice);
    }
    _pendingPedals.clear();
    for (final e in _pendingOttavas.entries) {
      _openOttavas[e.key] = (id, voice, e.value);
    }
    _pendingOttavas.clear();
  }

  void _handleWedge(
    XmlNode wedge,
    List<MusicElement> elements,
    List<MusicElement> voice2,
  ) {
    final number = wedge.attributes['number'] ?? '1';
    final type = wedge.attributes['type'];
    if (type == 'crescendo' || type == 'diminuendo') {
      // Bound when the next NOTE arrives (see _bindPendingWedges), not
      // predicted — a rest must not take the anchor.
      _pendingWedges[number] =
          type == 'crescendo' ? HairpinType.crescendo : HairpinType.diminuendo;
    } else if (type == 'stop') {
      _pendingWedges.remove(number); // opened and closed with no note between
      final open = _openWedges.remove(number);
      if (open != null) {
        // The last note read IN THE START'S OWN VOICE. That is also what keeps
        // the span from running backwards: the start note is itself in that
        // voice, so the answer can never precede it.
        final endId = _lastNoteOfVoice[open.$2] ?? open.$1;
        _hairpins.add(Hairpin(open.$1, endId, open.$3));
      }
    }
  }

  void _handleOctaveShift(XmlNode shift) {
    final number = shift.attributes['number'] ?? '1';
    switch (shift.attributes['type']) {
      // MusicXML "down" writes the notes lower → 8va bracket above.
      case 'down':
        _pendingOttavas[number] = false;
      case 'up':
        _pendingOttavas[number] = true;
      case 'stop':
        _pendingOttavas.remove(number);
        final open = _openOttavas.remove(number);
        if (open != null) {
          _ottavas.add(Ottava(
            open.$1,
            _lastNoteOfVoice[open.$2] ?? open.$1,
            down: open.$3,
          ));
        }
    }
  }

  void _readLyric(XmlNode note, String id) {
    // A note may carry several <lyric> elements — one per verse.
    for (final lyric in note.childrenNamed('lyric')) {
      // Multiple <text> runs separated by <elision> are syllables elided onto
      // this one note; each becomes its own Lyric, joined by elidesToNext.
      final texts = [
        for (final t in lyric.childrenNamed('text'))
          if (t.text.isNotEmpty) t.text,
      ];
      if (texts.isEmpty) continue;
      final syllabic = lyric.childText('syllabic');
      final verse = int.tryParse(lyric.attributes['number'] ?? '1') ?? 1;
      final hasExtend = lyric.child('extend') != null;
      for (var i = 0; i < texts.length; i++) {
        final isLast = i == texts.length - 1;
        _lyrics.add(
          Lyric(
            id,
            texts[i],
            hyphenToNext:
                isLast && (syllabic == 'begin' || syllabic == 'middle'),
            extender: isLast && hasExtend,
            elidesToNext: !isLast,
            verse: verse < 1 ? 1 : verse,
          ),
        );
      }
    }
  }

  /// Parses a `<harmony>` into a structured chord (root/quality/bass); null if
  /// it has no readable root.
  static ({Pitch root, ChordSymbolKind quality, Pitch? bass})? _chordSymbolOf(
    XmlNode harmony,
  ) {
    final root = _harmonyPitch(
      harmony.child('root'),
      'root-step',
      'root-alter',
    );
    if (root == null) return null;
    final kind = harmony.child('kind')?.text;
    final quality = ChordSymbolKind.values.firstWhere(
      (q) => q.musicXmlKind == kind,
      orElse: () => ChordSymbolKind.major,
    );
    final bass = _harmonyPitch(
      harmony.child('bass'),
      'bass-step',
      'bass-alter',
    );
    return (root: root, quality: quality, bass: bass);
  }

  /// A `<root>`/`<bass>` step+alter into a [Pitch] (octave is nominal — chord
  /// roots are pitch classes).
  static Pitch? _harmonyPitch(XmlNode? node, String stepTag, String alterTag) {
    if (node == null) return null;
    final step =
        Step.values.asNameMap()[node.childText(stepTag)?.toLowerCase()];
    if (step == null) return null;
    final alter = (int.tryParse(node.childText(alterTag) ?? '0') ?? 0).clamp(
      -2,
      2,
    );
    return Pitch(step, alter: alter);
  }
}
