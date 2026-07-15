import 'dart:math' as math;

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
// Flutter also defines a PageMetrics (scroll metrics); we mean the engraving
// one from crisp_notation_core.
import 'package:flutter/widgets.dart' hide PageMetrics;

import '../interaction/editor_caret.dart';
import '../interaction/element_region_controller.dart';
import '../interaction/staff_target.dart';
import 'layout_painter.dart';
import 'music_font.dart';
import 'theme.dart';

/// Renders one page of a paginated [MultiPartScore] — a whole multi-part piece
/// (N parts line-broken together into multi-staff systems and paginated) at a
/// fixed [PageMetrics] box.
///
/// Generalizes [ScorePageView] to many parts and [StaffSystemView] to a paged
/// document: every system spans the same measure range across all parts, with
/// bracket/brace groups at the left edge and barlines drawn per [BarlineGroup]
/// — a systemic barline runs continuously through a group and breaks in the gap
/// between groups (the custom-span barline). Layout runs on the shared
/// [layoutMultiPartPages] (which line-breaks via `layoutStaffSystemSystems`).
class MultiPartView extends LeafRenderObjectWidget {
  /// The multi-part document to paginate and render.
  final MultiPartScore document;

  /// The page box (size + margins, in staff spaces).
  final PageMetrics metrics;

  /// Colors and ergonomics.
  final CrispNotationTheme theme;

  /// Pixels per staff space.
  final double staffSpace;

  /// Line-to-line vertical distance between adjacent parts, in staff spaces.
  final double staffGap;

  /// Natural distance between systems, in staff spaces (before justification).
  final double systemGap;

  /// Whether to vertically justify all but the last page.
  final bool justifyVertically;

  /// Whether to drop parts that are entirely rests over a system's range (the
  /// first system always shows every part). See [layoutStaffSystemSystems].
  final bool hideEmptyStaves;

  /// Which page to paint (0-based; out-of-range paints an empty page).
  final int pageIndex;

  /// Whether to stroke a thin frame around the page edge.
  final bool drawPageBorder;

  /// Called with the element id when the user taps an element on the current
  /// page. Ids come from any part; keep them unique across parts.
  final void Function(String elementId)? onElementTap;

  /// Creates a multi-part page view.
  const MultiPartView({
    super.key,
    required this.document,
    required this.metrics,
    this.theme = CrispNotationTheme.standard,
    this.staffSpace = 8,
    this.staffGap = 4,
    this.systemGap = 10,
    this.justifyVertically = true,
    this.hideEmptyStaves = false,
    this.pageIndex = 0,
    this.drawPageBorder = false,
    this.onElementTap,
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
        hideEmptyStaves: hideEmptyStaves,
        pageIndex: pageIndex,
        drawPageBorder: drawPageBorder,
      )..onElementTap = onElementTap;

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
      ..hideEmptyStaves = hideEmptyStaves
      ..pageIndex = pageIndex
      ..drawPageBorder = drawPageBorder
      ..onElementTap = onElementTap;
  }
}

/// Render object behind [MultiPartView].
class RenderMultiPartView extends RenderBox implements ElementRegionProvider {
  /// Creates the render object.
  RenderMultiPartView({
    required MultiPartScore document,
    required PageMetrics metrics,
    required CrispNotationTheme theme,
    required double staffSpace,
    required double staffGap,
    required double systemGap,
    required bool justifyVertically,
    required bool hideEmptyStaves,
    required int pageIndex,
    required bool drawPageBorder,
  })  : _document = document,
        _metrics = metrics,
        _theme = theme,
        _staffSpace = staffSpace,
        _staffGap = staffGap,
        _systemGap = systemGap,
        _justifyVertically = justifyVertically,
        _hideEmptyStaves = hideEmptyStaves,
        _pageIndex = pageIndex,
        _drawPageBorder = drawPageBorder {
    _tap = TapGestureRecognizer(debugOwner: this)..onTapUp = _handleTapUp;
  }

  /// Space reserved at the left for brackets/braces, in staff spaces — drawn
  /// into the left page margin, left of the system's x = 0.
  static const double leftInset = 1.8;

  late final TapGestureRecognizer _tap;

  /// Called with the element id when the user taps an element on the current
  /// page.
  void Function(String elementId)? onElementTap;

  /// Called when a tap lands on empty staff space: the part index it fell in and
  /// the quantized [StaffTarget]. Used by `InteractiveMultiPartView`.
  void Function(int partIndex, StaffTarget target)? onStaffTapRaw;

  ElementRegionController? _regionController;

  /// The C7 region controller this view feeds (marquee / drag-reorder across
  /// parts), or null. This render object already reports [elementRegions] /
  /// [elementIdsIn] for the current page, so it *is* the provider — the
  /// controller just re-binds to it. Neither layout nor paint.
  ElementRegionController? get regionController => _regionController;
  set regionController(ElementRegionController? value) {
    if (identical(value, _regionController)) return;
    _regionController?.detach(this);
    _regionController = value;
    _regionController?.attach(this);
  }

  /// Ids painted in the highlight color; per-element ink colors; and ids hidden
  /// from the layout (a clean drag-source hide, C10a). Repaint-only.
  Set<String> _highlightedIds = const {};
  set highlightedIds(Set<String> value) {
    if (_setEq(value, _highlightedIds)) return;
    _highlightedIds = value;
    _painter.highlightedIds = value;
    markNeedsPaint();
  }

  set elementColors(Map<String, Color> value) {
    _painter.elementColors = value;
    markNeedsPaint();
  }

  Set<String> _suppressElementIds = const {};
  set suppressElementIds(Set<String> value) {
    if (_setEq(value, _suppressElementIds)) return;
    _suppressElementIds = value;
    _painter.suppressIds = value;
    markNeedsPaint();
  }

  /// A placement ghost: a translucent notehead of [_ghostDuration] at
  /// [_ghostTarget] in part [_ghostPart]'s coordinate space, or none.
  int? _ghostPart;
  StaffTarget? _ghostTarget;
  NoteDuration _ghostDuration = NoteDuration.quarter;
  set ghostPart(int? value) {
    if (value == _ghostPart) return;
    _ghostPart = value;
    markNeedsPaint();
  }

  set ghostTarget(StaffTarget? value) {
    if (value == _ghostTarget) return;
    _ghostTarget = value;
    markNeedsPaint();
  }

  set ghostDuration(NoteDuration value) {
    if (value == _ghostDuration) return;
    _ghostDuration = value;
    markNeedsPaint();
  }

  /// An insertion caret drawn before its `beforeElementId` (C12b). The element
  /// id uniquely locates the part, so the caret lands in the right staff.
  EditorCaret? _caret;
  set caret(EditorCaret? value) {
    if (value == _caret) return;
    _caret = value;
    markNeedsPaint();
  }

  bool _showMeasureNumbers = false;

  /// Whether to label the first bar of each system (from bar 2 on) with its
  /// global measure number, above the top part's staff. Repaint only.
  set showMeasureNumbers(bool value) {
    if (value == _showMeasureNumbers) return;
    _showMeasureNumbers = value;
    markNeedsPaint();
  }

  static bool _setEq(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

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

  bool _hideEmptyStaves;

  /// Whether to drop all-rest parts per system.
  bool get hideEmptyStaves => _hideEmptyStaves;
  set hideEmptyStaves(bool value) {
    if (value == _hideEmptyStaves) return;
    _hideEmptyStaves = value;
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
        hideEmptyStaves: _hideEmptyStaves,
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

  // ---------------------------------------------------------------- regions
  //
  // The region queries below are scoped to the **current page** ([pageIndex]) —
  // the page this view paints — in local pixel coordinates.

  /// The current page's placed systems, or empty while the layout is loading or
  /// the page index is out of range.
  List<PositionedMultiPartSystem> get _currentPageSystems {
    final layout = _layout;
    if (layout == null || _pageIndex < 0 || _pageIndex >= layout.pages.length) {
      return const [];
    }
    return layout.pages[_pageIndex].systems;
  }

  /// The shared left x (local pixels) where every system's x = 0 maps.
  double get _originX => _metrics.marginLeft * _staffSpace;

  /// Local-pixel y where [placed]'s coordinate origin (its top-most ink) maps.
  double _systemTopY(PositionedMultiPartSystem placed) =>
      (_metrics.marginTop + placed.top - placed.system.layout.top) *
      _staffSpace;

  /// The id of the element containing [local] (local pixels) on the current
  /// page, searching every part of every system, or null. Ties break to the
  /// smallest region, like the other views.
  String? elementIdAt(Offset local) {
    final slop = _theme.hitSlop;
    for (final placed in _currentPageSystems) {
      final system = placed.system.layout;
      final systemTopY = _systemTopY(placed);
      String? bestId;
      var bestArea = double.infinity;
      for (var i = 0; i < system.staves.length; i++) {
        final partOriginY = systemTopY + system.staffTop(i) * _staffSpace;
        final point = math.Point(
          (local.dx - _originX) / _staffSpace,
          (local.dy - partOriginY) / _staffSpace,
        );
        for (final region in system.staves[i].regions) {
          final b = region.bounds;
          final inflated = math.Rectangle(
            b.left - slop,
            b.top - slop,
            b.width + 2 * slop,
            b.height + 2 * slop,
          );
          if (inflated.containsPoint(point)) {
            final area = inflated.width * inflated.height;
            if (area < bestArea) {
              bestArea = area;
              bestId = region.elementId;
            }
          }
        }
      }
      if (bestId != null) return bestId;
    }
    return null;
  }

  /// Read-only hit regions of every element with an id on the current page, in
  /// local pixels, each tagged with the global `measureIndex` it sits in — for
  /// app-side marquee / range selection and custom overlays.
  @override
  List<({String id, Rect bounds, int measureIndex})> get elementRegions {
    final out = <({String id, Rect bounds, int measureIndex})>[];
    for (final placed in _currentPageSystems) {
      final system = placed.system.layout;
      final systemTopY = _systemTopY(placed);
      for (var i = 0; i < system.staves.length; i++) {
        final staff = system.staves[i];
        final partOriginY = systemTopY + system.staffTop(i) * _staffSpace;
        for (final region in staff.regions) {
          final b = region.bounds;
          final centerX = b.left + b.width / 2;
          var localMeasure = 0;
          for (final m in staff.measureRegions) {
            if (m.startX <= centerX) {
              localMeasure = m.index;
            } else {
              break;
            }
          }
          out.add((
            id: region.elementId,
            bounds: Rect.fromLTWH(
              _originX + b.left * _staffSpace,
              partOriginY + b.top * _staffSpace,
              b.width * _staffSpace,
              b.height * _staffSpace,
            ),
            measureIndex: placed.system.firstMeasure + localMeasure,
          ));
        }
      }
    }
    return out;
  }

  /// The ids of every element whose hit region intersects [localRect] (local
  /// pixels) on the current page — a marquee selection.
  @override
  List<String> elementIdsIn(Rect localRect) => [
        for (final region in elementRegions)
          if (region.bounds.overlaps(localRect)) region.id,
      ];

  /// The local-pixel bounds of the element with [id] on the current page, or
  /// null if it is not shown on this page.
  Rect? rectOfElement(String id) {
    for (final region in elementRegions) {
      if (region.id == id) return region.bounds;
    }
    return null;
  }

  /// Resolves [local] (local pixels) to the **part** it falls in plus a
  /// quantized [StaffTarget] in that part's coordinate space — the inverse of
  /// [elementIdAt], for staff-tap note entry and drag-to-move. Picks the part
  /// whose staff centre is nearest vertically (so a tap lands in one part even
  /// in the gaps), or null when the page is empty. `partIndex` is the new axis;
  /// `StaffTarget.staffIndex` mirrors it, `systemIndex` is the page-local system.
  ({int partIndex, StaffTarget target})? targetAt(Offset local) {
    ({int partIndex, StaffTarget target})? best;
    var bestDy = double.infinity;
    final systems = _currentPageSystems;
    for (var s = 0; s < systems.length; s++) {
      final placed = systems[s];
      final system = placed.system.layout;
      final systemTopY = _systemTopY(placed);
      for (var i = 0; i < system.staves.length; i++) {
        final partOriginY = systemTopY + system.staffTop(i) * _staffSpace;
        // Distance from the tap to this part's staff centre (its y = 2 line).
        final centreY = partOriginY + 2 * _staffSpace;
        final dy = (local.dy - centreY).abs();
        if (dy >= bestDy) continue;
        final yStaff = (local.dy - partOriginY) / _staffSpace;
        final xStaff = (local.dx - _originX) / _staffSpace;
        // Same quantization as the single-part view: position 8 = top line.
        final staffPosition = (8 - 2 * yStaff).round().clamp(-6, 14);
        var localMeasure = 0;
        for (final m in system.staves[i].measureRegions) {
          if (m.startX <= xStaff) {
            localMeasure = m.index;
          } else {
            break;
          }
        }
        bestDy = dy;
        best = (
          partIndex: i,
          target: StaffTarget(
            staffPosition: staffPosition,
            measureIndex: placed.system.firstMeasure + localMeasure,
            systemIndex: s,
            staffIndex: i,
          ),
        );
      }
    }
    return best;
  }

  // ------------------------------------------------------------------ input

  @override
  bool hitTestSelf(Offset position) =>
      onElementTap != null || onStaffTapRaw != null;

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerDownEvent &&
        (onElementTap != null || onStaffTapRaw != null)) {
      _tap.addPointer(event);
    }
  }

  void _handleTapUp(TapUpDetails details) {
    final id = elementIdAt(details.localPosition);
    if (id != null) {
      onElementTap?.call(id);
      return;
    }
    final handler = onStaffTapRaw;
    if (handler != null) {
      final hit = targetAt(details.localPosition);
      if (hit != null) handler(hit.partIndex, hit.target);
    }
  }

  @override
  void dispose() {
    _regionController?.detach(this);
    _tap.dispose();
    super.dispose();
  }

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
      final system = placed.system.layout;
      // Content-box top for this system's coordinate origin (its own `top` may
      // reach above the first part's top line).
      final systemTopY = offset.dy +
          (_metrics.marginTop + placed.top - system.top) * _staffSpace;

      // Per-part y where that part's own y = 0 (top line) maps.
      double partOriginY(int i) =>
          systemTopY + system.staffTop(i) * _staffSpace;

      for (var i = 0; i < system.staves.length; i++) {
        _painter.paintLayout(
            canvas, Offset(originX, partOriginY(i)), system.staves[i]);
      }
      _paintBarlineGroups(canvas, system, originX, systemTopY);
      _paintBrackets(canvas, system, originX, systemTopY);
    }
    _paintGhost(canvas, page, originX, offset);
    _paintCaret(canvas, page, originX, offset);
    _paintMeasureNumbers(canvas, page, originX, offset);
  }

  /// Labels each system's first bar (skipping bar 1) with its global measure
  /// number, above the top part's staff at the left edge.
  void _paintMeasureNumbers(
      Canvas canvas, MultiPartPageLayout page, double originX, Offset offset) {
    if (!_showMeasureNumbers) return;
    for (final placed in page.systems) {
      if (placed.system.firstMeasure <= 0) continue;
      final system = placed.system.layout;
      final systemTopY = offset.dy +
          (_metrics.marginTop + placed.top - system.top) * _staffSpace;
      final topPartY = systemTopY + system.staffTop(0) * _staffSpace;
      final tp = TextPainter(
        text: TextSpan(
          text: '${placed.system.firstMeasure + 1}',
          style: TextStyle(
            color: _theme.staffColor,
            fontSize: 0.9 * _staffSpace,
            fontFamily: _theme.textFontFamily,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(originX + 0.2 * _staffSpace, topPartY - 2.1 * _staffSpace),
      );
    }
  }

  /// A vertical insertion caret just left of the caret's `beforeElementId`,
  /// spanning the staff of whichever part owns that element (C12b).
  void _paintCaret(
      Canvas canvas, MultiPartPageLayout page, double originX, Offset offset) {
    final caret = _caret;
    final beforeId = caret?.beforeElementId;
    if (beforeId == null) return;
    for (final placed in page.systems) {
      final system = placed.system.layout;
      final systemTopY = offset.dy +
          (_metrics.marginTop + placed.top - system.top) * _staffSpace;
      for (var i = 0; i < system.staves.length; i++) {
        for (final region in system.staves[i].regions) {
          if (region.elementId != beforeId) continue;
          final partOriginY = systemTopY + system.staffTop(i) * _staffSpace;
          final x = originX + (region.bounds.left - 0.3) * _staffSpace;
          canvas.drawLine(
            Offset(x, partOriginY - 1 * _staffSpace),
            Offset(x, partOriginY + 5 * _staffSpace),
            Paint()
              ..color = _theme.highlightColor
              ..strokeWidth = 0.14 * _staffSpace,
          );
          return;
        }
      }
    }
  }

  /// A translucent placement notehead at [_ghostTarget] in part [_ghostPart].
  void _paintGhost(
      Canvas canvas, MultiPartPageLayout page, double originX, Offset offset) {
    final target = _ghostTarget;
    final part = _ghostPart;
    if (target == null || part == null) return;
    if (target.systemIndex < 0 || target.systemIndex >= page.systems.length) {
      return;
    }
    final placed = page.systems[target.systemIndex];
    final system = placed.system.layout;
    if (part < 0 || part >= system.staves.length) return;
    final staff = system.staves[part];
    final localMeasure = target.measureIndex - placed.system.firstMeasure;
    MeasureRegion? region;
    for (final m in staff.measureRegions) {
      if (m.index == localMeasure) region = m;
    }
    if (region == null) return;
    final systemTopY = offset.dy +
        (_metrics.marginTop + placed.top - system.top) * _staffSpace;
    final partOriginY = systemTopY + system.staffTop(part) * _staffSpace;
    final glyph = switch (_ghostDuration.base) {
      DurationBase.whole => SmuflGlyph.noteheadWhole,
      DurationBase.half => SmuflGlyph.noteheadHalf,
      _ => SmuflGlyph.noteheadBlack,
    };
    final width =
        MusicFonts.metadataOrNull(_theme.musicFont)?.bBoxOf(glyph).width ??
            1.18;
    final x = region.startX + 0.6; // just inside the measure
    final y = (8 - target.staffPosition) / 2;
    _painter.paintGlyph(
      canvas,
      Offset(originX, partOriginY),
      glyph,
      math.Point(x - width / 2, y),
      _theme.highlightColor.withValues(alpha: 0.45),
    );
  }

  /// Draws the systemic barlines for each [BarlineSpan]: a vertical line at
  /// every barline x, running from the span's top to its bottom — so it
  /// connects within a group and breaks in the gap between groups. The spans
  /// and their staff indices already refer to the parts shown on this system
  /// (hide-empty clipped the source), so hidden staves neither carry nor bridge
  /// a barline.
  void _paintBarlineGroups(
    Canvas canvas,
    StaffSystemLayout system,
    double originX,
    double systemTopY,
  ) {
    if (system.staves.length < 2) return;
    final barPaint = Paint()..color = _theme.staffColor;

    // Barline x positions and thicknesses, read once from the first part (all
    // parts share their measure widths, so these match across parts).
    final ref = system.staves.first.primitives.whereType<LinePrimitive>();
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
      final topY = systemTopY + span.top * _staffSpace;
      final bottomY = systemTopY + span.bottom * _staffSpace;
      for (final bar in bars) {
        final x = originX + bar.x * _staffSpace;
        canvas.drawLine(Offset(x, topY), Offset(x, bottomY),
            barPaint..strokeWidth = bar.thickness * _staffSpace);
      }
    }
  }

  /// How many other brackets strictly contain [b] — its nesting depth.
  int _depthOf(StaffSystemLayout system, StaffBracket b) =>
      system.source.brackets
          .where((a) =>
              !identical(a, b) &&
              a.first <= b.first &&
              b.last <= a.last &&
              (a.last - a.first) > (b.last - b.first))
          .length;

  void _paintBrackets(
    Canvas canvas,
    StaffSystemLayout system,
    double originX,
    double systemTopY,
  ) {
    // Brackets follow the laid-out system (already remapped when staves hide).
    final brackets = system.source.brackets;
    if (brackets.isEmpty) return;
    const step = 0.6; // staff spaces per nesting level
    final maxDepth = brackets
        .map((b) => _depthOf(system, b))
        .fold(0, (m, d) => d > m ? d : m);
    double partOriginY(int i) => systemTopY + system.staffTop(i) * _staffSpace;
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
