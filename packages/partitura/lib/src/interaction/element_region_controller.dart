import 'dart:ui' show Rect;

/// Something that can report its element hit-regions — implemented by the
/// render objects behind [MultiSystemView] and [InteractiveGrandStaffView].
/// App code does not implement this; it is the bridge a controller attaches to.
abstract interface class ElementRegionProvider {
  /// Every element's hit region in local pixel coordinates, tagged with its
  /// global measure index.
  List<({String id, Rect bounds, int measureIndex})> get elementRegions;

  /// The ids of every element whose hit region intersects [localRect].
  List<String> elementIdsIn(Rect localRect);
}

/// A controller that exposes a view's element hit-regions to app code —
/// the geometry behind **marquee selection** and **drag-to-reorder**.
///
/// The region data already exists on the private render object; this makes it
/// reachable from the public widget. Attach it to a
/// [MultiSystemView] or an [InteractiveGrandStaffView]:
///
/// ```dart
/// final regions = ElementRegionController();
/// MultiSystemView(score: score, controller: regions, ...);
/// // ...after the first frame:
/// final hit = regions.elementIdsIn(marqueeRect); // ids under a rubber-band
/// for (final r in regions.elementRegions) { /* r.id, r.bounds, r.measureIndex */ }
/// ```
///
/// The data is valid once the view has mounted and laid out (i.e. from the
/// first frame on); before then the getters return empty. Coordinates are in
/// the view's local pixel space. One controller drives one view at a time.
class ElementRegionController {
  ElementRegionProvider? _view;

  /// Whether a laid-out view is currently attached.
  bool get isAttached => _view != null;

  /// Every element's hit region in the view's local pixel coordinates, tagged
  /// with its global measure index. Empty until the view has laid out.
  List<({String id, Rect bounds, int measureIndex})> get elementRegions =>
      _view?.elementRegions ?? const [];

  /// The ids of every element whose hit region intersects [localRect] — feed it
  /// a rubber-band rectangle for marquee selection. Empty until laid out.
  List<String> elementIdsIn(Rect localRect) =>
      _view?.elementIdsIn(localRect) ?? const [];

  /// Framework use — the view's render object calls this on attach/update. App
  /// code never calls it.
  void attach(ElementRegionProvider view) => _view = view;

  /// Framework use — the view's render object calls this on detach/dispose so a
  /// stale render object never lingers. App code never calls it.
  void detach(ElementRegionProvider view) {
    if (identical(_view, view)) _view = null;
  }
}

/// The name the Workshop editor contract (C7) refers to; an alias of
/// [ElementRegionController], which drives either wrapped view.
typedef MultiSystemViewController = ElementRegionController;
