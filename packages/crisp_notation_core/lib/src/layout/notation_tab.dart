/// Pairs a notation staff with a tab staff of the *same* [Score], aligned
/// barline-for-barline — the standard guitar/bass score layout.
library;

import 'dart:math';

import '../model/score.dart';
import '../theory/tuning.dart';
import 'layout_engine.dart';
import 'layout_settings.dart';
import 'score_layout.dart';
import 'tab_layout.dart';

/// A notation staff laid out directly above a tab staff of the same music,
/// with barlines aligned. Produced by [layoutNotationTab].
class NotationTabLayout {
  /// Layout of the upper (notation) staff.
  final ScoreLayout notation;

  /// Layout of the lower (tab) staff.
  final ScoreLayout tab;

  /// Vertical distance in staff spaces from the notation staff's bottom line
  /// (y = 4) to the tab staff's top string line (y = 0).
  final double staffGap;

  /// Creates a notation+tab layout.
  const NotationTabLayout({
    required this.notation,
    required this.tab,
    required this.staffGap,
  });

  /// Shared total width in staff spaces (both staves are aligned to it).
  double get width => max(notation.width, tab.width);

  /// The y offset (in staff spaces) at which the tab staff's frame begins,
  /// i.e. where its top string line (its own y = 0) sits in the combined frame.
  ///
  /// Measured from the notation's actual bottom *ink*, not just its bottom staff
  /// line (y = 4): low notes (e.g. a low E on ledger lines) descend below the
  /// staff, so we push the tab down by however far the notation box extends
  /// past y = 4. When nothing descends below the staff this is 0 and the gap is
  /// the plain line-to-line [staffGap] (unchanged).
  double get tabTop {
    final belowStaff = max(0.0, (notation.top + notation.height) - 4);
    return (4 - notation.top) + staffGap + belowStaff;
  }

  /// Total height in staff spaces: the notation box, the gap, and the tab box.
  double get height => tabTop + (tab.top + tab.height);

  @override
  String toString() => 'NotationTabLayout(${width}x$height)';
}

/// Lays out [score] as a notation staff over a tab staff for [tuning], with
/// barlines aligned: each staff is laid out once to find its natural leading
/// and per-measure widths, then both are re-laid with the column-wise maxima so
/// every barline lines up.
///
/// [capo] and [showTuning] are forwarded to the tab staff.
NotationTabLayout layoutNotationTab(
  Score score,
  Tuning tuning,
  LayoutSettings settings, {
  double staffGap = 5.0,
  bool drawTimeSignature = true,
  bool finalBarline = true,
  int capo = 0,
  bool showTuning = false,
}) {
  const notationEngine = LayoutEngine();
  const tabEngine = TabLayoutEngine();

  final notationNatural = notationEngine.layout(score, settings,
      drawTimeSignature: drawTimeSignature);
  final tabNatural = tabEngine.layout(score, tuning, settings,
      capo: capo, showTuning: showTuning);

  double leadingOf(ScoreLayout l) =>
      l.measureRegions.isEmpty ? l.width : l.measureRegions.first.startX;
  final leading = max(leadingOf(notationNatural), leadingOf(tabNatural));

  final measureCount = min(
      notationNatural.measureRegions.length, tabNatural.measureRegions.length);
  double measureWidth(ScoreLayout l, int i) =>
      l.measureRegions[i].endX - l.measureRegions[i].startX;
  final measureWidths = <double>[
    for (var i = 0; i < measureCount; i++)
      max(measureWidth(notationNatural, i), measureWidth(tabNatural, i)),
  ];

  // Lay the notation staff out with the shared widths to fix the canonical
  // barline positions, then pin the tab staff's barlines to exactly those x
  // (the two engines use different inter-measure gaps, so relative widths alone
  // would drift — absolute barline x keeps every barline aligned).
  final notation = notationEngine.layout(
    score,
    settings,
    leadingWidth: leading,
    measureWidths: measureWidths,
    drawTimeSignature: drawTimeSignature,
    finalBarline: finalBarline,
  );
  final barlineXs = [for (final r in notation.measureRegions) r.endX];
  final tab = tabEngine.layout(
    score,
    tuning,
    settings,
    capo: capo,
    showTuning: showTuning,
    leadingWidth: leading,
    barlineXs: barlineXs,
  );

  return NotationTabLayout(
    notation: notation,
    tab: tab,
    staffGap: staffGap,
  );
}
