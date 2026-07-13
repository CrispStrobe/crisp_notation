import 'package:partitura_core/partitura_core.dart';

/// An empty staff location the user tapped or dropped on, quantized to the
/// nearest line/space (including the ledger range).
class StaffTarget {
  /// Quantized staff position, same convention as `Pitch.staffPosition`:
  /// 0 = bottom staff line, +1 per line/space upward.
  final int staffPosition;

  /// Index of the measure under the tap in `Score.measures`.
  final int measureIndex;

  /// Index of the wrapped system (line) the tap landed on, for multi-system
  /// views; 0 for a single-system view.
  final int systemIndex;

  /// Index of the staff the tap landed on within a multi-staff system (grand
  /// staff / ensemble); 0 for a single-staff view.
  final int staffIndex;

  /// Creates a staff target.
  const StaffTarget({
    required this.staffPosition,
    required this.measureIndex,
    this.systemIndex = 0,
    this.staffIndex = 0,
  });

  /// The pitch at this staff position in [clef]. The natural note by
  /// default; pass [preferredAlter] to spell it sharp/flat (e.g. a game
  /// asking for F♯ passes 1).
  Pitch pitchFor(Clef clef, {int preferredAlter = 0}) {
    final natural = clef.pitchAt(staffPosition);
    return Pitch(natural.step, alter: preferredAlter, octave: natural.octave);
  }

  @override
  bool operator ==(Object other) =>
      other is StaffTarget &&
      other.staffPosition == staffPosition &&
      other.measureIndex == measureIndex &&
      other.systemIndex == systemIndex &&
      other.staffIndex == staffIndex;

  @override
  int get hashCode =>
      Object.hash(staffPosition, measureIndex, systemIndex, staffIndex);

  @override
  String toString() => 'StaffTarget(position $staffPosition, '
      'measure $measureIndex, system $systemIndex, staff $staffIndex)';
}
