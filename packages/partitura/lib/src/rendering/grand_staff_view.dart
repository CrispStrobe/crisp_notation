import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:partitura_core/partitura_core.dart';

import 'layout_painter.dart';
import 'music_font.dart';
import 'theme.dart';

/// Renders a [GrandStaff] (two staves joined by a brace, with connected
/// barlines and vertically aligned measures — a piano system).
///
/// Element taps report ids from either staff via [onElementTap]; keep ids
/// unique across both scores. Highlighting works exactly like
/// [StaffView]: repaint-only.
class GrandStaffView extends LeafRenderObjectWidget {
  /// The two staves.
  final GrandStaff grandStaff;

  /// Colors and ergonomics.
  final PartituraTheme theme;

  /// Pixels per staff space; null fits the system to the available width.
  final double? staffSpace;

  /// Vertical distance in staff spaces between the staves (upper bottom
  /// line to lower top line).
  final double staffGap;

  /// Ids of elements to paint in [PartituraTheme.highlightColor].
  final Set<String> highlightedIds;

  /// Called with the element id when the user taps an element on either
  /// staff.
  final void Function(String elementId)? onElementTap;

  /// Creates a grand staff view.
  const GrandStaffView({
    super.key,
    required this.grandStaff,
    this.theme = PartituraTheme.standard,
    this.staffSpace,
    this.staffGap = 4.0,
    this.highlightedIds = const {},
    this.onElementTap,
  });

  @override
  RenderGrandStaffView createRenderObject(BuildContext context) =>
      RenderGrandStaffView(
        grandStaff: grandStaff,
        theme: theme,
        staffSpace: staffSpace,
        staffGap: staffGap,
        highlightedIds: highlightedIds,
      )..onElementTap = onElementTap;

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGrandStaffView renderObject,
  ) {
    renderObject
      ..grandStaff = grandStaff
      ..theme = theme
      ..staffSpace = staffSpace
      ..staffGap = staffGap
      ..highlightedIds = highlightedIds
      ..onElementTap = onElementTap;
  }
}

/// Render object behind [GrandStaffView].
class RenderGrandStaffView extends RenderBox {
  /// Creates the render object.
  RenderGrandStaffView({
    required GrandStaff grandStaff,
    required PartituraTheme theme,
    double? staffSpace,
    required double staffGap,
    required Set<String> highlightedIds,
  })  : _grandStaff = grandStaff,
        _theme = theme,
        _staffSpace = staffSpace,
        _staffGap = staffGap,
        _highlightedIds = highlightedIds {
    _tap = TapGestureRecognizer(debugOwner: this)..onTapUp = _handleTapUp;
  }

  static const double _fallbackStaffSpace = 12;

  /// Space reserved left of the system for the brace, in staff spaces.
  static const double braceInset = 1.4;

  late final TapGestureRecognizer _tap;

  GrandStaffLayout? _layout;
  double _scale = _fallbackStaffSpace;
  late final LayoutPainter _painter = LayoutPainter(
    theme: _theme,
    scale: _scale,
    highlightedIds: _highlightedIds,
  );

  /// Called with the element id when the user taps an element.
  void Function(String elementId)? onElementTap;

  GrandStaff _grandStaff;

  /// The two staves.
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

  double? _staffSpace;

  /// Pixels per staff space; null fits to width.
  double? get staffSpace => _staffSpace;
  set staffSpace(double? value) {
    if (value == _staffSpace) return;
    _staffSpace = value;
    markNeedsLayout();
  }

  double _staffGap;

  /// Vertical distance in staff spaces between the staves.
  double get staffGap => _staffGap;
  set staffGap(double value) {
    if (value == _staffGap) return;
    _staffGap = value;
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

  /// The current layout, or null while the font metadata is loading.
  GrandStaffLayout? get grandLayout => _layout;

  /// Pixels per staff space in the current layout.
  double get scale => _scale;

  /// The pixel origin of the upper staff's staff-space (0, 0).
  Offset get upperOrigin {
    final layout = _layout;
    if (layout == null) return Offset.zero;
    return Offset(braceInset * _scale, -layout.upper.top * _scale);
  }

  /// The pixel origin of the lower staff's staff-space (0, 0).
  Offset get lowerOrigin {
    final layout = _layout;
    if (layout == null) return Offset.zero;
    return Offset(
      braceInset * _scale,
      (-layout.upper.top + 4 + layout.staffGap) * _scale,
    );
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
      final space = _staffSpace ?? _fallbackStaffSpace;
      return constraints.constrain(Size(
        constraints.hasBoundedWidth ? constraints.maxWidth : 40 * space,
        24 * space,
      ));
    }
    final layout = layoutGrandStaff(
      _grandStaff,
      _settingsFor(metadata),
      staffGap: _staffGap,
    );
    _layout = layout;
    final widthSpaces = layout.width + braceInset;
    _scale = _staffSpace ??
        (constraints.hasBoundedWidth
            ? constraints.maxWidth / widthSpaces
            : _fallbackStaffSpace);
    return constraints.constrain(
      Size(widthSpaces * _scale, layout.height * _scale),
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
    _painter.scale = _scale;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _measure(constraints);

  /// The id of the element containing [local] on either staff, or null.
  String? elementIdAt(Offset local) {
    final layout = _layout;
    if (layout == null) return null;
    String? findIn(ScoreLayout staff, Offset origin) {
      final point = math.Point(
        (local.dx - origin.dx) / _scale,
        (local.dy - origin.dy) / _scale,
      );
      final slop = _theme.hitSlop;
      String? bestId;
      var bestArea = double.infinity;
      for (final region in staff.regions) {
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
      return bestId;
    }

    return findIn(layout.upper, upperOrigin) ??
        findIn(layout.lower, lowerOrigin);
  }

  @override
  bool hitTestSelf(Offset position) => onElementTap != null;

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerDownEvent && onElementTap != null) {
      _tap.addPointer(event);
    }
  }

  void _handleTapUp(TapUpDetails details) {
    final id = elementIdAt(details.localPosition);
    if (id != null) onElementTap?.call(id);
  }

  @override
  void dispose() {
    _tap.dispose();
    _painter.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final layout = _layout;
    if (layout == null) return;
    final canvas = context.canvas;
    final upper = offset + upperOrigin;
    final lower = offset + lowerOrigin;

    _painter.paintLayout(canvas, upper, layout.upper);
    _painter.paintLayout(canvas, lower, layout.lower);

    // Barline connectors: join every full-staff barline of the upper
    // staff down to the lower staff, plus the systemic start line.
    final barPaint = Paint()..color = _theme.staffColor;
    void connect(double xSpaces, double thickness) {
      canvas.drawLine(
        upper + Offset(xSpaces * _scale, 4 * _scale),
        lower + Offset(xSpaces * _scale, 0),
        barPaint..strokeWidth = thickness * _scale,
      );
    }

    connect(
        0, layout.upper.primitives.whereType<LinePrimitive>().first.thickness);
    for (final line in layout.upper.primitives.whereType<LinePrimitive>()) {
      final vertical = line.from.x == line.to.x;
      final fullStaff = line.from.y == 0 && line.to.y == 4 ||
          line.from.y == 4 && line.to.y == 0;
      if (vertical && fullStaff) connect(line.from.x, line.thickness);
    }

    // Brace spanning from the upper top line to the lower bottom line:
    // 4 spaces per staff plus the gap between them.
    final braceBox =
        MusicFonts.metadataOrNull(_theme.musicFont)?.bBoxOf('brace');
    if (braceBox != null) {
      final spanSpaces = 4 + layout.staffGap + 4;
      final glyphScale = spanSpaces / braceBox.height;
      _painter.paintGlyph(
        canvas,
        lower,
        'brace',
        math.Point(-braceInset + 0.15, 4.0),
        _theme.staffColor,
        glyphScale: glyphScale,
      );
    }
  }
}
