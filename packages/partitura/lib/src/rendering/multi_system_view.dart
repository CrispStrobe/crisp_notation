import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:partitura_core/partitura_core.dart';

import '../interaction/editor_caret.dart';
import '../interaction/editor_mark.dart';
import '../interaction/element_region_controller.dart';
import '../interaction/staff_target.dart';
import 'layout_painter.dart';
import 'music_font.dart';
import 'theme.dart';

/// Renders a [Score] wrapped into multiple systems (lines) that fit the
/// available width — sheet-music style.
///
/// Line breaking comes from `partitura_core`'s [layoutSystems]: measures
/// are packed greedily, every system restates clef and key signature, and
/// all systems except the last are justified to the full width (disable
/// with [justify]). Resizing the widget rebreaks the score.
///
/// Highlighting and tapping work exactly like `StaffView`: changing
/// [highlightedIds] repaints but never relayouts, and [onElementTap]
/// reports element ids from any system.
class MultiSystemView extends LeafRenderObjectWidget {
  /// The score to render.
  final Score score;

  /// Colors and ergonomics.
  final PartituraTheme theme;

  /// Pixels per staff space. Fixed (unlike `StaffView` there is no
  /// fit-to-width mode — the available width is what drives line
  /// breaking, so it cannot also derive the scale).
  final double staffSpace;

  /// Vertical distance in staff spaces between the bounding boxes of
  /// consecutive systems.
  final double systemGap;

  /// Whether to stretch every non-final system to the full width.
  final bool justify;

  /// Ids of elements to paint in [PartituraTheme.highlightColor].
  final Set<String> highlightedIds;

  /// Per-element ink colors (id → color) — e.g. green/red for correct/wrong
  /// notes. A highlight in [highlightedIds] still wins over these and
  /// [PartituraTheme.elementColors].
  final Map<String, Color> elementColors;

  /// Called with the element id when the user taps an element on any
  /// system.
  final void Function(String elementId)? onElementTap;

  /// Called with a quantized [StaffTarget] when the user taps empty staff
  /// (not on an element) on any system — for click-to-place. The target
  /// carries the `systemIndex`, the global `measureIndex` and the nearest
  /// line/space `staffPosition`.
  final void Function(StaffTarget target)? onStaffTap;

  /// Called on mouse hover (pointer move, no button) with the staff location
  /// under the cursor, or null when the pointer leaves the widget. Desktop
  /// placement preview: drive [ghostTarget] from this.
  final void Function(StaffTarget? target)? onHover;

  /// An insertion caret to draw (between elements or at a model position), or
  /// null to hide it.
  final EditorCaret? caret;

  /// A translucent preview notehead to draw at this staff location (e.g. the
  /// live [onHover] target), or null for none.
  final StaffTarget? ghostTarget;

  /// Duration whose notehead the [ghostTarget] preview uses.
  final NoteDuration ghostDuration;

  /// Called when a drag begins on an existing element, with its id.
  final void Function(String elementId)? onElementDragStart;

  /// Called as a dragged element moves, with its id and the live quantized
  /// [StaffTarget] under the pointer (carrying the system index).
  final void Function(String elementId, StaffTarget target)?
  onElementDragUpdate;

  /// Called when the drag ends, with the element id and the drop target.
  final void Function(String elementId, StaffTarget target)? onElementDragEnd;

  /// Per-element overlay flags (assessment / ear-training): each id is drawn in
  /// its [EditorMark] color with a small wedge above it. Wins over
  /// [elementColors]; a highlight in [highlightedIds] still wins over both.
  final Map<String, EditorMark> errorOverlay;

  /// A contiguous element range (`(startId, endId)`) painted as a translucent
  /// loop/selection band spanning the two ids across systems, or null for none.
  final (String startId, String endId)? loopRange;

  /// A region controller (C7) this view feeds its element hit-regions to, for
  /// app-side marquee selection and drag-to-reorder, or null.
  final ElementRegionController? controller;

  /// Ids to omit from painting entirely — notehead, stem, flag, beam, ledger.
  /// A clean, theme-independent hide (no background-color trickery, no ink
  /// bleed): the app suppresses a note it is previewing itself (e.g. while
  /// dragging it, with its own ghost following the pointer). Repaint only.
  final Set<String> suppressElementIds;

  /// Creates a multi-system view.
  const MultiSystemView({
    super.key,
    required this.score,
    this.theme = PartituraTheme.standard,
    this.staffSpace = 12,
    this.systemGap = 4.0,
    this.justify = true,
    this.highlightedIds = const {},
    this.elementColors = const {},
    this.onElementTap,
    this.onStaffTap,
    this.onHover,
    this.caret,
    this.ghostTarget,
    this.ghostDuration = NoteDuration.quarter,
    this.onElementDragStart,
    this.onElementDragUpdate,
    this.onElementDragEnd,
    this.errorOverlay = const {},
    this.loopRange,
    this.controller,
    this.suppressElementIds = const {},
  });

  @override
  RenderMultiSystemView createRenderObject(BuildContext context) =>
      RenderMultiSystemView(
          score: score,
          theme: theme,
          staffSpace: staffSpace,
          systemGap: systemGap,
          justify: justify,
          highlightedIds: highlightedIds,
          elementColors: elementColors,
        )
        ..onElementTap = onElementTap
        ..onStaffTap = onStaffTap
        ..onHover = onHover
        ..caret = caret
        ..ghostTarget = ghostTarget
        ..ghostDuration = ghostDuration
        ..onElementDragStart = onElementDragStart
        ..onElementDragUpdate = onElementDragUpdate
        ..onElementDragEnd = onElementDragEnd
        ..errorOverlay = errorOverlay
        ..loopRange = loopRange
        ..regionController = controller
        ..suppressElementIds = suppressElementIds;

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMultiSystemView renderObject,
  ) {
    renderObject
      ..score = score
      ..theme = theme
      ..staffSpace = staffSpace
      ..systemGap = systemGap
      ..justify = justify
      ..highlightedIds = highlightedIds
      ..elementColors = elementColors
      ..onElementTap = onElementTap
      ..onStaffTap = onStaffTap
      ..onHover = onHover
      ..caret = caret
      ..ghostTarget = ghostTarget
      ..ghostDuration = ghostDuration
      ..onElementDragStart = onElementDragStart
      ..onElementDragUpdate = onElementDragUpdate
      ..onElementDragEnd = onElementDragEnd
      ..errorOverlay = errorOverlay
      ..loopRange = loopRange
      ..regionController = controller
      ..suppressElementIds = suppressElementIds;
  }
}

/// Render object behind [MultiSystemView].
class RenderMultiSystemView extends RenderBox
    implements MouseTrackerAnnotation, ElementRegionProvider {
  /// Creates the render object.
  RenderMultiSystemView({
    required Score score,
    required PartituraTheme theme,
    required double staffSpace,
    required double systemGap,
    required bool justify,
    required Set<String> highlightedIds,
    Map<String, Color> elementColors = const {},
  }) : _score = score,
       _theme = theme,
       _staffSpace = staffSpace,
       _systemGap = systemGap,
       _justify = justify,
       _highlightedIds = highlightedIds,
       _elementColors = elementColors {
    _tap = TapGestureRecognizer(debugOwner: this)..onTapUp = _handleTapUp;
    _pan = PanGestureRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  late final TapGestureRecognizer _tap;
  late final PanGestureRecognizer _pan;

  /// The element currently being dragged, or null.
  String? _draggingId;
  Offset? _lastDragLocal;

  MultiSystemLayout? _layout;
  late final LayoutPainter _painter = LayoutPainter(
    theme: _theme,
    scale: _staffSpace,
    highlightedIds: _highlightedIds,
    elementColors: _elementColors,
  );

  /// Called with the element id when the user taps an element.
  void Function(String elementId)? onElementTap;

  /// Called with a quantized [StaffTarget] when the user taps empty staff.
  void Function(StaffTarget target)? onStaffTap;

  /// Called on mouse hover with the staff location, or null on exit.
  void Function(StaffTarget? target)? onHover;

  /// Called when a drag begins on an existing element.
  void Function(String elementId)? onElementDragStart;

  /// Called as a dragged element moves, with the live target.
  void Function(String elementId, StaffTarget target)? onElementDragUpdate;

  /// Called when the drag ends, with the drop target.
  void Function(String elementId, StaffTarget target)? onElementDragEnd;

  bool get _wantsElementDrag =>
      onElementDragStart != null ||
      onElementDragUpdate != null ||
      onElementDragEnd != null;

  EditorCaret? _caret;

  /// The insertion caret to draw, or null. Repaint only.
  EditorCaret? get caret => _caret;
  set caret(EditorCaret? value) {
    if (value == _caret) return;
    _caret = value;
    markNeedsPaint();
  }

  StaffTarget? _ghostTarget;

  /// The preview-notehead location, or null. Repaint only.
  StaffTarget? get ghostTarget => _ghostTarget;
  set ghostTarget(StaffTarget? value) {
    if (value == _ghostTarget) return;
    _ghostTarget = value;
    markNeedsPaint();
  }

  NoteDuration _ghostDuration = NoteDuration.quarter;

  /// The ghost preview's duration. Repaint only.
  NoteDuration get ghostDuration => _ghostDuration;
  set ghostDuration(NoteDuration value) {
    if (value == _ghostDuration) return;
    _ghostDuration = value;
    if (_ghostTarget != null) markNeedsPaint();
  }

  Score _score;

  /// The score to render.
  Score get score => _score;
  set score(Score value) {
    if (value == _score) return;
    _score = value;
    markNeedsLayout();
  }

  PartituraTheme _theme;

  /// Colors and ergonomics.
  PartituraTheme get theme => _theme;
  set theme(PartituraTheme value) {
    if (value == _theme) return;
    final needsLayout =
        value.lineBoost != _theme.lineBoost ||
        value.musicFont != _theme.musicFont;
    _theme = value;
    _painter.theme = value;
    if (needsLayout) {
      markNeedsLayout();
    } else {
      _painter.clearCache();
      markNeedsPaint();
    }
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

  /// Vertical distance in staff spaces between systems.
  double get systemGap => _systemGap;
  set systemGap(double value) {
    if (value == _systemGap) return;
    _systemGap = value;
    markNeedsLayout();
  }

  bool _justify;

  /// Whether non-final systems stretch to the full width.
  bool get justify => _justify;
  set justify(bool value) {
    if (value == _justify) return;
    _justify = value;
    markNeedsLayout();
  }

  Set<String> _highlightedIds;

  /// Ids painted in the highlight color. Repaint only — no relayout.
  Set<String> get highlightedIds => _highlightedIds;
  set highlightedIds(Set<String> value) {
    if (value == _highlightedIds ||
        (value.length == _highlightedIds.length &&
            value.containsAll(_highlightedIds))) {
      return;
    }
    _highlightedIds = value;
    _painter.highlightedIds = value;
    markNeedsPaint();
  }

  Set<String> _suppressIds = const {};

  /// Ids omitted from painting entirely (C10a). Repaint only — no relayout.
  Set<String> get suppressElementIds => _suppressIds;
  set suppressElementIds(Set<String> value) {
    if (value == _suppressIds ||
        (value.length == _suppressIds.length &&
            value.containsAll(_suppressIds))) {
      return;
    }
    _suppressIds = value;
    _painter.suppressIds = value;
    markNeedsPaint();
  }

  Map<String, Color> _elementColors;

  /// Per-element ink colors. Repaint only — no relayout.
  Map<String, Color> get elementColors => _elementColors;
  set elementColors(Map<String, Color> value) {
    if (mapEquals(value, _elementColors)) return;
    _elementColors = value;
    _syncPainterColors();
    markNeedsPaint();
  }

  Map<String, EditorMark> _errorOverlay = const {};

  /// Per-element overlay flags. Repaint only.
  Map<String, EditorMark> get errorOverlay => _errorOverlay;
  set errorOverlay(Map<String, EditorMark> value) {
    if (mapEquals(value, _errorOverlay)) return;
    _errorOverlay = value;
    _syncPainterColors();
    markNeedsPaint();
  }

  (String, String)? _loopRange;

  /// The loop/selection band range. Repaint only.
  (String, String)? get loopRange => _loopRange;
  set loopRange((String, String)? value) {
    if (value == _loopRange) return;
    _loopRange = value;
    markNeedsPaint();
  }

  ElementRegionController? _regionController;

  /// The C7 region controller this view feeds (marquee / drag-reorder), or
  /// null. Re-binds on change; neither layout nor paint.
  ElementRegionController? get regionController => _regionController;
  set regionController(ElementRegionController? value) {
    if (identical(value, _regionController)) return;
    _regionController?.detach(this);
    _regionController = value;
    _regionController?.attach(this);
  }

  /// Feeds the painter the widget's element colors with the overlay colors
  /// merged on top (overlay wins), so flagged notes draw in their mark color.
  void _syncPainterColors() {
    _painter.elementColors = _errorOverlay.isEmpty
        ? _elementColors
        : {
            ..._elementColors,
            for (final entry in _errorOverlay.entries)
              entry.key: entry.value.color,
          };
  }

  // -------------------------------------------------------------- geometry

  /// The current multi-system layout, or null while the font metadata is
  /// loading.
  MultiSystemLayout? get multiSystemLayout => _layout;

  /// Pixels per staff space.
  double get scale => _staffSpace;

  /// The pixel origin of [system]'s staff-space (0, 0) — its top staff
  /// line at the left edge.
  Offset originOfSystem(int system) {
    final layout = _layout;
    if (layout == null) return Offset.zero;
    var y = 0.0;
    for (var i = 0; i < system; i++) {
      y += (layout.systems[i].layout.height + _systemGap) * _staffSpace;
    }
    return Offset(0, y - layout.systems[system].layout.top * _staffSpace);
  }

  LayoutSettings _settingsFor(SmuflMetadata metadata) {
    final boost = _theme.lineBoost;
    final base = LayoutSettings(metadata: metadata);
    if (boost == 1.0) return base;
    return LayoutSettings(
      metadata: metadata,
      staffLineThickness: base.staffLineThickness * boost,
      stemThickness: base.stemThickness * boost,
      legerLineThickness: base.legerLineThickness * boost,
      thinBarlineThickness: base.thinBarlineThickness * boost,
    );
  }

  Size _measure(BoxConstraints constraints) {
    final metadata = MusicFonts.metadataOrNull(_theme.musicFont);
    if (metadata == null) {
      _layout = null;
      return constraints.constrain(
        Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : 40 * _staffSpace,
          12 * _staffSpace,
        ),
      );
    }
    final maxWidthSpaces = constraints.hasBoundedWidth
        ? constraints.maxWidth / _staffSpace
        : 40.0;
    final layout = layoutSystems(
      _score,
      _settingsFor(metadata),
      maxWidth: maxWidthSpaces,
      justify: _justify,
    );
    _layout = layout;
    final widthSpaces = layout.systems
        .map((s) => s.layout.width)
        .reduce(math.max);
    return constraints.constrain(
      Size(
        widthSpaces * _staffSpace,
        layout.heightWith(_systemGap) * _staffSpace,
      ),
    );
  }

  @override
  void performLayout() {
    if (MusicFonts.metadataOrNull(_theme.musicFont) == null) {
      MusicFonts.load(_theme.musicFont).then((_) {
        if (attached) markNeedsLayout();
      });
    }
    _painter.clearCache();
    size = _measure(constraints);
    _painter.scale = _staffSpace;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _measure(constraints);

  /// The id of the element containing [local] on any system, or null.
  String? elementIdAt(Offset local) {
    final layout = _layout;
    if (layout == null) return null;
    final slop = _theme.hitSlop;
    for (var i = 0; i < layout.systems.length; i++) {
      final origin = originOfSystem(i);
      final point = math.Point(
        (local.dx - origin.dx) / _staffSpace,
        (local.dy - origin.dy) / _staffSpace,
      );
      String? bestId;
      var bestArea = double.infinity;
      for (final region in layout.systems[i].layout.regions) {
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
      if (bestId != null) return bestId;
    }
    return null;
  }

  /// The empty-staff location under [local], quantized to the nearest
  /// line/space, or null while the layout is loading. Resolves the system
  /// whose band contains [local] (nearest if the tap fell in a gap), then the
  /// system-local measure and staff position — the multi-system analogue of
  /// `RenderStaffView.quantizeStaffPosition`.
  StaffTarget? resolveStaffTarget(Offset local) {
    final layout = _layout;
    if (layout == null || layout.systems.isEmpty) return null;

    // Pick the system whose vertical band is nearest to the tap.
    var systemIndex = 0;
    var bestDist = double.infinity;
    var y = 0.0;
    for (var i = 0; i < layout.systems.length; i++) {
      final h = layout.systems[i].layout.height * _staffSpace;
      final dist = local.dy < y
          ? y - local.dy
          : (local.dy > y + h ? local.dy - (y + h) : 0.0);
      if (dist < bestDist) {
        bestDist = dist;
        systemIndex = i;
      }
      y += h + _systemGap * _staffSpace;
    }

    final system = layout.systems[systemIndex];
    final origin = originOfSystem(systemIndex);
    final point = math.Point(
      (local.dx - origin.dx) / _staffSpace,
      (local.dy - origin.dy) / _staffSpace,
    );
    // Same quantization as RenderStaffView: 2 units per staff space, top line
    // is position 8, clamped to the ledger range.
    final staffPosition = (8 - 2 * point.y).round().clamp(-6, 14);

    // Last measure whose start is at or left of the tap; global via the
    // system's first-measure offset.
    var localMeasure = 0;
    for (final region in system.layout.measureRegions) {
      if (region.startX <= point.x) {
        localMeasure = region.index;
      } else {
        break;
      }
    }

    return StaffTarget(
      staffPosition: staffPosition,
      measureIndex: system.firstMeasure + localMeasure,
      systemIndex: systemIndex,
    );
  }

  /// Read-only hit regions of every element with an id, in **local pixel**
  /// coordinates, each tagged with the global `measureIndex` it sits in —
  /// for app-side marquee / shift-click range selection and custom overlays.
  @override
  List<({String id, Rect bounds, int measureIndex})> get elementRegions {
    final layout = _layout;
    if (layout == null) return const [];
    final out = <({String id, Rect bounds, int measureIndex})>[];
    for (var i = 0; i < layout.systems.length; i++) {
      final origin = originOfSystem(i);
      final system = layout.systems[i];
      for (final region in system.layout.regions) {
        final b = region.bounds;
        final centerX = b.left + b.width / 2;
        var localMeasure = 0;
        for (final m in system.layout.measureRegions) {
          if (m.startX <= centerX) {
            localMeasure = m.index;
          } else {
            break;
          }
        }
        out.add((
          id: region.elementId,
          bounds: Rect.fromLTWH(
            origin.dx + b.left * _staffSpace,
            origin.dy + b.top * _staffSpace,
            b.width * _staffSpace,
            b.height * _staffSpace,
          ),
          measureIndex: system.firstMeasure + localMeasure,
        ));
      }
    }
    return out;
  }

  /// The ids of every element whose hit region intersects [localRect] (local
  /// pixel coordinates) — a marquee selection.
  @override
  List<String> elementIdsIn(Rect localRect) => [
    for (final region in elementRegions)
      if (region.bounds.overlaps(localRect)) region.id,
  ];

  // ------------------------------------------------------------------ input

  @override
  bool hitTestSelf(Offset position) =>
      onElementTap != null ||
      onStaffTap != null ||
      onHover != null ||
      _wantsElementDrag;

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerDownEvent) {
      if (onElementTap != null || onStaffTap != null) _tap.addPointer(event);
      if (_wantsElementDrag) _pan.addPointer(event);
    } else if (event is PointerHoverEvent && onHover != null) {
      onHover!.call(resolveStaffTarget(event.localPosition));
    }
  }

  void _handleDragStart(DragStartDetails details) {
    _lastDragLocal = details.localPosition;
    _draggingId = elementIdAt(details.localPosition);
    if (_draggingId != null) onElementDragStart?.call(_draggingId!);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _lastDragLocal = details.localPosition;
    final id = _draggingId;
    if (id == null) return;
    final target = resolveStaffTarget(details.localPosition);
    if (target != null) onElementDragUpdate?.call(id, target);
  }

  void _handleDragEnd(DragEndDetails details) {
    final id = _draggingId;
    final local = _lastDragLocal;
    if (id != null && local != null) {
      final target = resolveStaffTarget(local);
      if (target != null) onElementDragEnd?.call(id, target);
    }
    _draggingId = null;
  }

  void _handleDragCancel() => _draggingId = null;

  // MouseTrackerAnnotation — reports null when the pointer leaves the widget.
  /// No enter callback (hover moves drive [onHover] via [handleEvent]).
  @override
  PointerEnterEventListener? get onEnter => null;

  /// Fires [onHover] with null when the pointer leaves the widget.
  @override
  PointerExitEventListener? get onExit =>
      onHover == null ? null : (_) => onHover?.call(null);

  /// The default cursor (this view does not change it).
  @override
  MouseCursor get cursor => MouseCursor.defer;

  /// Whether this render object participates in mouse tracking (only when a
  /// hover handler is set).
  @override
  bool get validForMouseTracker => onHover != null;

  void _handleTapUp(TapUpDetails details) {
    final id = elementIdAt(details.localPosition);
    if (id != null) {
      onElementTap?.call(id);
    } else if (onStaffTap != null) {
      final target = resolveStaffTarget(details.localPosition);
      if (target != null) onStaffTap!.call(target);
    }
  }

  @override
  void dispose() {
    _regionController?.detach(this);
    _tap.dispose();
    _pan.dispose();
    _painter.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ paint

  @override
  void paint(PaintingContext context, Offset offset) {
    final layout = _layout;
    if (layout == null) return;
    _paintLoopBand(context.canvas, offset); // behind the notes
    for (var i = 0; i < layout.systems.length; i++) {
      _painter.paintLayout(
        context.canvas,
        offset + originOfSystem(i),
        layout.systems[i].layout,
      );
    }
    _paintErrorMarks(context.canvas, offset);
    _paintGhost(context.canvas, offset);
    _paintCaret(context.canvas, offset);
  }

  /// The (system index, staff-space bounds) of element [id], or null.
  (int, math.Rectangle<double>)? _locate(String id) {
    final layout = _layout;
    if (layout == null) return null;
    for (var i = 0; i < layout.systems.length; i++) {
      for (final region in layout.systems[i].layout.regions) {
        if (region.elementId == id) return (i, region.bounds);
      }
    }
    return null;
  }

  /// The local **pixel** rectangle of element [id], or null — for scroll-to-note
  /// (the app scrolls its own viewport to bring this rect into view).
  Rect? rectOfElement(String id) {
    final located = _locate(id);
    if (located == null) return null;
    final origin = originOfSystem(located.$1);
    final b = located.$2;
    return Rect.fromLTWH(
      origin.dx + b.left * _staffSpace,
      origin.dy + b.top * _staffSpace,
      b.width * _staffSpace,
      b.height * _staffSpace,
    );
  }

  void _paintLoopBand(Canvas canvas, Offset offset) {
    final range = _loopRange;
    final layout = _layout;
    if (range == null || layout == null) return;
    var start = _locate(range.$1);
    var end = _locate(range.$2);
    if (start == null || end == null) return;
    // Order start before end (by system, then x).
    if (start.$1 > end.$1 ||
        (start.$1 == end.$1 && start.$2.left > end.$2.left)) {
      final swap = start;
      start = end;
      end = swap;
    }
    final paint = Paint()
      ..color = _theme.highlightColor.withValues(alpha: 0.18);
    for (var i = start.$1; i <= end.$1; i++) {
      final origin = offset + originOfSystem(i);
      final left = i == start.$1 ? start.$2.left : 0.0;
      final right = i == end.$1 ? end.$2.right : layout.systems[i].layout.width;
      canvas.drawRect(
        Rect.fromLTRB(
          origin.dx + left * _staffSpace,
          origin.dy + -1 * _staffSpace,
          origin.dx + right * _staffSpace,
          origin.dy + 5 * _staffSpace,
        ),
        paint,
      );
    }
  }

  void _paintErrorMarks(Canvas canvas, Offset offset) {
    if (_errorOverlay.isEmpty) return;
    for (final entry in _errorOverlay.entries) {
      final located = _locate(entry.key);
      if (located == null) continue;
      final origin = offset + originOfSystem(located.$1);
      final b = located.$2;
      final cx = origin.dx + (b.left + b.width / 2) * _staffSpace;
      final topY = origin.dy + -1.6 * _staffSpace;
      final w = 0.55 * _staffSpace;
      // A small downward wedge above the staff, in the mark's color.
      final path = Path()
        ..moveTo(cx - w / 2, topY)
        ..lineTo(cx + w / 2, topY)
        ..lineTo(cx, topY + w)
        ..close();
      canvas.drawPath(path, Paint()..color = entry.value.color);
    }
  }

  /// The (system index, start x in staff spaces) of [measureIndex], or null if
  /// no system holds it.
  (int, double)? _measurePlacement(int measureIndex) {
    final layout = _layout;
    if (layout == null) return null;
    for (var i = 0; i < layout.systems.length; i++) {
      final system = layout.systems[i];
      if (measureIndex < system.firstMeasure ||
          measureIndex > system.lastMeasure) {
        continue;
      }
      final localIndex = measureIndex - system.firstMeasure;
      for (final region in system.layout.measureRegions) {
        if (region.index == localIndex) return (i, region.startX);
      }
    }
    return null;
  }

  void _paintGhost(Canvas canvas, Offset offset) {
    final ghost = _ghostTarget;
    if (ghost == null) return;
    final placement = _measurePlacement(ghost.measureIndex);
    if (placement == null) return;
    final (system, startX) = placement;
    final xSpaces = startX + 1.0; // just inside the measure
    final glyph = switch (_ghostDuration.base) {
      DurationBase.whole => SmuflGlyph.noteheadWhole,
      DurationBase.half => SmuflGlyph.noteheadHalf,
      _ => SmuflGlyph.noteheadBlack,
    };
    final color = _theme.highlightColor.withValues(alpha: 0.45);
    final y = (8 - ghost.staffPosition) / 2;
    final metadata = MusicFonts.metadataOrNull(_theme.musicFont);
    final width = metadata?.bBoxOf(glyph).width ?? 1.18;
    final origin = offset + originOfSystem(system);
    _painter.paintGlyph(
      canvas,
      origin,
      glyph,
      math.Point(xSpaces - width / 2, y),
      color,
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.16 * _staffSpace;
    for (var p = -2; p >= ghost.staffPosition; p -= 2) {
      _paintLedger(canvas, origin, xSpaces, p, width, paint);
    }
    for (var p = 10; p <= ghost.staffPosition; p += 2) {
      _paintLedger(canvas, origin, xSpaces, p, width, paint);
    }
  }

  void _paintLedger(
    Canvas canvas,
    Offset origin,
    double xSpaces,
    int position,
    double headWidth,
    Paint paint,
  ) {
    final y = (8 - position) / 2;
    canvas.drawLine(
      origin +
          Offset(
            (xSpaces - headWidth / 2 - 0.4) * _staffSpace,
            y * _staffSpace,
          ),
      origin +
          Offset(
            (xSpaces + headWidth / 2 + 0.4) * _staffSpace,
            y * _staffSpace,
          ),
      paint,
    );
  }

  void _paintCaret(Canvas canvas, Offset offset) {
    final caret = _caret;
    final layout = _layout;
    if (caret == null || layout == null) return;

    int? system;
    double? xSpaces;
    final beforeId = caret.beforeElementId;
    if (beforeId != null) {
      outer:
      for (var i = 0; i < layout.systems.length; i++) {
        for (final region in layout.systems[i].layout.regions) {
          if (region.elementId == beforeId) {
            system = i;
            xSpaces = region.bounds.left - 0.3;
            break outer;
          }
        }
      }
    } else if (caret.measureIndex != null) {
      final placement = _measurePlacement(caret.measureIndex!);
      if (placement != null) {
        system = placement.$1;
        xSpaces = placement.$2;
      }
    }
    if (system == null || xSpaces == null) return;

    final origin = offset + originOfSystem(system);
    final paint = Paint()
      ..color = _theme.highlightColor
      ..strokeWidth = 0.14 * _staffSpace;
    // A vertical insertion bar spanning the staff with a small overshoot.
    canvas.drawLine(
      origin + Offset(xSpaces * _staffSpace, -1 * _staffSpace),
      origin + Offset(xSpaces * _staffSpace, 5 * _staffSpace),
      paint,
    );
  }
}
