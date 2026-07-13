/// Multi-part document model: a whole piece as N parts that line-break
/// together into multi-staff systems and paginate, with barlines spanning
/// chosen groups of parts. Generalizes the single-system [StaffSystem] to a
/// full document, and the all-or-nothing `connectBarlines` to per-group
/// [BarlineGroup] spans.
library;

import '../internal/util.dart';
import '../model/score.dart';
import 'staff_system.dart';

/// A contiguous run of parts [first]..[last] (inclusive, 0-based) whose
/// barlines are drawn through the inter-staff gaps within the group — the
/// "custom-span barline". Parts outside every group get their own per-staff
/// barlines (no connection to their neighbours).
///
/// A single group spanning all parts reproduces the old
/// `StaffSystem.connectBarlines: true` (one continuous systemic barline); a
/// document with two groups (e.g. strings connected, winds connected, but the
/// barline broken between the sections) is the feature single-part layout
/// could not express.
class BarlineGroup {
  /// First part index in the group (0-based).
  final int first;

  /// Last part index in the group (inclusive).
  final int last;

  /// Creates a barline group over parts [first]..[last].
  const BarlineGroup(this.first, this.last)
      : assert(last >= first, 'last must be >= first'),
        assert(first >= 0, 'first must be >= 0');

  /// Whether part [index] falls inside this group.
  bool contains(int index) => index >= first && index <= last;

  @override
  bool operator ==(Object other) =>
      other is BarlineGroup && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);

  @override
  String toString() => 'BarlineGroup($first..$last)';
}

/// A whole piece as N [parts] (each part a [Score] with the same measure count
/// and meter). Line-breaks into multi-staff systems and paginates as one
/// document, drawing [brackets] at the left edge and barlines per
/// [barlineGroups].
///
/// Element ids should be unique across parts so interaction stays unambiguous.
class MultiPartScore {
  /// The parts, top to bottom.
  final List<Score> parts;

  /// Bracket/brace groups drawn at the left edge (may be empty or nested).
  final List<StaffBracket> brackets;

  /// Contiguous part-index runs whose barlines connect through the group. An
  /// empty list means the barlines connect through the whole system (one
  /// implicit group over every part) — see [effectiveBarlineGroups].
  final List<BarlineGroup> barlineGroups;

  /// Creates a multi-part score from [parts] (at least one).
  const MultiPartScore(
    this.parts, {
    this.brackets = const [],
    this.barlineGroups = const [],
  }) : assert(parts.length > 0, 'a document needs at least one part');

  /// The measure count shared by every part (taken from the first part).
  int get measureCount => parts.first.measures.length;

  /// The barline groups to draw: [barlineGroups] as given, or — when that is
  /// empty — a single group spanning every part (fully connected barlines,
  /// like `StaffSystem.connectBarlines: true`).
  List<BarlineGroup> get effectiveBarlineGroups => barlineGroups.isNotEmpty
      ? barlineGroups
      : [BarlineGroup(0, parts.length - 1)];

  /// This document with every transposing part shown at concert (sounding)
  /// pitch — the concert-pitch toggle. Non-transposing parts are unchanged.
  MultiPartScore atConcertPitch() => MultiPartScore(
        [for (final part in parts) part.atConcertPitch()],
        brackets: brackets,
        barlineGroups: barlineGroups,
      );

  @override
  bool operator ==(Object other) =>
      other is MultiPartScore &&
      listEquals(other.parts, parts) &&
      listEquals(other.brackets, brackets) &&
      listEquals(other.barlineGroups, barlineGroups);

  @override
  int get hashCode => Object.hash(Object.hashAll(parts),
      Object.hashAll(brackets), Object.hashAll(barlineGroups));

  @override
  String toString() => 'MultiPartScore(${parts.length} parts)';
}
