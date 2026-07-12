import 'package:flutter/widgets.dart';
import 'package:partitura_core/partitura_core.dart';

import 'layout_painter.dart';
import 'music_font.dart';
import 'theme.dart';

/// Renders a [Score] as guitar/bass **tablature** for a [tuning].
///
/// A parallel notation mode: pitches become fret numbers on an N-line string
/// staff (see [TabLayoutEngine]). The music font's metadata (Bravura by
/// default; see [PartituraTheme.musicFont]) loads asynchronously; call
/// [MusicFonts.load] up front to guarantee a first paint.
class TabStaffView extends StatelessWidget {
  /// The music to render as tab.
  final Score score;

  /// The instrument tuning (string count + open pitches).
  final Tuning tuning;

  /// Pixels per staff space.
  final double staffSpace;

  /// Colors and fonts. Fret digits use [PartituraTheme.textFontFamily].
  final PartituraTheme theme;

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
    this.theme = PartituraTheme.standard,
    this.highlightedIds = const {},
    this.capo = 0,
    this.showTuning = false,
  });

  @override
  Widget build(BuildContext context) {
    final metadata = MusicFonts.metadataOrNull(theme.musicFont);
    if (metadata == null) return const SizedBox.shrink();
    final settings = LayoutSettings(metadata: metadata);
    final layout = const TabLayoutEngine()
        .layout(score, tuning, settings, capo: capo, showTuning: showTuning);
    return CustomPaint(
      size: Size(layout.width * staffSpace, layout.height * staffSpace),
      painter: _TabPainter(
        layout: layout,
        theme: theme,
        scale: staffSpace,
        highlightedIds: highlightedIds,
      ),
    );
  }
}

class _TabPainter extends CustomPainter {
  final ScoreLayout layout;
  final PartituraTheme theme;
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
