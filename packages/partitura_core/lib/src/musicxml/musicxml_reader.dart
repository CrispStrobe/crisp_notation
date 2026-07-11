/// MusicXML import (subset): score-partwise → [Score] / [GrandStaff].
///
/// Covers the v0.3/v0.4 feature set: pitches/chords/rests, durations
/// (breve…64th, dots), accidentals, ties, slurs, tuplets, articulations,
/// grace notes, dynamics, hairpin wedges, lyrics, chord symbols
/// (`<harmony>`), key/time/clef with mid-score changes, repeat barlines
/// and voltas, and two voices per staff. Unsupported markup is ignored.
library;

import '../layout/grand_staff.dart';
import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/time_signature.dart';
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
  return _PartReader(parts[partIndex], staff: 1).read();
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

  _PartReader(this.part, {required this.staff, this.idOffset = 0});

  int _nextId = 0;
  int _divisions = 1;

  Clef? _clef; // running clef (mid-score changes update it)
  Clef? _leadingClef;
  KeySignature? _key;
  TimeSignature? _time;
  bool _leadingSet = false;

  final _measures = <Measure>[];
  final _slurs = <Slur>[];
  final _dynamics = <DynamicMarking>[];
  final _hairpins = <Hairpin>[];
  final _lyrics = <Lyric>[];
  final _annotations = <Annotation>[];

  // Open spans keyed by MusicXML "number" attribute.
  final _openSlurs = <String, String>{};
  final _openWedges = <String, (String, HairpinType)>{};

  Score read() {
    for (final measureNode in part.childrenNamed('measure')) {
      _readMeasure(measureNode);
    }
    if (_openSlurs.isNotEmpty) {
      throw const FormatException('Unclosed <slur> in document');
    }
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
    );
  }

  String _newId() => 'e${idOffset + _nextId++}';

  void _readMeasure(XmlNode measureNode) {
    final elements = <MusicElement>[];
    final voice2 = <MusicElement>[];
    final tuplets = <TupletSpan>[];
    Clef? clefChange;
    KeySignature? keyChange;
    TimeSignature? timeChange;
    var startRepeat = false;
    var endRepeat = false;
    int? volta;

    String? firstVoice; // this measure's voice-1 label
    var pendingGraces = <Pitch>[];
    String? pendingDynamic;
    String? pendingHarmony;
    int? openTupletStart;
    (int, int)? openTupletRatio;

    for (final node in measureNode.children) {
      switch (node.name) {
        case 'attributes':
          final divisions = int.tryParse(node.childText('divisions') ?? '');
          if (divisions != null) _divisions = divisions;
          final fifths =
              int.tryParse(node.child('key')?.childText('fifths') ?? '');
          if (fifths != null) {
            final key = KeySignature(fifths);
            if (!_leadingSet) {
              _key = key;
            } else if (key != (_key ?? const KeySignature(0))) {
              keyChange = key;
            }
          }
          final time = node.child('time');
          if (time != null) {
            final signature = TimeSignature(
              int.parse(time.childText('beats')!),
              int.parse(time.childText('beat-type')!),
            );
            if (!_leadingSet) {
              _time = signature;
            } else if (signature != _time) {
              timeChange = signature;
            }
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
        case 'direction':
          if (!_isForStaff(node)) break;
          final dynamicsNode = node.child('direction-type')?.child('dynamics');
          if (dynamicsNode != null && dynamicsNode.children.isNotEmpty) {
            pendingDynamic = dynamicsNode.children.first.name;
          }
          final wedge = node.child('direction-type')?.child('wedge');
          if (wedge != null) _handleWedge(wedge, elements, voice2);
        case 'harmony':
          pendingHarmony = _harmonyText(node);
        case 'note':
          if (!_isForStaff(node)) break;
          if (node.child('grace') != null) {
            final pitch = _pitchOf(node.child('pitch'));
            if (pitch != null) pendingGraces.add(pitch);
            break;
          }
          final voiceLabel = node.childText('voice') ?? '1';
          firstVoice ??= voiceLabel;
          final isVoice1 = voiceLabel == firstVoice;
          final target = isVoice1 ? elements : voice2;

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
                  id: last.id,
                );
              }
              break;
            }
          }

          final id = _newId();
          final duration = _durationOf(node);
          if (node.child('rest') != null) {
            target.add(RestElement(duration, id: id));
          } else {
            final pitch = _pitchOf(node.child('pitch'));
            if (pitch == null) {
              throw const FormatException('<note> without <pitch> or <rest>');
            }
            target.add(NoteElement(
              pitches: [pitch],
              duration: duration,
              showAccidental: node.child('accidental') != null ? true : null,
              tieToNext: _startsTie(node),
              articulations: _articulationsOf(node),
              graceNotes: pendingGraces.isEmpty ? const [] : pendingGraces,
              id: id,
            ));
            pendingGraces = <Pitch>[];
            if (pendingDynamic != null) {
              final level = DynamicLevel.values.asNameMap()[pendingDynamic];
              if (level != null) _dynamics.add(DynamicMarking(id, level));
              pendingDynamic = null;
            }
            if (pendingHarmony != null) {
              _annotations.add(Annotation(id, pendingHarmony));
              pendingHarmony = null;
            }
            _readSpans(node, id);
            _readLyric(node, id);
          }

          // Tuplets (voice 1 only, mirroring the DSL).
          if (isVoice1) {
            final tuplet = _notations(node)
                .expand((n) => n.childrenNamed('tuplet'))
                .firstOrNull;
            final modification = node.child('time-modification');
            if (tuplet?.attributes['type'] == 'start' && modification != null) {
              openTupletStart = target.length - 1;
              openTupletRatio = (
                int.parse(modification.childText('actual-notes')!),
                int.parse(modification.childText('normal-notes')!),
              );
            }
            if (tuplet?.attributes['type'] == 'stop' &&
                openTupletStart != null) {
              tuplets.add(TupletSpan(
                openTupletStart,
                target.length - 1,
                actual: openTupletRatio!.$1,
                normal: openTupletRatio.$2,
              ));
              openTupletStart = null;
              openTupletRatio = null;
            }
          }
        default:
          break; // backup/forward/print/sound…: ignored
      }
    }

    _leadingSet = true;
    _measures.add(Measure(
      elements,
      voice2: voice2,
      tuplets: tuplets,
      clefChange: clefChange,
      keyChange: keyChange,
      timeChange: timeChange,
      startRepeat: startRepeat,
      endRepeat: endRepeat,
      volta: volta,
    ));
  }

  bool _isForStaff(XmlNode node) =>
      (int.tryParse(node.childText('staff') ?? '1') ?? 1) == staff;

  static Clef _clefOf(XmlNode clefNode) {
    final sign = clefNode.childText('sign');
    final line = int.tryParse(clefNode.childText('line') ?? '');
    return switch ((sign, line)) {
      ('G', _) => Clef.treble,
      ('F', _) => Clef.bass,
      ('C', 4) => Clef.tenor,
      ('C', _) => Clef.alto,
      _ => throw FormatException('Unsupported clef: $sign$line'),
    };
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
    if (type != null) {
      final base = types[type];
      if (base == null) {
        throw FormatException('Unsupported note type: "$type"');
      }
      final dots = note.childrenNamed('dot').length.clamp(0, 2);
      return NoteDuration(base, dots: dots);
    }
    // No <type> (e.g. whole-measure rests): derive from duration/divisions.
    final duration = int.tryParse(note.childText('duration') ?? '');
    if (duration == null) {
      throw const FormatException('<note> without <type> or <duration>');
    }
    final quarters = duration / _divisions;
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
    }
    throw FormatException('Cannot map duration $duration/$_divisions');
  }

  static bool _startsTie(XmlNode note) =>
      note.childrenNamed('tie').any((tie) => tie.attributes['type'] == 'start');

  Iterable<XmlNode> _notations(XmlNode note) => note.childrenNamed('notations');

  Set<Articulation> _articulationsOf(XmlNode note) {
    final result = <Articulation>{};
    for (final notations in _notations(note)) {
      if (notations.child('fermata') != null) {
        result.add(Articulation.fermata);
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

  void _readLyric(XmlNode note, String id) {
    final lyric = note.child('lyric');
    if (lyric == null) return;
    final text = lyric.childText('text');
    if (text == null || text.isEmpty) return;
    final syllabic = lyric.childText('syllabic');
    _lyrics.add(Lyric(
      id,
      text,
      hyphenToNext: syllabic == 'begin' || syllabic == 'middle',
      extender: lyric.child('extend') != null,
    ));
  }

  static String? _harmonyText(XmlNode harmony) {
    final root = harmony.child('root');
    if (root == null) return null;
    final step = root.childText('root-step') ?? '';
    final alter = int.tryParse(root.childText('root-alter') ?? '0') ?? 0;
    final accidental = switch (alter) {
      1 => '♯',
      -1 => '♭',
      _ => '',
    };
    final kind = harmony.child('kind');
    final kindText = kind?.attributes['text'] ??
        switch (kind?.text) {
          'minor' => 'm',
          'diminished' => 'dim',
          'augmented' => 'aug',
          'dominant' => '7',
          'major-seventh' => 'maj7',
          'minor-seventh' => 'm7',
          _ => '',
        };
    return '$step$accidental$kindText';
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
