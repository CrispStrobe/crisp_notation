// Flutter also defines a PageMetrics (scroll metrics); we mean the engraving
// one from crisp_notation_core.
import 'dart:math' as math;

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter/widgets.dart' hide PageMetrics;

import 'layout_painter.dart';
import 'music_font.dart';
import 'theme.dart';

/// Renders one page of a paginated [Score] at a fixed [PageMetrics] size —
/// print / page-preview style.
///
/// Pagination comes from `crisp_notation_core`'s [layoutPages]: the score is
/// line-broken to the content width, packed into pages no taller than the
/// content height, and (by default) vertically justified so every page but the
/// last fills its content box. This widget paints the single page [pageIndex]
/// at its exact page aspect ratio, with the margins from [metrics].
class ScorePageView extends LeafRenderObjectWidget {
  /// The score to paginate and render.
  final Score score;

  /// The page box (size + margins, in staff spaces).
  final PageMetrics metrics;

  /// Colors and ergonomics.
  final CrispNotationTheme theme;

  /// Pixels per staff space.
  final double staffSpace;

  /// Natural distance between systems, in staff spaces (before justification).
  final double systemGap;

  /// Whether to vertically justify all but the last page.
  final bool justifyVertically;

  /// Which page to paint (0-based; out-of-range paints an empty page).
  final int pageIndex;

  /// Whether to stroke a thin frame around the page edge.
  final bool drawPageBorder;

  /// Whether to draw a system divider (a pair of slashes in the left margin)
  /// in the gap above each system after the first — the engraver's cue that a
  /// new system begins, for busy multi-system pages.
  final bool showSystemDividers;

  /// Creates a page view.
  const ScorePageView({
    super.key,
    required this.score,
    required this.metrics,
    this.theme = CrispNotationTheme.standard,
    this.staffSpace = 8,
    this.systemGap = 8,
    this.justifyVertically = true,
    this.pageIndex = 0,
    this.drawPageBorder = false,
    this.showSystemDividers = false,
  });

  @override
  RenderScorePageView createRenderObject(BuildContext context) =>
      RenderScorePageView(
        score: score,
        metrics: metrics,
        theme: theme,
        staffSpace: staffSpace,
        systemGap: systemGap,
        justifyVertically: justifyVertically,
        pageIndex: pageIndex,
        drawPageBorder: drawPageBorder,
        showSystemDividers: showSystemDividers,
      );

  @override
  void updateRenderObject(
      BuildContext context, RenderScorePageView renderObject) {
    renderObject
      ..score = score
      ..metrics = metrics
      ..theme = theme
      ..staffSpace = staffSpace
      ..systemGap = systemGap
      ..justifyVertically = justifyVertically
      ..pageIndex = pageIndex
      ..drawPageBorder = drawPageBorder
      ..showSystemDividers = showSystemDividers;
  }
}

/// Render object behind [ScorePageView].
class RenderScorePageView extends RenderBox {
  /// Creates the render object.
  RenderScorePageView({
    required Score score,
    required PageMetrics metrics,
    required CrispNotationTheme theme,
    required double staffSpace,
    required double systemGap,
    required bool justifyVertically,
    required int pageIndex,
    required bool drawPageBorder,
    bool showSystemDividers = false,
  })  : _score = score,
        _metrics = metrics,
        _theme = theme,
        _staffSpace = staffSpace,
        _systemGap = systemGap,
        _justifyVertically = justifyVertically,
        _pageIndex = pageIndex,
        _drawPageBorder = drawPageBorder,
        _showSystemDividers = showSystemDividers;

  PagedLayout? _layout;
  late final LayoutPainter _painter =
      LayoutPainter(theme: _theme, scale: _staffSpace);

  Score _score;

  /// The score to render.
  Score get score => _score;
  set score(Score value) {
    if (value == _score) return;
    _score = value;
    markNeedsLayout();
  }

  PageMetrics _metrics;

  /// The page box.
  PageMetrics get metrics => _metrics;
  set metrics(PageMetrics value) {
    if (value == _metrics) return;
    _metrics = value;
    markNeedsLayout();
  }

  CrispNotationTheme _theme;

  /// Colors and ergonomics.
  CrispNotationTheme get theme => _theme;
  set theme(CrispNotationTheme value) {
    if (value == _theme) return;
    _theme = value;
    _painter.theme = value;
    _painter.clearCache();
    markNeedsLayout();
  }

  double _staffSpace;

  /// Pixels per staff space.
  double get staffSpace => _staffSpace;
  set staffSpace(double value) {
    if (value == _staffSpace) return;
    _staffSpace = value;
    markNeedsLayout();
  }

  double _systemGap;

  /// Natural distance between systems.
  double get systemGap => _systemGap;
  set systemGap(double value) {
    if (value == _systemGap) return;
    _systemGap = value;
    markNeedsLayout();
  }

  bool _justifyVertically;

  /// Whether to vertically justify all but the last page.
  bool get justifyVertically => _justifyVertically;
  set justifyVertically(bool value) {
    if (value == _justifyVertically) return;
    _justifyVertically = value;
    markNeedsLayout();
  }

  int _pageIndex;

  /// Which page to paint.
  int get pageIndex => _pageIndex;
  set pageIndex(int value) {
    if (value == _pageIndex) return;
    _pageIndex = value;
    markNeedsPaint();
  }

  bool _drawPageBorder;

  /// Whether to stroke the page frame.
  bool get drawPageBorder => _drawPageBorder;
  set drawPageBorder(bool value) {
    if (value == _drawPageBorder) return;
    _drawPageBorder = value;
    markNeedsPaint();
  }

  bool _showSystemDividers;

  /// Whether to draw a system divider above each system after the first.
  bool get showSystemDividers => _showSystemDividers;
  set showSystemDividers(bool value) {
    if (value == _showSystemDividers) return;
    _showSystemDividers = value;
    markNeedsPaint();
  }

  /// The paginated layout, or null while the font metadata is loading.
  PagedLayout? get pagedLayout => _layout;

  /// The number of pages (0 while the font metadata is loading).
  int get pageCount => _layout?.pages.length ?? 0;

  Size _measure(BoxConstraints constraints) {
    final metadata = MusicFonts.metadataOrNull(_theme.musicFont);
    if (metadata == null) {
      _layout = null;
    } else {
      _layout = layoutPages(
        _score,
        LayoutSettings(
            metadata: metadata, fingeringPlacement: _theme.fingeringPlacement),
        metrics: _metrics,
        systemGap: _systemGap,
        justifyVertically: _justifyVertically,
      );
    }
    return constraints.constrain(
        Size(_metrics.width * _staffSpace, _metrics.height * _staffSpace));
  }

  @override
  void performLayout() {
    if (MusicFonts.metadataOrNull(_theme.musicFont) == null) {
      MusicFonts.load(_theme.musicFont).then((_) {
        if (attached) markNeedsLayout();
      });
    }
    _painter.clearCache();
    _painter.scale = _staffSpace;
    size = _measure(constraints);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _measure(constraints);

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    if (_drawPageBorder) {
      canvas.drawRect(
        offset &
            Size(_metrics.width * _staffSpace, _metrics.height * _staffSpace),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.1 * _staffSpace
          ..color = _theme.staffColor.withValues(alpha: 0.4),
      );
    }
    final layout = _layout;
    if (layout == null) return;
    if (_pageIndex < 0 || _pageIndex >= layout.pages.length) return;
    final page = layout.pages[_pageIndex];
    for (var i = 0; i < page.systems.length; i++) {
      final placed = page.systems[i];
      // Content-box top-left, then the system's position, less the layout's
      // own top offset (systems may reach above their staff's top line).
      final originX = _metrics.marginLeft * _staffSpace;
      final originY =
          (_metrics.marginTop + placed.top - placed.system.layout.top) *
              _staffSpace;
      _painter.paintLayout(
          canvas, offset + Offset(originX, originY), placed.system.layout);
      // A system divider in the gap above each system after the first, in the
      // left margin — the page's staff-space (0,0) is the page-box top-left.
      if (_showSystemDividers && i > 0) {
        final prev = page.systems[i - 1];
        final gapTop =
            _metrics.marginTop + prev.top + prev.system.layout.height;
        final gapMidY = (gapTop + _metrics.marginTop + placed.top) / 2;
        _painter.paintGlyph(
          canvas,
          offset,
          SmuflGlyph.systemDivider,
          math.Point(_metrics.marginLeft - 3.0, gapMidY),
          _theme.staffColor,
        );
      }
    }
  }
}
