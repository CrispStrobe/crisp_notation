import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter/widgets.dart' hide PageMetrics;

import '../interaction/editor_caret.dart';
import '../interaction/element_region_controller.dart';
import '../interaction/staff_target.dart';
import 'multi_part_view.dart';
import 'theme.dart';

/// [MultiPartView] with **part-aware** interaction (Workshop contract C12):
/// element taps, quantized staff-taps that report *which part* was hit, a hover
/// placement ghost and drag-to-move — the multi-part counterpart of
/// `InteractiveStaff` / `InteractiveGrandStaffView`.
///
/// Interaction lives here (a wrapper widget); [MultiPartView]'s render object
/// stays the geometry service (`targetAt`, `elementIdAt`). Every part-aware
/// callback reports a `partIndex` **plus** a [StaffTarget] (whose `staffIndex`
/// mirrors the part and `systemIndex` is the page-local system). The element id
/// is the element's own id in the `MultiPartScore` — no `p<n>:` prefix.
///
/// Wired now: tap-select, staff-tap-to-place, hover ghost, drag-to-move, the
/// `highlightedIds` / `elementColors` / `suppressElementIds` overlays, an
/// `ElementRegionController` binding (C12c — marquee / cross-part region
/// queries), and an `EditorCaret` (C12b — insertion caret in the owning part).
/// A **live drag preview** is achievable app-side by combining
/// `suppressElementIds` (hide the dragged note) with the placement ghost
/// (`ghostPart`/`ghostTarget` following the pointer) — so a dedicated
/// `dragPreviewOpacity` (real-glyph translation, as single-part C10b) is an
/// optional future nicety, not required.
class InteractiveMultiPartView extends StatefulWidget {
  /// The multi-part document to render.
  final MultiPartScore document;

  /// The page box.
  final PageMetrics metrics;

  /// Colors and ergonomics.
  final CrispNotationTheme theme;

  /// Pixels per staff space.
  final double staffSpace;

  /// Line-to-line distance between staves of a system, in staff spaces.
  final double staffGap;

  /// Distance between stacked systems, in staff spaces.
  final double systemGap;

  /// Which page to show.
  final int pageIndex;

  /// Ids painted in the highlight color.
  final Set<String> highlightedIds;

  /// Per-element ink colors.
  final Map<String, Color> elementColors;

  /// Ids hidden from the layout — a clean drag-source hide (C10a).
  final Set<String> suppressElementIds;

  /// A placement ghost of [ghostDuration] at [ghostTarget] in part [ghostPart].
  final int? ghostPart;

  /// The target of the placement ghost, or null for none.
  final StaffTarget? ghostTarget;

  /// The notehead duration of the placement ghost.
  final NoteDuration ghostDuration;

  /// Called with the element id when the user taps an element.
  final void Function(String elementId)? onElementTap;

  /// Called when a tap (or a placement drop) lands on empty staff space: the
  /// part it fell in and the quantized target.
  final void Function(int partIndex, StaffTarget target)? onStaffTap;

  /// Called as the pointer hovers, with the part and target under it (or null
  /// off the surface) — drive a placement ghost from this.
  final void Function(int partIndex, StaffTarget? target)? onHover;

  /// Called when a drag begins on an existing element, with its id.
  final void Function(String elementId)? onElementDragStart;

  /// Called as the dragged element moves, with its id and the live drop target.
  final void Function(String elementId, int partIndex, StaffTarget target)?
      onElementDragUpdate;

  /// Called when the drag ends, with the element id and its drop target.
  final void Function(String elementId, int partIndex, StaffTarget target)?
      onElementDragEnd;

  /// Exposes this page's element hit-regions (across all parts) to app code —
  /// the geometry behind marquee selection / drag-to-reorder (C12c).
  final ElementRegionController? controller;

  /// An insertion caret drawn before its `beforeElementId`, in that element's
  /// part (C12b). Null draws none.
  final EditorCaret? caret;

  /// Whether to label each system's first bar (from bar 2 on) with its global
  /// measure number.
  final bool showMeasureNumbers;

  /// Creates an interactive multi-part view.
  const InteractiveMultiPartView({
    super.key,
    required this.document,
    required this.metrics,
    this.theme = CrispNotationTheme.standard,
    this.staffSpace = 12,
    this.staffGap = 4.0,
    this.systemGap = 10,
    this.pageIndex = 0,
    this.highlightedIds = const {},
    this.elementColors = const {},
    this.suppressElementIds = const {},
    this.ghostPart,
    this.ghostTarget,
    this.ghostDuration = NoteDuration.quarter,
    this.onElementTap,
    this.onStaffTap,
    this.onHover,
    this.onElementDragStart,
    this.onElementDragUpdate,
    this.onElementDragEnd,
    this.controller,
    this.caret,
    this.showMeasureNumbers = false,
  });

  @override
  State<InteractiveMultiPartView> createState() =>
      _InteractiveMultiPartViewState();
}

class _InteractiveMultiPartViewState extends State<InteractiveMultiPartView> {
  final GlobalKey _key = GlobalKey();

  RenderMultiPartView? get _render =>
      _key.currentContext?.findRenderObject() as RenderMultiPartView?;

  Offset? _lastDragPosition;
  String? _draggingId; // the element being moved, or null for a placement drag

  bool get _wantsElementDrag =>
      widget.onElementDragStart != null ||
      widget.onElementDragUpdate != null ||
      widget.onElementDragEnd != null;

  void _handleRawStaffTap(int partIndex, StaffTarget target) =>
      widget.onStaffTap?.call(partIndex, target);

  void _setGhostFrom(Offset? local) {
    final render = _render;
    if (render == null) return;
    final hit = local == null ? null : render.targetAt(local);
    render
      ..ghostPart = hit?.partIndex
      ..ghostTarget = hit?.target;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: widget.onHover == null && widget.ghostTarget == null
          ? null
          : (event) {
              final hit = _render?.targetAt(event.localPosition);
              widget.onHover?.call(hit?.partIndex ?? -1, hit?.target);
            },
      child: GestureDetector(
        // Opaque (not deferToChild) so drags work even when no tap callback is
        // set — the child's tap recognizer still wins no-movement taps.
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          _lastDragPosition = details.localPosition;
          if (_wantsElementDrag) {
            final id = _render?.elementIdAt(details.localPosition);
            if (id != null) {
              _draggingId = id;
              widget.onElementDragStart?.call(id);
              _setGhostFrom(details.localPosition);
              return;
            }
          }
          _setGhostFrom(details.localPosition);
        },
        onPanUpdate: (details) {
          _lastDragPosition = details.localPosition;
          _setGhostFrom(details.localPosition);
          final id = _draggingId;
          if (id != null) {
            final hit = _render?.targetAt(details.localPosition);
            if (hit != null) {
              widget.onElementDragUpdate?.call(id, hit.partIndex, hit.target);
            }
          }
        },
        onPanEnd: (_) {
          _setGhostFrom(null);
          final id = _draggingId;
          final pos = _lastDragPosition;
          _draggingId = null;
          if (id != null) {
            final hit = pos == null ? null : _render?.targetAt(pos);
            if (hit != null) {
              widget.onElementDragEnd?.call(id, hit.partIndex, hit.target);
            }
            return;
          }
          // A placement drag drops as a staff tap (unless it lands on ink).
          if (pos != null && _render?.elementIdAt(pos) == null) {
            final hit = _render?.targetAt(pos);
            if (hit != null) _handleRawStaffTap(hit.partIndex, hit.target);
          }
        },
        onPanCancel: () {
          _draggingId = null;
          _setGhostFrom(null);
        },
        child: _MultiPartViewWithHooks(
          key: _key,
          document: widget.document,
          metrics: widget.metrics,
          theme: widget.theme,
          staffSpace: widget.staffSpace,
          staffGap: widget.staffGap,
          systemGap: widget.systemGap,
          pageIndex: widget.pageIndex,
          highlightedIds: widget.highlightedIds,
          elementColors: widget.elementColors,
          suppressElementIds: widget.suppressElementIds,
          ghostPart: widget.ghostPart,
          ghostTarget: widget.ghostTarget,
          ghostDuration: widget.ghostDuration,
          onElementTap: widget.onElementTap,
          onStaffTapRaw: widget.onStaffTap == null ? null : _handleRawStaffTap,
          controller: widget.controller,
          caret: widget.caret,
          showMeasureNumbers: widget.showMeasureNumbers,
        ),
      ),
    );
  }
}

/// A [MultiPartView] variant that injects the render-object-only overlay,
/// ghost and raw staff-tap state (which the base widget does not expose).
class _MultiPartViewWithHooks extends MultiPartView {
  final Set<String> highlightedIds;
  final Map<String, Color> elementColors;
  final Set<String> suppressElementIds;
  final int? ghostPart;
  final StaffTarget? ghostTarget;
  final NoteDuration ghostDuration;
  final void Function(int partIndex, StaffTarget target)? onStaffTapRaw;
  final ElementRegionController? controller;
  final EditorCaret? caret;
  final bool showMeasureNumbers;

  const _MultiPartViewWithHooks({
    super.key,
    required super.document,
    required super.metrics,
    super.theme,
    super.staffSpace,
    super.staffGap,
    super.systemGap,
    super.pageIndex,
    super.onElementTap,
    this.highlightedIds = const {},
    this.elementColors = const {},
    this.suppressElementIds = const {},
    this.ghostPart,
    this.ghostTarget,
    this.ghostDuration = NoteDuration.quarter,
    this.onStaffTapRaw,
    this.controller,
    this.caret,
    this.showMeasureNumbers = false,
  });

  void _apply(RenderMultiPartView r) {
    r
      ..onStaffTapRaw = onStaffTapRaw
      ..regionController = controller
      ..caret = caret
      ..showMeasureNumbers = showMeasureNumbers
      ..highlightedIds = highlightedIds
      ..elementColors = elementColors
      ..suppressElementIds = suppressElementIds
      ..ghostPart = ghostPart
      ..ghostTarget = ghostTarget
      ..ghostDuration = ghostDuration;
  }

  @override
  RenderMultiPartView createRenderObject(BuildContext context) {
    final render = super.createRenderObject(context);
    _apply(render);
    return render;
  }

  @override
  void updateRenderObject(
      BuildContext context, RenderMultiPartView renderObject) {
    super.updateRenderObject(context, renderObject);
    _apply(renderObject);
  }
}
