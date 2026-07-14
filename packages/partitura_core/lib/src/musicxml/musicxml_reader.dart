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
/// Throws [FormatException] on documents this subset cannot represent.
Score scoreFromMusicXml(String xml, {int partIndex = 0}) {
  final root = parseXml(xml);
  final parts = _partsOf(root);
  if (partIndex < 0 || partIndex >= parts.length) {
    throw FormatException('Part $partIndex not found (${parts.length} parts)');
  }
  return _PartReader(parts[partIndex],
          staff: 1, metadata: _metadataOf(root, parts[partIndex]))
      .read();
}

/// The default part-name the writer emits when no instrument is set; the reader
/// maps it back to a null instrument so empty metadata round-trips.
const _defaultPartName = 'Music';

/// Reads `<work>`/`<identification>` and the part's `<part-name>` into
/// [ScoreMetadata].
ScoreMetadata _metadataOf(XmlNode root, XmlNode part) {
  final title = root.child('work')?.childText('work-title') ??
      root.childText('movement-title');
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
  final copyright = identification?.childText('rights');
  // Part name: match the score-part with this part's id, null out the default.
  final partId = part.attributes['id'];
  String? partName;
  for (final sp in root.child('part-list')?.childrenNamed('score-part') ??
      const <XmlNode>[]) {
    if (sp.attributes['id'] == partId) partName = sp.childText('part-name');
  }
  final instrument =
      partName == _defaultPartName || partName == '' ? null : partName;
  return ScoreMetadata(
    title: title == '' ? null : title,
    composer: composer == '' ? null : composer,
    lyricist: lyricist == '' ? null : lyricist,
    copyright: copyright == '' ? null : copyright,
    instrument: instrument,
  );
}

/// Parses a `score-partwise` document into a [GrandStaff]: either the
/// first part's staves 1+2, or the first two parts.
GrandStaff grandStaffFromMusicXml(String xml) {
  final root = parseXml(xml);
  final parts = _partsOf(root);
  final firstStaves =
      int.tryParse(_firstAttributes(parts.first)?.childText('staves') ?? '1');
  if ((firstStaves ?? 1) >= 2) {
    return GrandStaff(
      upper: _PartReader(parts.first, staff: 1).read(),
      lower: _PartReader(parts.first, staff: 2, idOffset: 1000).read(),
    );
  }
  if (parts.length < 2) {
    throw const FormatException(
        'Grand staff needs a two-staff part or two parts');
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
  for (final part in parts) {
    final n =
        int.tryParse(_firstAttributes(part)?.childText('staves') ?? '1') ?? 1;
    partStart.add(staves.length);
    partSpan.add(n);
    final first = staves.length;
    for (var s = 1; s <= n; s++) {
      staves.add(_PartReader(part, staff: s, idOffset: idBase).read());
      idBase += 1000;
    }
    if (n >= 2) {
      // A multi-staff part (piano/organ) is braced together.
      brackets.add(
          StaffBracket(first, staves.length - 1, kind: StaffBracketKind.brace));
    }
  }

  brackets.addAll(_partGroupBrackets(root, partStart, partSpan));
  return StaffSystem(
    staves,
    brackets: brackets,
    barlineGroups: _partGroupBarlines(root, partStart, partSpan),
  );
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
    XmlNode root, List<int> partStart, List<int> partSpan) {
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
/// `group-barline` absent or `no` contributes nothing (so a document with no
/// group-barlines keeps its default single systemic barline). Mirrors
/// [_partGroupBrackets]; `<score-part>` order matches `<part>` order.
List<BarlineGroup> _partGroupBarlines(
    XmlNode root, List<int> partStart, List<int> partSpan) {
  final list = root.child('part-list');
  if (list == null) return const [];
  final result = <BarlineGroup>[];
  final openStart = <String, int>{}; // group number -> first staff index
  final openConnects = <String, bool>{};
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
          openStart[number] = partStart[ordinal];
          openConnects[number] = barline == 'yes' || barline == 'Mensurstrich';
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

class _PartReader {
  final XmlNode part;

  /// Which staff of the part to read (1-based; grand staffs use 1 and 2).
  final int staff;

  /// Offset for generated element ids, so two staves of one document
  /// get disjoint id spaces (`e0…` and `e1000…`).
  final int idOffset;

  _PartReader(this.part,
      {required this.staff,
      this.idOffset = 0,
      this.metadata = const ScoreMetadata()});

  /// Document-level metadata (title/composer/…) to attach to the built score.
  final ScoreMetadata metadata;

  int _nextId = 0;
  int _divisions = 1;

  Clef? _clef; // running clef (mid-score changes update it)
  Clef? _leadingClef;
  KeySignature? _key;
  TimeSignature? _time;
  Transposition? _transposition;
  Tempo? _tempo;

  static const _beatUnits = {
    'breve': DurationBase.breve,
    'whole': DurationBase.whole,
    'half': DurationBase.half,
    'quarter': DurationBase.quarter,
    'eighth': DurationBase.eighth,
    '16th': DurationBase.sixteenth,
    '32nd': DurationBase.thirtySecond,
    '64th': DurationBase.sixtyFourth,
  };

  /// A `<metronome>` (beat-unit + per-minute) into a [Tempo].
  static Tempo? _tempoOf(XmlNode metronome) {
    final base = _beatUnits[metronome.childText('beat-unit')];
    final perMinute = double.tryParse(metronome.childText('per-minute') ?? '');
    if (base == null || perMinute == null) return null;
    final dots = metronome.childrenNamed('beat-unit-dot').length.clamp(0, 2);
    return Tempo(perMinute, beatUnit: base, dots: dots);
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
  final _openSlurs = <String, String>{};
  final _openGliss = <String, String>{};
  final _openTrills = <String, String>{};
  final _openPedals = <String, String>{};
  final _openWedges = <String, (String, HairpinType)>{};
  final _openOttavas = <String, (String, bool)>{};
  final _ottavas = <Ottava>[];

  Score read() {
    for (final measureNode in part.childrenNamed('measure')) {
      _readMeasure(measureNode);
    }
    // Tolerate a slur left open at the end (real files carry imbalances — a
    // number reused across a `type="continue"`, or a `stop` lost across a part
    // boundary): an unclosed slur simply never became a `Slur`, so drop it and
    // read the rest rather than aborting the whole document.
    return Score(
      clef: _leadingClef ?? Clef.treble,
      keySignature: _key ?? const KeySignature(0),
      timeSignature: _time,
      measures: _measures,
      slurs: _slurs,
      dynamics: _dynamics,
      hairpins: _hairpins,
      lyrics: _lyrics,
      annotations: _annotations,
      chordSymbols: _chordSymbols,
      ottavas: _ottavas,
      glissandos: _glissandos,
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
  TimeSignature _parseTimeSig(XmlNode time, {bool allowAlternate = true}) {
    final symbol = switch (time.attributes['symbol']) {
      'common' => TimeSymbol.common,
      'cut' => TimeSymbol.cut,
      _ => TimeSymbol.numeric,
    };
    final beatsText = time.childText('beats')!;
    final beatUnit = int.parse(time.childText('beat-type')!);
    final groups = beatsText.contains('+')
        ? beatsText.split('+').map(int.parse).toList()
        : null;
    TimeSignature? alt;
    if (allowAlternate) {
      final inter = time.child('interchangeable');
      if (inter != null) alt = _parseTimeSig(inter, allowAlternate: false);
    }
    return groups != null
        ? TimeSignature(groups.reduce((a, b) => a + b), beatUnit,
            components: List.unmodifiable(groups), alternate: alt)
        : TimeSignature(int.parse(beatsText), beatUnit,
            symbol: symbol, alternate: alt);
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

  void _readMeasure(XmlNode measureNode) {
    // An implicit measure (or the conventional number="0") is a pickup.
    final pickup = measureNode.attributes['implicit'] == 'yes' ||
        measureNode.attributes['number'] == '0';
    final elements = <MusicElement>[];
    final voice2 = <MusicElement>[];
    final voice3 = <MusicElement>[];
    final voice4 = <MusicElement>[];
    final voiceLists = [elements, voice2, voice3, voice4];
    final voiceOrder = <String>[]; // distinct voice labels in first-seen order
    final tuplets = <TupletSpan>[];
    Clef? clefChange;
    KeySignature? keyChange;
    TimeSignature? timeChange;
    Tempo? tempoChange;
    var startRepeat = false;
    var endRepeat = false;
    var barline = BarlineStyle.normal;
    int? volta;
    int? multiRest;
    NavigationMark? navigation;

    var pendingGraces = <Pitch>[];
    var pendingGraceStyle = GraceStyle.acciaccatura;
    String? pendingDynamic;
    ({Pitch root, ChordSymbolKind quality, Pitch? bass})? pendingChord;
    String? pendingAnnotation;
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
            } else if (key != (_key ?? const KeySignature(0))) {
              keyChange = key;
            }
          }
          final time = node.child('time');
          if (time != null) {
            final signature = _parseTimeSig(time);
            if (!_leadingSet) {
              _time = signature;
            } else if (signature != _time) {
              timeChange = signature;
            }
          }
          final multipleRest =
              node.child('measure-style')?.childText('multiple-rest');
          if (multipleRest != null) {
            multiRest = int.tryParse(multipleRest);
          }
          for (final clefNode in node.childrenNamed('clef')) {
            final number =
                int.tryParse(clefNode.attributes['number'] ?? '1') ?? 1;
            if (number != staff) continue;
            final clef = _clefOf(clefNode);
            if (!_leadingSet) {
              _clef = clef;
              _leadingClef = clef;
            } else if (clef != _clef) {
              clefChange = clef;
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
                (ending.attributes['number'] ?? '1').split(',').first.trim());
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
          final dynamicsNode = node.child('direction-type')?.child('dynamics');
          if (dynamicsNode != null && dynamicsNode.children.isNotEmpty) {
            pendingDynamic = dynamicsNode.children.first.name;
          }
          final wedge = node.child('direction-type')?.child('wedge');
          if (wedge != null) _handleWedge(wedge, elements, voice2);
          final shift = node.child('direction-type')?.child('octave-shift');
          if (shift != null) _handleOctaveShift(shift);
          final pedal = node.child('direction-type')?.child('pedal');
          if (pedal != null) _handlePedal(pedal);
          final metronome = node.child('direction-type')?.child('metronome');
          if (metronome != null) {
            final t = _tempoOf(metronome);
            // The first metronome is the score's initial tempo; any later one is
            // a mid-score change on this measure.
            if (_tempo == null) {
              _tempo = t;
            } else {
              tempoChange ??= t;
            }
          }
          navigation ??= _navigationOf(node);
          // A plain <words> that is not a navigation label is a text annotation.
          final words = node.child('direction-type')?.childText('words');
          if (words != null &&
              words.isNotEmpty &&
              _navigationOf(node) == null &&
              dynamicsNode == null) {
            pendingAnnotation ??= words;
          }
        case 'harmony':
          pendingChord = _chordSymbolOf(node);
        case 'figured-bass':
          pendingFigures = [
            for (final fig in node.childrenNamed('figure')) _figureText(fig),
          ];
        case 'note':
          if (!_isForStaff(node)) break;
          if (node.attributes['print-object'] == 'no') break;
          final grace = node.child('grace');
          if (grace != null) {
            final pitch = _pitchOf(node.child('pitch'));
            if (pitch != null) pendingGraces.add(pitch);
            if (grace.attributes['slash'] == 'no') {
              pendingGraceStyle = GraceStyle.appoggiatura;
            }
            break;
          }
          final voiceLabel = node.childText('voice') ?? '1';
          if (!voiceOrder.contains(voiceLabel) && voiceOrder.length < 4) {
            voiceOrder.add(voiceLabel);
          }
          final voiceIndex = voiceOrder.indexOf(voiceLabel).clamp(0, 3);
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
              }
              break;
            }
          }

          final id = _newId();
          final duration = _durationOf(node);
          // Percussion notes carry <unpitched> (display-step/octave for the
          // staff line) instead of <pitch>. A note that is neither pitched,
          // unpitched, nor a rest keeps its timing as a rest rather than
          // aborting the whole import.
          final pitch = _pitchOf(node.child('pitch')) ??
              _unpitchedOf(node.child('unpitched'));
          if (node.child('rest') != null || pitch == null) {
            target.add(RestElement(duration, id: id));
          } else {
            target.add(NoteElement(
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
            ));
            pendingGraces = <Pitch>[];
            pendingGraceStyle = GraceStyle.acciaccatura;
            if (pendingDynamic != null) {
              final level = DynamicLevel.values.asNameMap()[pendingDynamic];
              if (level != null) _dynamics.add(DynamicMarking(id, level));
              pendingDynamic = null;
            }
            if (pendingChord != null) {
              _chordSymbols.add(ChordSymbol(
                  id, pendingChord.root, pendingChord.quality,
                  bass: pendingChord.bass));
              pendingChord = null;
            }
            if (pendingAnnotation != null) {
              _annotations.add(Annotation(id, pendingAnnotation));
              pendingAnnotation = null;
            }
            if (pendingFigures != null) {
              if (pendingFigures.isNotEmpty) {
                _figuredBass.add(FiguredBass(id, pendingFigures));
              }
              pendingFigures = null;
            }
            _readSpans(node, id);
            _readLyric(node, id);
            final jazz = _jazzOf(node);
            if (jazz != null) _jazzMarks.add(JazzMark(id, jazz));
            final breath = _breathOf(node);
            if (breath != null) _breathMarks.add(BreathMark(id, breath));
            final lv = _laissezVibrerOf(node, id);
            if (lv != null) _laissezVibrer.add(lv);
          }

          final tuplet = _notations(node)
              .expand((n) => n.childrenNamed('tuplet'))
              .firstOrNull;
          final modification = node.child('time-modification');
          if (tuplet?.attributes['type'] == 'start' && modification != null) {
            openTupletStart[voiceIndex] = target.length - 1;
            openTupletRatio[voiceIndex] = (
              int.parse(modification.childText('actual-notes')!),
              int.parse(modification.childText('normal-notes')!),
            );
          }
          if (tuplet?.attributes['type'] == 'stop' &&
              openTupletStart[voiceIndex] != null) {
            final ratio = openTupletRatio[voiceIndex]!;
            tuplets.add(TupletSpan(
              openTupletStart[voiceIndex]!,
              target.length - 1,
              actual: ratio.$1,
              normal: ratio.$2,
              voice: voiceIndex,
            ));
            openTupletStart[voiceIndex] = null;
            openTupletRatio[voiceIndex] = null;
          }
        default:
          break; // backup/forward/print/sound…: ignored
      }
    }

    _leadingSet = true;
    if (multiRest != null && multiRest >= 2) {
      // Whole-measure rest markup inside a multiple-rest is redundant.
      elements.removeWhere((element) => element is RestElement);
    }
    _measures.add(Measure(
      elements,
      voice2: voice2,
      voice3: voice3,
      voice4: voice4,
      tuplets: tuplets,
      clefChange: clefChange,
      keyChange: keyChange,
      timeChange: timeChange,
      tempoChange: tempoChange,
      startRepeat: startRepeat,
      endRepeat: endRepeat,
      volta: volta,
      multiRest: multiRest != null && multiRest >= 2 ? multiRest : null,
      navigation: navigation,
      barline: barline,
      pickup: pickup,
    ));
  }

  /// A navigation mark from a `<direction>`: a `<segno>`/`<coda>` target, or
  /// an instruction whose `<words>` match a [SmuflGlyph.navigationLabel]
  /// (`D.C.`, `D.S. al Coda`, `Fine`, …). Returns null for other directions.
  static NavigationMark? _navigationOf(XmlNode node) {
    final type = node.child('direction-type');
    if (type == null) return null;
    if (type.child('segno') != null) return NavigationMark.segno;
    if (type.child('coda') != null) return NavigationMark.coda;
    final words = type.childText('words')?.trim();
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

  static Pitch? _pitchOf(XmlNode? pitchNode) {
    if (pitchNode == null) return null;
    final step =
        Step.values.asNameMap()[pitchNode.childText('step')!.toLowerCase()]!;
    final alter =
        (double.tryParse(pitchNode.childText('alter') ?? '0') ?? 0).round();
    return Pitch(
      step,
      alter: alter,
      octave: int.parse(pitchNode.childText('octave')!),
    );
  }

  NoteDuration _durationOf(XmlNode note) {
    const types = {
      'breve': DurationBase.breve,
      'whole': DurationBase.whole,
      'half': DurationBase.half,
      'quarter': DurationBase.quarter,
      'eighth': DurationBase.eighth,
      '16th': DurationBase.sixteenth,
      '32nd': DurationBase.thirtySecond,
      '64th': DurationBase.sixtyFourth,
    };
    final type = note.childText('type');
    final encoded = int.tryParse(note.childText('duration') ?? '');
    if (type != null) {
      final base = types[type];
      if (base == null) {
        throw FormatException('Unsupported note type: "$type"');
      }
      final dots = note.childrenNamed('dot').length.clamp(0, 2);
      final written = NoteDuration(base, dots: dots);
      if (encoded != null &&
          dots == 0 &&
          note.child('time-modification') == null) {
        final byDuration = _durationFromQuarters(encoded / _divisions, types,
            snapToNearest: false);
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
      final value = entry.value == DurationBase.breve
          ? 8.0
          : 4.0 / entry.value.denominator;
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
        final mult = switch (dots) { 1 => 1.5, 2 => 1.75, _ => 1.0 };
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
          return LaissezVibrer(id,
              down: o == 'under'
                  ? true
                  : o == 'over'
                      ? false
                      : null);
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
        final value = int.tryParse(mark.text.trim());
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

  void _readSpans(XmlNode note, String id) {
    for (final notations in _notations(note)) {
      for (final slur in notations.childrenNamed('slur')) {
        final number = slur.attributes['number'] ?? '1';
        switch (slur.attributes['type']) {
          case 'start':
            _openSlurs[number] = id;
          case 'stop':
            final start = _openSlurs.remove(number);
            if (start != null) _slurs.add(Slur(start, id));
        }
      }
      for (final slide in notations.childrenNamed('slide')) {
        final number = slide.attributes['number'] ?? '1';
        switch (slide.attributes['type']) {
          case 'start':
            _openGliss[number] = id;
          case 'stop':
            final start = _openGliss.remove(number);
            if (start != null) _glissandos.add(Glissando(start, id));
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
        _openPedals[number] = 'e${idOffset + _nextId}';
      case 'stop':
        final start = _openPedals.remove(number);
        if (start != null) {
          _pedals.add(Pedal(start, 'e${idOffset + _nextId - 1}'));
        }
    }
  }

  void _handleWedge(
    XmlNode wedge,
    List<MusicElement> elements,
    List<MusicElement> voice2,
  ) {
    final number = wedge.attributes['number'] ?? '1';
    final type = wedge.attributes['type'];
    if (type == 'crescendo' || type == 'diminuendo') {
      // Anchors on the next note read; remember via a placeholder that is
      // resolved when that note gets its id — simplest: anchor on the id
      // the next _newId() will produce.
      _openWedges[number] = (
        'e${idOffset + _nextId}',
        type == 'crescendo' ? HairpinType.crescendo : HairpinType.diminuendo,
      );
    } else if (type == 'stop') {
      final open = _openWedges.remove(number);
      if (open != null) {
        // Ends on the most recently created note element.
        final endId = 'e${idOffset + _nextId - 1}';
        _hairpins.add(Hairpin(open.$1, endId, open.$2));
      }
    }
  }

  void _handleOctaveShift(XmlNode shift) {
    final number = shift.attributes['number'] ?? '1';
    switch (shift.attributes['type']) {
      // MusicXML "down" writes the notes lower → 8va bracket above.
      case 'down':
        _openOttavas[number] = ('e${idOffset + _nextId}', false);
      case 'up':
        _openOttavas[number] = ('e${idOffset + _nextId}', true);
      case 'stop':
        final open = _openOttavas.remove(number);
        if (open != null) {
          _ottavas.add(Ottava(
            open.$1,
            'e${idOffset + _nextId - 1}',
            down: open.$2,
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
        _lyrics.add(Lyric(
          id,
          texts[i],
          hyphenToNext: isLast && (syllabic == 'begin' || syllabic == 'middle'),
          extender: isLast && hasExtend,
          elidesToNext: !isLast,
          verse: verse < 1 ? 1 : verse,
        ));
      }
    }
  }

  /// Parses a `<harmony>` into a structured chord (root/quality/bass); null if
  /// it has no readable root.
  static ({Pitch root, ChordSymbolKind quality, Pitch? bass})? _chordSymbolOf(
      XmlNode harmony) {
    final root =
        _harmonyPitch(harmony.child('root'), 'root-step', 'root-alter');
    if (root == null) return null;
    final kind = harmony.child('kind')?.text;
    final quality = ChordSymbolKind.values.firstWhere(
        (q) => q.musicXmlKind == kind,
        orElse: () => ChordSymbolKind.major);
    final bass =
        _harmonyPitch(harmony.child('bass'), 'bass-step', 'bass-alter');
    return (root: root, quality: quality, bass: bass);
  }

  /// A `<root>`/`<bass>` step+alter into a [Pitch] (octave is nominal — chord
  /// roots are pitch classes).
  static Pitch? _harmonyPitch(XmlNode? node, String stepTag, String alterTag) {
    if (node == null) return null;
    final step =
        Step.values.asNameMap()[node.childText(stepTag)?.toLowerCase()];
    if (step == null) return null;
    final alter =
        (int.tryParse(node.childText(alterTag) ?? '0') ?? 0).clamp(-2, 2);
    return Pitch(step, alter: alter);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
