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

import 'dart:math';

import '../internal/util.dart';
import '../layout/grand_staff.dart' show CrossStaffChord;
import '../layout/multi_part.dart';
import '../layout/staff_system.dart';
import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../musicxml/xml_reader.dart';
import '../theory/chord_name.dart';
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
          drumset: _drumsetFor(scoreNode, staves[staffIndex]),
          voltas: _mscxVoltasFor(staves, staffIndex))
      .read();
}

/// Parses a MuseScore `.mscx` document into a [StaffSystem] — one staff per
/// `<Staff>`-with-measures, top to bottom. Element ids are staff-prefixed so
/// they stay unique across parts. Throws [FormatException] if there are none.
///
/// A piano chord across two staves on one stem is MuseScore's `<Chord>`
/// carrying `<staffMove>` (the written staff's note drawn N staves away) —
/// see [_rewriteCrossStaffChords]. When that lands at the same onset as
/// another chord already on the target staff, the two become one
/// [StaffSystem.crossStaffChords] entry; otherwise the move is read as a
/// plain relocation (no link — nothing stayed home to join with a stem).
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
  final (rewritten, pendingLinks) = _rewriteCrossStaffChords(staves);
  final recordMaps = [
    for (var i = 0; i < rewritten.length; i++) <XmlNode, String>{}
  ];
  final readScores = <Score>[
    for (var i = 0; i < rewritten.length; i++)
      _StaffReader(
        rewritten[i],
        _staffMetadata(scoreNode, staves[i], base),
        drumset: _drumsetFor(scoreNode, staves[i]),
        idPrefix: 's${i}e',
        recordIds: recordMaps[i],
        voltas: _mscxVoltasFor(staves, i),
      ).read(),
  ];
  final crossStaffChords = <CrossStaffChord>[];
  for (final link in pendingLinks) {
    // Staves this format relocates between must be NEIGHBOURS in the final
    // list for the layout to understand the link (see
    // `StaffSystem.crossStaffChords`); it always is here, since the move is
    // only ever ±1 in the real corpus, but a stray ±2+ is dropped rather
    // than drawn wrong.
    if (link.lowerStaffIndex - link.upperStaffIndex != 1) continue;
    final upperId = recordMaps[link.upperStaffIndex][link.upperNode];
    final lowerId = recordMaps[link.lowerStaffIndex][link.lowerNode];
    if (upperId == null || lowerId == null) continue;
    crossStaffChords
        .add(CrossStaffChord(upperId, lowerId, stemsDown: link.stemsDown));
  }
  return StaffSystem(readScores, crossStaffChords: crossStaffChords);
}

/// A MuseScore `.mscx` document → a paginating [MultiPartScore], one part per
/// staff — so a multi-instrument file keeps EVERY part (unlike [scoreFromMscx],
/// which reads a single staff).
MultiPartScore multiPartScoreFromMscx(String mscx) =>
    MultiPartScore.fromStaffSystem(staffSystemFromMscx(mscx));

/// A cross-staff link found while [_rewriteCrossStaffChords] walks the
/// staves, named by the (relocated) source nodes its two halves end up as —
/// resolved to model ids once both staves have actually been read (see
/// `_StaffReader.recordIds`).
class _MscxPendingLink {
  final int upperStaffIndex;
  final int lowerStaffIndex;
  final XmlNode upperNode;
  final XmlNode lowerNode;
  final bool stemsDown;
  const _MscxPendingLink(this.upperStaffIndex, this.lowerStaffIndex,
      this.upperNode, this.lowerNode, this.stemsDown);
}

/// MuseScore writes a chord that is drawn away from the staff it is
/// structurally written in as a `<Chord>`/`<Rest>` carrying `<staffMove>` (the
/// number of staves to shift — see real corpus usage, e.g. a piano Lied's
/// right-hand figure dipping into the bass staff). Unlike MEI, the whole
/// `<Chord>` always moves together — MuseScore has no per-note `<staffMove>`
/// (confirmed against the `mscx-sample` corpus: thousands of chord-level
/// moves, zero split within one chord).
///
/// This relocates each such element to its target staff (a new `<voice>`,
/// padded by a `<Rest>` to the right onset) and replaces its old spot with a
/// same-duration `<Rest>` so the rest of that voice keeps its onsets. If the
/// move lands at the onset of an EXISTING chord in another voice of the
/// SAME (home) measure, the two are a genuine two-halves-on-one-stem chord —
/// recorded as a [_MscxPendingLink] — since nothing else in the format marks
/// that link explicitly; a move that lands on nothing (or on a rest) is read
/// as a plain relocation, which is what the overwhelming majority of real
/// `staffMove` usage (a melodic line crossing solo) is.
///
/// Limitations (left unmoved, as before): a chord/rest inside a `<Tuplet>`
/// (its real-time onset needs the tuplet ratio this ignores); a move whose
/// target staff doesn't exist for that measure.
(List<XmlNode>, List<_MscxPendingLink>) _rewriteCrossStaffChords(
    List<XmlNode> staves) {
  if (!staves.any(_hasAnyStaffMove)) return (staves, const []);
  final n = staves.length;
  final measureLists = [
    for (final s in staves) s.childrenNamed('Measure').toList()
  ];
  var measureCount = 0;
  for (final list in measureLists) {
    if (list.length > measureCount) measureCount = list.length;
  }
  final homeReplacements = <XmlNode, XmlNode>{};
  // Measure node -> extra `<voice>` children to append to it.
  final measureAugmentations = <XmlNode, List<XmlNode>>{};
  final links = <_MscxPendingLink>[];
  for (var mi = 0; mi < measureCount; mi++) {
    final measureAt = <int, XmlNode>{
      for (var s = 0; s < n; s++)
        if (mi < measureLists[s].length) s: measureLists[s][mi],
    };
    _rewriteCrossStaffMeasureSet(
        measureAt, homeReplacements, measureAugmentations, links);
  }
  if (homeReplacements.isEmpty && measureAugmentations.isEmpty) {
    return (staves, const []);
  }
  final finalReplacements = <XmlNode, XmlNode>{...homeReplacements};
  for (final MapEntry(key: measureNode, value: extraVoices)
      in measureAugmentations.entries) {
    final fixed = _applyMscxReplacements(measureNode, homeReplacements);
    final withVoice0 = fixed.childrenNamed('voice').isNotEmpty
        ? fixed
        : XmlNode(fixed.name, fixed.attributes,
            [XmlNode('voice', const {}, fixed.children, '')], fixed.text);
    finalReplacements[measureNode] = XmlNode(
        withVoice0.name,
        withVoice0.attributes,
        [...withVoice0.children, ...extraVoices],
        withVoice0.text);
  }
  final newStaves = [
    for (final staff in staves)
      _applyMscxReplacements(staff, finalReplacements),
  ];
  return (newStaves, links);
}

/// Whether any `<Chord>`/`<Rest>` anywhere under [staffNode] carries a
/// `<staffMove>` — a quick whole-staff check so the vast majority of files
/// (no cross-staff notation at all) skip the rewrite entirely.
bool _hasAnyStaffMove(XmlNode staffNode) {
  for (final node in staffNode.descendants) {
    if ((node.name == 'Chord' || node.name == 'Rest') &&
        node.child('staffMove') != null) {
      return true;
    }
  }
  return false;
}

/// [node] (and recursively its children) with every key of [replacements]
/// swapped for its value — identity-keyed, since a source [XmlNode] from one
/// parse is already unique by reference. A subtree with no replacement
/// anywhere inside it comes back as the SAME object (not a rebuilt copy) —
/// `staffSystemFromMscx` resolves a cross-staff link's "stayed home" half by
/// that identity surviving into the tree the matching `_StaffReader` reads.
XmlNode _applyMscxReplacements(
    XmlNode node, Map<XmlNode, XmlNode> replacements) {
  if (replacements[node] case final replacement?) return replacement;
  if (node.children.isEmpty) return node;
  var changed = false;
  final newChildren = <XmlNode>[];
  for (final c in node.children) {
    final r = _applyMscxReplacements(c, replacements);
    if (!identical(r, c)) changed = true;
    newChildren.add(r);
  }
  return changed
      ? XmlNode(node.name, node.attributes, newChildren, node.text)
      : node;
}

/// One `<Chord>`/`<Rest>` event in a voice's flat child list, with its
/// nominal onset (duration summed over earlier siblings in the SAME voice,
/// ignoring tuplet ratio — see [_rewriteCrossStaffChords]'s limitations).
class _MscxTimedNote {
  final XmlNode node;
  final int voiceIndex;
  final Fraction onset;
  final bool insideTuplet;
  const _MscxTimedNote(
      this.node, this.voiceIndex, this.onset, this.insideTuplet);
}

/// Every non-grace `<Chord>`/`<Rest>` in [measureNode]'s voices (an explicit
/// `<voice>` per voice, or the bare measure itself as the sole voice), in
/// document order per voice, with its nominal onset.
List<_MscxTimedNote> _mscxTimedNotesOf(XmlNode measureNode) {
  final voiceNodes = measureNode.childrenNamed('voice').toList();
  final voices = voiceNodes.isEmpty ? [measureNode] : voiceNodes;
  final out = <_MscxTimedNote>[];
  for (var v = 0; v < voices.length; v++) {
    var cursor = Fraction.zero;
    var insideTuplet = false;
    for (final node in voices[v].children) {
      switch (node.name) {
        case 'Tuplet':
          insideTuplet = true;
        case 'endTuplet':
          insideTuplet = false;
        case 'Chord':
          if (_isMscxGrace(node)) continue;
          out.add(_MscxTimedNote(node, v, cursor, insideTuplet));
          cursor += _mscxNominalDuration(node) ?? Fraction.zero;
        case 'Rest':
          out.add(_MscxTimedNote(node, v, cursor, insideTuplet));
          cursor += _mscxNominalDuration(node) ?? Fraction.zero;
      }
    }
  }
  return out;
}

/// Whether `<Chord>` [node] is a grace note (`<acciaccatura/>`/
/// `<appoggiatura/>`/`<grace…>`) — no duration of its own, so it never counts
/// toward a voice's running onset.
bool _isMscxGrace(XmlNode node) {
  for (final child in node.children) {
    final n = child.name;
    if (n == 'acciaccatura' || n == 'appoggiatura' || n.startsWith('grace')) {
      return true;
    }
  }
  return false;
}

/// [node]'s `<durationType>`/`<dots>` as a whole-note [Fraction], or null for
/// a whole-measure rest (`durationType>measure`, too imprecise to place a
/// cross-staff move against — treated as zero duration by callers).
Fraction? _mscxNominalDuration(XmlNode node) {
  final type = node.childText('durationType');
  if (type == null || type == 'measure') return null;
  final base = _durationBases[type];
  if (base == null) return null;
  final dots = (int.tryParse(node.childText('dots') ?? '0') ?? 0).clamp(0, 2);
  return NoteDuration(base, dots: dots).toFraction();
}

/// Undotted `durationType`s in descending length, for padding a target voice
/// up to a cross-staff insertion's onset.
const _mscxSpaceBases = [
  DurationBase.long,
  DurationBase.breve,
  DurationBase.whole,
  DurationBase.half,
  DurationBase.quarter,
  DurationBase.eighth,
  DurationBase.sixteenth,
  DurationBase.thirtySecond,
  DurationBase.sixtyFourth,
];

/// The inverse of [_durationBases] for the bases [_mscxSpaceBases] covers.
const _mscxDurationNames = {
  DurationBase.long: 'long',
  DurationBase.breve: 'breve',
  DurationBase.whole: 'whole',
  DurationBase.half: 'half',
  DurationBase.quarter: 'quarter',
  DurationBase.eighth: 'eighth',
  DurationBase.sixteenth: '16th',
  DurationBase.thirtySecond: '32nd',
  DurationBase.sixtyFourth: '64th',
};

/// `<Rest>` elements (invisible is not needed — MuseScore hides a filler rest
/// visually by leaving it where no other voice shows, same as any other
/// voice's rest) summing to [gap] — greedy largest-duration-first.
List<XmlNode> _mscxSpaceFor(Fraction gap) {
  var left = gap;
  final out = <XmlNode>[];
  final floor = Fraction(1, 128);
  while (left >= floor) {
    NoteDuration? pick;
    for (final base in _mscxSpaceBases) {
      for (final dots in const [1, 0]) {
        final d = NoteDuration(base, dots: dots);
        if (d.toFraction() <= left) {
          pick = d;
          break;
        }
      }
      if (pick != null) break;
    }
    if (pick == null) break;
    out.add(_mscxRest(pick));
    left -= pick.toFraction();
  }
  return out;
}

XmlNode _mscxRest(NoteDuration duration) => XmlNode(
    'Rest',
    const {},
    [
      XmlNode('durationType', const {}, const [],
          _mscxDurationNames[duration.base]!),
      if (duration.dots > 0)
        XmlNode('dots', const {}, const [], '${duration.dots}'),
    ],
    '');

/// A same-duration `<Rest>` standing in for a `<Chord>`/`<Rest>` that moved
/// off its voice entirely — keeps every later sibling in that voice at its
/// original onset.
XmlNode _mscxRestLike(XmlNode original) {
  final type = original.childText('durationType') ?? 'quarter';
  final dots = original.childText('dots');
  return XmlNode(
      'Rest',
      const {},
      [
        XmlNode('durationType', const {}, const [], type),
        if (dots != null) XmlNode('dots', const {}, const [], dots),
      ],
      '');
}

/// Splits every cross-staff move found across one measure INDEX's nodes
/// ([measureAt], staff index → that staff's measure at this index) — see
/// [_rewriteCrossStaffChords].
void _rewriteCrossStaffMeasureSet(
  Map<int, XmlNode> measureAt,
  Map<XmlNode, XmlNode> homeReplacements,
  Map<XmlNode, List<XmlNode>> measureAugmentations,
  List<_MscxPendingLink> links,
) {
  // Per-target-staff, accumulated (onset, duration, node) insertions, folded
  // into one new `<voice>` once every candidate in this measure has been
  // found (several home staves can cross into the same target staff).
  final insertionsByStaff = <int, List<(Fraction, Fraction, XmlNode)>>{};

  for (final MapEntry(key: homeIdx, value: measureNode) in measureAt.entries) {
    final timed = _mscxTimedNotesOf(measureNode);
    for (final t in timed) {
      if (t.insideTuplet) continue;
      final moveText = t.node.childText('staffMove');
      final move = moveText == null ? null : int.tryParse(moveText.trim());
      if (move == null || move == 0) continue;
      final targetIdx = homeIdx + move;
      if (!measureAt.containsKey(targetIdx)) continue;
      final duration = _mscxNominalDuration(t.node) ?? Fraction.zero;

      // A genuine two-halves chord: another voice of the SAME (home) measure
      // already sounds a real chord at this exact onset.
      XmlNode? paired;
      for (final other in timed) {
        if (other.voiceIndex == t.voiceIndex || other.onset != t.onset) {
          continue;
        }
        if (other.node.name == 'Chord') {
          paired = other.node;
          break;
        }
      }

      homeReplacements[t.node] = _mscxRestLike(t.node);
      final moved = XmlNode(
          t.node.name,
          t.node.attributes,
          [
            for (final c in t.node.children)
              if (c.name != 'staffMove') c
          ],
          t.node.text);
      (insertionsByStaff[targetIdx] ??= []).add((t.onset, duration, moved));

      if (paired != null) {
        final stemsDown = switch (t.node.childText('StemDirection')) {
          'up' => false,
          _ => true,
        };
        final upperIdx = homeIdx < targetIdx ? homeIdx : targetIdx;
        final lowerIdx = homeIdx < targetIdx ? targetIdx : homeIdx;
        final upperNode = homeIdx < targetIdx ? paired : moved;
        final lowerNode = homeIdx < targetIdx ? moved : paired;
        links.add(_MscxPendingLink(
            upperIdx, lowerIdx, upperNode, lowerNode, stemsDown));
      }
    }
  }

  for (final MapEntry(key: targetIdx, value: events)
      in insertionsByStaff.entries) {
    events.sort((a, b) => a.$1.compareTo(b.$1));
    final content = <XmlNode>[];
    var cursor = Fraction.zero;
    for (final (onset, duration, node) in events) {
      final gap = onset - cursor;
      if (gap > Fraction.zero) content.addAll(_mscxSpaceFor(gap));
      content.add(node);
      cursor = onset + duration;
    }
    final newVoice = XmlNode('voice', const {}, content, '');
    (measureAugmentations[measureAt[targetIdx]!] ??= []).add(newVoice);
  }
}

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
  ({
    Pitch root,
    ChordSymbolKind kind,
    Pitch? bass,
    List<ChordDegree> degrees,
  })? _harmonyOf(XmlNode node) {
    final rootTpc = int.tryParse(node.childText('root') ?? '');
    if (rootTpc == null) return null;
    final root = _pitchFromTpc(rootTpc);
    final baseTpc = int.tryParse(node.childText('base') ?? '');
    final bass = baseTpc == null ? null : _pitchFromTpc(baseTpc);

    final name = node.childText('name');
    if (name != null && name.trim().isNotEmpty) {
      // The name is the suffix as typed (`maj9`, `7(b9)`, `sus4(add9)`), so
      // the chord-name parser reads it, degrees and all; the older lenient
      // table catches what it does not.
      if (name.trim() == 'N.C.') {
        return (
          root: root,
          kind: ChordSymbolKind.none,
          bass: bass,
          degrees: const <ChordDegree>[],
        );
      }
      if (parseChordSuffix(name.trim()) case final spelled?) {
        return (
          root: root,
          kind: spelled.kind,
          bass: bass,
          degrees: spelled.degrees,
        );
      }
      return (
        root: root,
        kind: _kindFromName(name.trim()),
        bass: bass,
        degrees: const <ChordDegree>[],
      );
    }
    // ⚠️ MuseScore writes NEITHER `<name>` nor `<extension>` for a plain major
    // triad — the commonest chord there is. Treating "no quality stated" as
    // unknown dropped every one of them, from our own output and from real
    // MuseScore files alike. "Absent" and "present but unrecognised" are
    // different answers: only the second is a quality we cannot establish.
    final extText = node.childText('extension');
    if (extText == null || extText.trim().isEmpty) {
      return (
        root: root,
        kind: ChordSymbolKind.major,
        bass: bass,
        degrees: const <ChordDegree>[]
      );
    }
    final kind = _kindFromExtension(int.tryParse(extText));
    if (kind == null) return null; // unknown quality — say nothing
    return (root: root, kind: kind, bass: bass, degrees: const <ChordDegree>[]);
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

  _StaffReader(this.staff, this.metadata,
      {this.drumset,
      this.idPrefix = 'e',
      this.recordIds,
      Map<int, _MscxVolta>? voltas})
      : voltas = voltas ?? _mscxVoltaSpans(staff);

  /// The endings over this staff's bars, by bar index (see
  /// [_mscxVoltasFor]).
  final Map<int, _MscxVolta> voltas;

  /// Element-id prefix, made staff-specific when reading a multi-staff document
  /// so ids stay unique across parts.
  final String idPrefix;

  /// When given, every `<Chord>`/`<Rest>` source node is recorded against the
  /// model id it was given — identity-keyed, since a source node from one
  /// parse is already unique by reference. Lets `staffSystemFromMscx` resolve
  /// a cross-staff chord's two halves (found and relocated BEFORE either
  /// staff is read — see `_rewriteCrossStaffChords`) back to model ids once
  /// both staves have actually been read.
  final Map<XmlNode, String>? recordIds;

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
  final _hairpinStartDeltas = <Fraction?>[];
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
      // Paired by DECLARED DISTANCE, like slurs — a note may open a degenerate
      // hairpin and a real one, and positional pairing then crosses them.
      hairpins: [
        for (final (a, b, i) in _pairSpans(
            _hairpinStartIds, _hairpinStartDeltas, _hairpinEndIds))
          Hairpin(
              a,
              b,
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

  /// Element order and onset, for pairing spans.
  ///
  /// ⚠️ An onset is NOT unique: every staff and voice restarts at the same
  /// measure onset, so a four-voice score has four elements at each one. Any
  /// pairing that uses onsets must use document ORDER as well.
  (Map<String, Fraction>, Map<String, int>) _onsetAndOrder() {
    final onset = <String, Fraction>{};
    final order = <String, int>{};
    var measureStart = Fraction.zero;
    var seq = 0;
    for (final m in _measures) {
      var acc = measureStart;
      for (final e in m.elements) {
        if (e.id != null) {
          onset[e.id!] = acc;
          order[e.id!] = seq++;
        }
        acc = acc + e.duration.toFraction();
      }
      final measureEnd = acc;
      for (final voice in [m.voice2, m.voice3, m.voice4]) {
        var vacc = measureStart;
        for (final e in voice) {
          if (e.id != null) {
            onset[e.id!] = vacc;
            order[e.id!] = seq++;
          }
          vacc = vacc + e.duration.toFraction();
        }
      }
      measureStart = measureEnd;
    }
    return (onset, order);
  }

  /// Pairs span starts with ends by the DISTANCE each start declares.
  ///
  /// MuseScore STATES where a spanner ends. Pairing starts to ends by document
  /// POSITION instead threw that away, which crosses a nested pair
  /// (`e0-e3` inside `e1-e2` became `e0-e2` and `e1-e3`), collapses a chain
  /// sharing a boundary note, and — once onsets collide across voices — can
  /// even return a span running BACKWARDS.
  ///
  /// Falls back to positional pairing for any start whose declared end is not
  /// found: third-party files use `<measures>` too, and an unmatched start is
  /// better placed approximately than dropped.
  List<(String, String, int)> _pairSpans(
      List<String> starts, List<Fraction?> deltas, List<String> ends) {
    final (onset, order) = _onsetAndOrder();
    final remaining = List<String?>.from(ends);
    final out = <(String, String, int)>[];
    final unresolved = <int>[];
    for (var i = 0; i < starts.length; i++) {
      final start = starts[i];
      final delta = i < deltas.length ? deltas[i] : null;
      final from = onset[start];
      final fromSeq = order[start];
      var matched = false;
      if (delta != null && from != null && fromSeq != null) {
        final target = from + delta;
        var best = -1;
        for (var j = 0; j < remaining.length; j++) {
          final end = remaining[j];
          if (end == null || onset[end] != target) continue;
          final endSeq = order[end];
          if (endSeq == null || endSeq < fromSeq) continue;
          if (best < 0 || endSeq < order[remaining[best]]!) best = j;
        }
        if (best >= 0) {
          out.add((start, remaining[best]!, i));
          remaining[best] = null;
          matched = true;
        }
      }
      if (!matched) unresolved.add(i);
    }
    final leftovers = [
      for (final e in remaining)
        if (e != null) e
    ];
    for (var k = 0; k < unresolved.length && k < leftovers.length; k++) {
      out.add((starts[unresolved[k]], leftovers[k], unresolved[k]));
    }
    return out;
  }

  List<Slur> _pairSlurs() => [
        for (final (a, b, _)
            in _pairSpans(_slurStartIds, _slurStartDeltas, _slurEndIds))
          Slur(a, b)
      ];

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
            _hairpinStartDeltas.add(_locationDelta(s.child('next')));
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
      // Each with how far a `<location>` had moved it ahead of the voice.
      final pendingHarmonies = <({
        Pitch root,
        ChordSymbolKind kind,
        Pitch? bass,
        List<ChordDegree> degrees,
        Fraction shift,
      })>[];
      // The `<location>` moves since the last chord or rest: MuseScore places
      // a chord symbol between two notes by stepping forward, writing the
      // `<Harmony>`, and stepping back.
      var locationShift = Fraction.zero;
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
      // Every <StaffText> before the next chord — a chord may carry several.
      final pendingStaffTexts = <(String, AnnotationPlacement, bool, bool)>[];

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
            } else {
              // ⚠️ A RESTATED meter is recorded, not suppressed. A file that writes its
              // meter again mid-piece is saying something, and dropping it broke the
              // round trip for ~16% of kern files — the single largest remaining cause
              // in `krn -> lilypond`. The old fear was that redundant exports would draw
              // a meter at every bar; they cannot, because `layout_engine` guards
              // `timeChange != _time` before DRAWING one. Measured first: only 2 of 681
              // MusicXML files and 0 of 25 kern files restate in >50% of bars.
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
            if (chord.id != null) recordIds?[node] = chord.id!;
            // Attach any harmonies waiting for a note. Several can precede one
            // chord (MuseScore gives each its own <tick>), so they are spread
            // over the following notes rather than collapsed — dropping a chord
            // leaves a hole in the chart, which is worse than a small shift.
            // A harmony moved off this chord by a `<location>` stays on it,
            // at its offset; of those on the chord itself, the first.
            if (chord.id != null && pendingHarmonies.isNotEmpty) {
              final here = [
                for (final h in pendingHarmonies)
                  if (h.shift != locationShift) h,
              ];
              final on = pendingHarmonies
                  .where((h) => h.shift == locationShift)
                  .firstOrNull;
              for (final h in [if (on != null) on, ...here]) {
                _chordSymbols.add(
                  ChordSymbol(
                    chord.id!,
                    h.root,
                    h.kind,
                    bass: h.bass,
                    offset: h.shift - locationShift,
                    degrees: h.degrees,
                  ),
                );
                pendingHarmonies.remove(h);
              }
            }
            locationShift = Fraction.zero;
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
            if (pendingStaffTexts.isNotEmpty && chord.id != null) {
              for (final (text, placement, italic, bold) in pendingStaffTexts) {
                _annotations.add(Annotation(chord.id!, text,
                    placement: placement, italic: italic, bold: bold));
              }
              pendingStaffTexts.clear();
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
            if (h != null) {
              pendingHarmonies.add((
                root: h.root,
                kind: h.kind,
                bass: h.bass,
                degrees: h.degrees,
                shift: locationShift,
              ));
            }
          case 'location':
            // `<location><fractions>1/8</fractions></location>` steps the
            // voice's position; only a chord symbol's place reads it.
            final f = RegExp(r'^\s*(-?\d+)/(\d+)\s*$')
                .firstMatch(node.childText('fractions') ?? '');
            if (f != null && int.parse(f[2]!) != 0) {
              locationShift += Fraction(int.parse(f[1]!), int.parse(f[2]!));
            }
          case 'StaffText':
            // Precedes the chord it belongs to, like `<Harmony>` and
            // `<Dynamic>`, so it is held until that chord arrives.
            // Its text may carry `<i>`/`<b>` markup; the Expression style
            // (dolce, espress.) is italic in MuseScore.
            final textNode = node.child('text');
            final txt = textNode?.deepText.trim();
            if (textNode != null && txt != null && txt.isNotEmpty) {
              final marks = textNode.descendants.map((n) => n.name).toSet();
              pendingStaffTexts.add((
                txt,
                node.childText('placement') == 'below'
                    ? AnnotationPlacement.below
                    : AnnotationPlacement.above,
                marks.contains('i') || node.childText('style') == 'Expression',
                marks.contains('b'),
              ));
            }
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
            final rest = RestElement(_durationOf(node),
                id: _newId(), hidden: node.childText('visible') == '0');
            elements.add(rest);
            locationShift = Fraction.zero;
            if (rest.id != null) recordIds?[node] = rest.id!;
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
    // A `<Spanner type="Volta">` covering this bar, else the one-bar
    // Measure-level `<Volta>` this package's writer uses.
    final measureVolta = measureNode.child('Volta');
    final ending = voltas[_measures.length] ??
        (measureVolta == null
            ? null
            : _mscxVoltaOf(measureVolta, closedByDefault: true));
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
      volta: ending?.volta,
      voltaNumbers: ending?.numbers ?? const [],
      voltaText: ending?.text,
      voltaOpenEnd: ending?.openEnd ?? false,
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
      stemsDown: switch (chord.childText('StemDirection')) {
        'down' => true,
        'up' => false,
        _ => null,
      },
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

/// One ending as a bar carries it: its first pass, every pass when several,
/// its printed text, and whether its bracket is left open at this bar.
typedef _MscxVolta = ({
  int volta,
  List<int> numbers,
  String? text,
  bool openEnd,
});

/// A `<Volta>` element's ending: `<endings>` lists the passes ("1, 2"),
/// `<text>` (or 3.x `<beginText>`) the label, and an `<endHookType>` of 0
/// leaves the end open. A spanner's omitted hook type is MuseScore's default,
/// 0; [closedByDefault] reads it as closed instead (this package's one-bar
/// Measure-level `<Volta>`, which states only an open end).
_MscxVolta? _mscxVoltaOf(XmlNode volta, {bool closedByDefault = false}) {
  final numbers = [
    for (final m in RegExp(r'\d+').allMatches(volta.childText('endings') ?? ''))
      if (int.parse(m[0]!) case final n when n >= 1) n,
  ];
  if (numbers.isEmpty) return null;
  final hook =
      volta.childText('endHookType')?.trim() ?? (closedByDefault ? '1' : '0');
  return (
    volta: numbers.first,
    numbers: numbers.length > 1 ? numbers : const <int>[],
    text: voltaTextOf(
        volta.childText('text') ?? volta.childText('beginText'), numbers),
    openEnd: hook == '0',
  );
}

/// The endings over [staff]'s bars, by bar index, from MuseScore's
/// `<Spanner type="Volta">`: the `<Volta>` sits in the bar the ending opens,
/// and `<next><location><measures>N` says it covers N bars. Spanners may hang
/// off the `<Measure>` (2.x) or one of its `<voice>`s (3.x+).
Map<int, _MscxVolta> _mscxVoltaSpans(XmlNode staff) {
  final measures = staff.childrenNamed('Measure').toList();
  final out = <int, _MscxVolta>{};
  for (var i = 0; i < measures.length; i++) {
    final spanners = [
      ...measures[i].childrenNamed('Spanner'),
      for (final voice in measures[i].childrenNamed('voice'))
        ...voice.childrenNamed('Spanner'),
    ];
    for (final spanner in spanners) {
      if (spanner.attributes['type'] != 'Volta') continue;
      final next = spanner.child('next');
      final volta = spanner.child('Volta');
      if (next == null || volta == null) continue;
      final ending = _mscxVoltaOf(volta);
      if (ending == null) continue;
      final length = int.tryParse(
              next.child('location')?.childText('measures')?.trim() ?? '') ??
          1;
      final last = min(measures.length - 1, i + max(1, length) - 1);
      for (var k = i; k <= last; k++) {
        out[k] = (
          volta: ending.volta,
          numbers: ending.numbers,
          text: ending.text,
          openEnd: k == last && ending.openEnd,
        );
      }
    }
  }
  return out;
}

/// The endings for staff [index] of [staves]. MuseScore keeps them, like
/// other system-wide marks, on the top staff only; every part takes them
/// from there so each plays (and draws) the same endings.
Map<int, _MscxVolta> _mscxVoltasFor(List<XmlNode> staves, int index) {
  final top = _mscxVoltaSpans(staves.first);
  return top.isNotEmpty || index == 0 ? top : _mscxVoltaSpans(staves[index]);
}
