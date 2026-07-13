import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:partitura_core/partitura_core.dart';

import 'layout_painter.dart';
import 'music_font.dart';
import 'theme.dart';

/// Renders a [StaffSystem] — N notation staves stacked as one system, with
/// vertically aligned measures, barlines connected through the system, and
/// bracket/brace groups at the left. Generalizes [GrandStaffView].
///
/// Element taps report ids from any staff via [onElementTap]; keep ids unique
/// across the staves. Highlighting is repaint-only, like [StaffView].
class StaffSystemView extends LeafRenderObjectWidget {
  /// The staves and their groups.
  final StaffSystem system;

  /// Colors and ergonomics.
  final PartituraTheme theme;

  /// Pixels per staff space; null fits the system to the available width.
  final double? staffSpace;

  /// Line-to-line vertical distance between adjacent staves, in staff spaces.
  final double staffGap;

  /// Whether to align simultaneous notes vertically across every staff of the
  /// system (cross-staff onset gridding). Single-voice staves only.
  final bool gridAlign;

  /// Whether to drop staves that hold only rests in this system (keeping at
  /// least one), the standard "hide empty staves" engraving option.
  final bool hideEmptyStaves;

  /// Ids painted in [PartituraTheme.highlightColor].
  final Set<String> highlightedIds;

  /// Called with the element id when the user taps an element.
  final void Function(String elementId)? onElementTap;

  /// Creates a staff-system view.
  const StaffSystemView({
    super.key,
    required this.system,
    this.theme = PartituraTheme.standard,
    this.staffSpace,
    this.staffGap = 4.0,
    this.gridAlign = true,
    this.hideEmptyStaves = false,
    this.highlightedIds = const {},
    this.onElementTap,
  });

  @override
  RenderStaffSystemView createRenderObject(BuildContext context) =>
      RenderStaffSystemView(
        system: system,
        theme: theme,
        staffSpace: staffSpace,
        staffGap: staffGap,
        gridAlign: gridAlign,
        hideEmptyStaves: hideEmptyStaves,
        highlightedIds: highlightedIds,
      )..onElementTap = onElementTap;

  @override
  void updateRenderObject(
      BuildContext context, RenderStaffSystemView renderObject) {
    renderObject
      ..system = system
      ..theme = theme
      ..staffSpace = staffSpace
      ..staffGap = staffGap
      ..gridAlign = gridAlign
      ..hideEmptyStaves = hideEmptyStaves
      ..highlightedIds = highlightedIds
      ..onElementTap = onElementTap;
  }
}

/// Render object behind [StaffSystemView].
class RenderStaffSystemView extends RenderBox {
  /// Creates the render object.
  RenderStaffSystemView({
    required StaffSystem system,
    required PartituraTheme theme,
    double? staffSpace,
    required double staffGap,
    required bool gridAlign,
    required bool hideEmptyStaves,
    required Set<String> highlightedIds,
  })  : _system = system,
        _theme = theme,
        _staffSpace = staffSpace,
        _staffGap = staffGap,
        _gridAlign = gridAlign,
        _hideEmptyStaves = hideEmptyStaves,
        _highlightedIds = highlightedIds {
    _tap = TapGestureRecognizer(debugOwner: this)..onTapUp = _handleTapUp;
  }

  /// Space reserved at the left for brackets/braces, in staff spaces.
  static const double leftInset = 1.8;

  late final TapGestureRecognizer _tap;
  StaffSystemLayout? _layout;
  double _scale = 12;

  late final LayoutPainter _painter = LayoutPainter(
      theme: _theme, scale: _scale, highlightedIds: _highlightedIds);

  /// Called with the element id when the user taps an element.
  void Function(String elementId)? onElementTap;

  StaffSystem _system;

  /// The staves and groups to render.
  StaffSystem get system => _system;
  set system(StaffSystem value) {
    if (value == _system) return;
    _system = value;
    markNeedsLayout();
  }

  PartituraTheme _theme;

  /// Colors and ergonomics.
  PartituraTheme get theme => _theme;
  set theme(PartituraTheme value) {
    if (value == _theme) return;
    final relayout = value.lineBoost != _theme.lineBoost ||
        value.musicFont != _theme.musicFont;
    _theme = value;
    _painter.theme = value;
    if (relayout) {
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

  /// Line-to-line vertical distance between adjacent staves.
  double get staffGap => _staffGap;
  set staffGap(double value) {
    if (value == _staffGap) return;
    _staffGap = value;
    markNeedsLayout();
  }

  bool _gridAlign;

  /// Whether simultaneous notes align across every staff of the system.
  bool get gridAlign => _gridAlign;
  set gridAlign(bool value) {
    if (value == _gridAlign) return;
    _gridAlign = value;
    markNeedsLayout();
  }

  bool _hideEmptyStaves;

  /// Whether staves holding only rests are dropped from this system.
  bool get hideEmptyStaves => _hideEmptyStaves;
  set hideEmptyStaves(bool value) {
    if (value == _hideEmptyStaves) return;
    _hideEmptyStaves = value;
    markNeedsLayout();
  }

  Set<String> _highlightedIds;

  /// Ids painted in the highlight color.
  Set<String> get highlightedIds => _highlightedIds;
  set highlightedIds(Set<String> value) {
    if (value.length == _highlightedIds.length &&
        value.containsAll(_highlightedIds)) {
      return;
    }
    _highlightedIds = value;
    _painter.highlightedIds = value;
    markNeedsPaint();
  }

  /// The laid-out system (for tests / interaction geometry).
  StaffSystemLayout? get systemLayout => _layout;

  /// Pixel origin (where its own y=0 maps) of staff [i].
  Offset staffOrigin(int i) {
    final layout = _layout;
    if (layout == null) return Offset.zero;
    return Offset(
      leftInset * _scale,
      (layout.staffTop(i) - layout.top) * _scale,
    );
  }

  Size _measure(BoxConstraints constraints) {
    final metadata = MusicFonts.metadataOrNull(_theme.musicFont);
    if (metadata == null) return constraints.smallest;
    final layout = layoutStaffSystem(
        _system, LayoutSettings(metadata: metadata),
        staffGap: _staffGap,
        gridAlign: _gridAlign,
        hideEmptyStaves: _hideEmptyStaves);
    _layout = layout;
    final widthSpaces = layout.width + leftInset;
    _scale = _staffSpace ??
        (constraints.hasBoundedWidth ? constraints.maxWidth / widthSpaces : 12);
    _painter.scale = _scale;
    return constraints
        .constrain(Size(widthSpaces * _scale, layout.height * _scale));
  }

  @override
  void performLayout() => size = _measure(constraints);

  @override
  Size computeDryLayout(BoxConstraints constraints) => _measure(constraints);

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

  /// The element id at [local] pixels, searching every staff.
  String? elementIdAt(Offset local) {
    final layout = _layout;
    if (layout == null) return null;
    for (var i = 0; i < layout.staves.length; i++) {
      final origin = staffOrigin(i);
      final p = (local - origin) / _scale;
      for (final region in layout.staves[i].regions) {
        if (region.bounds.containsPoint(math.Point(p.dx, p.dy))) {
          return region.elementId;
        }
      }
    }
    return null;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final layout = _layout;
    if (layout == null) return;
    final canvas = context.canvas;
    final origins = [
      for (var i = 0; i < layout.staves.length; i++) offset + staffOrigin(i),
    ];
    for (var i = 0; i < layout.staves.length; i++) {
      _painter.paintLayout(canvas, origins[i], layout.staves[i]);
    }
    if (layout.staves.length < 2) {
      _paintBrackets(canvas, origins);
      return;
    }

    // Connect full-staff barlines within each barline group — the group's top
    // staff down to its bottom line — breaking in the gaps between groups (the
    // custom-span barline). A single-staff group draws no systemic connector
    // (its own per-staff barlines already show). With the default
    // `connectBarlines: true` and no explicit groups, this is one group over
    // every staff — the classic continuous systemic barline.
    final barPaint = Paint()..color = _theme.staffColor;
    final ref = layout.staves.first.primitives.whereType<LinePrimitive>();
    final startThickness = ref.isEmpty ? 0.13 : ref.first.thickness;
    final bars = <({double x, double thickness})>[
      (x: 0.0, thickness: startThickness), // systemic start line
      for (final line in ref)
        if (line.from.x == line.to.x &&
            ((line.from.y == 0 && line.to.y == 4) ||
                (line.from.y == 4 && line.to.y == 0)))
          (x: line.from.x, thickness: line.thickness),
    ];
    for (final group in layout.source.effectiveBarlineGroups) {
      if (group.first == group.last) continue; // no cross-staff connector
      final topY = origins[group.first].dy;
      final bottomY = origins[group.last].dy + 4 * _scale;
      for (final bar in bars) {
        final x = origins.first.dx + bar.x * _scale;
        canvas.drawLine(Offset(x, topY), Offset(x, bottomY),
            barPaint..strokeWidth = bar.thickness * _scale);
      }
    }
    _paintBrackets(canvas, origins);
  }

  /// How many other brackets strictly contain [b] — its nesting depth. Deeper
  /// (more-contained) groups sit nearer the staff; outer groups shift left.
  int _depthOf(StaffBracket b, List<StaffBracket> all) => all
      .where((a) =>
          !identical(a, b) &&
          a.first <= b.first &&
          b.last <= a.last &&
          (a.last - a.first) > (b.last - b.first))
      .length;

  void _paintBrackets(Canvas canvas, List<Offset> origins) {
    final layout = _layout!;
    // Brackets follow the laid-out system (remapped when staves are hidden).
    final brackets = layout.source.brackets;
    if (brackets.isEmpty) return;
    // Innermost sits at the base position; each enclosing level steps left.
    const step = 0.6; // staff spaces per nesting level
    final maxDepth =
        brackets.map((b) => _depthOf(b, brackets)).fold(0, (m, d) => d > m ? d : m);
    for (final group in brackets) {
      final shift = (maxDepth - _depthOf(group, brackets)) * step * _scale;
      final top = origins[group.first].dy; // top line of the first staff
      final bottom = origins[group.last].dy + 4 * _scale;
      final x = origins.first.dx;
      if (group.kind == StaffBracketKind.brace) {
        final box =
            MusicFonts.metadataOrNull(_theme.musicFont)?.bBoxOf('brace');
        if (box != null) {
          final span =
              layout.staffTop(group.last) + 4 - layout.staffTop(group.first);
          _painter.paintGlyph(
            canvas,
            Offset(x - shift, origins[group.last].dy),
            'brace',
            math.Point(-leftInset + 0.35, 4.0),
            _theme.staffColor,
            glyphScale: span / box.height,
          );
        }
      } else {
        // A square bracket: a thick line just left of the staves, with short
        // horizontal serifs top and bottom.
        final bx = x - 0.5 * _scale - shift;
        final paint = Paint()
          ..color = _theme.staffColor
          ..strokeWidth = 0.4 * _scale;
        canvas.drawLine(Offset(bx, top), Offset(bx, bottom), paint);
        final serif = Paint()
          ..color = _theme.staffColor
          ..strokeWidth = 0.16 * _scale;
        canvas.drawLine(Offset(bx, top), Offset(bx + 0.6 * _scale, top), serif);
        canvas.drawLine(
            Offset(bx, bottom), Offset(bx + 0.6 * _scale, bottom), serif);
      }
    }
  }

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }
}
