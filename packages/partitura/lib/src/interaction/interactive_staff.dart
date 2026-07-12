import 'package:flutter/widgets.dart';
import 'package:partitura_core/partitura_core.dart';

import '../rendering/staff_view.dart';
import '../rendering/theme.dart';
import 'staff_target.dart';

/// [StaffView] with gesture handling: element taps, quantized staff taps
/// and a ghost-note drag preview. The layer minigames build on.
///
/// - Tapping an element fires [onElementTap] with its id.
/// - Tapping (or ending a drag on) an empty staff location fires
///   [onStaffTap] with a [StaffTarget], quantized to the nearest staff
///   position — line or space, including the ledger range.
/// - While dragging, a semi-transparent preview notehead of
///   [ghostDuration] follows the pointer when [showGhostNote] is on.
///
/// Selection/highlighting stays app state: pass [highlightedIds] (and
/// per-element colors via the theme); changes repaint without relayout.
class InteractiveStaff extends StatefulWidget {
  /// The score to render.
  final Score score;

  /// Colors and ergonomics; [PartituraTheme.kids] enlarges hit targets.
  final PartituraTheme theme;

  /// Pixels per staff space; null fits the available width.
  final double? staffSpace;

  /// Ids of elements to paint in the theme's highlight color.
  final Set<String> highlightedIds;

  /// Called with the element id when the user taps an element.
  final void Function(String elementId)? onElementTap;

  /// Called when the user taps or drops on an empty staff location.
  final void Function(StaffTarget target)? onStaffTap;

  /// Whether a ghost note follows drags across the staff.
  final bool showGhostNote;

  /// Notehead used for the ghost preview.
  final NoteDuration ghostDuration;

  /// Creates an interactive staff.
  const InteractiveStaff({
    super.key,
    required this.score,
    this.theme = PartituraTheme.standard,
    this.staffSpace,
    this.highlightedIds = const {},
    this.onElementTap,
    this.onStaffTap,
    this.showGhostNote = true,
    this.ghostDuration = NoteDuration.quarter,
  });

  @override
  State<InteractiveStaff> createState() => _InteractiveStaffState();
}

class _InteractiveStaffState extends State<InteractiveStaff> {
  final GlobalKey _staffKey = GlobalKey();

  RenderStaffView? get _renderStaff =>
      _staffKey.currentContext?.findRenderObject() as RenderStaffView?;

  void _handleRawStaffTap(int staffPosition, int measureIndex) {
    widget.onStaffTap?.call(
      StaffTarget(staffPosition: staffPosition, measureIndex: measureIndex),
    );
  }

  void _updateGhost(Offset localPosition) {
    final staff = _renderStaff;
    if (staff == null || !widget.showGhostNote) return;
    final (position, _) = staff.quantizeStaffPosition(localPosition);
    staff.ghostNote = GhostNote(
      xSpaces: staff.localToStaff(localPosition).x,
      staffPosition: position,
      duration: widget.ghostDuration,
    );
  }

  void _endDrag({Offset? dropPosition}) {
    final staff = _renderStaff;
    if (staff == null) return;
    staff.ghostNote = null;
    if (dropPosition != null && widget.onStaffTap != null) {
      // A drop counts as a staff tap unless it lands on an element.
      if (staff.elementIdAt(dropPosition) == null) {
        final (position, measureIndex) =
            staff.quantizeStaffPosition(dropPosition);
        _handleRawStaffTap(position, measureIndex);
      }
    }
  }

  Offset? _lastDragPosition;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onPanStart: (details) {
        _lastDragPosition = details.localPosition;
        _updateGhost(details.localPosition);
      },
      onPanUpdate: (details) {
        _lastDragPosition = details.localPosition;
        _updateGhost(details.localPosition);
      },
      onPanEnd: (_) => _endDrag(dropPosition: _lastDragPosition),
      onPanCancel: () => _endDrag(),
      child: _StaffViewWithStaffTap(
        key: _staffKey,
        score: widget.score,
        theme: widget.theme,
        staffSpace: widget.staffSpace,
        highlightedIds: widget.highlightedIds,
        onElementTap: widget.onElementTap,
        onStaffTapRaw: widget.onStaffTap == null ? null : _handleRawStaffTap,
      ),
    );
  }
}

/// Internal [StaffView] variant that also wires the raw staff-tap callback
/// into the render object.
class _StaffViewWithStaffTap extends StaffView {
  final void Function(int staffPosition, int measureIndex)? onStaffTapRaw;

  const _StaffViewWithStaffTap({
    super.key,
    required super.score,
    super.theme,
    super.staffSpace,
    super.highlightedIds,
    super.onElementTap,
    this.onStaffTapRaw,
  });

  @override
  RenderStaffView createRenderObject(BuildContext context) =>
      super.createRenderObject(context)..onStaffTap = onStaffTapRaw;

  @override
  void updateRenderObject(BuildContext context, RenderStaffView renderObject) {
    super.updateRenderObject(context, renderObject);
    renderObject.onStaffTap = onStaffTapRaw;
  }
}
