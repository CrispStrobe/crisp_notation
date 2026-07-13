import 'dart:math' as math;

// Flutter also defines a PageMetrics (scroll metrics); we mean the engraving
// one from partitura_core.
import 'package:flutter/widgets.dart' hide PageMetrics;
import 'package:partitura_core/partitura_core.dart';

import 'layout_painter.dart';
import 'music_font.dart';
import 'theme.dart';

/// Renders one page of a paginated [MultiPartScore] — a whole multi-part piece
/// (N parts line-broken together into multi-staff systems and paginated) at a
/// fixed [PageMetrics] box.
///
/// Generalizes [ScorePageView] to many parts and [StaffSystemView] to a paged
/// document: every system spans the same measure range across all parts, with
/// bracket/brace groups at the left edge and barlines drawn per
/// [BarlineGroup] — a systemic barline runs continuously through a group and
/// breaks in the gap between groups (the custom-span barline).
class MultiPartView extends LeafRenderObjectWidget {
  /// The multi-part document to paginate and render.
  final MultiPartScore document;

  /// The page box (size + margins, in staff spaces).
  final PageMetrics metrics;

  /// Colors and ergonomics.
  final PartituraTheme theme;

  /// Pixels per staff space.
  final double staffSpace;

  /// Line-to-line vertical distance between adjacent parts, in staff spaces.
  final double staffGap;

  /// Natural distance between systems, in staff spaces (before justification).
  final double systemGap;

  /// Whether to vertically justify all but the last page.
  final bool justifyVertically;

  /// Which page to paint (0-based; out-of-range paints an empty page).
  final int pageIndex;

  /// Whether to stroke a thin frame around the page edge.
  final bool drawPageBorder;

  /// Creates a multi-part page view.
  const MultiPartView({
    super.key,
    required this.document,
    required this.metrics,
    this.theme = PartituraTheme.standard,
    this.staffSpace = 8,
    this.staffGap = 4,
    this.systemGap = 10,
    this.justifyVertically = true,
    this.pageIndex = 0,
    this.drawPageBorder = false,
  });

  @override
  RenderMultiPartView createRenderObject(BuildContext context) =>
      RenderMultiPartView(
        document: document,
        metrics: metrics,
        theme: theme,
        staffSpace: staffSpace,
        staffGap: staffGap,
        systemGap: systemGap,
        justifyVertically: justifyVertically,
        pageIndex: pageIndex,
        drawPageBorder: drawPageBorder,
      );

  @override
  void updateRenderObject(
      BuildContext context, RenderMultiPartView renderObject) {
    renderObject
      ..document = document
      ..metrics = metrics
      ..theme = theme
      ..staffSpace = staffSpace
      ..staffGap = staffGap
      ..systemGap = systemGap
      ..justifyVertically = justifyVertically
      ..pageIndex = pageIndex
      ..drawPageBorder = drawPageBorder;
  }
}

/// Render object behind [MultiPartView].
class RenderMultiPartView extends RenderBox {
  /// Creates the render object.
  RenderMultiPartView({
    required MultiPartScore document,
    required PageMetrics metrics,
    required PartituraTheme theme,
    required double staffSpace,
    required double staffGap,
    required double systemGap,
    required bool justifyVertically,
    required int pageIndex,
    required bool drawPageBorder,
  })  : _document = document,
        _metrics = metrics,
        _theme = theme,
        _staffSpace = staffSpace,
        _staffGap = staffGap,
        _systemGap = systemGap,
        _justifyVertically = justifyVertically,
        _pageIndex = pageIndex,
        _drawPageBorder = drawPageBorder;

  /// Space reserved at the left for brackets/braces, in staff spaces — drawn
  /// into the left page margin, left of the system's x = 0.
  static const double leftInset = 1.8;

  MultiPartPagedLayout? _layout;
  late final LayoutPainter _painter =
      LayoutPainter(theme: _theme, scale: _staffSpace);

  MultiPartScore _document;

  /// The document to render.
  MultiPartScore get document => _document;
  set document(MultiPartScore value) {
    if (value == _document) return;
    _document = value;
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

  PartituraTheme _theme;

  /// Colors and ergonomics.
  PartituraTheme get theme => _theme;
  set theme(PartituraTheme value) {
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

  double _staffGap;

  /// Line-to-line vertical distance between adjacent parts.
  double get staffGap => _staffGap;
  set staffGap(double value) {
    if (value == _staffGap) return;
    _staffGap = value;
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

  /// The paginated layout, or null while the font metadata is loading.
  MultiPartPagedLayout? get pagedLayout => _layout;

  /// The number of pages (0 while the font metadata is loading).
  int get pageCount => _layout?.pages.length ?? 0;

  Size _measure(BoxConstraints constraints) {
    final metadata = MusicFonts.metadataOrNull(_theme.musicFont);
    if (metadata == null) {
      _layout = null;
    } else {
      _layout = layoutMultiPartPages(
        _document,
        LayoutSettings(metadata: metadata),
        metrics: _metrics,
        staffGap: _staffGap,
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
    final originX = offset.dx + _metrics.marginLeft * _staffSpace;
    for (final placed in page.systems) {
      final system = placed.system;
      // Content-box top for this system's coordinate origin (its own `top`
      // may reach above the first part's top line).
      final systemTopY = offset.dy +
          (_metrics.marginTop + placed.top - system.top) * _staffSpace;

      // Per-part y where that part's own y = 0 (top line) maps.
      double partOriginY(int i) =>
          systemTopY + system.staffTop(i) * _staffSpace;

      for (var i = 0; i < system.parts.length; i++) {
        _painter.paintLayout(
            canvas, Offset(originX, partOriginY(i)), system.parts[i]);
      }
      _paintBarlineGroups(canvas, system, originX, partOriginY);
      _paintBrackets(canvas, system, originX, partOriginY);
    }
  }

  /// Draws the systemic barlines for each [BarlineGroup]: a vertical line at
  /// every barline x, running from the group's first part's top line to its
  /// last part's bottom line — so it connects within a group and breaks in the
  /// gap between groups. Single-part or no-group documents connect through all.
  void _paintBarlineGroups(
    Canvas canvas,
    MultiPartSystemLayout system,
    double originX,
    double Function(int) partOriginY,
  ) {
    if (system.parts.length < 2) return;
    final barPaint = Paint()..color = _theme.staffColor;

    // Barline x positions and thicknesses, read once from the first part
    // (all parts share their measure widths, so these match across parts).
    final ref = system.parts.first.primitives.whereType<LinePrimitive>();
    final startThickness = ref.isEmpty ? 0.13 : ref.first.thickness;
    final bars = <({double x, double thickness})>[
      (x: 0.0, thickness: startThickness), // the systemic left line
      for (final line in ref)
        if (line.from.x == line.to.x &&
            ((line.from.y == 0 && line.to.y == 4) ||
                (line.from.y == 4 && line.to.y == 0)))
          (x: line.from.x, thickness: line.thickness),
    ];

    for (final span in system.barlineSpans) {
      final topY = partOriginY(span.group.first); // first part's y = 0
      final bottomY = partOriginY(span.group.last) + 4 * _staffSpace;
      for (final bar in bars) {
        final x = originX + bar.x * _staffSpace;
        canvas.drawLine(Offset(x, topY), Offset(x, bottomY),
            barPaint..strokeWidth = bar.thickness * _staffSpace);
      }
    }
  }

  /// How many other brackets strictly contain [b] — its nesting depth.
  int _depthOf(MultiPartSystemLayout system, StaffBracket b) =>
      system.source.brackets
          .where((a) =>
              !identical(a, b) &&
              a.first <= b.first &&
              b.last <= a.last &&
              (a.last - a.first) > (b.last - b.first))
          .length;

  void _paintBrackets(
    Canvas canvas,
    MultiPartSystemLayout system,
    double originX,
    double Function(int) partOriginY,
  ) {
    final brackets = system.source.brackets;
    if (brackets.isEmpty) return;
    const step = 0.6; // staff spaces per nesting level
    final maxDepth = brackets
        .map((b) => _depthOf(system, b))
        .fold(0, (m, d) => d > m ? d : m);
    for (final group in brackets) {
      final shift = (maxDepth - _depthOf(system, group)) * step * _staffSpace;
      final top = partOriginY(group.first);
      final bottom = partOriginY(group.last) + 4 * _staffSpace;
      if (group.kind == StaffBracketKind.brace) {
        final box =
            MusicFonts.metadataOrNull(_theme.musicFont)?.bBoxOf('brace');
        if (box != null) {
          final span =
              system.staffTop(group.last) + 4 - system.staffTop(group.first);
          _painter.paintGlyph(
            canvas,
            Offset(originX - shift, partOriginY(group.last)),
            'brace',
            math.Point(-leftInset + 0.35, 4.0),
            _theme.staffColor,
            glyphScale: span / box.height,
          );
        }
      } else {
        // A square bracket: a thick line just left of the parts, with short
        // horizontal serifs top and bottom.
        final bx = originX - 0.5 * _staffSpace - shift;
        final paint = Paint()
          ..color = _theme.staffColor
          ..strokeWidth = 0.4 * _staffSpace;
        canvas.drawLine(Offset(bx, top), Offset(bx, bottom), paint);
        final serif = Paint()
          ..color = _theme.staffColor
          ..strokeWidth = 0.16 * _staffSpace;
        canvas.drawLine(
            Offset(bx, top), Offset(bx + 0.6 * _staffSpace, top), serif);
        canvas.drawLine(
            Offset(bx, bottom), Offset(bx + 0.6 * _staffSpace, bottom), serif);
      }
    }
  }
}
