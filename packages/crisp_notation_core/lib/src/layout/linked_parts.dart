/// Linked parts: edit one instrument's part on its own and have the full score
/// follow.
///
/// A part extracted from a [MultiPartScore] is an ordinary [Score], so it can
/// be edited with any single-part tooling. What makes it LINKED is the way the
/// edit comes back: [LinkedParts.withLinkedPart] replaces that part and carries
/// the score-wide structure of the edit to every other part, so the document
/// stays one piece:
///
/// - **bars** inserted into or deleted from the part are inserted (as rest
///   bars) into or deleted from every part;
/// - **meter, tempo, repeats, voltas, navigation marks, barline styles,
///   pickups and irregular bar lengths** set on a bar apply to that bar in
///   every part;
/// - **key** changes apply everywhere too, each part getting the key it
///   writes for its own transposition (a B-flat clarinet reads D major where
///   the score sounds C).
///
/// Everything else — notes, clefs, dynamics, slurs, lyrics — belongs to the
/// part alone. A part may be edited at concert pitch: pass `concertPitch` to
/// both [LinkedParts.linkedPart] and [LinkedParts.withLinkedPart].
///
/// Bars are matched between the old and the edited part by the ids of their
/// elements, so an edit that keeps element ids (the normal case for an
/// editor) is tracked exactly; bars whose content was wholly replaced are
/// matched by position between their nearest matched neighbours.
library;

import '../internal/bar_fill.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/key_signature.dart';
import '../theory/transposition.dart';
import 'multi_part.dart';

/// Linked-part editing on a [MultiPartScore]; see the library comment.
extension LinkedParts on MultiPartScore {
  /// Part [index] for editing on its own: as written, or at concert pitch.
  Score linkedPart(int index, {bool concertPitch = false}) =>
      concertPitch ? parts[index].atConcertPitch() : parts[index];

  /// This document with part [index] replaced by [edited], and the edit's
  /// score-wide structure (bars, meter, key, tempo, repeats, voltas,
  /// navigation, barlines) carried to every other part.
  ///
  /// Set [concertPitch] when [edited] came from
  /// `linkedPart(index, concertPitch: true)`: it is converted back to the
  /// part's written pitch first.
  MultiPartScore withLinkedPart(int index, Score edited,
      {bool concertPitch = false}) {
    final old = parts[index];
    final t = old.transposition;
    final written =
        concertPitch && t != null ? edited.atWrittenPitch(t) : edited;
    final pairs = _alignBars(old.measures, written.measures);

    // The edited part's keys at concert pitch, so each other part can take
    // the key IT writes.
    KeySignature toConcert(KeySignature k) =>
        t == null ? k : k.transposedBy(t.interval, descending: t.down);
    KeySignature toWritten(KeySignature k, Transposition? tj) =>
        tj == null ? k : k.transposedBy(tj.interval, descending: !tj.down);

    final out = <Score>[];
    for (var j = 0; j < parts.length; j++) {
      if (j == index) {
        out.add(written);
        continue;
      }
      final part = parts[j];
      final tj = part.transposition;
      KeySignature keyFor(KeySignature k) => toWritten(toConcert(k), tj);
      final capacities = barCapacities(written);
      final measures = <Measure>[
        for (final (o, n) in pairs)
          if (n != null)
            _withStructure(
              o != null && o < part.measures.length
                  ? part.measures[o]
                  : Measure(restsFilling(capacities[n], 'lp$j.$n')),
              written.measures[n],
              keyFor,
            ),
      ];
      out.add(part.copyWith(
        measures: measures,
        keySignature: keyFor(written.keySignature),
        timeSignature: written.timeSignature,
        tempo: written.tempo,
      ));
    }
    return MultiPartScore(out,
        brackets: brackets,
        barlineGroups: barlineGroups,
        partialParts: partialParts);
  }
}

/// [base]'s own music with the score-wide fields of [source].
Measure _withStructure(Measure base, Measure source,
        KeySignature Function(KeySignature) keyFor) =>
    Measure(
      base.elements,
      voice2: base.voice2,
      voice3: base.voice3,
      voice4: base.voice4,
      tuplets: base.tuplets,
      clefChange: base.clefChange,
      inlineClefs: base.inlineClefs,
      multiRest: base.multiRest,
      measureRepeat: base.measureRepeat,
      // Score-wide.
      keyChange: source.keyChange == null ? null : keyFor(source.keyChange!),
      timeChange: source.timeChange,
      tempoChange: source.tempoChange,
      startRepeat: source.startRepeat,
      endRepeat: source.endRepeat,
      volta: source.volta,
      navigation: source.navigation,
      barline: source.barline,
      pickup: source.pickup,
      actualDuration: source.actualDuration,
    );

Set<String> _idsOf(Measure m) => {
      for (var v = 0; v < 4; v++)
        for (final e in m.voiceAt(v))
          if (e.id != null) e.id!,
    };

/// The old→new bar correspondence, in order: `(old, new)` for a kept bar,
/// `(null, new)` for an inserted one, `(old, null)` for a deleted one.
List<(int?, int?)> _alignBars(List<Measure> before, List<Measure> after) {
  // Anchor bars that share an element id, keeping only a monotonic chain.
  final newOfId = <String, int>{};
  for (var n = 0; n < after.length; n++) {
    for (final id in _idsOf(after[n])) {
      newOfId[id] = n;
    }
  }
  final anchors = <(int, int)>[];
  for (var o = 0; o < before.length; o++) {
    int? match;
    for (final id in _idsOf(before[o])) {
      final n = newOfId[id];
      if (n != null) {
        match = n;
        break;
      }
    }
    if (match != null && (anchors.isEmpty || match > anchors.last.$2)) {
      anchors.add((o, match));
    }
  }
  // Between consecutive anchors, pair leftover bars by position; the surplus
  // is an insertion or a deletion at the end of the gap.
  final out = <(int?, int?)>[];
  var o = 0, n = 0;
  for (final (ao, an) in [...anchors, (before.length, after.length)]) {
    while (o < ao && n < an) {
      out.add((o++, n++));
    }
    while (o < ao) {
      out.add((o++, null));
    }
    while (n < an) {
      out.add((null, n++));
    }
    if (ao < before.length) out.add((o++, n++));
  }
  return out;
}
