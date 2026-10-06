/// Ossia and divisi staves: extra staves that appear only where they have
/// music.
///
/// Both are PARTIAL parts of a [MultiPartScore] (see
/// [MultiPartScore.partialParts]): the layout draws them only over the bars
/// where they hold notes, and only on systems where they hold any, while
/// their notes stay aligned with the staff they belong to.
///
/// - [PartialStaves.withOssia] places an alternative passage on a staff above
///   a part;
/// - [PartialStaves.withDivisi] splits a part's second voice onto a staff
///   below it for chosen bars ("div."), leaving the first voice on the part.
library;

import '../internal/bar_fill.dart';
import '../model/measure.dart';
import '../model/score.dart';
import 'multi_part.dart';
import 'staff_system.dart';

/// Ossia and divisi builders on a [MultiPartScore]; see the library comment.
extension PartialStaves on MultiPartScore {
  /// This document with an ossia staff above part [part]: [measures] are the
  /// alternative bars, placed from bar [start] on. Bars outside them are
  /// rests, which the partial staff never draws.
  MultiPartScore withOssia(int part, int start, List<Measure> measures) {
    final src = parts[part];
    if (start < 0 || start + measures.length > src.measures.length) {
      throw RangeError('the ossia must lie within the part\'s bars');
    }
    final caps = barCapacities(src);
    final ossia = src.copyWith(
      measures: [
        for (var i = 0; i < src.measures.length; i++)
          _structureOf(
            src.measures[i],
            i >= start && i < start + measures.length
                ? measures[i - start]
                : Measure(restsFilling(caps[i], 'ossia$part.$i')),
          ),
      ],
      slurs: const [],
      dynamics: const [],
      hairpins: const [],
      lyrics: const [],
      annotations: const [],
    );
    return _inserted(part, ossia, owner: part);
  }

  /// This document with part [part]'s second voice moved, in [measures], onto
  /// a divisi staff below it. The part keeps its other voices; elsewhere the
  /// divisi staff is rests, which it never draws. Slurs, dynamics and
  /// hairpins on the moved notes move with them.
  MultiPartScore withDivisi(int part, Set<int> measures) {
    final src = parts[part];
    final caps = barCapacities(src);
    final moved = <String>{};
    final upper = <Measure>[];
    final lower = <Measure>[];
    for (var i = 0; i < src.measures.length; i++) {
      final m = src.measures[i];
      if (measures.contains(i) && m.voice2.isNotEmpty) {
        for (final e in m.voice2) {
          if (e.id != null) moved.add(e.id!);
        }
        upper.add(Measure(
          m.elements,
          voice3: m.voice3,
          voice4: m.voice4,
          tuplets: [
            for (final t in m.tuplets)
              if (t.voice != 1) t
          ],
          clefChange: m.clefChange,
          inlineClefs: m.inlineClefs,
          keyChange: m.keyChange,
          timeChange: m.timeChange,
          tempoChange: m.tempoChange,
          startRepeat: m.startRepeat,
          endRepeat: m.endRepeat,
          volta: m.volta,
          navigation: m.navigation,
          barline: m.barline,
          pickup: m.pickup,
          actualDuration: m.actualDuration,
        ));
        lower.add(_structureOf(
          m,
          Measure(m.voice2, tuplets: [
            for (final t in m.tuplets)
              if (t.voice == 1)
                TupletSpan(t.startIndex, t.endIndex,
                    actual: t.actual, normal: t.normal),
          ]),
        ));
      } else {
        upper.add(m);
        lower.add(
            _structureOf(m, Measure(restsFilling(caps[i], 'div$part.$i'))));
      }
    }
    bool onMoved(String a, [String? b]) =>
        moved.contains(a) && (b == null || moved.contains(b));
    final divisi = src.copyWith(
      measures: lower,
      slurs: [
        for (final s in src.slurs)
          if (onMoved(s.startId, s.endId)) s
      ],
      dynamics: [
        for (final d in src.dynamics)
          if (onMoved(d.elementId)) d
      ],
      hairpins: [
        for (final h in src.hairpins)
          if (onMoved(h.startId, h.endId)) h
      ],
      lyrics: const [],
      annotations: const [],
    );
    final kept = src.copyWith(
      measures: upper,
      slurs: [
        for (final s in src.slurs)
          if (!onMoved(s.startId) && !onMoved(s.endId)) s
      ],
      dynamics: [
        for (final d in src.dynamics)
          if (!onMoved(d.elementId)) d
      ],
      hairpins: [
        for (final h in src.hairpins)
          if (!onMoved(h.startId) && !onMoved(h.endId)) h
      ],
    );
    final withLower = _inserted(part + 1, divisi, owner: part);
    return MultiPartScore(
      [
        for (var i = 0; i < withLower.parts.length; i++)
          i == part ? kept : withLower.parts[i],
      ],
      brackets: withLower.brackets,
      barlineGroups: withLower.barlineGroups,
      partialParts: withLower.partialParts,
    );
  }

  /// This document with [staff] inserted as a partial part at [at] (shifting
  /// the later parts down), belonging to part [owner] — the part it is drawn
  /// with. A bracket or barline group that contains the owner grows to
  /// include it, except that an ossia stays outside a group its owner starts.
  MultiPartScore _inserted(int at, Score staff, {required int owner}) {
    (int, int) grown(int first, int last) =>
        (first >= at ? first + 1 : first, last >= owner ? last + 1 : last);
    return MultiPartScore(
      [...parts.sublist(0, at), staff, ...parts.sublist(at)],
      brackets: [
        for (final b in brackets)
          if (grown(b.first, b.last) case (final f, final l))
            StaffBracket(f, l, kind: b.kind),
      ],
      barlineGroups: [
        for (final g in barlineGroups)
          if (grown(g.first, g.last) case (final f, final l))
            BarlineGroup(f, l),
      ],
      partialParts: {
        for (final p in partialParts) p >= at ? p + 1 : p,
        at,
      },
    );
  }
}

/// [music] carrying [source]'s score-wide bar fields, so a partial staff keeps
/// the same meter, key and bar lengths as the staff it belongs to.
Measure _structureOf(Measure source, Measure music) => Measure(
      music.elements,
      voice2: music.voice2,
      voice3: music.voice3,
      voice4: music.voice4,
      tuplets: music.tuplets,
      clefChange: music.clefChange,
      inlineClefs: music.inlineClefs,
      keyChange: source.keyChange,
      timeChange: source.timeChange,
      actualDuration: source.actualDuration,
      pickup: source.pickup,
    );
