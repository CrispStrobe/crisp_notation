import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter/widgets.dart';

import 'layout_painter.dart';
import 'music_font.dart';
import 'theme.dart';

/// Renders a [Score] as a **notation staff over a tab staff** of the same music
/// (Phase 6.3) — the standard guitar/bass score layout. The two staves are laid
/// out by [layoutNotationTab] so their barlines line up, and this view joins
/// them with barline connectors across the gap.
///
/// The music font's metadata (Bravura by default) loads asynchronously; call
/// [MusicFonts.load] up front to guarantee a first paint.
class NotationTabView extends StatelessWidget {
  /// The music to render on both staves.
  final Score score;

  /// The instrument tuning for the tab staff.
  final Tuning tuning;

  /// Pixels per staff space.
  final double staffSpace;

  /// Vertical distance in staff spaces from the notation staff's bottom line to
  /// the tab staff's top string line.
  final double staffGap;

  /// Colors and fonts.
  final CrispNotationTheme theme;

  /// Ids painted in the highlight color (on either staff).
  final Set<String> highlightedIds;

  /// Frets the capo clamps at (0 = none) on the tab staff.
  final int capo;

  /// Whether to draw each open string's note letter left of the tab staff.
  final bool showTuning;

  /// Creates a paired notation + tab view.
  const NotationTabView({
    super.key,
    required this.score,
    required this.tuning,
    this.staffSpace = 12,
    this.staffGap = 5.0,
    this.theme = CrispNotationTheme.standard,
    this.highlightedIds = const {},
    this.capo = 0,
    this.showTuning = false,
  });

  @override
  Widget build(BuildContext context) {
    final metadata = MusicFonts.metadataOrNull(theme.musicFont);
    if (metadata == null) return const SizedBox.shrink();
    final settings = LayoutSettings(
        metadata: metadata, fingeringPlacement: theme.fingeringPlacement);
    final layout = layoutNotationTab(score, tuning, settings,
        staffGap: staffGap, capo: capo, showTuning: showTuning);
    return CustomPaint(
      size: Size(layout.width * staffSpace, layout.height * staffSpace),
      painter: _NotationTabPainter(
        layout: layout,
        theme: theme,
        scale: staffSpace,
        highlightedIds: highlightedIds,
      ),
    );
  }
}

class _NotationTabPainter extends CustomPainter {
  final NotationTabLayout layout;
  final CrispNotationTheme theme;
  final double scale;
  final Set<String> highlightedIds;

  _NotationTabPainter({
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
    // Shift so the highest ink of the notation staff sits at pixel 0.
    final notationOrigin = Offset(0, -layout.notation.top * scale);
    final tabOrigin = Offset(0, layout.tabTop * scale);
    painter.paintLayout(canvas, notationOrigin, layout.notation);
    painter.paintLayout(canvas, tabOrigin, layout.tab);

    // Join each full-height notation barline down to the tab staff's top line,
    // bridging the gap so the barlines read as one continuous line.
    final barPaint = Paint()..color = theme.staffColor;
    for (final line in layout.notation.primitives.whereType<LinePrimitive>()) {
      final vertical = line.from.x == line.to.x;
      final fullStaff = (line.from.y == 0 && line.to.y == 4) ||
          (line.from.y == 4 && line.to.y == 0);
      if (!vertical || !fullStaff) continue;
      canvas.drawLine(
        notationOrigin + Offset(line.from.x * scale, 4 * scale),
        tabOrigin + Offset(line.from.x * scale, 0),
        barPaint..strokeWidth = line.thickness * scale,
      );
    }
    painter.dispose();
  }

  @override
  bool shouldRepaint(_NotationTabPainter old) =>
      old.layout != layout ||
      old.theme != theme ||
      old.scale != scale ||
      old.highlightedIds != highlightedIds;
}
