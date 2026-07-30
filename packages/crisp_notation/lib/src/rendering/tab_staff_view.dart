import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter/widgets.dart';

import 'layout_painter.dart';
import 'music_font.dart';
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
    return CustomPaint(
      size: Size(
        layout.width * widget.staffSpace,
        layout.height * widget.staffSpace,
      ),
      painter: _TabPainter(
        layout: layout,
        theme: widget.theme,
        scale: widget.staffSpace,
        highlightedIds: widget.highlightedIds,
      ),
    );
  }
}

class _TabPainter extends CustomPainter {
  final ScoreLayout layout;
  final CrispNotationTheme theme;
  final double scale;
  final Set<String> highlightedIds;

  _TabPainter({
    required this.layout,
    required this.theme,
    required this.scale,
    required this.highlightedIds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final painter = LayoutPainter(
      theme: theme,
      scale: scale,
      highlightedIds: highlightedIds,
    );
    painter.paintLayout(canvas, Offset(0, -layout.top * scale), layout);
    painter.dispose();
  }

  @override
  bool shouldRepaint(_TabPainter old) =>
      old.layout != layout ||
      old.theme != theme ||
      old.scale != scale ||
      old.highlightedIds != highlightedIds;
}
