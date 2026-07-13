/// N-staff systems: several notation staves stacked as one system with
/// aligned barlines and optional bracket/brace grouping. Generalizes the
/// two-staff [GrandStaff].
library;

import '../model/score.dart';
import 'layout_engine.dart';
import 'layout_settings.dart';
import 'score_layout.dart';

/// The left-edge sign joining a contiguous run of staves.
enum StaffBracketKind {
  /// A curly brace `{` — a single instrument on multiple staves (piano, organ).
  brace,

  /// A square bracket `[` — a section of instruments (strings, winds).
  bracket,
}

/// Groups staves [first]..[last] (inclusive, 0-based) with a [kind] sign drawn
/// at the system's left edge.
class StaffBracket {
  /// First staff index in the group.
  final int first;

  /// Last staff index in the group (inclusive).
  final int last;

  /// The sign to draw.
  final StaffBracketKind kind;

  /// Creates a staff group [first]..[last] joined by [kind].
  const StaffBracket(this.first, this.last,
      {this.kind = StaffBracketKind.bracket})
      : assert(last >= first, 'last must be >= first');

  @override
  bool operator ==(Object other) =>
      other is StaffBracket &&
      other.first == first &&
      other.last == last &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(first, last, kind);

  @override
  String toString() => 'StaffBracket($first..$last, ${kind.name})';
}

/// Several [Score] staves rendered as one aligned system. Element ids should be
/// unique across staves so interaction stays unambiguous.
class StaffSystem {
  /// The staves, top to bottom.
  final List<Score> staves;

  /// Bracket/brace groups drawn at the left edge (may be empty or nested).
  final List<StaffBracket> brackets;

  /// Whether barlines are drawn continuously through the whole system.
  final bool connectBarlines;

  /// Creates a system from [staves] (at least one).
  const StaffSystem(
    this.staves, {
    this.brackets = const [],
    this.connectBarlines = true,
  }) : assert(staves.length > 0, 'a system needs at least one staff');

  /// This system with every transposing staff shown at concert (sounding)
  /// pitch — the "concert-pitch toggle". Non-transposing staves are unchanged.
  StaffSystem atConcertPitch() => StaffSystem(
        [for (final staff in staves) staff.atConcertPitch()],
        brackets: brackets,
        connectBarlines: connectBarlines,
      );

  @override
  bool operator ==(Object other) =>
      other is StaffSystem &&
      _listEquals(other.staves, staves) &&
      _listEquals(other.brackets, brackets) &&
      other.connectBarlines == connectBarlines;

  @override
  int get hashCode => Object.hash(
      Object.hashAll(staves), Object.hashAll(brackets), connectBarlines);

  @override
  String toString() => 'StaffSystem(${staves.length} staves)';
}

/// The laid-out system: one [ScoreLayout] per staff (all sharing leading width,
/// per-measure widths and total width, so barlines align), stacked [staffGap]
/// staff-spaces apart (bottom line of one staff to top line of the next).
class StaffSystemLayout {
  /// The per-staff layouts, top to bottom.
  final List<ScoreLayout> staves;

  /// Line-to-line vertical distance between adjacent staves, in staff spaces.
  final double staffGap;

  /// The source system (for its brackets).
  final StaffSystem source;

  /// Creates a system layout.
  const StaffSystemLayout({
    required this.staves,
    required this.staffGap,
    required this.source,
  });

  /// Shared total width in staff spaces.
  double get width => staves.first.width;

  /// The system-space y of staff [i]'s top line (y = 0 in its own coords).
  double staffTop(int i) => i * (4 + staffGap);

  /// The topmost inked y (may be negative — ink above the first staff).
  double get top {
    var t = double.infinity;
    for (var i = 0; i < staves.length; i++) {
      final s = staffTop(i) + staves[i].top;
      if (s < t) t = s;
    }
    return t;
  }

  /// Total inked height in staff spaces.
  double get height {
    var bottom = double.negativeInfinity;
    for (var i = 0; i < staves.length; i++) {
      final b = staffTop(i) + staves[i].top + staves[i].height;
      if (b > bottom) bottom = b;
    }
    return bottom - top;
  }

  @override
  String toString() =>
      'StaffSystemLayout(${staves.length} staves, ${width}x$height)';
}

/// Lays out a [system]: each staff is laid out once to find its natural leading
/// and per-measure widths, then all staves are laid out again with the
/// column-wise maxima so barlines align across the system.
///
/// Throws [ArgumentError] if the staves disagree on measure count.
StaffSystemLayout layoutStaffSystem(
  StaffSystem system,
  LayoutSettings settings, {
  double staffGap = 4.0,
}) {
  const engine = LayoutEngine();
  final natural = [for (final s in system.staves) engine.layout(s, settings)];

  final measureCount = natural.first.measureRegions.length;
  for (final layout in natural) {
    if (layout.measureRegions.length != measureCount) {
      throw ArgumentError('system staves must have the same measure count');
    }
  }

  double leadingOf(ScoreLayout l) =>
      l.measureRegions.isEmpty ? l.width : l.measureRegions.first.startX;
  var leading = 0.0;
  for (final l in natural) {
    leading = _max(leading, leadingOf(l));
  }

  final measureWidths = <double>[
    for (var i = 0; i < measureCount; i++)
      natural
          .map((l) => l.measureRegions[i].endX - l.measureRegions[i].startX)
          .reduce(_max),
  ];

  final crossStaffOffset = 4 + staffGap;
  return StaffSystemLayout(
    staves: [
      for (var i = 0; i < system.staves.length; i++)
        engine.layout(system.staves[i], settings,
            leadingWidth: leading,
            measureWidths: measureWidths,
            crossStaffOffset: crossStaffOffset,
            clefAbove: i > 0 ? system.staves[i - 1].clef : null,
            clefBelow: i < system.staves.length - 1
                ? system.staves[i + 1].clef
                : null),
    ],
    staffGap: staffGap,
    source: system,
  );
}

double _max(double a, double b) => a > b ? a : b;

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
