/// N-staff systems: several notation staves stacked as one system with
/// aligned barlines and optional bracket/brace grouping. Generalizes the
/// two-staff [GrandStaff].
library;

import 'dart:math' as math;

import '../model/element.dart';
import '../model/score.dart';
import 'grand_staff.dart' show alignedColumns;
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

/// A contiguous run of staves [first]..[last] (inclusive, 0-based) whose
/// barlines are drawn through the inter-staff gaps within the group — the
/// "custom-span barline". Staves outside every group get their own per-staff
/// barlines (no connection to their neighbours).
///
/// A single group spanning every staff reproduces
/// `StaffSystem.connectBarlines: true` (one continuous systemic barline); a
/// system with two groups (e.g. strings connected, winds connected, but the
/// barline broken between the sections) is what all-or-nothing
/// [StaffSystem.connectBarlines] could not express.
class BarlineGroup {
  /// First staff index in the group (0-based).
  final int first;

  /// Last staff index in the group (inclusive).
  final int last;

  /// Creates a barline group over staves [first]..[last].
  const BarlineGroup(this.first, this.last)
      : assert(last >= first, 'last must be >= first'),
        assert(first >= 0, 'first must be >= 0');

  /// Whether staff [index] falls inside this group.
  bool contains(int index) => index >= first && index <= last;

  @override
  bool operator ==(Object other) =>
      other is BarlineGroup && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);

  @override
  String toString() => 'BarlineGroup($first..$last)';
}

/// Several [Score] staves rendered as one aligned system. Element ids should be
/// unique across staves so interaction stays unambiguous.
class StaffSystem {
  /// The staves, top to bottom.
  final List<Score> staves;

  /// Bracket/brace groups drawn at the left edge (may be empty or nested).
  final List<StaffBracket> brackets;

  /// Whether barlines are drawn continuously through the whole system. Ignored
  /// when [barlineGroups] is non-empty (the groups take precedence); it stays
  /// the simple switch for the fully-connected / fully-disconnected cases.
  final bool connectBarlines;

  /// Contiguous staff-index runs whose barlines connect through the group. An
  /// empty list defers to [connectBarlines] (one implicit group over every
  /// staff, or per-staff) — see [effectiveBarlineGroups].
  final List<BarlineGroup> barlineGroups;

  /// Measure indices that must begin a new system, preserving source line
  /// breaks such as MusicXML `<print new-system="yes">`.
  final Set<int> systemBreaks;

  /// Creates a system from [staves] (at least one).
  const StaffSystem(
    this.staves, {
    this.brackets = const [],
    this.connectBarlines = true,
    this.barlineGroups = const [],
    this.systemBreaks = const {},
  }) : assert(staves.length > 0, 'a system needs at least one staff');

  /// The barline groups to draw: [barlineGroups] as given, or — when that is
  /// empty — a single group spanning every staff (when [connectBarlines]) or
  /// one group per staff (when not). The custom-span barline breaks in the gap
  /// between adjacent groups.
  List<BarlineGroup> get effectiveBarlineGroups {
    if (barlineGroups.isNotEmpty) return barlineGroups;
    if (connectBarlines) return [BarlineGroup(0, staves.length - 1)];
    return [for (var i = 0; i < staves.length; i++) BarlineGroup(i, i)];
  }

  /// This system with every transposing staff shown at concert (sounding)
  /// pitch — the "concert-pitch toggle". Non-transposing staves are unchanged.
  StaffSystem atConcertPitch() => StaffSystem(
        [for (final staff in staves) staff.atConcertPitch()],
        brackets: brackets,
        connectBarlines: connectBarlines,
        barlineGroups: barlineGroups,
        systemBreaks: systemBreaks,
      );

  @override
  bool operator ==(Object other) =>
      other is StaffSystem &&
      _listEquals(other.staves, staves) &&
      _listEquals(other.brackets, brackets) &&
      other.connectBarlines == connectBarlines &&
      _listEquals(other.barlineGroups, barlineGroups) &&
      _setEquals(other.systemBreaks, systemBreaks);

  @override
  int get hashCode => Object.hash(
      Object.hashAll(staves),
      Object.hashAll(brackets),
      connectBarlines,
      Object.hashAll(barlineGroups),
      Object.hashAll(systemBreaks));

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

  /// The vertical extents of the systemic barlines, one [BarlineSpan] per
  /// effective barline group of the (already staff-reduced) [source]. A barline
  /// drawn at any x in [barlineXs] runs continuously over each span and breaks
  /// in the gap between spans, so grouped staves connect and the barline breaks
  /// between groups. A single-staff group spans just its own staff (its top
  /// line to y = 4) — no cross-staff connector, matching a disconnected staff.
  List<BarlineSpan> get barlineSpans => [
        for (final group in source.effectiveBarlineGroups)
          if (group.first < staves.length)
            BarlineSpan(
              group: group,
              top: staffTop(group.first),
              bottom: staffTop(math.min(group.last, staves.length - 1)) + 4,
            ),
      ];

  /// The shared x positions (staff spaces, ascending) at which systemic
  /// barlines are drawn: the left system line at x = 0 plus every full-staff
  /// vertical barline. Because the staves share their measure widths these are
  /// identical across staves, so they are read once from the first staff.
  List<double> get barlineXs {
    final xs = <double>{0.0};
    for (final line in staves.first.primitives.whereType<LinePrimitive>()) {
      final vertical = line.from.x == line.to.x;
      final fullStaff = (line.from.y == 0 && line.to.y == 4) ||
          (line.from.y == 4 && line.to.y == 0);
      if (vertical && fullStaff) xs.add(line.from.x);
    }
    return xs.toList()..sort();
  }

  @override
  String toString() =>
      'StaffSystemLayout(${staves.length} staves, ${width}x$height)';
}

/// The vertical extent of one [BarlineGroup]'s connected barlines within a
/// system, in system-space y (staff spaces from the system's origin): from the
/// top line of the group's first staff to the bottom line (y = 4) of its last.
/// The gap between one span's [bottom] and the next span's [top] is exactly
/// where the systemic barline breaks between groups.
class BarlineSpan {
  /// The group this span connects (in the layout's own staff indices).
  final BarlineGroup group;

  /// System y of the top staff line of the group's first staff.
  final double top;

  /// System y of the bottom staff line (y = 4) of the group's last staff.
  final double bottom;

  /// Creates a barline span.
  const BarlineSpan({
    required this.group,
    required this.top,
    required this.bottom,
  });

  @override
  String toString() => 'BarlineSpan($group, $top..$bottom)';
}

/// Lays out a [system]: each staff is laid out once to find its natural leading
/// and per-measure widths, then all staves are laid out again with the
/// column-wise maxima so barlines align across the system.
///
/// With [hideEmptyStaves], staves whose measures hold only rests in this system
/// are dropped (the common "hide empty staves" engraving option); at least one
/// staff is always kept, and the [StaffSystemLayout.source]'s brackets are
/// remapped to the surviving staves.
///
/// Throws [ArgumentError] if the staves disagree on measure count.
StaffSystemLayout layoutStaffSystem(
  StaffSystem system,
  LayoutSettings settings, {
  double staffGap = 4.0,
  bool gridAlign = true,
  bool hideEmptyStaves = false,
  bool drawTimeSignature = true,
  bool finalBarline = true,
  double spacingStretch = 1.0,
  double? targetWidth,
}) {
  if (hideEmptyStaves) {
    system = _withEmptyStavesHidden(system);
  }
  const engine = LayoutEngine();
  // The natural pass carries the same [spacingStretch] as the final pass, so
  // the shared per-measure widths grow with the stretch and the staves stay
  // aligned (used when wrapping into justified systems).
  final natural = [
    for (final s in system.staves)
      engine.layout(s, settings,
          drawTimeSignature: drawTimeSignature, spacingStretch: spacingStretch),
  ];

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

  // §2.9: align simultaneous notes across every staff of the system (all
  // voices).
  final columns = gridAlign
      ? alignedColumns(system.staves, settings, spacingStretch: spacingStretch)
      : null;

  final measureWidths = columns != null
      ? null
      : <double>[
          for (var i = 0; i < measureCount; i++)
            natural
                .map((l) =>
                    l.measureRegions[i].endX - l.measureRegions[i].startX)
                .reduce(_max),
        ];

  final staves = [
    for (final s in system.staves)
      engine.layout(s, settings,
          leadingWidth: leading,
          measureWidths: measureWidths,
          forcedColumns: columns,
          drawTimeSignature: drawTimeSignature,
          finalBarline: finalBarline,
          targetWidth: targetWidth,
          spacingStretch: spacingStretch),
  ];

  var resolvedStaffGap = staffGap;
  const interStaffInkGap = 0.8;
  for (var i = 0; i < staves.length - 1; i++) {
    final upperBottom = staves[i].top + staves[i].height;
    final lowerTop = staves[i + 1].top;
    final requiredGap = upperBottom - lowerTop - 4 + interStaffInkGap;
    if (requiredGap > resolvedStaffGap) {
      resolvedStaffGap = requiredGap;
    }
  }

  return StaffSystemLayout(
    staves: staves,
    staffGap: resolvedStaffGap,
    source: system,
  );
}

/// [system] reduced to the staves that carry at least one note, with brackets
/// remapped to the surviving staves. Keeps the first staff if every staff is
/// empty (a system can never be empty).
StaffSystem _withEmptyStavesHidden(StaffSystem system) {
  final visible = <int>[
    for (var i = 0; i < system.staves.length; i++)
      if (_staffHasNotes(system.staves[i])) i,
  ];
  if (visible.isEmpty) visible.add(0);
  if (visible.length == system.staves.length) return system; // nothing hidden

  final brackets = <StaffBracket>[];
  for (final b in system.brackets) {
    final positions = <int>[
      for (var p = 0; p < visible.length; p++)
        if (visible[p] >= b.first && visible[p] <= b.last) p,
    ];
    if (positions.isNotEmpty) {
      brackets.add(StaffBracket(positions.first, positions.last, kind: b.kind));
    }
  }
  // Explicit barline groups clip to the surviving staves the same way; an empty
  // list defers to [connectBarlines], so it needs no remap (the effective
  // groups just recompute over the reduced staff count).
  final barlineGroups = <BarlineGroup>[];
  for (final g in system.barlineGroups) {
    final positions = <int>[
      for (var p = 0; p < visible.length; p++)
        if (visible[p] >= g.first && visible[p] <= g.last) p,
    ];
    if (positions.isNotEmpty) {
      barlineGroups.add(BarlineGroup(positions.first, positions.last));
    }
  }
  return StaffSystem(
    [for (final i in visible) system.staves[i]],
    brackets: brackets,
    connectBarlines: system.connectBarlines,
    barlineGroups: barlineGroups,
    systemBreaks: system.systemBreaks,
  );
}

bool _staffHasNotes(Score staff) =>
    staff.measures.any((m) => m.elements.any((e) => e is NoteElement));

double _max(double a, double b) => a > b ? a : b;

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _setEquals<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);
