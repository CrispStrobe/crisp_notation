import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:partitura_core/partitura_core.dart';

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
        ..onStaffTap = onStaffTap;

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
      ..onStaffTap = onStaffTap;
  }
}

/// Render object behind [MultiSystemView].
class RenderMultiSystemView extends RenderBox {
  /// Creates the render object.
  RenderMultiSystemView({
    required Score score,
    required PartituraTheme theme,
    required double staffSpace,
    required double systemGap,
    required bool justify,
    required Set<String> highlightedIds,
    Map<String, Color> elementColors = const {},
  })  : _score = score,
        _theme = theme,
        _staffSpace = staffSpace,
        _systemGap = systemGap,
        _justify = justify,
        _highlightedIds = highlightedIds,
        _elementColors = elementColors {
    _tap = TapGestureRecognizer(debugOwner: this)..onTapUp = _handleTapUp;
  }

  late final TapGestureRecognizer _tap;

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

  Map<String, Color> _elementColors;

  /// Per-element ink colors. Repaint only — no relayout.
  Map<String, Color> get elementColors => _elementColors;
  set elementColors(Map<String, Color> value) {
    if (mapEquals(value, _elementColors)) return;
    _elementColors = value;
    _painter.elementColors = value;
    markNeedsPaint();
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
      return constraints.constrain(Size(
        constraints.hasBoundedWidth ? constraints.maxWidth : 40 * _staffSpace,
        12 * _staffSpace,
      ));
    }
    final maxWidthSpaces =
        constraints.hasBoundedWidth ? constraints.maxWidth / _staffSpace : 40.0;
    final layout = layoutSystems(
      _score,
      _settingsFor(metadata),
      maxWidth: maxWidthSpaces,
      justify: _justify,
    );
    _layout = layout;
    final widthSpaces =
        layout.systems.map((s) => s.layout.width).reduce(math.max);
    return constraints.constrain(Size(
      widthSpaces * _staffSpace,
      layout.heightWith(_systemGap) * _staffSpace,
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

  // ------------------------------------------------------------------ input

  @override
  bool hitTestSelf(Offset position) =>
      onElementTap != null || onStaffTap != null;

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerDownEvent &&
        (onElementTap != null || onStaffTap != null)) {
      _tap.addPointer(event);
    }
  }

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
    _tap.dispose();
    _painter.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ paint

  @override
  void paint(PaintingContext context, Offset offset) {
    final layout = _layout;
    if (layout == null) return;
    for (var i = 0; i < layout.systems.length; i++) {
      _painter.paintLayout(
        context.canvas,
        offset + originOfSystem(i),
        layout.systems[i].layout,
      );
    }
  }
}
