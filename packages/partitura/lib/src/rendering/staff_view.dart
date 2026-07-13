import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:partitura_core/partitura_core.dart';

import 'layout_painter.dart';
import 'music_font.dart';
import 'theme.dart';

/// Renders a [Score] as a single staff.
///
/// Layout comes from `partitura_core`'s [LayoutEngine]; this widget only
/// converts staff spaces to pixels (one scale factor) and paints. Elements
/// whose id is in [highlightedIds] are painted in the theme's highlight
/// color — changing highlights repaints but never relayouts.
///
/// The music font's metadata (Bravura by default; see
/// [PartituraTheme.musicFont]) loads asynchronously on first use; until it
/// arrives the widget paints nothing. Await [MusicFonts.load] up front (e.g. in
/// `main()`) to avoid the one-frame gap.
class StaffView extends LeafRenderObjectWidget {
  /// The score to render.
  final Score score;

  /// Colors and ergonomics.
  final PartituraTheme theme;

  /// Pixels per staff space; null fits the score to the available width.
  final double? staffSpace;

  /// Ids of elements to paint in [PartituraTheme.highlightColor].
  final Set<String> highlightedIds;

  /// Per-element ink colors (app-driven note coloring). Takes precedence over
  /// [PartituraTheme.elementColors]; a highlight still wins over both.
  final Map<String, Color> elementColors;

  /// Draws the educational note-name overlay (the pitch letter under each
  /// note) — for teaching/beginner views.
  final bool showNoteNames;

  /// Draws the educational rhythm-count overlay (the beat number / `+` above
  /// each note) — for teaching/beginner views.
  final bool showBeatNumbers;

  /// Draws a small bar number above the start of each measure (pickups are
  /// unnumbered, so the first full bar reads `1`).
  final bool showMeasureNumbers;

  /// With [showMeasureNumbers], label only bar 1 and every Nth bar (the common
  /// "every 5 bars" convention); 1 (default) numbers every bar.
  final int measureNumberInterval;

  /// Called with the element id when the user taps an element.
  final void Function(String elementId)? onElementTap;

  /// Notehead shape scheme (e.g. Sacred-Harp four-shape); defaults to round.
  final NoteheadScheme noteheadScheme;

  /// Creates a staff view.
  const StaffView({
    super.key,
    required this.score,
    this.theme = PartituraTheme.standard,
    this.staffSpace,
    this.highlightedIds = const {},
    this.elementColors = const {},
    this.showNoteNames = false,
    this.showBeatNumbers = false,
    this.showMeasureNumbers = false,
    this.measureNumberInterval = 1,
    this.onElementTap,
    this.noteheadScheme = NoteheadScheme.normal,
  });

  @override
  RenderStaffView createRenderObject(BuildContext context) => RenderStaffView(
        score: score,
        theme: theme,
        staffSpace: staffSpace,
        highlightedIds: highlightedIds,
        elementColors: elementColors,
        showNoteNames: showNoteNames,
        showBeatNumbers: showBeatNumbers,
        showMeasureNumbers: showMeasureNumbers,
        measureNumberInterval: measureNumberInterval,
        noteheadScheme: noteheadScheme,
      )..onElementTap = onElementTap;

  @override
  void updateRenderObject(BuildContext context, RenderStaffView renderObject) {
    renderObject
      ..score = score
      ..theme = theme
      ..staffSpace = staffSpace
      ..highlightedIds = highlightedIds
      ..elementColors = elementColors
      ..showNoteNames = showNoteNames
      ..showBeatNumbers = showBeatNumbers
      ..showMeasureNumbers = showMeasureNumbers
      ..measureNumberInterval = measureNumberInterval
      ..noteheadScheme = noteheadScheme
      ..onElementTap = onElementTap;
  }
}

/// A ghost-note preview: a semi-transparent notehead following a drag,
/// quantized to a staff position. Set on [RenderStaffView] by
/// `InteractiveStaff`.
class GhostNote {
  /// Horizontal center of the ghost notehead, in staff spaces.
  final double xSpaces;

  /// Quantized staff position (0 = bottom line).
  final int staffPosition;

  /// Duration deciding the notehead glyph.
  final NoteDuration duration;

  /// Creates a ghost-note preview spec.
  const GhostNote({
    required this.xSpaces,
    required this.staffPosition,
    required this.duration,
  });

  @override
  bool operator ==(Object other) =>
      other is GhostNote &&
      other.xSpaces == xSpaces &&
      other.staffPosition == staffPosition &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(xSpaces, staffPosition, duration);
}

/// Render object behind [StaffView]; also the geometry service used by
/// `InteractiveStaff` (element hit testing, staff-position quantization,
/// ghost-note painting).
class RenderStaffView extends RenderBox {
  /// Creates the render object.
  RenderStaffView({
    required Score score,
    required PartituraTheme theme,
    double? staffSpace,
    required Set<String> highlightedIds,
    Map<String, Color> elementColors = const {},
    bool showNoteNames = false,
    bool showBeatNumbers = false,
    bool showMeasureNumbers = false,
    int measureNumberInterval = 1,
    NoteheadScheme noteheadScheme = NoteheadScheme.normal,
  })  : _score = score,
        _theme = theme,
        _staffSpace = staffSpace,
        _highlightedIds = highlightedIds,
        _elementColors = elementColors,
        _showNoteNames = showNoteNames,
        _showBeatNumbers = showBeatNumbers,
        _showMeasureNumbers = showMeasureNumbers,
        _measureNumberInterval = measureNumberInterval,
        _noteheadScheme = noteheadScheme {
    _tap = TapGestureRecognizer(debugOwner: this)..onTapUp = _handleTapUp;
  }

  static const LayoutEngine _engine = LayoutEngine();
  static const double _fallbackStaffSpace = 12;

  late final TapGestureRecognizer _tap;

  ScoreLayout? _layout;
  double _scale = _fallbackStaffSpace;
  late final LayoutPainter _painter = LayoutPainter(
    theme: _theme,
    scale: _scale,
    highlightedIds: _highlightedIds,
    elementColors: _elementColors,
  );

  /// Called with the element id when the user taps an element.
  void Function(String elementId)? onElementTap;

  /// Called when a tap lands on no element: quantized staff position and
  /// measure index (used by `InteractiveStaff`).
  void Function(int staffPosition, int measureIndex)? onStaffTap;

  Score _score;

  /// The score to render.
  Score get score => _score;
  set score(Score value) {
    if (value == _score) return;
    _score = value;
    markNeedsLayout();
    markNeedsSemanticsUpdate(); // element labels changed
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

  bool _showNoteNames;

  /// Whether to draw the educational note-name overlay. Changes the display
  /// list, so this relayouts.
  bool get showNoteNames => _showNoteNames;
  set showNoteNames(bool value) {
    if (value == _showNoteNames) return;
    _showNoteNames = value;
    markNeedsLayout();
  }

  NoteheadScheme _noteheadScheme;

  /// Notehead shape scheme (round or a shape-note scheme). Relayouts.
  NoteheadScheme get noteheadScheme => _noteheadScheme;
  set noteheadScheme(NoteheadScheme value) {
    if (value == _noteheadScheme) return;
    _noteheadScheme = value;
    markNeedsLayout();
  }

  bool _showBeatNumbers;

  /// Whether to draw the educational beat-count overlay. Relayouts.
  bool get showBeatNumbers => _showBeatNumbers;
  set showBeatNumbers(bool value) {
    if (value == _showBeatNumbers) return;
    _showBeatNumbers = value;
    markNeedsLayout();
  }

  bool _showMeasureNumbers;

  /// Whether to draw bar numbers above each measure. Relayouts.
  bool get showMeasureNumbers => _showMeasureNumbers;
  set showMeasureNumbers(bool value) {
    if (value == _showMeasureNumbers) return;
    _showMeasureNumbers = value;
    markNeedsLayout();
  }

  int _measureNumberInterval;

  /// Label only bar 1 and every Nth bar (1 = every bar). Relayouts.
  int get measureNumberInterval => _measureNumberInterval;
  set measureNumberInterval(int value) {
    if (value == _measureNumberInterval) return;
    _measureNumberInterval = value;
    markNeedsLayout();
  }

  GhostNote? _ghostNote;

  /// Ghost-note preview; repaint only.
  GhostNote? get ghostNote => _ghostNote;
  set ghostNote(GhostNote? value) {
    if (value == _ghostNote) return;
    _ghostNote = value;
    markNeedsPaint();
  }

  // -------------------------------------------------------------- geometry

  /// The current layout in staff spaces, or null while the font metadata
  /// is still loading.
  ScoreLayout? get scoreLayout => _layout;

  /// Pixels per staff space in the current layout.
  double get scale => _scale;

  LayoutSettings _settingsFor(SmuflMetadata metadata) {
    final boost = _theme.lineBoost;
    final base = LayoutSettings(metadata: metadata);
    if (boost == 1.0 && _noteheadScheme == NoteheadScheme.normal) return base;
    return LayoutSettings(
      metadata: metadata,
      noteheadScheme: _noteheadScheme,
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
        12 * space,
      ));
    }
    final layout = _engine.layout(_score, _settingsFor(metadata),
        showNoteNames: _showNoteNames,
        showBeatNumbers: _showBeatNumbers,
        showMeasureNumbers: _showMeasureNumbers,
        measureNumberInterval: _measureNumberInterval);
    _layout = layout;
    _scale = _staffSpace ??
        (constraints.hasBoundedWidth
            ? constraints.maxWidth / layout.width
            : _fallbackStaffSpace);
    return constraints
        .constrain(Size(layout.width * _scale, layout.height * _scale));
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

  /// Converts a local pixel offset to staff-space coordinates.
  math.Point<double> localToStaff(Offset local) {
    final top = _layout?.top ?? 0;
    return math.Point(local.dx / _scale, local.dy / _scale + top);
  }

  /// Converts staff-space coordinates to a local pixel offset.
  Offset staffToLocal(math.Point<double> point) {
    final top = _layout?.top ?? 0;
    return Offset(point.x * _scale, (point.y - top) * _scale);
  }

  /// The id of the element whose (hit-slop-inflated) region contains
  /// [local], or null. Overlapping regions resolve to the smallest one.
  String? elementIdAt(Offset local) {
    final layout = _layout;
    if (layout == null) return null;
    final point = localToStaff(local);
    final slop = _theme.hitSlop;
    String? bestId;
    var bestArea = double.infinity;
    for (final region in layout.regions) {
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

  /// Read-only hit regions of every element with an id, in **local pixel**
  /// coordinates, each tagged with the `measureIndex` it sits in — for
  /// app-side marquee / range selection and custom overlays.
  List<({String id, Rect bounds, int measureIndex})> get elementRegions {
    final layout = _layout;
    if (layout == null) return const [];
    return [
      for (final region in layout.regions)
        (
          id: region.elementId,
          bounds: () {
            final b = region.bounds;
            final topLeft = staffToLocal(math.Point(b.left, b.top));
            return Rect.fromLTWH(
                topLeft.dx, topLeft.dy, b.width * _scale, b.height * _scale);
          }(),
          measureIndex: quantizeStaffPosition(staffToLocal(
                  math.Point(region.bounds.left + region.bounds.width / 2, 2)))
              .$2,
        ),
    ];
  }

  /// The ids of every element whose hit region intersects [localRect] (local
  /// pixel coordinates) — a marquee selection.
  List<String> elementIdsIn(Rect localRect) => [
        for (final region in elementRegions)
          if (region.bounds.overlaps(localRect)) region.id,
      ];

  // ------------------------------------------------------- accessibility (3.9)

  List<SemanticsNode> _semanticsNodes = const [];

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    // Each note/rest becomes an explicit child node a screen reader can focus.
    config.isSemanticBoundary = true;
    config.explicitChildNodes = true;
  }

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    final labels = semanticLabels(_score);
    final nodes = <SemanticsNode>[];
    for (final region in elementRegions) {
      final label = labels[region.id];
      if (label == null || region.bounds.isEmpty) continue;
      final child = _semanticsNodes.length > nodes.length
          ? _semanticsNodes[nodes.length]
          : SemanticsNode();
      child
        ..rect = region.bounds
        ..updateWith(
          config: SemanticsConfiguration()
            ..isReadOnly = true
            ..textDirection = TextDirection.ltr
            ..label = label,
          childrenInInversePaintOrder: const <SemanticsNode>[],
        );
      nodes.add(child);
    }
    _semanticsNodes = nodes;
    node.updateWith(config: config, childrenInInversePaintOrder: nodes);
  }

  /// Quantizes [local] to the nearest staff position (line or space,
  /// including the ledger range) and the measure index under the tap.
  (int staffPosition, int measureIndex) quantizeStaffPosition(Offset local) {
    final layout = _layout;
    final point = localToStaff(local);
    final position = (8 - 2 * point.y).round().clamp(-6, 14);
    var measureIndex = 0;
    if (layout != null) {
      for (final region in layout.measureRegions) {
        if (point.x >= region.startX) measureIndex = region.index;
      }
    }
    return (position, measureIndex);
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
      return;
    }
    final handler = onStaffTap;
    if (handler != null) {
      final (position, measureIndex) =
          quantizeStaffPosition(details.localPosition);
      handler(position, measureIndex);
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
    final canvas = context.canvas;
    final origin = offset + Offset(0, -layout.top * _scale);
    _painter.paintLayout(canvas, origin, layout);
    _paintGhostNote(canvas, offset);
  }

  void _paintGhostNote(Canvas canvas, Offset offset) {
    final ghost = _ghostNote;
    if (ghost == null) return;
    final glyph = switch (ghost.duration.base) {
      DurationBase.whole => SmuflGlyph.noteheadWhole,
      DurationBase.half => SmuflGlyph.noteheadHalf,
      _ => SmuflGlyph.noteheadBlack,
    };
    final color = _theme.highlightColor.withValues(alpha: 0.45);
    final y = (8 - ghost.staffPosition) / 2;
    final metadata = MusicFonts.metadataOrNull(_theme.musicFont);
    final width = metadata?.bBoxOf(glyph).width ?? 1.18;
    final origin = offset + Offset(0, -(_layout?.top ?? 0) * _scale);
    _painter.paintGlyph(
      canvas,
      origin,
      glyph,
      math.Point(ghost.xSpaces - width / 2, y),
      color,
    );
    // Preview ledger lines so out-of-staff targets read correctly.
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.16 * _scale;
    for (var p = -2; p >= ghost.staffPosition; p -= 2) {
      _paintGhostLedger(canvas, offset, ghost.xSpaces, p, width, paint);
    }
    for (var p = 10; p <= ghost.staffPosition; p += 2) {
      _paintGhostLedger(canvas, offset, ghost.xSpaces, p, width, paint);
    }
  }

  void _paintGhostLedger(
    Canvas canvas,
    Offset offset,
    double xSpaces,
    int position,
    double headWidth,
    Paint paint,
  ) {
    final y = (8 - position) / 2;
    canvas.drawLine(
      offset + staffToLocal(math.Point(xSpaces - headWidth / 2 - 0.4, y)),
      offset + staffToLocal(math.Point(xSpaces + headWidth / 2 + 0.4, y)),
      paint,
    );
  }
}
