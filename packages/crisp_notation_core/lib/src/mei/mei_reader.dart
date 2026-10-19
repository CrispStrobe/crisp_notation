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

import '../internal/util.dart';
import '../internal/volta.dart';
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

const _durBases = {
  'maxima': DurationBase.maxima,
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
    // The header's incipits (`meiHead > … > incip > score`) quote the opening
    // bars; read as the music, a whole hymn came back as its first phrase.
    if (n.name == 'meiHead') return;
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
/// A piano chord written across two staves on one stem is MEI's `<chord>`
/// (or a lone `<note>`) carrying `@staff` on the notes/note that actually
/// sound on the OTHER staff — see [_rewriteCrossStaffChords]. Those become
/// [StaffSystem.crossStaffChords], by element id, between adjacent staves.
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
  // Cross-staff chords only make sense with a real staff to cross TO, so the
  // rewrite only runs for an actually multi-staff document — a single-staff
  // one that happens to carry a stray `@staff` is read unchanged.
  final (rewritten, pendingLinks) = count >= 2
      ? _rewriteCrossStaffChords(score)
      : (score, const <_PendingCrossLink>[]);
  final readers = <_MeiReader>[
    for (var i = 0; i < count; i++)
      _MeiReader(
        rewritten,
        meta,
        staffN: staffDefs.isEmpty
            ? 1
            : int.tryParse(staffDefs[i].attributes['n'] ?? '') ?? (i + 1),
        idOffset: i * 1000,
      ),
  ];
  final staves = <Score>[for (final r in readers) r.read()];
  final readerOfStaffN = <int, int>{
    for (var i = 0; i < readers.length; i++) readers[i].staffN: i,
  };
  final crossStaffChords = <CrossStaffChord>[];
  for (final link in pendingLinks) {
    final ui = readerOfStaffN[link.upperStaffN];
    final li = readerOfStaffN[link.lowerStaffN];
    // The layout only understands a cross-staff chord between NEIGHBOURING
    // staves (see `StaffSystem.crossStaffChords`); a link to a staff that
    // isn't the very next one is dropped rather than drawn wrong.
    if (ui == null || li == null || li - ui != 1) continue;
    final upperId = readers[ui]._xmlIdToId[link.upperXmlId] ?? link.upperXmlId;
    final lowerId = readers[li]._xmlIdToId[link.lowerXmlId] ?? link.lowerXmlId;
    crossStaffChords
        .add(CrossStaffChord(upperId, lowerId, stemsDown: link.stemsDown));
  }
  return StaffSystem(staves,
      brackets: _staffGrpBrackets(scoreDef, staffDefs),
      crossStaffChords: crossStaffChords);
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

/// A cross-staff link discovered while [_rewriteCrossStaffChords] splits a
/// measure, named by the xml:id its two halves end up carrying (resolved to
/// model ids once both staves have been read).
class _PendingCrossLink {
  final int upperStaffN;
  final int lowerStaffN;
  final String upperXmlId;
  final String lowerXmlId;
  final bool stemsDown;
  const _PendingCrossLink(this.upperStaffN, this.lowerStaffN, this.upperXmlId,
      this.lowerXmlId, this.stemsDown);
}

/// MEI writes a chord across two staves on one stem as a `<chord>` (or a lone
/// `<note>`) whose note(s) carry `@staff` pointing at the OTHER staff — see the
/// real encodings in the MEI sample corpus (e.g. `attribute_copyof.mei`'s
/// `<chord>` in staff 2 with three of its four notes `@staff="3"`, and
/// `Brahms_WieMelodienZiehtEsMir.mei`'s chords written whole on one staff's
/// layer but entirely `@staff`-flagged onto its neighbour).
///
/// This rewrites [score] so each such chord/note splits into: the notes that
/// stay (if any — becoming the HOME half, unchanged in place) and the notes
/// that cross (a synthetic `<chord>`/`<note>`, appended as a new `<layer>` on
/// the TARGET staff, preceded by a `<space>` that pads it to the right onset).
/// A chord with notes left on NEITHER staff just moves wholesale (no link —
/// there is nothing left on the home staff to join with a stem); the returned
/// [_PendingCrossLink]s cover only the genuine two-halves-on-one-stem case.
///
/// Limitations (left unsplit, matching the pre-existing behaviour of reading
/// the chord whole on its home staff): a chord/note inside a `<tuplet>`
/// (ratio-aware onset tracking would be needed to place its target-staff
/// half correctly); `<chord copyof="#…">` (no notes of its own to inspect);
/// more than one foreign staff on the same chord.
(XmlNode, List<_PendingCrossLink>) _rewriteCrossStaffChords(XmlNode score) {
  if (!_hasAnyStaffAttr(score)) return (score, const []);
  final links = <_PendingCrossLink>[];
  XmlNode rebuild(XmlNode node) {
    if (node.name == 'measure') return _rewriteCrossStaffMeasure(node, links);
    if (node.children.isEmpty) return node;
    return XmlNode(node.name, node.attributes,
        [for (final c in node.children) rebuild(c)], node.text);
  }

  return (rebuild(score), links);
}

/// Whether any `<note>` (bare, or inside a `<chord>`) anywhere under [node]
/// carries `@staff` — a quick whole-document check so the vast majority of
/// files (no cross-staff notation at all) skip the rewrite entirely.
bool _hasAnyStaffAttr(XmlNode node) {
  if (node.name == 'note' && node.attributes.containsKey('staff')) {
    return true;
  }
  for (final child in node.children) {
    if (_hasAnyStaffAttr(child)) return true;
  }
  return false;
}

/// One note/chord event found while walking a `<layer>`, with its nominal
/// onset (duration summed over earlier siblings, ignoring tuplet ratio — see
/// [_rewriteCrossStaffChords]'s limitations) and whether a `<tuplet>` wraps it.
class _TimedNote {
  final XmlNode node;
  final Fraction onset;
  final bool insideTuplet;
  const _TimedNote(this.node, this.onset, this.insideTuplet);
}

/// Every non-grace `<note>`/`<chord>` directly or beam-nested in [layer], in
/// document order, with its nominal onset. `<tupletSpan>`-style precision is
/// not needed here — this onset only positions a SYNTHETIC cross-staff
/// insertion, not the model's own layout.
List<_TimedNote> _timedNotesOf(XmlNode layer) {
  final out = <_TimedNote>[];
  var cursor = Fraction.zero;
  void walk(Iterable<XmlNode> nodes, bool insideTuplet) {
    for (final node in nodes) {
      switch (node.name) {
        case 'beam':
          walk(node.children, insideTuplet);
        case 'tuplet':
          walk(node.children, true);
        case 'note':
          if (node.attributes.containsKey('grace')) continue;
          out.add(_TimedNote(node, cursor, insideTuplet));
          cursor += _nominalDuration(node) ?? Fraction.zero;
        case 'chord':
          if (node.attributes.containsKey('grace')) continue;
          if (node.attributes.containsKey('copyof')) {
            cursor += _nominalDuration(node) ?? Fraction.zero;
            continue;
          }
          out.add(_TimedNote(node, cursor, insideTuplet));
          cursor += _nominalDuration(node) ?? Fraction.zero;
        case 'rest':
        case 'mRest':
        case 'space':
          cursor += _nominalDuration(node) ?? Fraction.zero;
      }
    }
  }

  walk(layer.children, false);
  return out;
}

/// [node]'s `@dur`/`@dots` as a whole-note [Fraction], or null when `@dur` is
/// absent (a full-measure rest) — too imprecise to place a cross-staff
/// insertion against, so callers treat it as zero duration.
Fraction? _nominalDuration(XmlNode node) {
  final base = _durBases[node.attributes['dur']];
  if (base == null) return null;
  final dots = (int.tryParse(node.attributes['dots'] ?? '0') ?? 0).clamp(0, 2);
  return NoteDuration(base, dots: dots).toFraction();
}

/// A chord's notes split by effective staff (`@staff`, defaulting to [homeN]):
/// [localNotes] stay home, [foreignNotes] cross to [foreignStaffN]. Null when
/// every note is local (nothing to split) or the notes name more than one
/// foreign staff (unsupported).
class _CrossSplit {
  final List<XmlNode> localNotes;
  final int foreignStaffN;
  final List<XmlNode> foreignNotes;
  const _CrossSplit(this.localNotes, this.foreignStaffN, this.foreignNotes);
}

_CrossSplit? _crossSplitOf(XmlNode chordNode, int homeN) {
  final members = chordNode.childrenNamed('note').toList();
  int effectiveStaff(XmlNode n) =>
      int.tryParse(n.attributes['staff'] ?? '') ?? homeN;
  final local = [
    for (final n in members)
      if (effectiveStaff(n) == homeN) n
  ];
  final foreignByStaff = <int, List<XmlNode>>{};
  for (final n in members) {
    final s = effectiveStaff(n);
    if (s != homeN) (foreignByStaff[s] ??= []).add(n);
  }
  if (foreignByStaff.length != 1) return null;
  final entry = foreignByStaff.entries.single;
  return _CrossSplit(local, entry.key, entry.value);
}

/// [original] with `@staff` removed — it is meaningless (and redundant) once
/// the note has actually been moved onto that staff.
XmlNode _withoutStaffAttr(XmlNode n) {
  if (!n.attributes.containsKey('staff')) return n;
  return XmlNode(
      n.name, {...n.attributes}..remove('staff'), n.children, n.text);
}

/// A same-duration invisible rest standing in for a note/chord that moved
/// entirely off its home staff — keeps every later sibling in [original]'s
/// layer at its original onset.
XmlNode _spaceLike(XmlNode original) {
  final attrs = <String, String>{};
  if (original.attributes['dur'] case final dur?) attrs['dur'] = dur;
  if (original.attributes['dots'] case final dots?) attrs['dots'] = dots;
  return XmlNode('space', attrs, const [], '');
}

/// Undotted `@dur` bases in descending length, for padding a target layer up
/// to a cross-staff insertion's onset.
const _spaceBases = [
  DurationBase.maxima,
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

/// The inverse of [_durBases] for the bases [_spaceBases] covers.
const _durBaseNames = {
  DurationBase.maxima: 'maxima',
  DurationBase.long: 'long',
  DurationBase.breve: 'breve',
  DurationBase.whole: '1',
  DurationBase.half: '2',
  DurationBase.quarter: '4',
  DurationBase.eighth: '8',
  DurationBase.sixteenth: '16',
  DurationBase.thirtySecond: '32',
  DurationBase.sixtyFourth: '64',
};

/// `<space>` elements (MEI's invisible rest) summing to [gap] — greedy
/// largest-duration-first, like the MusicXML reader's `_hiddenRests`.
List<XmlNode> _spaceFor(Fraction gap) {
  var left = gap;
  final out = <XmlNode>[];
  final floor = Fraction(1, 128);
  while (left >= floor) {
    NoteDuration? pick;
    for (final base in _spaceBases) {
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
    out.add(XmlNode(
        'space',
        {
          'dur': _durBaseNames[pick.base]!,
          if (pick.dots > 0) 'dots': '${pick.dots}',
        },
        const [],
        ''));
    left -= pick.toFraction();
  }
  return out;
}

/// [node] (and recursively its children) with every key of [replacements]
/// swapped for its value — identity-keyed, since [XmlNode] has no structural
/// equality and every node from one parse is already unique by reference. A
/// subtree with no replacement anywhere inside it comes back as the SAME
/// object rather than a rebuilt copy, so identity survives for anything this
/// pass leaves untouched.
XmlNode _applyReplacements(XmlNode node, Map<XmlNode, XmlNode> replacements) {
  if (replacements[node] case final replacement?) return replacement;
  if (node.children.isEmpty) return node;
  var changed = false;
  final newChildren = <XmlNode>[];
  for (final c in node.children) {
    final r = _applyReplacements(c, replacements);
    if (!identical(r, c)) changed = true;
    newChildren.add(r);
  }
  return changed
      ? XmlNode(node.name, node.attributes, newChildren, node.text)
      : node;
}

/// Splits every cross-staff chord/note found directly in [measureNode]'s
/// `<staff>`s (see [_rewriteCrossStaffChords]), returning the rewritten
/// measure and recording each genuine two-halves link into [links].
XmlNode _rewriteCrossStaffMeasure(
    XmlNode measureNode, List<_PendingCrossLink> links) {
  final staves = measureNode.childrenNamed('staff').toList();
  if (staves.isEmpty) return measureNode;
  final homeReplacements = <XmlNode, XmlNode>{};
  final insertionsByTarget = <int, List<(Fraction, Fraction, XmlNode)>>{};

  void processChord(XmlNode node, int homeN, Fraction onset) {
    if (node.attributes.containsKey('copyof')) return;
    final split = _crossSplitOf(node, homeN);
    if (split == null) return;
    final duration = _nominalDuration(node) ?? Fraction.zero;
    if (split.localNotes.isEmpty) {
      // Nothing stays home: the whole chord moves, with no stem to join.
      homeReplacements[node] = _spaceLike(node);
      final moved = XmlNode(
          'chord',
          node.attributes,
          [for (final n in split.foreignNotes) _withoutStaffAttr(n)],
          node.text);
      (insertionsByTarget[split.foreignStaffN] ??= [])
          .add((onset, duration, moved));
      return;
    }
    // A genuine split: both halves exist, joined by one stem.
    var homeAttrs = node.attributes;
    var homeId = node.attributes['xml:id'];
    if (homeId == null) {
      homeId = 'xs${identityHashCode(node)}h';
      homeAttrs = {...node.attributes, 'xml:id': homeId};
    }
    homeReplacements[node] =
        XmlNode('chord', homeAttrs, split.localNotes, node.text);
    final foreignId = 'xs${identityHashCode(node)}f';
    final foreignNode = XmlNode(
        'chord',
        {...node.attributes, 'xml:id': foreignId},
        [for (final n in split.foreignNotes) _withoutStaffAttr(n)],
        node.text);
    (insertionsByTarget[split.foreignStaffN] ??= [])
        .add((onset, duration, foreignNode));
    final stemsDown = node.attributes['stem.dir'] != 'up';
    final upperIsHome = homeN < split.foreignStaffN;
    links.add(_PendingCrossLink(
      upperIsHome ? homeN : split.foreignStaffN,
      upperIsHome ? split.foreignStaffN : homeN,
      upperIsHome ? homeId : foreignId,
      upperIsHome ? foreignId : homeId,
      stemsDown,
    ));
  }

  void processNote(XmlNode node, int homeN, Fraction onset) {
    final target = int.tryParse(node.attributes['staff'] ?? '');
    if (target == null || target == homeN) return;
    final duration = _nominalDuration(node) ?? Fraction.zero;
    // A lone note has nothing else to keep home with, so it always moves
    // wholesale — never a two-halves link.
    homeReplacements[node] = _spaceLike(node);
    (insertionsByTarget[target] ??= [])
        .add((onset, duration, _withoutStaffAttr(node)));
  }

  for (final staff in staves) {
    final homeN = int.tryParse(staff.attributes['n'] ?? '') ?? 1;
    for (final layer in staff.childrenNamed('layer')) {
      for (final timed in _timedNotesOf(layer)) {
        if (timed.insideTuplet) continue;
        if (timed.node.name == 'chord') {
          processChord(timed.node, homeN, timed.onset);
        } else {
          processNote(timed.node, homeN, timed.onset);
        }
      }
    }
  }

  if (homeReplacements.isEmpty && insertionsByTarget.isEmpty) {
    return measureNode;
  }

  final byN = <int, XmlNode>{};
  final order = <int>[];
  for (final staff in staves) {
    final n = int.tryParse(staff.attributes['n'] ?? '') ?? 1;
    byN[n] = _applyReplacements(staff, homeReplacements);
    order.add(n);
  }
  for (final target in insertionsByTarget.keys) {
    final events = insertionsByTarget[target]!
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final existing = byN[target];
    final usedLayerNs = {
      for (final l in existing?.childrenNamed('layer') ?? const <XmlNode>[])
        int.tryParse(l.attributes['n'] ?? '') ?? 0,
    };
    var newLayerN = 1;
    while (usedLayerNs.contains(newLayerN)) {
      newLayerN++;
    }
    // The model caps a measure at 4 voices; a staff that already uses all of
    // them has no room left for the crossing content, which is dropped
    // rather than overwriting one of the real voices.
    if (newLayerN > 4) continue;
    final content = <XmlNode>[];
    var cursor = Fraction.zero;
    for (final (onset, duration, node) in events) {
      final gap = onset - cursor;
      if (gap > Fraction.zero) content.addAll(_spaceFor(gap));
      content.add(node);
      cursor = onset + duration;
    }
    final newLayer = XmlNode('layer', {'n': '$newLayerN'}, content, '');
    if (existing == null) {
      byN[target] = XmlNode('staff', {'n': '$target'}, [newLayer], '');
      order.add(target);
    } else {
      byN[target] = XmlNode('staff', existing.attributes,
          [...existing.children, newLayer], existing.text);
    }
  }
  order.sort();
  final newStaves = [for (final n in order) byN[n]!];
  final children = measureNode.children;
  final firstStaffIdx = children.indexWhere((c) => c.name == 'staff');
  final lastStaffIdx = children.lastIndexWhere((c) => c.name == 'staff');
  final before = children.sublist(0, firstStaffIdx);
  final after = children.sublist(lastStaffIdx + 1);
  return XmlNode(measureNode.name, measureNode.attributes,
      [...before, ...newStaves, ...after], measureNode.text);
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
    // An <ending n="…"> wrapping measures marks them as that volta; carry it
    // down to the measures it contains. `@n` names the passes ("1", "1-3"),
    // `@label` the printed label (its numbers stand in for a missing `@n`),
    // and `@lendsym="none"` leaves the ending's last bar open.
    void collect(XmlNode node, Measure Function(Measure)? ending) {
      for (final child in node.children) {
        switch (child.name) {
          case 'measure':
            final m = _readMeasure(child);
            measures.add(ending == null ? m : ending(m));
          case 'section':
            collect(child, ending);
          case 'ending':
            final label = child.attributes['label'];
            var passes = voltaNumbersIn(child.attributes['n'] ?? '');
            if (passes.isEmpty) passes = voltaNumbersIn(label ?? '');
            if (passes.isEmpty) passes = [nextVoltaPass(measures)];
            final text = voltaTextOf(label, passes);
            final from = measures.length;
            collect(
                child,
                (m) => m.copyWith(
                      volta: passes.first,
                      voltaNumbers: passes.length > 1 ? passes : const [],
                      voltaText: text,
                    ));
            if (child.attributes['lendsym'] == 'none' &&
                measures.length > from) {
              measures.last = measures.last.copyWith(voltaOpenEnd: true);
            }
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
              _xmlIdToId[s.endId] ?? s.endId,
              placement: s.placement),
      ],
      dynamics: [
        for (final d in _dynamics)
          DynamicMarking(_xmlIdToId[d.elementId] ?? d.elementId, d.level),
      ],
      // A mark on a note this score did not read (another staff's, in a
      // one-staff read) is dropped: layout cannot place text on a note it
      // does not have.
      annotations: [
        for (final a in _annotations)
          if (_xmlIdToId[a.elementId] case final id?)
            Annotation(id, a.text,
                placement: a.placement, italic: a.italic, bold: a.bold),
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
      portamentos: [
        for (final p in _portamentos)
          Portamento(_xmlIdToId[p.startId] ?? p.startId,
              _xmlIdToId[p.endId] ?? p.endId),
      ],
      figuredBass: [
        for (final f in _figuredBass)
          FiguredBass(_xmlIdToId[f.noteId] ?? f.noteId, f.figures),
      ],
      cueNoteIds: [
        for (final c in _cueNoteIds) _xmlIdToId[c] ?? c,
      ],
      glissandos: [
        for (final g in _glissandos)
          Glissando(_xmlIdToId[g.startId] ?? g.startId,
              _xmlIdToId[g.endId] ?? g.endId),
      ],
      chordSymbols: [
        for (final c in _chordSymbols)
          if (_xmlIdToId[c.elementId] case final id?) c.copyWith(elementId: id),
      ],
      hairpins: [
        for (final h in _hairpins)
          Hairpin(_xmlIdToId[h.startId] ?? h.startId,
              _xmlIdToId[h.endId] ?? h.endId, h.type,
              above: h.above),
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
  final _arpeggios = <String, Arpeggio>{};
  final _portamentos = <Portamento>[];
  final _cueNoteIds = <String>[];
  final _figuredBass = <FiguredBass>[];

  /// MEI's `@head.shape` back to the model's shape.
  static NoteheadShape _headOf(XmlNode n) =>
      switch (n.attributes['head.shape']) {
        'x' => NoteheadShape.x,
        'diamond' => NoteheadShape.diamond,
        'isotriangle' => NoteheadShape.triangleUp,
        'slash' => NoteheadShape.slash,
        'circle' => NoteheadShape.circleX,
        _ => NoteheadShape.normal,
      };

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
              Slur(startid.replaceFirst('#', ''), endid.replaceFirst('#', ''),
                  placement: switch (node.attributes['curvedir']) {
                    'above' => SlurPlacement.above,
                    'below' => SlurPlacement.below,
                    _ => SlurPlacement.auto,
                  }));
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
        // Styled text sits in `<rend>`: its text is the mark's, its
        // fontstyle/fontweight the mark's style.
        final text = node.deepText;
        final rends = [
          node,
          ...node.descendants.where((n) => n.name == 'rend'),
        ];
        if (text.isNotEmpty) {
          _annotations.add(Annotation(
            startid.replaceFirst('#', ''),
            text,
            placement: node.attributes['place'] == 'below'
                ? AnnotationPlacement.below
                : AnnotationPlacement.above,
            italic: rends.any((n) => n.attributes['fontstyle'] == 'italic'),
            bold: rends.any((n) => n.attributes['fontweight'] == 'bold'),
          ));
        }
      }
      if (node.name == 'arpeg' && startid != null) {
        _arpeggios[startid.replaceFirst('#', '')] =
            node.attributes['order'] == 'down' ? Arpeggio.down : Arpeggio.up;
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
          final a = startid.replaceFirst('#', '');
          final b = end.replaceFirst('#', '');
          // `@lform="solid"` is the plain line — a portamento; anything else
          // (wavy, or unstated) is a glissando.
          if (node.attributes['lform'] == 'solid') {
            _portamentos.add(Portamento(a, b));
          } else {
            _glissandos.add(Glissando(a, b));
          }
        }
      }
      if (node.name == 'harm' && startid != null) {
        // A `<harm>` carrying `<fb>` is FIGURED BASS, not a chord label — the
        // same element, told apart by what is inside it.
        final fb = node.child('fb');
        if (fb != null) {
          final figures = [
            for (final f in fb.childrenNamed('f'))
              if (f.text.trim().isNotEmpty) f.text.trim(),
          ];
          if (figures.isNotEmpty) {
            _figuredBass
                .add(FiguredBass(startid.replaceFirst('#', ''), figures));
          }
          continue;
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
            degrees: parsed.degrees,
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
    final inlineClefs = <InlineClefChange>[];
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
              // ⚠️ POSITION decides. A `<clef>` after elements have been read
              // is a MID-BAR change at that onset; the measure-level ones open
              // the layer, so they arrive here with nothing before them.
              var at = Fraction.zero;
              for (final e in elements) {
                at = at + e.duration.toFraction();
              }
              if (at > Fraction.zero) {
                inlineClefs.add(InlineClefChange(at, clef));
              } else {
                clefChange = clef;
              }
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
            if (time != null) {
              // ⚠️ A RESTATED meter is recorded, not suppressed. A file that writes its
              // meter again mid-piece is saying something, and dropping it broke the
              // round trip for ~16% of kern files — the single largest remaining cause
              // in `krn -> lilypond`. The old fear was that redundant exports would draw
              // a meter at every bar; they cannot, because `layout_engine` guards
              // `timeChange != _time` before DRAWING one. Measured first: only 2 of 681
              // MusicXML files and 0 of 25 kern files restate in >50% of bars.
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
            if (node.attributes['cue'] == 'true' && elements.last.id != null) {
              _cueNoteIds.add(elements.last.id!);
            }
            pendingGraces = <Pitch>[];
            pendingGraceStyle = GraceStyle.acciaccatura;
          case 'chord':
            elements.add(_chordFrom(node,
                graceNotes: pendingGraces, graceStyle: pendingGraceStyle));
            _noteLv(node, elements.last);
            if (node.attributes['cue'] == 'true' && elements.last.id != null) {
              _cueNoteIds.add(elements.last.id!);
            }
            pendingGraces = <Pitch>[];
            pendingGraceStyle = GraceStyle.acciaccatura;
          case 'rest':
          case 'mRest':
          case 'space': // MEI's invisible rest
            elements.add(RestElement(_durationFrom(node),
                id: _idFor(node.attributes['xml:id']),
                hidden: node.name == 'space'));
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
                case 'space':
                  elements.add(RestElement(_durationFrom(child),
                      id: _idFor(child.attributes['xml:id']),
                      hidden: child.name == 'space'));
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
          // Encoders often state a tuplet twice — a <tuplet> element around
          // the notes AND a <tupletSpan> over the same notes (the MEI
          // sample encodings' Schubert "Lindenbaum" does). Overlapping spans
          // are invalid in the model and failed layout, so a span that
          // overlaps a tuplet already read for this voice is that tuplet.
          final duplicate = tuplets.any(
              (t) => t.voice == v && t.startIndex <= ei && si <= t.endIndex);
          if (!duplicate) {
            tuplets.add(TupletSpan(si, ei,
                actual: ts.num, normal: ts.numbase, voice: v));
          }
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
      inlineClefs: inlineClefs,
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
      arpeggio: _arpeggios[note.attributes['xml:id']],
      notehead: _headOf(note),
      tremolo: _tremoloOf(note),
      graceNotes: graceNotes,
      graceStyle: graceStyle,
      stemsDown: _stemDownOf(note),
      id: id,
    );
  }

  /// The stated stem direction (`@stem.dir`): true down, false up, null when
  /// the file leaves it to the engraver.
  static bool? _stemDownOf(XmlNode node) =>
      switch (node.attributes['stem.dir']) {
        'down' => true,
        'up' => false,
        _ => null,
      };

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
      arpeggio: _arpeggios[chord.attributes['xml:id']],
      notehead: _headOf(chord),
      tremolo: _tremoloOf(chord),
      graceNotes: graceNotes,
      graceStyle: graceStyle,
      stemsDown: _stemDownOf(chord),
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
