import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'layout_painter.dart';
import 'music_font.dart';
import 'score_semantics.dart';
import 'theme.dart';

/// Renders a [Score] as guitar/bass **tablature** for a [tuning].
///
/// A parallel notation mode: pitches become fret numbers on an N-line string
/// staff (see [TabLayoutEngine]). The music font's metadata (Bravura by
/// default; see [CrispNotationTheme.musicFont]) loads asynchronously; call
/// [MusicFonts.load] up front to guarantee a first paint.
/// ⚠️ **PERF, and the reason this is stateful:** engraving is expensive and
/// [highlightedIds] does not affect it.
///
/// This used to be a `StatelessWidget` that ran the whole [TabLayoutEngine] in
/// `build`. Everything downstream was already careful — the painter repaints
/// without relaying out, and `StaffView`'s render object gates on its inputs —
/// but a *rebuild* re-engraved the entire piece, so a moving playhead re-laid
/// out every note of the score for each column it lit up. That is the same cost
/// as opening the file, sixty times a minute.
///
/// The layout is now cached and recomputed only when something it actually
/// depends on changes: the score, the tuning, the capo, the theme's font, the
/// tuning-letters flag. A highlight change repaints and nothing more.
class TabStaffView extends StatefulWidget {
  /// The music to render as tab.
  final Score score;

  /// The instrument tuning (string count + open pitches).
  final Tuning tuning;

  /// Pixels per staff space.
  final double staffSpace;

  /// Colors and fonts. Fret digits use [CrispNotationTheme.textFontFamily].
  final CrispNotationTheme theme;

  /// Ids painted in the highlight color.
  final Set<String> highlightedIds;

  /// Frets the capo clamps at (0 = none); shown numbers read relative to it.
  final int capo;

  /// Whether to draw each open string's note letter on the left.
  final bool showTuning;

  /// Creates a tablature view.
  const TabStaffView({
    super.key,
    required this.score,
    required this.tuning,
    this.staffSpace = 12,
    this.theme = CrispNotationTheme.standard,
    this.highlightedIds = const {},
    this.capo = 0,
    this.showTuning = false,
  });

  @override
  State<TabStaffView> createState() => _TabStaffViewState();
}

class _TabStaffViewState extends State<TabStaffView> {
  ScoreLayout? _layout;

  /// How many times this view has actually engraved.
  ///
  /// Exposed for tests because the whole point of the cache is invisible from
  /// the outside: a view that re-engraves on every rebuild paints exactly the
  /// same pixels as one that does not, so nothing but a counter can tell them
  /// apart — and a cache nobody can observe is a cache nobody will notice
  /// breaking.
  @visibleForTesting
  int engraveCount = 0;

  /// What [_layout] was engraved from, so a rebuild can tell whether it still
  /// applies. `score` is compared by IDENTITY: a caller that hands back the same
  /// instance (which is what a document-revision cache does) gets a free hit,
  /// and a caller that builds a fresh equal score pays a deep `==` it did not
  /// need — identity is the honest question here, since a new instance may well
  /// be new music.
  Score? _forScore;
  Tuning? _forTuning;
  int? _forCapo;
  bool? _forShowTuning;
  Object? _forFont;

  ScoreLayout? _engrave() {
    final metadata = MusicFonts.metadataOrNull(widget.theme.musicFont);
    if (metadata == null) return null;
    final fresh = _layout == null ||
        !identical(_forScore, widget.score) ||
        _forTuning != widget.tuning ||
        _forCapo != widget.capo ||
        _forShowTuning != widget.showTuning ||
        _forFont != widget.theme.musicFont;
    if (!fresh) return _layout;
    final layout = const TabLayoutEngine().layout(
      widget.score,
      widget.tuning,
      LayoutSettings(metadata: metadata),
      capo: widget.capo,
      showTuning: widget.showTuning,
    );
    engraveCount++;
    _layout = layout;
    _forScore = widget.score;
    _forTuning = widget.tuning;
    _forCapo = widget.capo;
    _forShowTuning = widget.showTuning;
    _forFont = widget.theme.musicFont;
    return layout;
  }

  @override
  Widget build(BuildContext context) {
    final layout = _engrave();
    // The font metadata loads asynchronously; until it arrives there is nothing
    // to draw, exactly as before.
    if (layout == null) return const SizedBox.shrink();
    return _TabLeaf(
      layout: layout,
      score: widget.score,
      scale: widget.staffSpace,
      theme: widget.theme,
      highlightedIds: widget.highlightedIds,
    );
  }
}

class _TabLeaf extends LeafRenderObjectWidget {
  final ScoreLayout layout;
  final Score score;
  final double scale;
  final CrispNotationTheme theme;
  final Set<String> highlightedIds;

  const _TabLeaf({
    required this.layout,
    required this.score,
    required this.scale,
    required this.theme,
    required this.highlightedIds,
  });

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTabLeaf(
        layout: layout,
        score: score,
        scale: scale,
        theme: theme,
        highlightedIds: highlightedIds,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderTabLeaf renderObject) {
    renderObject
      ..tabLayout = layout
      ..score = score
      ..scale = scale
      ..theme = theme
      ..highlightedIds = highlightedIds;
  }
}

class _RenderTabLeaf extends RenderBox {
  _RenderTabLeaf({
    required ScoreLayout layout,
    required Score score,
    required double scale,
    required CrispNotationTheme theme,
    required Set<String> highlightedIds,
  })  : _tabLayout = layout,
        _score = score,
        _scale = scale,
        _theme = theme,
        _highlightedIds = highlightedIds {
    _painter = LayoutPainter(
      theme: _theme,
      scale: _scale,
      highlightedIds: _highlightedIds,
    );
  }

  ScoreLayout _tabLayout;
  ScoreLayout get tabLayout => _tabLayout;
  set tabLayout(ScoreLayout value) {
    if (value == _tabLayout) return;
    _tabLayout = value;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  Score _score;
  Score get score => _score;
  set score(Score value) {
    if (value == _score) return;
    _score = value;
    markNeedsSemanticsUpdate();
  }

  double _scale;
  double get scale => _scale;
  set scale(double value) {
    if (value == _scale) return;
    _scale = value;
    _painter.scale = value;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  CrispNotationTheme _theme;
  CrispNotationTheme get theme => _theme;
  set theme(CrispNotationTheme value) {
    if (value == _theme) return;
    _theme = value;
    _painter.theme = value;
    // Tab string lines are baked into primitives (thickness from settings at
    // layout time), so a pure color change only needs repaint. We conservatively
    // repaint; layout invalidation is driven by _TabStaffViewState's cache
    // (musicFont change re-engraves).
    _painter.clearCache();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  Set<String> _highlightedIds;
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

  late LayoutPainter _painter;

  @override
  void performLayout() {
    size = constraints.constrain(
      Size(_tabLayout.width * _scale, _tabLayout.height * _scale),
    );
    _painter.scale = _scale;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
        Size(_tabLayout.width * _scale, _tabLayout.height * _scale),
      );

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final origin = offset + Offset(0, -_tabLayout.top * _scale);
    _painter.paintLayout(canvas, origin, _tabLayout);
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }

  // ------------------------------------------------------ accessibility (3.9)

  List<SemanticsNode> _semanticsNodes = const [];

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
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
    final regions = _semanticRegions;
    final nodes = buildScoreSemanticsNodes(
      labels: labels,
      regions: regions,
      existingNodes: _semanticsNodes,
    );
    _semanticsNodes = nodes;
    node.updateWith(config: config, childrenInInversePaintOrder: nodes);
  }

  List<({String id, Rect bounds})> get _semanticRegions {
    // Reading order for tablature is a single system left to right; the
    // layout's regions are already emitted in that order (measure by measure,
    // element by element). We preserve that order so screen readers follow the
    // score.
    final out = <({String id, Rect bounds})>[];
    for (final region in _tabLayout.regions) {
      final b = region.bounds;
      // Convert staff-space bounds to local pixel coordinates. The paint origin
      // is (0, -top*scale), so local y = (b.top - top)*scale.
      out.add((
        id: region.elementId,
        bounds: Rect.fromLTWH(
          b.left * _scale,
          (b.top - _tabLayout.top) * _scale,
          b.width * _scale,
          b.height * _scale,
        ),
      ));
    }
    return out;
  }
}
