/// Multi-part document model: a whole piece as N parts that line-break together
/// into multi-staff systems and paginate, with barlines spanning chosen groups
/// of parts.
///
/// This is a thin *document* layer over the layout primitives: a
/// [MultiPartScore] promotes to a [StaffSystem] and delegates line-breaking to
/// [layoutStaffSystemSystems] (so barlines align across parts and non-final
/// systems justify) and pagination to [layoutMultiPartPages]. The per-group
/// [BarlineGroup] "custom-span barline" lives on [StaffSystem]; this layer adds
/// the document semantics (a shared measure count, the importer bridge, the
/// concert-pitch toggle) and page assembly.
library;

import '../internal/util.dart';
import '../model/score.dart';
import 'layout_settings.dart';
import 'multi_system.dart';
import 'page_layout.dart';
import 'staff_system.dart';

/// A whole piece as N [parts] (each a [Score] with the same measure count and
/// meter). Line-breaks into multi-staff systems and paginates as one document,
/// drawing [brackets] at the left edge and barlines per [barlineGroups].
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
  /// preserving its barline semantics: a system with connected barlines becomes
  /// one group over all parts (empty [barlineGroups]), and a disconnected one
  /// gives each part its own barline. Its brackets carry over unchanged. This
  /// bridges the `staffSystemFromAbc` / `staffSystemFromMusicXml` importers to
  /// the multi-part layout so imported scores line-break and paginate.
  factory MultiPartScore.fromStaffSystem(StaffSystem system) => MultiPartScore(
        system.staves,
        brackets: system.brackets,
        barlineGroups: system.barlineGroups.isNotEmpty
            ? system.barlineGroups
            : system.connectBarlines
                ? const []
                : [
                    for (var i = 0; i < system.staves.length; i++)
                      BarlineGroup(i, i)
                  ],
      );

  /// The measure count shared by every part (taken from the first part).
  int get measureCount => parts.first.measures.length;

  /// The barline groups to draw: [barlineGroups] as given, or — when that is
  /// empty — a single group spanning every part (fully connected barlines).
  List<BarlineGroup> get effectiveBarlineGroups => barlineGroups.isNotEmpty
      ? barlineGroups
      : [BarlineGroup(0, parts.length - 1)];

  /// This document promoted to the layout primitive: an N-staff [StaffSystem]
  /// carrying the same parts, brackets and barline groups. Line-breaking and
  /// pagination run on top of this.
  StaffSystem toStaffSystem() => StaffSystem(
        parts,
        brackets: brackets,
        barlineGroups: barlineGroups,
      );

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

/// One multi-part system placed on a page: the [system] (a line broken by
/// [layoutStaffSystemSystems]) and its [top] offset within the page's content
/// box (staff spaces from the content-box top; add [PageMetrics.marginTop] for
/// the page-relative position).
class PositionedMultiPartSystem {
  /// The laid-out system (line).
  final StaffSystemSystem system;

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
/// width (via [layoutStaffSystemSystems]), then packed top-to-bottom into pages
/// no taller than the content height, with adjacent systems [systemGap]
/// staff-spaces apart.
///
/// With [justifyVertically] (the default), every page except the last spreads
/// its systems to fill the content height; the last page and any single-system
/// page keep the natural [systemGap]. Set [justify] to false to skip
/// horizontal justification of the systems themselves. [hideEmptyStaves] is
/// forwarded to [layoutStaffSystemSystems].
///
/// A system taller than the content height still gets its own page rather than
/// failing.
MultiPartPagedLayout layoutMultiPartPages(
  MultiPartScore document,
  LayoutSettings settings, {
  required PageMetrics metrics,
  double staffGap = 4.0,
  double systemGap = 8,
  bool justifyVertically = true,
  bool justify = true,
  bool hideEmptyStaves = false,
  bool showNoteNames = false,
  NoteNameStyle noteNameStyle = NoteNameStyle.letter,
}) {
  final wrapped = layoutStaffSystemSystems(
    document.toStaffSystem(),
    settings,
    maxWidth: metrics.contentWidth,
    staffGap: staffGap,
    justify: justify,
    hideEmptyStaves: hideEmptyStaves,
    showNoteNames: showNoteNames,
    noteNameStyle: noteNameStyle,
  );
  final contentHeight = metrics.contentHeight;

  final pages = <MultiPartPageLayout>[];
  var i = 0;
  while (i < wrapped.systems.length) {
    // Greedy vertical packing: fill the page, keeping at least one system.
    final onPage = <StaffSystemSystem>[];
    var used = 0.0;
    while (i < wrapped.systems.length) {
      final systemHeight = wrapped.systems[i].layout.height;
      final needed =
          onPage.isEmpty ? systemHeight : used + systemGap + systemHeight;
      if (onPage.isNotEmpty && needed > contentHeight) break;
      onPage.add(wrapped.systems[i]);
      used = needed;
      i++;
    }
    final isLastPage = i >= wrapped.systems.length;
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
  List<StaffSystemSystem> onPage,
  double contentHeight,
  double systemGap,
  bool justify,
) {
  final naturalHeight = onPage.fold<double>(0, (h, s) => h + s.layout.height) +
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
    y += system.layout.height + gap;
  }
  return MultiPartPageLayout(
      systems: positioned, justified: justify && extra > 0);
}
