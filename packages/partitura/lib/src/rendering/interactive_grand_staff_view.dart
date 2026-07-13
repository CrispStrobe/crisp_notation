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

/// A grand staff (two clefs, e.g. piano) wrapped into multiple systems that
/// fit the available width, with tap interaction on both staves — the editor
/// counterpart of [MultiSystemView] for a keyboard system.
///
/// Line breaking (`layoutGrandStaffSystems`) packs measures by the wider of the
/// two staves so barlines stay aligned; the time signature is drawn only on the
/// first system. Tapping an element fires [onElementTap]; tapping empty staff
/// fires [onStaffTap] with a [StaffTarget] carrying the `systemIndex` and the
/// `staffIndex` (0 = upper, 1 = lower).
class InteractiveGrandStaffView extends LeafRenderObjectWidget {
  /// The two-staff grand staff to render.
  final GrandStaff grandStaff;

  /// Colors and ergonomics.
  final PartituraTheme theme;

  /// Pixels per staff space (fixed — the width drives line breaking).
  final double staffSpace;

  /// Staff spaces between the upper staff's bottom line and the lower staff's
  /// top line within each system.
  final double staffGap;

  /// Staff spaces between the bounding boxes of consecutive systems.
  final double systemGap;

  /// Whether to justify every non-final system to the full width (shared
  /// note-spacing stretch across both staves).
  final bool justify;

  /// Whether to align simultaneous notes vertically across the two staves
  /// (cross-staff onset gridding). Single-voice staves only.
  final bool gridAlign;

  /// Ids painted in the highlight color.
  final Set<String> highlightedIds;

  /// Per-element ink colors.
  final Map<String, Color> elementColors;

  /// Per-element overlay flags: each keyed element is drawn in its [EditorMark]
  /// color with a small wedge above its staff. Wins over [elementColors]. For
  /// assessment / ear-training / proofreading editors. Like [elementColors] and
  /// [highlightedIds], ids match on either staff, so give the two hands globally
  /// unique element ids if a mark must land on only one of them.
  final Map<String, EditorMark> errorOverlay;

  /// A loop/selection band painted behind the notes, spanning both staves from
  /// the `startId` element to the `endId` element (across systems), or null. The
  /// endpoints resolve to the first matching element on either staff.
  final (String startId, String endId)? loopRange;

  /// A region controller (C7) this view feeds its element hit-regions to, for
  /// app-side marquee selection and drag-to-reorder, or null.
  final ElementRegionController? controller;

  /// Called with the element id when the user taps an element on any staff.
  final void Function(String elementId)? onElementTap;

  /// Called with a quantized [StaffTarget] (with `systemIndex` and
  /// `staffIndex`) when the user taps empty staff.
  final void Function(StaffTarget target)? onStaffTap;

  /// Called on mouse hover with the staff location, or null on exit.
  final void Function(StaffTarget? target)? onHover;

  /// An insertion caret to draw (spans the system at the resolved x), or null.
  final EditorCaret? caret;

  /// A translucent preview notehead to draw at this staff location (its
  /// `staffIndex` picks the staff), or null.
  final StaffTarget? ghostTarget;

  /// Duration whose notehead the [ghostTarget] preview uses.
  final NoteDuration ghostDuration;

  /// Called when a drag begins on an existing element, with its id.
  final void Function(String elementId)? onElementDragStart;

  /// Called as a dragged element moves, with the live target.
  final void Function(String elementId, StaffTarget target)?
      onElementDragUpdate;

  /// Called when the drag ends, with the drop target.
  final void Function(String elementId, StaffTarget target)? onElementDragEnd;

  /// Creates a wrapped, interactive grand staff.
  const InteractiveGrandStaffView({
    super.key,
    required this.grandStaff,
    this.theme = PartituraTheme.standard,
    this.staffSpace = 12,
    this.staffGap = 4.0,
    this.systemGap = 6.0,
    this.justify = true,
    this.gridAlign = true,
    this.highlightedIds = const {},
    this.elementColors = const {},
    this.errorOverlay = const {},
    this.loopRange,
    this.controller,
    this.onElementTap,
    this.onStaffTap,
    this.onHover,
    this.caret,
    this.ghostTarget,
    this.ghostDuration = NoteDuration.quarter,
    this.onElementDragStart,
    this.onElementDragUpdate,
    this.onElementDragEnd,
  });

  @override
  RenderInteractiveGrandStaffView createRenderObject(BuildContext context) =>
      RenderInteractiveGrandStaffView(
        grandStaff: grandStaff,
        theme: theme,
        staffSpace: staffSpace,
        staffGap: staffGap,
        systemGap: systemGap,
        justify: justify,
        gridAlign: gridAlign,
        highlightedIds: highlightedIds,
        elementColors: elementColors,
      )
        ..errorOverlay = errorOverlay
        ..loopRange = loopRange
        ..regionController = controller
        ..onElementTap = onElementTap
        ..onStaffTap = onStaffTap
        ..onHover = onHover
        ..caret = caret
        ..ghostTarget = ghostTarget
        ..ghostDuration = ghostDuration
        ..onElementDragStart = onElementDragStart
        ..onElementDragUpdate = onElementDragUpdate
        ..onElementDragEnd = onElementDragEnd;

  @override
  void updateRenderObject(
    BuildContext context,
    RenderInteractiveGrandStaffView renderObject,
  ) {
    renderObject
      ..grandStaff = grandStaff
      ..theme = theme
      ..staffSpace = staffSpace
      ..staffGap = staffGap
      ..systemGap = systemGap
      ..justify = justify
      ..gridAlign = gridAlign
      ..highlightedIds = highlightedIds
      ..elementColors = elementColors
      ..errorOverlay = errorOverlay
      ..loopRange = loopRange
      ..regionController = controller
      ..onElementTap = onElementTap
      ..onStaffTap = onStaffTap
      ..onHover = onHover
      ..caret = caret
      ..ghostTarget = ghostTarget
      ..ghostDuration = ghostDuration
      ..onElementDragStart = onElementDragStart
      ..onElementDragUpdate = onElementDragUpdate
      ..onElementDragEnd = onElementDragEnd;
  }
}

/// Render object behind [InteractiveGrandStaffView].
class RenderInteractiveGrandStaffView extends RenderBox
    implements MouseTrackerAnnotation, ElementRegionProvider {
  /// Creates the render object.
  RenderInteractiveGrandStaffView({
    required GrandStaff grandStaff,
    required PartituraTheme theme,
    required double staffSpace,
    required double staffGap,
    required double systemGap,
    required bool justify,
    required bool gridAlign,
    required Set<String> highlightedIds,
    Map<String, Color> elementColors = const {},
  })  : _grandStaff = grandStaff,
        _theme = theme,
        _staffSpace = staffSpace,
        _staffGap = staffGap,
        _systemGap = systemGap,
        _justify = justify,
        _gridAlign = gridAlign,
        _highlightedIds = highlightedIds,
        _elementColors = elementColors {
    _tap = TapGestureRecognizer(debugOwner: this)..onTapUp = _handleTapUp;
    _pan = PanGestureRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  /// Left inset (staff spaces) reserved for the brace.
  static const double braceInset = 1.4;

  late final TapGestureRecognizer _tap;
  late final PanGestureRecognizer _pan;
  String? _draggingId;
  Offset? _lastDragLocal;
  GrandStaffSystems? _systems;
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

  GrandStaff _grandStaff;

  /// The grand staff to render.
  GrandStaff get grandStaff => _grandStaff;
  set grandStaff(GrandStaff value) {
    if (value == _grandStaff) return;
    _grandStaff = value;
    markNeedsLayout();
  }

  PartituraTheme _theme;

  /// Colors and ergonomics.
  PartituraTheme get theme => _theme;
  set theme(PartituraTheme value) {
    if (value == _theme) return;
    final needsLayout = value.lineBoost != _theme.lineBoost ||
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

  double _staffGap;

  /// Staff spaces between the two staves of a system.
  double get staffGap => _staffGap;
  set staffGap(double value) {
    if (value == _staffGap) return;
    _staffGap = value;
    markNeedsLayout();
  }

  double _systemGap;

  /// Staff spaces between systems.
  double get systemGap => _systemGap;
  set systemGap(double value) {
    if (value == _systemGap) return;
    _systemGap = value;
    markNeedsLayout();
  }

  bool _justify;

  /// Whether non-final systems fill the width.
  bool get justify => _justify;
  set justify(bool value) {
    if (value == _justify) return;
    _justify = value;
    markNeedsLayout();
  }

  bool _gridAlign;

  /// Whether simultaneous notes align across the two staves.
  bool get gridAlign => _gridAlign;
  set gridAlign(bool value) {
    if (value == _gridAlign) return;
    _gridAlign = value;
    markNeedsLayout();
  }

  Set<String> _highlightedIds;

  /// Ids painted in the highlight color. Repaint only.
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

  Map<String, Color> _elementColors;

  /// Per-element ink colors. Repaint only.
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

  /// The current wrapped-grand-staff layout, or null while loading.
  GrandStaffSystems? get grandStaffSystems => _systems;

  /// Pixels per staff space.
  double get scale => _staffSpace;

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

  /// Pixel y of system [i]'s bounding-box top.
  double _bandTop(int i) {
    final systems = _systems!.systems;
    var y = 0.0;
    for (var j = 0; j < i; j++) {
      y += (systems[j].layout.height + _systemGap) * _staffSpace;
    }
    return y;
  }

  /// Pixel origin of the upper staff's staff-space (0, 0) on system [i].
  Offset upperOrigin(int i) {
    final layout = _systems!.systems[i].layout;
    return Offset(
        braceInset * _staffSpace, _bandTop(i) - layout.upper.top * _staffSpace);
  }

  /// Pixel origin of the lower staff's staff-space (0, 0) on system [i].
  Offset lowerOrigin(int i) {
    final layout = _systems!.systems[i].layout;
    return Offset(
      braceInset * _staffSpace,
      _bandTop(i) + (-layout.upper.top + 4 + layout.staffGap) * _staffSpace,
    );
  }

  Size _measure(BoxConstraints constraints) {
    final metadata = MusicFonts.metadataOrNull(_theme.musicFont);
    if (metadata == null) {
      _systems = null;
      return constraints.constrain(Size(
        constraints.hasBoundedWidth ? constraints.maxWidth : 40 * _staffSpace,
        24 * _staffSpace,
      ));
    }
    final maxWidthSpaces = (constraints.hasBoundedWidth
                ? constraints.maxWidth
                : 40 * _staffSpace) /
            _staffSpace -
        braceInset;
    final systems = layoutGrandStaffSystems(
      _grandStaff,
      _settingsFor(metadata),
      maxWidth: math.max(8.0, maxWidthSpaces),
      staffGap: _staffGap,
      justify: _justify,
      gridAlign: _gridAlign,
    );
    _systems = systems;
    final width =
        systems.systems.fold<double>(0, (m, s) => math.max(m, s.layout.width)) +
            braceInset;
    return constraints.constrain(Size(
      width * _staffSpace,
      systems.heightWith(_systemGap) * _staffSpace,
    ));
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

  String? _findIn(ScoreLayout staff, Offset origin, Offset local) {
    final point = math.Point(
      (local.dx - origin.dx) / _staffSpace,
      (local.dy - origin.dy) / _staffSpace,
    );
    final slop = _theme.hitSlop;
    String? bestId;
    var bestArea = double.infinity;
    for (final region in staff.regions) {
      final b = region.bounds;
      final inflated = math.Rectangle(
          b.left - slop, b.top - slop, b.width + 2 * slop, b.height + 2 * slop);
      if (inflated.containsPoint(point)) {
        final area = inflated.width * inflated.height;
        if (area < bestArea) {
          bestArea = area;
          bestId = region.elementId;
        }
      }
    }
    return bestId;
  }

  /// The id of the element under [local] on any staff of any system, or null.
  String? elementIdAt(Offset local) {
    final systems = _systems;
    if (systems == null) return null;
    for (var i = 0; i < systems.systems.length; i++) {
      final layout = systems.systems[i].layout;
      final id = _findIn(layout.upper, upperOrigin(i), local) ??
          _findIn(layout.lower, lowerOrigin(i), local);
      if (id != null) return id;
    }
    return null;
  }

  /// Read-only hit regions of every element with an id, on either staff of any
  /// system, in **local pixel** coordinates, tagged with the global
  /// `measureIndex` — for app-side marquee / range selection.
  @override
  List<({String id, Rect bounds, int measureIndex})> get elementRegions {
    final systems = _systems;
    if (systems == null) return const [];
    final out = <({String id, Rect bounds, int measureIndex})>[];
    for (var i = 0; i < systems.systems.length; i++) {
      final system = systems.systems[i];
      for (final entry in [
        (system.layout.upper, upperOrigin(i)),
        (system.layout.lower, lowerOrigin(i)),
      ]) {
        final staff = entry.$1;
        final origin = entry.$2;
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
              origin.dx + b.left * _staffSpace,
              origin.dy + b.top * _staffSpace,
              b.width * _staffSpace,
              b.height * _staffSpace,
            ),
            measureIndex: system.firstMeasure + localMeasure,
          ));
        }
      }
    }
    return out;
  }

  /// The ids of every element whose hit region intersects [localRect].
  @override
  List<String> elementIdsIn(Rect localRect) => [
        for (final region in elementRegions)
          if (region.bounds.overlaps(localRect)) region.id,
      ];

  /// The (system index, staff index 0=upper/1=lower, staff-space bounds) of
  /// element [id], or null.
  (int, int, math.Rectangle<double>)? _locate(String id) {
    final systems = _systems;
    if (systems == null) return null;
    for (var i = 0; i < systems.systems.length; i++) {
      final layout = systems.systems[i].layout;
      for (var s = 0; s < 2; s++) {
        final staff = s == 0 ? layout.upper : layout.lower;
        for (final region in staff.regions) {
          if (region.elementId == id) return (i, s, region.bounds);
        }
      }
    }
    return null;
  }

  /// The local **pixel** rectangle of element [id] on either staff, or null —
  /// for scroll-to-note (the app scrolls its viewport to reveal this rect).
  Rect? rectOfElement(String id) {
    final located = _locate(id);
    if (located == null) return null;
    final origin =
        located.$2 == 0 ? upperOrigin(located.$1) : lowerOrigin(located.$1);
    final b = located.$3;
    return Rect.fromLTWH(
      origin.dx + b.left * _staffSpace,
      origin.dy + b.top * _staffSpace,
      b.width * _staffSpace,
      b.height * _staffSpace,
    );
  }

  /// The empty-staff location under [local]: the nearest system, then the
  /// nearer of its two staves, quantized to the nearest line/space.
  StaffTarget? resolveStaffTarget(Offset local) {
    final systems = _systems;
    if (systems == null || systems.systems.isEmpty) return null;

    // Nearest system band.
    var systemIndex = 0;
    var bestDist = double.infinity;
    var y = 0.0;
    for (var i = 0; i < systems.systems.length; i++) {
      final h = systems.systems[i].layout.height * _staffSpace;
      final dist = local.dy < y
          ? y - local.dy
          : (local.dy > y + h ? local.dy - (y + h) : 0.0);
      if (dist < bestDist) {
        bestDist = dist;
        systemIndex = i;
      }
      y += h + _systemGap * _staffSpace;
    }

    final system = systems.systems[systemIndex];
    // Nearer staff: upper band top..+4, lower band top..+4.
    final upperTop = upperOrigin(systemIndex).dy;
    final lowerTop = lowerOrigin(systemIndex).dy;
    final boundary = (upperTop + 4 * _staffSpace + lowerTop) / 2;
    final staffIndex = local.dy < boundary ? 0 : 1;
    final staffLayout =
        staffIndex == 0 ? system.layout.upper : system.layout.lower;
    final origin =
        staffIndex == 0 ? upperOrigin(systemIndex) : lowerOrigin(systemIndex);

    final point = math.Point(
      (local.dx - origin.dx) / _staffSpace,
      (local.dy - origin.dy) / _staffSpace,
    );
    final staffPosition = (8 - 2 * point.y).round().clamp(-6, 14);
    var localMeasure = 0;
    for (final region in staffLayout.measureRegions) {
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
      staffIndex: staffIndex,
    );
  }

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

  // MouseTrackerAnnotation — reports null when the pointer leaves the widget.
  /// No enter callback (hover moves drive [onHover] via [handleEvent]).
  @override
  PointerEnterEventListener? get onEnter => null;

  /// Fires [onHover] with null when the pointer leaves the widget.
  @override
  PointerExitEventListener? get onExit =>
      onHover == null ? null : (_) => onHover?.call(null);

  /// The default cursor.
  @override
  MouseCursor get cursor => MouseCursor.defer;

  /// Whether this render object participates in mouse tracking.
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
    final systems = _systems;
    if (systems == null) return;
    final canvas = context.canvas;
    final braceBox =
        MusicFonts.metadataOrNull(_theme.musicFont)?.bBoxOf('brace');

    _paintLoopBand(canvas, offset); // behind the notes

    for (var i = 0; i < systems.systems.length; i++) {
      final layout = systems.systems[i].layout;
      final upper = offset + upperOrigin(i);
      final lower = offset + lowerOrigin(i);
      _painter.paintLayout(canvas, upper, layout.upper);
      _painter.paintLayout(canvas, lower, layout.lower);

      // Barline connectors between the staves.
      final barPaint = Paint()..color = _theme.staffColor;
      void connect(double xSpaces, double thickness) {
        canvas.drawLine(
          upper + Offset(xSpaces * _staffSpace, 4 * _staffSpace),
          lower + Offset(xSpaces * _staffSpace, 0),
          barPaint..strokeWidth = thickness * _staffSpace,
        );
      }

      final lines = layout.upper.primitives.whereType<LinePrimitive>();
      if (lines.isNotEmpty) connect(0, lines.first.thickness);
      for (final line in lines) {
        final vertical = line.from.x == line.to.x;
        final fullStaff = line.from.y == 0 && line.to.y == 4 ||
            line.from.y == 4 && line.to.y == 0;
        if (vertical && fullStaff) connect(line.from.x, line.thickness);
      }

      // Brace.
      if (braceBox != null) {
        final spanSpaces = 4 + layout.staffGap + 4;
        _painter.paintGlyph(
          canvas,
          lower,
          'brace',
          math.Point(-braceInset + 0.15, 4.0),
          _theme.staffColor,
          glyphScale: spanSpaces / braceBox.height,
        );
      }
    }

    _paintErrorMarks(canvas, offset);
    _paintGhost(canvas, offset);
    _paintCaret(canvas, offset);
  }

  void _paintLoopBand(Canvas canvas, Offset offset) {
    final range = _loopRange;
    final systems = _systems;
    if (range == null || systems == null) return;
    var start = _locate(range.$1);
    var end = _locate(range.$2);
    if (start == null || end == null) return;
    // Order start before end (by system, then x).
    if (start.$1 > end.$1 ||
        (start.$1 == end.$1 && start.$3.left > end.$3.left)) {
      final swap = start;
      start = end;
      end = swap;
    }
    final paint = Paint()
      ..color = _theme.highlightColor.withValues(alpha: 0.18);
    for (var i = start.$1; i <= end.$1; i++) {
      // A band spanning both staves of the system, at the resolved x range.
      final upper = offset + upperOrigin(i);
      final lower = offset + lowerOrigin(i);
      final left = i == start.$1 ? start.$3.left : 0.0;
      final right =
          i == end.$1 ? end.$3.right : systems.systems[i].layout.width;
      canvas.drawRect(
        Rect.fromLTRB(
          upper.dx + left * _staffSpace,
          upper.dy + -1 * _staffSpace,
          upper.dx + right * _staffSpace,
          lower.dy + 5 * _staffSpace,
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
      final origin = offset +
          (located.$2 == 0 ? upperOrigin(located.$1) : lowerOrigin(located.$1));
      final b = located.$3;
      final cx = origin.dx + (b.left + b.width / 2) * _staffSpace;
      final topY = origin.dy + -1.6 * _staffSpace;
      final w = 0.55 * _staffSpace;
      // A small downward wedge above the note's staff, in the mark's color.
      final path = Path()
        ..moveTo(cx - w / 2, topY)
        ..lineTo(cx + w / 2, topY)
        ..lineTo(cx, topY + w)
        ..close();
      canvas.drawPath(path, Paint()..color = entry.value.color);
    }
  }

  /// The (system index, staff layout, staff origin, measure start x) of
  /// [measureIndex] on [staffIndex] (0 upper, 1 lower), or null.
  (int, ScoreLayout, Offset, double)? _place(int measureIndex, int staffIndex) {
    final systems = _systems;
    if (systems == null) return null;
    for (var i = 0; i < systems.systems.length; i++) {
      final system = systems.systems[i];
      if (measureIndex < system.firstMeasure ||
          measureIndex > system.lastMeasure) {
        continue;
      }
      final staff = staffIndex == 0 ? system.layout.upper : system.layout.lower;
      final origin = staffIndex == 0 ? upperOrigin(i) : lowerOrigin(i);
      final localIndex = measureIndex - system.firstMeasure;
      for (final region in staff.measureRegions) {
        if (region.index == localIndex) {
          return (i, staff, origin, region.startX);
        }
      }
    }
    return null;
  }

  void _paintGhost(Canvas canvas, Offset offset) {
    final ghost = _ghostTarget;
    if (ghost == null) return;
    final placement = _place(ghost.measureIndex, ghost.staffIndex);
    if (placement == null) return;
    final (_, _, origin, startX) = placement;
    final xSpaces = startX + 1.0;
    final glyph = switch (_ghostDuration.base) {
      DurationBase.whole => SmuflGlyph.noteheadWhole,
      DurationBase.half => SmuflGlyph.noteheadHalf,
      _ => SmuflGlyph.noteheadBlack,
    };
    final color = _theme.highlightColor.withValues(alpha: 0.45);
    final y = (8 - ghost.staffPosition) / 2;
    final metadata = MusicFonts.metadataOrNull(_theme.musicFont);
    final width = metadata?.bBoxOf(glyph).width ?? 1.18;
    final o = offset + origin;
    _painter.paintGlyph(
        canvas, o, glyph, math.Point(xSpaces - width / 2, y), color);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.16 * _staffSpace;
    void ledger(int position) {
      final ly = (8 - position) / 2;
      canvas.drawLine(
        o + Offset((xSpaces - width / 2 - 0.4) * _staffSpace, ly * _staffSpace),
        o + Offset((xSpaces + width / 2 + 0.4) * _staffSpace, ly * _staffSpace),
        paint,
      );
    }

    for (var p = -2; p >= ghost.staffPosition; p -= 2) {
      ledger(p);
    }
    for (var p = 10; p <= ghost.staffPosition; p += 2) {
      ledger(p);
    }
  }

  void _paintCaret(Canvas canvas, Offset offset) {
    final caret = _caret;
    final systems = _systems;
    if (caret == null || systems == null) return;

    int? systemIndex;
    double? xSpaces;
    final beforeId = caret.beforeElementId;
    if (beforeId != null) {
      outer:
      for (var i = 0; i < systems.systems.length; i++) {
        final layout = systems.systems[i].layout;
        for (final staff in [layout.upper, layout.lower]) {
          for (final region in staff.regions) {
            if (region.elementId == beforeId) {
              systemIndex = i;
              xSpaces = region.bounds.left - 0.3;
              break outer;
            }
          }
        }
      }
    } else if (caret.measureIndex != null) {
      final placement = _place(caret.measureIndex!, 0);
      if (placement != null) {
        systemIndex = placement.$1;
        xSpaces = placement.$4;
      }
    }
    if (systemIndex == null || xSpaces == null) return;

    // A full-height insertion bar spanning both staves at the resolved x.
    final upper = offset + upperOrigin(systemIndex);
    final lower = offset + lowerOrigin(systemIndex);
    final paint = Paint()
      ..color = _theme.highlightColor
      ..strokeWidth = 0.14 * _staffSpace;
    canvas.drawLine(
      upper + Offset(xSpaces * _staffSpace, -1 * _staffSpace),
      lower + Offset(xSpaces * _staffSpace, 5 * _staffSpace),
      paint,
    );
  }
}
