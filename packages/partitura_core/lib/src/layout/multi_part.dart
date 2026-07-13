/// Multi-part document model: a whole piece as N parts that line-break
/// together into multi-staff systems and paginate, with barlines spanning
/// chosen groups of parts. Generalizes the single-system [StaffSystem] to a
/// full document, and the all-or-nothing `connectBarlines` to per-group
/// [BarlineGroup] spans.
library;

import '../internal/util.dart';
import '../model/element.dart';
import '../model/score.dart';
import 'layout_engine.dart';
import 'layout_settings.dart';
import 'page_layout.dart';
import 'score_layout.dart';
import 'staff_system.dart';
import 'system_break.dart';

/// A contiguous run of parts [first]..[last] (inclusive, 0-based) whose
/// barlines are drawn through the inter-staff gaps within the group — the
/// "custom-span barline". Parts outside every group get their own per-staff
/// barlines (no connection to their neighbours).
///
/// A single group spanning all parts reproduces the old
/// `StaffSystem.connectBarlines: true` (one continuous systemic barline); a
/// document with two groups (e.g. strings connected, winds connected, but the
/// barline broken between the sections) is the feature single-part layout
/// could not express.
class BarlineGroup {
  /// First part index in the group (0-based).
  final int first;

  /// Last part index in the group (inclusive).
  final int last;

  /// Creates a barline group over parts [first]..[last].
  const BarlineGroup(this.first, this.last)
      : assert(last >= first, 'last must be >= first'),
        assert(first >= 0, 'first must be >= 0');

  /// Whether part [index] falls inside this group.
  bool contains(int index) => index >= first && index <= last;

  @override
  bool operator ==(Object other) =>
      other is BarlineGroup && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);

  @override
  String toString() => 'BarlineGroup($first..$last)';
}

/// A whole piece as N [parts] (each part a [Score] with the same measure count
/// and meter). Line-breaks into multi-staff systems and paginates as one
/// document, drawing [brackets] at the left edge and barlines per
/// [barlineGroups].
///
/// Element ids should be unique across parts so interaction stays unambiguous.
class MultiPartScore {
  /// The parts, top to bottom.
  final List<Score> parts;

  /// Bracket/brace groups drawn at the left edge (may be empty or nested).
  final List<StaffBracket> brackets;

  /// Contiguous part-index runs whose barlines connect through the group. An
  /// empty list means the barlines connect through the whole system (one
  /// implicit group over every part) — see [effectiveBarlineGroups].
  final List<BarlineGroup> barlineGroups;

  /// Creates a multi-part score from [parts] (at least one).
  const MultiPartScore(
    this.parts, {
    this.brackets = const [],
    this.barlineGroups = const [],
  }) : assert(parts.length > 0, 'a document needs at least one part');

  /// Promotes a single-system [StaffSystem] into a paginating document,
  /// preserving its barline semantics: a system with connected barlines
  /// becomes one group over all parts, and a disconnected one gives each part
  /// its own barline. Its brackets carry over unchanged. This bridges the
  /// `staffSystemFromAbc` / `staffSystemFromMusicXml` importers to the
  /// multi-part layout so imported scores line-break and paginate.
  factory MultiPartScore.fromStaffSystem(StaffSystem system) => MultiPartScore(
        system.staves,
        brackets: system.brackets,
        barlineGroups: system.connectBarlines
            ? const []
            : [
                for (var i = 0; i < system.staves.length; i++)
                  BarlineGroup(i, i)
              ],
      );

  /// The measure count shared by every part (taken from the first part).
  int get measureCount => parts.first.measures.length;

  /// The barline groups to draw: [barlineGroups] as given, or — when that is
  /// empty — a single group spanning every part (fully connected barlines,
  /// like `StaffSystem.connectBarlines: true`).
  List<BarlineGroup> get effectiveBarlineGroups => barlineGroups.isNotEmpty
      ? barlineGroups
      : [BarlineGroup(0, parts.length - 1)];

  /// This document with every transposing part shown at concert (sounding)
  /// pitch — the concert-pitch toggle. Non-transposing parts are unchanged.
  MultiPartScore atConcertPitch() => MultiPartScore(
        [for (final part in parts) part.atConcertPitch()],
        brackets: brackets,
        barlineGroups: barlineGroups,
      );

  @override
  bool operator ==(Object other) =>
      other is MultiPartScore &&
      listEquals(other.parts, parts) &&
      listEquals(other.brackets, brackets) &&
      listEquals(other.barlineGroups, barlineGroups);

  @override
  int get hashCode => Object.hash(Object.hashAll(parts),
      Object.hashAll(brackets), Object.hashAll(barlineGroups));

  @override
  String toString() => 'MultiPartScore(${parts.length} parts)';
}

/// The vertical extent of one [BarlineGroup]'s connected barlines within a
/// system, in system-space y (staff spaces from the system's coordinate
/// origin): from the top line of the group's first part to the bottom line
/// (y = 4) of its last part. The gap between one span's [bottom] and the next
/// span's [top] is exactly where the systemic barline breaks between groups.
class BarlineSpan {
  /// The group this span connects.
  final BarlineGroup group;

  /// System y of the top staff line of [BarlineGroup.first].
  final double top;

  /// System y of the bottom staff line (y = 4) of [BarlineGroup.last].
  final double bottom;

  /// Creates a barline span.
  const BarlineSpan({
    required this.group,
    required this.top,
    required this.bottom,
  });

  @override
  String toString() => 'BarlineSpan($group, $top..$bottom)';
}

/// One laid-out multi-part system: one [ScoreLayout] per part (all sharing
/// leading width, per-measure widths and total width, so barlines align),
/// stacked [staffGap] staff-spaces apart. Generalizes [StaffSystemLayout] to
/// carry the [source] document's bracket and barline-group structure, plus the
/// [firstMeasure]..[lastMeasure] range this system covers (for pagination).
class MultiPartSystemLayout {
  /// The laid-out staves actually shown on this system, top to bottom. With
  /// hide-empty this is a subset of the document's parts; [visibleParts] maps
  /// each entry back to its original index in [MultiPartScore.parts].
  final List<ScoreLayout> parts;

  /// The original [MultiPartScore.parts] index of each entry in [parts], in
  /// order. With every part shown this is `[0, 1, …, n-1]`; with hide-empty it
  /// omits the dropped parts.
  final List<int> visibleParts;

  /// Line-to-line vertical distance between adjacent parts, in staff spaces.
  final double staffGap;

  /// The source document (for its brackets and barline groups, in original
  /// part indices — remap through [visibleParts] / [visibleRange]).
  final MultiPartScore source;

  /// Index of the first original measure on this system.
  final int firstMeasure;

  /// Index of the last original measure on this system (inclusive).
  final int lastMeasure;

  /// Creates a multi-part system layout.
  const MultiPartSystemLayout({
    required this.parts,
    required this.visibleParts,
    required this.staffGap,
    required this.source,
    required this.firstMeasure,
    required this.lastMeasure,
  });

  /// The visible-index range (positions in [parts]) covered by the original
  /// part range [firstPart]..[lastPart], or null if none of those parts are
  /// shown on this system. Because [visibleParts] preserves order, a
  /// contiguous original range maps to a contiguous visible range.
  ({int first, int last})? visibleRange(int firstPart, int lastPart) {
    int? first, last;
    for (var j = 0; j < visibleParts.length; j++) {
      if (visibleParts[j] >= firstPart && visibleParts[j] <= lastPart) {
        first ??= j;
        last = j;
      }
    }
    return first == null ? null : (first: first, last: last!);
  }

  /// Shared total width in staff spaces.
  double get width => parts.first.width;

  /// The system-space y of part [i]'s top line (y = 0 in its own coords).
  double staffTop(int i) => i * (4 + staffGap);

  /// The topmost inked y (may be negative — ink above the first part).
  double get top {
    var t = double.infinity;
    for (var i = 0; i < parts.length; i++) {
      final s = staffTop(i) + parts[i].top;
      if (s < t) t = s;
    }
    return t;
  }

  /// Total inked height in staff spaces.
  double get height {
    var bottom = double.negativeInfinity;
    for (var i = 0; i < parts.length; i++) {
      final b = staffTop(i) + parts[i].top + parts[i].height;
      if (b > bottom) bottom = b;
    }
    return bottom - top;
  }

  /// The vertical extents of the systemic barlines, one [BarlineSpan] per
  /// effective barline group that has at least one visible part. A barline
  /// drawn at any x in [barlineXs] runs continuously over each span and breaks
  /// in the gap between spans. The span is clipped to the group's *visible*
  /// parts, so a group whose middle parts are hidden connects only what shows.
  List<BarlineSpan> get barlineSpans {
    final spans = <BarlineSpan>[];
    for (final group in source.effectiveBarlineGroups) {
      final range = visibleRange(group.first, group.last);
      if (range == null) continue; // whole group hidden on this system
      spans.add(BarlineSpan(
        group: group,
        top: staffTop(range.first),
        bottom: staffTop(range.last) + 4,
      ));
    }
    return spans;
  }

  /// The shared x positions (staff spaces, ascending) at which systemic
  /// barlines are drawn: the left system line at x = 0 plus every full-staff
  /// vertical barline. Because the parts share their measure widths these are
  /// identical across parts, so they are read once from the first part.
  List<double> get barlineXs {
    final xs = <double>{0.0};
    for (final line in parts.first.primitives.whereType<LinePrimitive>()) {
      final vertical = line.from.x == line.to.x;
      final fullStaff = (line.from.y == 0 && line.to.y == 4) ||
          (line.from.y == 4 && line.to.y == 0);
      if (vertical && fullStaff) xs.add(line.from.x);
    }
    return xs.toList()..sort();
  }

  @override
  String toString() => 'MultiPartSystemLayout(${parts.length} parts, measures '
      '$firstMeasure..$lastMeasure, ${width}x$height)';
}

/// Lays out one system of a [document]: each part is laid out once to find its
/// natural leading and per-measure widths, then all parts are laid out again
/// with the column-wise maxima so barlines align across every part.
///
/// [drawTimeSignature] and [finalBarline] are forwarded to the engine (the
/// line breaker in [layoutMultiPartSystems] uses them for interior systems).
/// [firstMeasure]/[lastMeasure] record which original measures this system
/// covers; they default to the whole document. When [justifyToWidth] is set
/// and the natural system is narrower, the shared measure widths are scaled
/// up uniformly to fill it — every part scales identically so barlines stay
/// aligned. An over-wide system (already past [justifyToWidth]) is left as is.
///
/// [visibleParts] selects which of the document's parts are drawn on this
/// system (their original indices, ascending) — the hide-empty case. It
/// defaults to every part; only the selected parts drive the alignment and are
/// laid out, but [source]'s brackets/groups keep their original indices (remap
/// through [MultiPartSystemLayout.visibleRange]).
///
/// Throws an [ArgumentError] if the parts disagree on measure count, or if
/// [visibleParts] is empty.
MultiPartSystemLayout layoutMultiPartSystem(
  MultiPartScore document,
  LayoutSettings settings, {
  double staffGap = 4.0,
  bool drawTimeSignature = true,
  bool finalBarline = true,
  int? firstMeasure,
  int? lastMeasure,
  double? justifyToWidth,
  List<int>? visibleParts,
}) {
  const engine = LayoutEngine();
  final visible =
      visibleParts ?? [for (var i = 0; i < document.parts.length; i++) i];
  if (visible.isEmpty) {
    throw ArgumentError.value(
        visibleParts, 'visibleParts', 'at least one part must be visible');
  }
  final shown = [for (final i in visible) document.parts[i]];
  final natural = [
    for (final part in shown)
      engine.layout(part, settings, drawTimeSignature: drawTimeSignature),
  ];

  final measureCount = natural.first.measureRegions.length;
  for (final layout in natural) {
    if (layout.measureRegions.length != measureCount) {
      throw ArgumentError('document parts must have the same measure count');
    }
  }

  double leadingOf(ScoreLayout l) =>
      l.measureRegions.isEmpty ? l.width : l.measureRegions.first.startX;
  var leading = 0.0;
  for (final l in natural) {
    leading = _max(leading, leadingOf(l));
  }

  final baseWidths = <double>[
    for (var i = 0; i < measureCount; i++)
      natural
          .map((l) => l.measureRegions[i].endX - l.measureRegions[i].startX)
          .reduce(_max),
  ];

  MultiPartSystemLayout build(List<double> widths) => MultiPartSystemLayout(
        parts: [
          for (final part in shown)
            engine.layout(
              part,
              settings,
              leadingWidth: leading,
              measureWidths: widths,
              drawTimeSignature: drawTimeSignature,
              finalBarline: finalBarline,
            ),
        ],
        visibleParts: visible,
        staffGap: staffGap,
        source: document,
        firstMeasure: firstMeasure ?? 0,
        lastMeasure: lastMeasure ?? measureCount - 1,
      );

  var layout = build(baseWidths);
  if (justifyToWidth != null &&
      measureCount > 0 &&
      layout.width < justifyToWidth) {
    // Binary-search a uniform scale on the shared measure widths to hit the
    // target width. Width is monotonic in the scale, and the leading block is
    // held fixed (only the music stretches).
    List<double> scaled(double s) => [for (final w in baseWidths) w * s];
    var low = 1.0, high = 2.0;
    for (var i = 0; i < 8 && build(scaled(high)).width < justifyToWidth; i++) {
      high *= 2;
    }
    for (var i = 0; i < 24; i++) {
      final mid = (low + high) / 2;
      final candidate = build(scaled(mid));
      if (candidate.width > justifyToWidth) {
        high = mid;
      } else {
        low = mid;
        layout = candidate;
        if (justifyToWidth - candidate.width < 0.05) break;
      }
    }
  }
  return layout;
}

/// A multi-part document broken into systems (every system spans the same
/// measure range across all parts).
class MultiPartMultiSystemLayout {
  /// The systems, top to bottom.
  final List<MultiPartSystemLayout> systems;

  /// The width every non-final system was justified to.
  final double maxWidth;

  /// Creates a multi-system layout.
  const MultiPartMultiSystemLayout({
    required this.systems,
    required this.maxWidth,
  });

  /// Total height in staff spaces when systems are stacked [systemGap] spaces
  /// apart (bounding box to bounding box).
  double heightWith(double systemGap) {
    var height = 0.0;
    for (final system in systems) {
      height += system.height;
    }
    return height + systemGap * (systems.length - 1);
  }

  @override
  String toString() => 'MultiPartMultiSystemLayout(${systems.length} systems)';
}

/// Breaks [document] into systems no wider than [maxWidth] staff spaces. Every
/// system spans the same measure range across all parts (the break points are
/// shared), driven by the combined per-measure widths (max across parts) so a
/// bar that is wide in any one part reserves that width in all of them. Every
/// system but the last is justified to [maxWidth] (disable with [justify]);
/// the last closes with the end-of-document barline.
///
/// A measure wider than [maxWidth] gets its own (over-wide) system rather than
/// failing.
///
/// With [hideEmptyStaves], a part whose measures over a system's range are
/// entirely rests (or a multi-measure rest) is dropped from that system — the
/// standard orchestral space-saver. The first system always shows every part
/// (so the full instrumentation reads once), and a system that would otherwise
/// be blank keeps all its parts. Brackets and barline groups clip to the parts
/// that remain (see [MultiPartSystemLayout.visibleParts]).
///
/// Throws an [ArgumentError] if the parts disagree on measure count or
/// [maxWidth] is not positive.
MultiPartMultiSystemLayout layoutMultiPartSystems(
  MultiPartScore document,
  LayoutSettings settings, {
  required double maxWidth,
  double staffGap = 4.0,
  bool justify = true,
  bool hideEmptyStaves = false,
}) {
  if (maxWidth <= 0) {
    throw ArgumentError.value(maxWidth, 'maxWidth', 'must be positive');
  }
  const engine = LayoutEngine();
  final parts = document.parts;
  final measureCount = document.measureCount;
  for (final part in parts) {
    if (part.measures.length != measureCount) {
      throw ArgumentError('document parts must have the same measure count');
    }
  }
  if (measureCount == 0) {
    return MultiPartMultiSystemLayout(systems: const [], maxWidth: maxWidth);
  }

  final states = [for (final part in parts) SystemBreakState.of(part)];
  final naturals = [for (final part in parts) engine.layout(part, settings)];

  var finalBarAllowance = 0.0;
  for (final n in naturals) {
    finalBarAllowance =
        _max(finalBarAllowance, n.width - n.measureRegions.last.endX);
  }

  // The combined leading (clef/key/time restatement) for a system starting at
  // measure [start]: the widest such block over all parts.
  double combinedLeadingAt(int start) {
    var leading = 0.0;
    for (var pi = 0; pi < parts.length; pi++) {
      final probe = engine.layout(
        sliceScore(parts[pi], start, start, states[pi]),
        settings,
        drawTimeSignature: drawsTimeAt(parts[pi], start),
      );
      leading = _max(leading, probe.measureRegions.first.startX);
    }
    return leading;
  }

  // The combined content extent of measures [start]..[end]: the widest such
  // run over all parts (natural cumulative extents already include the
  // interior barlines and spacing).
  double spanContent(int start, int end) {
    var w = 0.0;
    for (final n in naturals) {
      w = _max(w, n.measureRegions[end].endX - n.measureRegions[start].startX);
    }
    return w;
  }

  MultiPartScore sliceDoc(int start, int end) => MultiPartScore(
        [
          for (var pi = 0; pi < parts.length; pi++)
            sliceScore(parts[pi], start, end, states[pi]),
        ],
        brackets: document.brackets,
        barlineGroups: document.barlineGroups,
      );

  // The parts to show on the system covering [start]..[end]: with hide-empty,
  // parts silent throughout the range are dropped, except on the first system
  // and unless every part is silent (a blank system keeps them all).
  List<int>? visibleFor(int start, int end) {
    if (!hideEmptyStaves || start == 0) return null;
    final visible = [
      for (var pi = 0; pi < parts.length; pi++)
        if (!_isSilentRange(parts[pi], start, end)) pi,
    ];
    if (visible.isEmpty || visible.length == parts.length) return null;
    return visible;
  }

  final systems = <MultiPartSystemLayout>[];
  var start = 0;
  while (start < measureCount) {
    // Greedy packing on the combined-width estimate; the first bar always
    // goes on the line, even over-wide.
    final leading = combinedLeadingAt(start);
    var end = start;
    while (end + 1 < measureCount &&
        leading + spanContent(start, end + 1) + finalBarAllowance <= maxWidth) {
      end++;
    }
    final drawTime =
        start == 0 || parts.any((p) => p.measures[start].timeChange != null);

    MultiPartSystemLayout layoutTo(int e, {double? justifyToWidth}) =>
        layoutMultiPartSystem(
          sliceDoc(start, e),
          settings,
          staffGap: staffGap,
          drawTimeSignature: drawTime,
          finalBarline: e == measureCount - 1,
          firstMeasure: start,
          lastMeasure: e,
          justifyToWidth: justifyToWidth,
          visibleParts: visibleFor(start, e),
        );

    var layout = layoutTo(end);
    // Safety trim: push measures to the next system rather than overflow.
    while (layout.width > maxWidth && end > start) {
      end--;
      layout = layoutTo(end);
    }
    final isLastSystem = end == measureCount - 1;
    if (justify && !isLastSystem && layout.width < maxWidth) {
      layout = layoutTo(end, justifyToWidth: maxWidth);
    }
    systems.add(layout);
    start = end + 1;
  }
  return MultiPartMultiSystemLayout(systems: systems, maxWidth: maxWidth);
}

/// One multi-part system placed on a page: the [system] and its [top] offset
/// within the page's content box (staff spaces from the content-box top).
class PositionedMultiPartSystem {
  /// The laid-out system (line).
  final MultiPartSystemLayout system;

  /// Distance from the content-box top to this system's top, in staff spaces.
  final double top;

  /// Creates a positioned system.
  const PositionedMultiPartSystem({required this.system, required this.top});
}

/// The multi-part systems assigned to one page, with their vertical positions.
class MultiPartPageLayout {
  /// The systems on this page, top to bottom.
  final List<PositionedMultiPartSystem> systems;

  /// Whether this page's systems were spread to fill the content height.
  final bool justified;

  /// Creates a page layout.
  const MultiPartPageLayout({required this.systems, required this.justified});
}

/// A multi-part document broken into systems and paginated.
class MultiPartPagedLayout {
  /// The pages in order.
  final List<MultiPartPageLayout> pages;

  /// The page box used.
  final PageMetrics metrics;

  /// The width every non-final system was justified to (== content width).
  final double systemWidth;

  /// Creates a paged layout.
  const MultiPartPagedLayout({
    required this.pages,
    required this.metrics,
    required this.systemWidth,
  });
}

/// Lays [document] out into pages of [metrics]: line-broken to the content
/// width (via [layoutMultiPartSystems]), then packed top-to-bottom into pages
/// no taller than the content height, with adjacent systems [systemGap]
/// staff-spaces apart.
///
/// With [justifyVertically] (the default), every page except the last spreads
/// its systems to fill the content height; the last page and any single-system
/// page keep the natural [systemGap]. Set [justify] to false to skip
/// horizontal justification of the systems themselves.
///
/// A system taller than the content height still gets its own page rather than
/// failing. [hideEmptyStaves] is forwarded to [layoutMultiPartSystems].
MultiPartPagedLayout layoutMultiPartPages(
  MultiPartScore document,
  LayoutSettings settings, {
  required PageMetrics metrics,
  double staffGap = 4.0,
  double systemGap = 8,
  bool justifyVertically = true,
  bool justify = true,
  bool hideEmptyStaves = false,
}) {
  final multi = layoutMultiPartSystems(document, settings,
      maxWidth: metrics.contentWidth,
      staffGap: staffGap,
      justify: justify,
      hideEmptyStaves: hideEmptyStaves);
  final contentHeight = metrics.contentHeight;

  final pages = <MultiPartPageLayout>[];
  var i = 0;
  while (i < multi.systems.length) {
    // Greedy vertical packing: fill the page, keeping at least one system.
    final onPage = <MultiPartSystemLayout>[];
    var used = 0.0;
    while (i < multi.systems.length) {
      final systemHeight = multi.systems[i].height;
      final needed =
          onPage.isEmpty ? systemHeight : used + systemGap + systemHeight;
      if (onPage.isNotEmpty && needed > contentHeight) break;
      onPage.add(multi.systems[i]);
      used = needed;
      i++;
    }
    final isLastPage = i >= multi.systems.length;
    final doJustify = justifyVertically && !isLastPage && onPage.length >= 2;
    pages.add(_positionPage(onPage, contentHeight, systemGap, doJustify));
  }

  return MultiPartPagedLayout(
    pages: pages,
    metrics: metrics,
    systemWidth: metrics.contentWidth,
  );
}

MultiPartPageLayout _positionPage(
  List<MultiPartSystemLayout> onPage,
  double contentHeight,
  double systemGap,
  bool justify,
) {
  final naturalHeight = onPage.fold<double>(0, (h, s) => h + s.height) +
      systemGap * (onPage.length - 1);
  final extra = justify ? (contentHeight - naturalHeight) : 0.0;
  // Spread any surplus equally across the inter-system gaps.
  final gap = onPage.length > 1
      ? systemGap + (extra > 0 ? extra / (onPage.length - 1) : 0)
      : systemGap;

  final positioned = <PositionedMultiPartSystem>[];
  var y = 0.0;
  for (final system in onPage) {
    positioned.add(PositionedMultiPartSystem(system: system, top: y));
    y += system.height + gap;
  }
  return MultiPartPageLayout(
      systems: positioned, justified: justify && extra > 0);
}

double _max(double a, double b) => a > b ? a : b;

/// Whether [part] is silent across measures [start]..[end]: every voice-1 and
/// voice-2 element is a rest (a multi-measure rest counts as silent, and by
/// the model already has empty voices).
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
