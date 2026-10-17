import 'package:flutter/rendering.dart';

/// Builds per-element semantics nodes for a score view.
///
/// Reuses existing nodes in [existingNodes] to avoid allocating new
/// SemanticsNodes on every frame (the same pattern used by the framework's
/// own assembleSemanticsNode). Each entry in [regions] is an element id and
/// its hit region in the view's local pixel coordinates. Only elements whose
/// id is in [labels] and whose rect is non-empty get a node. Nodes are
/// returned in the order given — callers must sort [regions] into reading
/// order before calling.
///
/// This is the single shared helper for all seven views plus StaffView;
/// StaffView now delegates to it so its behaviour cannot drift.
List<SemanticsNode> buildScoreSemanticsNodes({
  required Map<String, String> labels,
  required List<({String id, Rect bounds})> regions,
  required List<SemanticsNode> existingNodes,
}) {
  final nodes = <SemanticsNode>[];
  for (final region in regions) {
    final label = labels[region.id];
    if (label == null || region.bounds.isEmpty) continue;
    final child = existingNodes.length > nodes.length
        ? existingNodes[nodes.length]
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
  return nodes;
}
