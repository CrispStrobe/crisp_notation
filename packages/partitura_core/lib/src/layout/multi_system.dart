/// Line breaking: wrap a score into systems of a target width.
library;

import 'dart:math';

import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/key_signature.dart';
import '../theory/time_signature.dart';
import 'grand_staff.dart';
import 'layout_engine.dart';
import 'layout_settings.dart';
import 'score_layout.dart';
import 'staff_system.dart';

/// One system (line) of a broken score.
class SystemLayout {
  /// The laid-out line.
  final ScoreLayout layout;

  /// Index of the first original measure on this system.
  final int firstMeasure;

  /// Index of the last original measure on this system (inclusive).
  final int lastMeasure;

  /// Creates a system layout.
  const SystemLayout({
    required this.layout,
    required this.firstMeasure,
    required this.lastMeasure,
  });

  @override
  String toString() => 'SystemLayout(measures $firstMeasure..$lastMeasure, '
      'width ${layout.width})';
}

/// A score broken into systems.
class MultiSystemLayout {
  /// The systems, top to bottom.
  final List<SystemLayout> systems;

  /// The width every non-final system was justified to.
  final double maxWidth;

  /// Creates a multi-system layout.
  const MultiSystemLayout({required this.systems, required this.maxWidth});

  /// Total height in staff spaces when systems are stacked [systemGap]
  /// spaces apart (bounding box to bounding box).
  double heightWith(double systemGap) {
    var height = 0.0;
    for (final system in systems) {
      height += system.layout.height;
    }
    return height + systemGap * (systems.length - 1);
  }

  @override
  String toString() => 'MultiSystemLayout(${systems.length} systems)';
}

/// Breaks [score] into systems no wider than [maxWidth] staff spaces and
/// justifies every system except the last to exactly that width
/// (via uniform spacing stretch; disable with [justify]).
///
/// Every system restates the clef and key signature current at its first
/// measure; the time signature appears only on the first system and at
/// explicit changes. Non-final systems close with a plain thin barline;
/// only the last carries the end-of-score barline. Slurs, dynamics and hairpins whose endpoints fall on
/// different systems are dropped (ties degrade gracefully on their own).
/// A measure wider than [maxWidth] gets its own (overwide) system rather
/// than failing. [systemBreaks] holds measure indices that must **begin** a new
/// system — an explicit line break before each — regardless of remaining width.
MultiSystemLayout layoutSystems(
  Score score,
  LayoutSettings settings, {
  required double maxWidth,
  bool justify = true,
  Set<int> systemBreaks = const {},
}) {
  const engine = LayoutEngine();
  if (maxWidth <= 0) {
    throw ArgumentError.value(maxWidth, 'maxWidth', 'must be positive');
  }

  // Natural widths of every measure, plus the running clef/key/time state
  // at each measure start.
  final natural = engine.layout(score, settings);
  final measureCount = score.measures.length;
  final clefAt = List<Clef>.filled(measureCount + 1, score.clef);
  final keyAt = List<KeySignature>.filled(measureCount + 1, score.keySignature);
  final timeAt =
      List<TimeSignature?>.filled(measureCount + 1, score.timeSignature);
  for (var i = 0; i < measureCount; i++) {
    final measure = score.measures[i];
    clefAt[i + 1] = measure.clefChange ?? clefAt[i];
    keyAt[i + 1] = measure.keyChange ?? keyAt[i];
    timeAt[i + 1] = measure.timeChange ?? timeAt[i];
    if (measure.clefChange != null) clefAt[i] = clefAt[i + 1];
    if (measure.keyChange != null) keyAt[i] = keyAt[i + 1];
    if (measure.timeChange != null) timeAt[i] = timeAt[i + 1];
  }

  // The time signature is drawn on the first system and where a system
  // starts on an explicit change (the change glyph moves into the leading
  // segment).
  bool drawTimeFor(int firstMeasure) =>
      firstMeasure == 0 || score.measures[firstMeasure].timeChange != null;

  // The system's leading segment (clef/key/time restatement) is re-laid
  // per system; measure a one-measure probe for its exact width.
  double leadingWidthFor(int firstMeasure) {
    final probe = engine.layout(
      _slice(score, firstMeasure, firstMeasure, clefAt, keyAt, timeAt),
      settings,
      drawTimeSignature: drawTimeFor(firstMeasure),
    );
    return probe.measureRegions.first.startX;
  }

  // Cumulative positions from the natural layout are exact for everything
  // between measure starts (barlines, repeat signs, inline changes).
  final finalBarAllowance = natural.width - natural.measureRegions.last.endX;

  final systems = <SystemLayout>[];
  var start = 0;
  while (start < measureCount) {
    // Greedy packing: extend while the estimated width still fits. The
    // first measure always goes on the line, even overwide.
    final leading = leadingWidthFor(start);
    var end = start;
    while (end + 1 < measureCount &&
        !systemBreaks.contains(end + 1) && // a forced break starts a new system
        leading +
                (natural.measureRegions[end + 1].endX -
                    natural.measureRegions[start].startX) +
                finalBarAllowance <=
            maxWidth) {
      end++;
    }
    final drawTime = drawTimeFor(start);
    var slice = _slice(score, start, end, clefAt, keyAt, timeAt);
    var layout = engine.layout(slice, settings,
        drawTimeSignature: drawTime, finalBarline: end == measureCount - 1);
    // Safety trim: if the estimate was ever optimistic, push measures to
    // the next system rather than overflow.
    while (layout.width > maxWidth && end > start) {
      end--;
      slice = _slice(score, start, end, clefAt, keyAt, timeAt);
      layout = engine.layout(slice, settings,
          drawTimeSignature: drawTime, finalBarline: end == measureCount - 1);
    }
    final isLastSystem = end == measureCount - 1;
    if (justify && !isLastSystem && layout.width < maxWidth) {
      // Binary-search the uniform spacing stretch to hit maxWidth.
      var low = 1.0, high = 4.0;
      for (var iteration = 0; iteration < 24; iteration++) {
        final mid = (low + high) / 2;
        final candidate = engine.layout(slice, settings,
            spacingStretch: mid,
            drawTimeSignature: drawTime,
            finalBarline: false);
        if (candidate.width > maxWidth) {
          high = mid;
        } else {
          low = mid;
          layout = candidate;
          if (maxWidth - candidate.width < 0.05) break;
        }
      }
    }
    systems.add(
      SystemLayout(layout: layout, firstMeasure: start, lastMeasure: end),
    );
    start = end + 1;
  }
  return MultiSystemLayout(systems: systems, maxWidth: maxWidth);
}

/// One system (line) of a wrapped grand staff.
class GrandStaffSystem {
  /// The laid-out grand-staff line (upper + lower).
  final GrandStaffLayout layout;

  /// Index of the first original measure on this system.
  final int firstMeasure;

  /// Index of the last original measure on this system (inclusive).
  final int lastMeasure;

  /// Creates a grand-staff system.
  const GrandStaffSystem({
    required this.layout,
    required this.firstMeasure,
    required this.lastMeasure,
  });
}

/// A grand staff broken into systems.
class GrandStaffSystems {
  /// The systems, top to bottom.
  final List<GrandStaffSystem> systems;

  /// The target width in staff spaces.
  final double maxWidth;

  /// Creates a wrapped grand staff.
  const GrandStaffSystems({required this.systems, required this.maxWidth});

  /// Total height in staff spaces when systems are stacked [systemGap] spaces
  /// apart (bounding box to bounding box).
  double heightWith(double systemGap) {
    var height = 0.0;
    for (final system in systems) {
      height += system.layout.height;
    }
    return height + systemGap * (systems.length - 1);
  }
}

/// Breaks a two-staff [grandStaff] into systems no wider than [maxWidth] staff
/// spaces, packing measures by the wider of the two staves so barlines stay
/// aligned, then laying out each system as its own [layoutGrandStaff] (upper +
/// lower). The time signature is drawn only on the first system (and at
/// explicit changes); every non-final system closes with a plain barline.
///
/// Every non-final system is justified to [maxWidth] (disable with [justify])
/// via a **shared note-spacing stretch across both staves** — binary-searched
/// so the slack becomes note spacing, not end-padding, and barlines stay
/// aligned. (Onset columns are still spaced per staff, not gridded across the
/// two — that is a separate, deeper spacing feature.)
///
/// Cross-staff beams are not carried onto wrapped systems (use a single-system
/// [layoutGrandStaff] for those). Throws if the staves disagree on measure
/// count or [maxWidth] is not positive.
GrandStaffSystems layoutGrandStaffSystems(
  GrandStaff grandStaff,
  LayoutSettings settings, {
  required double maxWidth,
  double staffGap = 4.0,
  bool justify = true,
  bool gridAlign = true,
}) {
  if (maxWidth <= 0) {
    throw ArgumentError.value(maxWidth, 'maxWidth', 'must be positive');
  }
  final upper = grandStaff.upper;
  final lower = grandStaff.lower;
  if (upper.measures.length != lower.measures.length) {
    throw ArgumentError('Grand staff staves must have the same measure count '
        '(${upper.measures.length} vs ${lower.measures.length})');
  }
  const engine = LayoutEngine();
  final naturalU = engine.layout(upper, settings);
  final naturalL = engine.layout(lower, settings);
  final n = upper.measures.length;

  double measureWidth(ScoreLayout layout, int i) =>
      layout.measureRegions[i].endX - layout.measureRegions[i].startX;
  final combined = [
    for (var i = 0; i < n; i++)
      max(measureWidth(naturalU, i), measureWidth(naturalL, i)),
  ];
  double leadingOf(ScoreLayout layout) => layout.measureRegions.isEmpty
      ? layout.width
      : layout.measureRegions.first.startX;
  final leadEstimate = max(leadingOf(naturalU), leadingOf(naturalL));

  final upperState = _stateArrays(upper);
  final lowerState = _stateArrays(lower);

  final systems = <GrandStaffSystem>[];
  var start = 0;
  while (start < n) {
    var end = start;
    var used = leadEstimate + combined[start];
    while (end + 1 < n && used + combined[end + 1] <= maxWidth) {
      end++;
      used += combined[end];
    }
    final drawTime = start == 0 ||
        upper.measures[start].timeChange != null ||
        lower.measures[start].timeChange != null;
    final isLast = end == n - 1;
    final gs = GrandStaff(
      upper: _slice(
          upper, start, end, upperState.$1, upperState.$2, upperState.$3),
      lower: _slice(
          lower, start, end, lowerState.$1, lowerState.$2, lowerState.$3),
    );
    GrandStaffLayout render(double stretch) => layoutGrandStaff(
          gs,
          settings,
          staffGap: staffGap,
          drawTimeSignature: drawTime,
          finalBarline: isLast,
          spacingStretch: stretch,
          gridAlign: gridAlign,
        );
    var layout = render(1.0);
    // Justify non-final systems: binary-search a single spacing stretch (shared
    // by both staves, so barlines stay aligned) up to [maxWidth].
    if (justify && !isLast && layout.width < maxWidth) {
      var low = 1.0, high = 4.0;
      for (var iteration = 0; iteration < 24; iteration++) {
        final mid = (low + high) / 2;
        final candidate = render(mid);
        if (candidate.width > maxWidth) {
          high = mid;
        } else {
          low = mid;
          layout = candidate;
          if (maxWidth - candidate.width < 0.05) break;
        }
      }
    }
    systems.add(GrandStaffSystem(
        layout: layout, firstMeasure: start, lastMeasure: end));
    start = end + 1;
  }
  return GrandStaffSystems(systems: systems, maxWidth: maxWidth);
}

/// One system (line) of a wrapped multi-part [StaffSystem] document.
class StaffSystemSystem {
  /// The laid-out system line (all parts, aligned).
  final StaffSystemLayout layout;

  /// Index of the first original measure on this system.
  final int firstMeasure;

  /// Index of the last original measure on this system (inclusive).
  final int lastMeasure;

  /// Creates a multi-part system.
  const StaffSystemSystem({
    required this.layout,
    required this.firstMeasure,
    required this.lastMeasure,
  });
}

/// An N-part [StaffSystem] document (Workshop contract C6) broken into systems.
class StaffSystemSystems {
  /// The systems, top to bottom.
  final List<StaffSystemSystem> systems;

  /// The target width in staff spaces.
  final double maxWidth;

  /// Creates a wrapped multi-part document.
  const StaffSystemSystems({required this.systems, required this.maxWidth});

  /// Total height in staff spaces when systems are stacked [systemGap] spaces
  /// apart (bounding box to bounding box).
  double heightWith(double systemGap) {
    var height = 0.0;
    for (final system in systems) {
      height += system.layout.height;
    }
    return height + systemGap * (systems.length - 1);
  }
}

/// Breaks an N-part [document] into systems no wider than [maxWidth] staff
/// spaces — the multi-part counterpart of [layoutGrandStaffSystems]. Measures
/// are packed by the widest part so barlines stay aligned across every part,
/// then each system is laid out with [layoutStaffSystem] (its brackets and
/// barline connectors intact). The time signature is drawn only on the first
/// system (and at explicit changes); every non-final system closes with a plain
/// barline and, unless [justify] is false, is stretched to fill [maxWidth] via
/// a shared note-spacing stretch (so slack becomes note spacing and barlines
/// stay aligned).
///
/// With [hideEmptyStaves], a part whose measures over a system's range are
/// entirely rests (or a multi-measure rest) is dropped from that system — the
/// standard orchestral space-saver. The first system always shows every part
/// (so the full instrumentation reads once), and a system that would otherwise
/// be blank keeps all its parts. Brackets and barline groups clip to the parts
/// that remain.
///
/// Throws if the parts disagree on measure count or [maxWidth] is not positive.
StaffSystemSystems layoutStaffSystemSystems(
  StaffSystem document,
  LayoutSettings settings, {
  required double maxWidth,
  double staffGap = 4.0,
  bool justify = true,
  bool gridAlign = true,
  bool hideEmptyStaves = false,
}) {
  if (maxWidth <= 0) {
    throw ArgumentError.value(maxWidth, 'maxWidth', 'must be positive');
  }
  final parts = document.staves;
  final n = parts.first.measures.length;
  for (final p in parts) {
    if (p.measures.length != n) {
      throw ArgumentError('all parts must have the same measure count');
    }
  }
  const engine = LayoutEngine();
  final naturals = [for (final p in parts) engine.layout(p, settings)];
  double measureWidth(ScoreLayout l, int i) =>
      l.measureRegions[i].endX - l.measureRegions[i].startX;
  final combined = [
    for (var i = 0; i < n; i++)
      naturals.map((l) => measureWidth(l, i)).reduce(max),
  ];
  double leadingOf(ScoreLayout l) =>
      l.measureRegions.isEmpty ? l.width : l.measureRegions.first.startX;
  final leadEstimate = naturals.map(leadingOf).reduce(max);
  final states = [for (final p in parts) _stateArrays(p)];

  // The parts to show on the system covering [start]..[end]: with hide-empty,
  // parts silent throughout the range are dropped — except on the first system
  // and unless every part is silent (a blank system keeps them all).
  List<int> visibleFor(int start, int end) {
    final all = [for (var i = 0; i < parts.length; i++) i];
    if (!hideEmptyStaves || start == 0) return all;
    final shown = [
      for (var i = 0; i < parts.length; i++)
        if (!_isSilentRange(parts[i], start, end)) i,
    ];
    if (shown.isEmpty || shown.length == parts.length) return all;
    return shown;
  }

  // The per-system document over just [visible] parts, with brackets and
  // barline groups clipped to those parts (so a hidden staff neither carries
  // nor bridges a connector).
  StaffSystem buildSysDoc(int start, int end, List<int> visible) {
    List<int> remap(int first, int last) => [
          for (var p = 0; p < visible.length; p++)
            if (visible[p] >= first && visible[p] <= last) p,
        ];
    final brackets = <StaffBracket>[];
    for (final b in document.brackets) {
      final pos = remap(b.first, b.last);
      if (pos.isNotEmpty) {
        brackets.add(StaffBracket(pos.first, pos.last, kind: b.kind));
      }
    }
    final groups = <BarlineGroup>[];
    for (final g in document.barlineGroups) {
      final pos = remap(g.first, g.last);
      if (pos.isNotEmpty) groups.add(BarlineGroup(pos.first, pos.last));
    }
    return StaffSystem(
      [
        for (final pi in visible)
          _slice(parts[pi], start, end, states[pi].$1, states[pi].$2,
              states[pi].$3),
      ],
      brackets: brackets,
      connectBarlines: document.connectBarlines,
      barlineGroups: groups,
    );
  }

  final systems = <StaffSystemSystem>[];
  var start = 0;
  while (start < n) {
    var end = start;
    var used = leadEstimate + combined[start];
    while (end + 1 < n && used + combined[end + 1] <= maxWidth) {
      end++;
      used += combined[end];
    }
    // Polymeter: restate the time signature at a system start if *any* staff's
    // own meter changes there (not just part 0), so a per-staff meter change is
    // never dropped at a wrap boundary. Each staff still draws its own meter.
    final drawTime =
        start == 0 || parts.any((p) => p.measures[start].timeChange != null);
    final isLast = end == n - 1;
    // Visibility is decided per system here (with the first-system / all-silent
    // rules); the reduced [sysDoc] then lays out with hide-empty off.
    final sysDoc = buildSysDoc(start, end, visibleFor(start, end));
    StaffSystemLayout render(double stretch) => layoutStaffSystem(
          sysDoc,
          settings,
          staffGap: staffGap,
          gridAlign: gridAlign,
          drawTimeSignature: drawTime,
          finalBarline: isLast,
          spacingStretch: stretch,
        );
    var layout = render(1.0);
    if (justify && !isLast && layout.width < maxWidth) {
      var low = 1.0, high = 4.0;
      for (var iteration = 0; iteration < 24; iteration++) {
        final mid = (low + high) / 2;
        final candidate = render(mid);
        if (candidate.width > maxWidth) {
          high = mid;
        } else {
          low = mid;
          layout = candidate;
          if (maxWidth - candidate.width < 0.05) break;
        }
      }
    }
    systems.add(StaffSystemSystem(
        layout: layout, firstMeasure: start, lastMeasure: end));
    start = end + 1;
  }
  return StaffSystemSystems(systems: systems, maxWidth: maxWidth);
}

/// Whether [part] is silent across measures [start]..[end]: every voice-1 and
/// voice-2 element is a rest (a multi-measure rest counts as silent).
bool _isSilentRange(Score part, int start, int end) {
  for (var i = start; i <= end; i++) {
    final measure = part.measures[i];
    if (measure.multiRest != null) continue;
    for (final element in measure.elements) {
      if (element is! RestElement) return false;
    }
    for (final element in measure.voice2) {
      if (element is! RestElement) return false;
    }
  }
  return true;
}

/// The running clef/key/time state at each measure start of [score].
(List<Clef>, List<KeySignature>, List<TimeSignature?>) _stateArrays(
    Score score) {
  final n = score.measures.length;
  final clefAt = List<Clef>.filled(n + 1, score.clef);
  final keyAt = List<KeySignature>.filled(n + 1, score.keySignature);
  final timeAt = List<TimeSignature?>.filled(n + 1, score.timeSignature);
  for (var i = 0; i < n; i++) {
    final m = score.measures[i];
    clefAt[i + 1] = m.clefChange ?? clefAt[i];
    keyAt[i + 1] = m.keyChange ?? keyAt[i];
    timeAt[i + 1] = m.timeChange ?? timeAt[i];
    if (m.clefChange != null) clefAt[i] = clefAt[i + 1];
    if (m.keyChange != null) keyAt[i] = keyAt[i + 1];
    if (m.timeChange != null) timeAt[i] = timeAt[i + 1];
  }
  return (clefAt, keyAt, timeAt);
}

/// A sub-score of measures [first]..[last] with the correct starting
/// state and only the spans that fit entirely inside the slice.
Score _slice(
  Score score,
  int first,
  int last,
  List<Clef> clefAt,
  List<KeySignature> keyAt,
  List<TimeSignature?> timeAt,
) {
  final measures = <Measure>[];
  for (var i = first; i <= last; i++) {
    var measure = score.measures[i];
    if (i == first &&
        (measure.clefChange != null ||
            measure.keyChange != null ||
            measure.timeChange != null)) {
      // The change is expressed by the system's leading state instead.
      measure = Measure(
        measure.elements,
        voice2: measure.voice2,
        voice3: measure.voice3,
        voice4: measure.voice4,
        tuplets: measure.tuplets,
        clefChange: null,
        keyChange: null,
        timeChange: null,
        tempoChange: measure.tempoChange,
        startRepeat: measure.startRepeat,
        endRepeat: measure.endRepeat,
        volta: measure.volta,
        multiRest: measure.multiRest,
        measureRepeat: measure.measureRepeat,
        navigation: measure.navigation,
        barline: measure.barline,
        pickup: measure.pickup,
        actualDuration: measure.actualDuration,
      );
    }
    measures.add(measure);
  }

  final ids = <String>{
    for (final measure in measures) ...[
      for (final element in measure.elements)
        if (element.id != null) element.id!,
      for (final element in measure.voice2)
        if (element.id != null) element.id!,
      for (final element in measure.voice3)
        if (element.id != null) element.id!,
      for (final element in measure.voice4)
        if (element.id != null) element.id!,
    ],
  };
  return Score(
    clef: clefAt[first],
    keySignature: keyAt[first],
    // The time signature shows on the first system and where it changes.
    // Kept even when not drawn — beaming windows derive from it.
    timeSignature: timeAt[first],
    measures: measures,
    slurs: [
      for (final slur in score.slurs)
        if (ids.contains(slur.startId) && ids.contains(slur.endId)) slur,
    ],
    dynamics: [
      for (final marking in score.dynamics)
        if (ids.contains(marking.elementId)) marking,
    ],
    hairpins: [
      for (final hairpin in score.hairpins)
        if (ids.contains(hairpin.startId) && ids.contains(hairpin.endId))
          hairpin,
    ],
    lyrics: [
      for (final lyric in score.lyrics)
        if (ids.contains(lyric.elementId)) lyric,
    ],
    annotations: [
      for (final annotation in score.annotations)
        if (ids.contains(annotation.elementId)) annotation,
    ],
    glissandos: [
      for (final gliss in score.glissandos)
        if (ids.contains(gliss.startId) && ids.contains(gliss.endId)) gliss,
    ],
    pedals: [
      for (final pedal in score.pedals)
        if (ids.contains(pedal.startId) && ids.contains(pedal.endId)) pedal,
    ],
    featheredBeams: [
      for (final fb in score.featheredBeams)
        if (ids.contains(fb.startId) && ids.contains(fb.endId)) fb,
    ],
    beamSlants: [
      for (final bs in score.beamSlants)
        if (ids.contains(bs.startId) && ids.contains(bs.endId)) bs,
    ],
    bends: [
      for (final bend in score.bends)
        if (ids.contains(bend.noteId)) bend,
    ],
    vibratos: [
      for (final vibrato in score.vibratos)
        if (ids.contains(vibrato.noteId)) vibrato,
    ],
    palmMutes: [
      for (final pm in score.palmMutes)
        if (ids.contains(pm.startId) && ids.contains(pm.endId)) pm,
    ],
    letRings: [
      for (final lr in score.letRings)
        if (ids.contains(lr.startId) && ids.contains(lr.endId)) lr,
    ],
    tabNoteMarks: [
      for (final tm in score.tabNoteMarks)
        if (ids.contains(tm.noteId)) tm,
    ],
    tabVoicings: [
      for (final tv in score.tabVoicings)
        if (ids.contains(tv.noteId)) tv,
    ],
    taps: [
      for (final tap in score.taps)
        if (ids.contains(tap.noteId)) tap,
    ],
    tremoloBars: [
      for (final tb in score.tremoloBars)
        if (ids.contains(tb.noteId)) tb,
    ],
    chordDiagrams: [
      for (final cd in score.chordDiagrams)
        if (ids.contains(cd.elementId)) cd,
    ],
  );
}
