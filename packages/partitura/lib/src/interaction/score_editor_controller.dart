import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:partitura_core/partitura_core.dart';

import 'drill.dart';
import 'editor_mark.dart';

/// An imperative control surface for an editor / player built on
/// [MultiSystemView] or [InteractiveGrandStaffView].
///
/// It is the single source of truth for the overlay state the view renders —
/// the loop band, the per-note [EditorMark]s, and the highlighted ids — and it
/// drives scroll-to-note on an **app-owned** [ScrollController]. Consistent with
/// the rest of partitura, the app owns the widgets and the scroll viewport; the
/// controller is the glue that lets app code say what to show and where to look:
///
/// ```dart
/// final controller = ScoreEditorController();
/// // Bind the overlay state into the view (rebuilds on change):
/// AnimatedBuilder(
///   animation: controller,
///   builder: (_, __) => MultiSystemView(
///     score: score,
///     errorOverlay: controller.errorOverlay,
///     loopRange: controller.loopRange,
///     highlightedIds: controller.highlightedIds,
///   ),
/// );
/// // Bind scroll-to-note to the app's ScrollController + the render geometry:
/// controller.attachViewport(
///   scrollController: myScrollController,
///   rectOfElement: () => renderObject.rectOfElement,
/// );
///
/// controller.setLoop('e10', 'e18');
/// controller.mark('e5', const EditorMark(Color(0xFFD32F2F), message: 'flat'));
/// await controller.scrollToNote('e42');
/// ```
class ScoreEditorController extends ChangeNotifier {
  (String, String)? _loopRange;

  /// The current loop/selection band range, or null.
  (String, String)? get loopRange => _loopRange;

  /// Sets the loop band from [startId] to [endId] (order-independent — the view
  /// paints from whichever comes first).
  void setLoop(String startId, String endId) {
    final next = (startId, endId);
    if (next == _loopRange) return;
    _loopRange = next;
    notifyListeners();
  }

  /// Clears the loop band.
  void clearLoop() {
    if (_loopRange == null) return;
    _loopRange = null;
    notifyListeners();
  }

  Map<String, EditorMark> _marks = const {};

  /// The per-element overlay flags, as an unmodifiable map to feed the view's
  /// `errorOverlay`.
  Map<String, EditorMark> get errorOverlay => _marks;

  /// Flags element [id] with [mark] (replacing any existing flag on it).
  void mark(String id, EditorMark mark) {
    if (_marks[id] == mark) return;
    _marks = {..._marks, id: mark};
    notifyListeners();
  }

  /// Replaces the entire overlay with [marks].
  void setMarks(Map<String, EditorMark> marks) {
    if (mapEquals(marks, _marks)) return;
    _marks = Map.of(marks);
    notifyListeners();
  }

  /// Removes any flag on element [id].
  void unmark(String id) {
    if (!_marks.containsKey(id)) return;
    _marks = {..._marks}..remove(id);
    notifyListeners();
  }

  /// Clears every overlay flag.
  void clearMarks() {
    if (_marks.isEmpty) return;
    _marks = const {};
    notifyListeners();
  }

  Set<String> _highlighted = const {};

  /// The highlighted element ids, to feed the view's `highlightedIds`.
  Set<String> get highlightedIds => _highlighted;

  /// Highlights exactly [ids] (replacing the previous set).
  void highlight(Iterable<String> ids) {
    final next = ids.toSet();
    if (next.length == _highlighted.length && next.containsAll(_highlighted)) {
      return;
    }
    _highlighted = next;
    notifyListeners();
  }

  /// Clears the highlight set.
  void clearHighlight() {
    if (_highlighted.isEmpty) return;
    _highlighted = const {};
    notifyListeners();
  }

  // ------------------------------------------------------- drills (Phase 3.7)

  /// Evaluates a play-the-right-note drill and applies the result to the overlay
  /// in one call: the expected elements ([expectedIds], usually the cursor's
  /// current notes) are marked correct/wrong against the MIDI pitches the player
  /// [played] (see [evaluateDrill]). Returns the [DrillResult] so the app can
  /// react to `isPerfect` / `extraPitches` / `missingPitches`.
  DrillResult showDrill({
    required Score score,
    required Iterable<String> expectedIds,
    required Set<int> played,
    Color correctColor = const Color(0xFF388E3C),
    Color wrongColor = const Color(0xFFD32F2F),
  }) {
    final result = evaluateDrill(
      score: score,
      expectedIds: expectedIds,
      played: played,
      correctColor: correctColor,
      wrongColor: wrongColor,
    );
    setMarks(result.overlay);
    return result;
  }

  // --------------------------------------------------- visualizer (Phase 3.8)

  /// The MIDI pitch numbers currently sounding — the highlighted ids resolved to
  /// pitches through [score]. Feed it to a `PianoKeyboardView` /
  /// `FretboardView` (inside an `AnimatedBuilder` on this controller) to drive
  /// an instrument visualizer straight from the cursor.
  Set<int> soundingPitches(Score score) =>
      pitchesForElements(score, _highlighted);

  // ------------------------------------------------- part visibility (3.8)

  Set<int> _hiddenParts = const {};

  /// The indices of parts (voices / staves — the app decides) the user has
  /// hidden. The app reads this to render only the visible subset.
  Set<int> get hiddenParts => _hiddenParts;

  /// Whether part [index] is currently shown.
  bool isPartVisible(int index) => !_hiddenParts.contains(index);

  /// Shows or hides part [index] (the opposite of its current state).
  void togglePart(int index) {
    _hiddenParts = _hiddenParts.contains(index)
        ? (_hiddenParts.toSet()..remove(index))
        : (_hiddenParts.toSet()..add(index));
    notifyListeners();
  }

  /// Hides part [index].
  void hidePart(int index) {
    if (_hiddenParts.contains(index)) return;
    _hiddenParts = _hiddenParts.toSet()..add(index);
    notifyListeners();
  }

  /// Shows part [index].
  void showPart(int index) {
    if (!_hiddenParts.contains(index)) return;
    _hiddenParts = _hiddenParts.toSet()..remove(index);
    notifyListeners();
  }

  /// Shows every part.
  void showAllParts() {
    if (_hiddenParts.isEmpty) return;
    _hiddenParts = const {};
    notifyListeners();
  }

  // ----------------------------------------------------------- scroll-to-note

  ScrollController? _scrollController;
  Rect? Function(String id)? _rectOf;
  Axis _axis = Axis.vertical;

  /// Whether a viewport is attached for [scrollToNote].
  bool get isViewportAttached => _scrollController != null && _rectOf != null;

  /// Binds scroll-to-note to an app-owned [scrollController] and a
  /// [rectOfElement] resolver (typically the render object's `rectOfElement`,
  /// which returns an element's rect in the scroll child's content space).
  ///
  /// [axis] is the scroll direction of the viewport (default vertical). Call
  /// [detachViewport] when the view is disposed.
  void attachViewport({
    required ScrollController scrollController,
    required Rect? Function(String id) rectOfElement,
    Axis axis = Axis.vertical,
  }) {
    _scrollController = scrollController;
    _rectOf = rectOfElement;
    _axis = axis;
  }

  /// Unbinds the viewport (does not dispose the app's [ScrollController]).
  void detachViewport() {
    _scrollController = null;
    _rectOf = null;
  }

  /// The scroll offset that would place element [id] at [alignment] of the
  /// viewport (0 = leading edge, 1 = trailing edge), clamped to the scroll
  /// range — or null if no viewport is attached, the element is unknown, or the
  /// scrollable has no clients yet. Useful when the app wants to jump/animate
  /// itself instead of via [scrollToNote].
  double? offsetToReveal(String id, {double alignment = 0.3}) {
    final rectOf = _rectOf;
    final controller = _scrollController;
    if (rectOf == null || controller == null || !controller.hasClients) {
      return null;
    }
    final rect = rectOf(id);
    if (rect == null) return null;
    final position = controller.position;
    final viewport = position.viewportDimension;
    final leading = _axis == Axis.vertical ? rect.top : rect.left;
    final extent = _axis == Axis.vertical ? rect.height : rect.width;
    final target = leading - alignment * (viewport - extent);
    return target.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  /// Animates the attached viewport so element [id] sits at [alignment] of the
  /// viewport. No-op if no viewport is attached or [id] is unknown.
  Future<void> scrollToNote(
    String id, {
    double alignment = 0.3,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) async {
    final target = offsetToReveal(id, alignment: alignment);
    if (target == null) return;
    await _scrollController!.animateTo(
      target,
      duration: duration,
      curve: curve,
    );
  }

  @override
  void dispose() {
    detachViewport();
    super.dispose();
  }
}
