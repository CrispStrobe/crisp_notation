/// Pagination: group broken systems into pages with margins and optional
/// vertical justification (page-fill).
library;

import '../model/score.dart';
import 'layout_settings.dart';
import 'multi_system.dart';

/// The page box and its margins, all in staff-space units (the caller converts
/// from physical sizes via the spatium). The content box — where systems are
/// laid out — is the page minus its margins.
class PageMetrics {
  /// Full page width in staff spaces.
  final double width;

  /// Full page height in staff spaces.
  final double height;

  /// Top margin in staff spaces.
  final double marginTop;

  /// Bottom margin in staff spaces.
  final double marginBottom;

  /// Left margin in staff spaces.
  final double marginLeft;

  /// Right margin in staff spaces.
  final double marginRight;

  /// Creates page metrics; all values are in staff spaces.
  const PageMetrics({
    required this.width,
    required this.height,
    this.marginTop = 8,
    this.marginBottom = 8,
    this.marginLeft = 8,
    this.marginRight = 8,
  })  : assert(width > 0 && height > 0, 'page must be positive'),
        assert(marginLeft + marginRight < width, 'horizontal margins too wide'),
        assert(marginTop + marginBottom < height, 'vertical margins too tall');

  /// Usable width for systems (page width minus left/right margins).
  double get contentWidth => width - marginLeft - marginRight;

  /// Usable height for systems (page height minus top/bottom margins).
  double get contentHeight => height - marginTop - marginBottom;
}

/// One system placed on a page: the [system] and its [top] offset within the
/// page's content box (staff spaces from the content-box top; add
/// [PageMetrics.marginTop] for the page-relative position).
class PositionedSystem {
  /// The laid-out system (line).
  final SystemLayout system;

  /// Distance from the content-box top to this system's top, in staff spaces.
  final double top;

  /// Creates a positioned system.
  const PositionedSystem({required this.system, required this.top});
}

/// The systems assigned to one page, with their vertical positions.
class PageLayout {
  /// The systems on this page, top to bottom.
  final List<PositionedSystem> systems;

  /// Whether this page's systems were spread to fill the content height.
  final bool justified;

  /// Creates a page layout.
  const PageLayout({required this.systems, required this.justified});
}

/// A score broken into systems and paginated.
class PagedLayout {
  /// The pages in order.
  final List<PageLayout> pages;

  /// The page box used.
  final PageMetrics metrics;

  /// The width every non-final system was justified to (== content width).
  final double systemWidth;

  /// Creates a paged layout.
  const PagedLayout({
    required this.pages,
    required this.metrics,
    required this.systemWidth,
  });
}

/// Lays [score] out into pages of [metrics]: line-broken to the content width
/// (via [layoutSystems]), then packed top-to-bottom into pages no taller than
/// the content height, with adjacent systems [systemGap] staff-spaces apart.
///
/// With [justifyVertically] (the default), every page except the last spreads
/// its systems to fill the content height (extra space shared equally between
/// the inter-system gaps); the last page and any single-system page keep the
/// natural [systemGap]. Set [justify] to false to skip horizontal
/// justification of the systems themselves.
///
/// A system taller than the content height still gets its own page rather than
/// failing.
PagedLayout layoutPages(
  Score score,
  LayoutSettings settings, {
  required PageMetrics metrics,
  double systemGap = 8,
  bool justifyVertically = true,
  bool justify = true,
}) {
  final multi = layoutSystems(score, settings,
      maxWidth: metrics.contentWidth, justify: justify);
  final contentHeight = metrics.contentHeight;

  final pages = <PageLayout>[];
  var i = 0;
  while (i < multi.systems.length) {
    // Greedy vertical packing: fill the page, keeping at least one system.
    final onPage = <SystemLayout>[];
    var used = 0.0;
    while (i < multi.systems.length) {
      final systemHeight = multi.systems[i].layout.height;
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

  return PagedLayout(
    pages: pages,
    metrics: metrics,
    systemWidth: metrics.contentWidth,
  );
}

PageLayout _positionPage(
  List<SystemLayout> onPage,
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

  final positioned = <PositionedSystem>[];
  var y = 0.0;
  for (final system in onPage) {
    positioned.add(PositionedSystem(system: system, top: y));
    y += system.layout.height + gap;
  }
  return PageLayout(systems: positioned, justified: justify && extra > 0);
}
