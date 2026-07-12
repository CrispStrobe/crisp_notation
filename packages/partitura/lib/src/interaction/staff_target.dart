import 'package:partitura_core/partitura_core.dart';

/// An empty staff location the user tapped or dropped on, quantized to the
/// nearest line/space (including the ledger range).
class StaffTarget {
  /// Quantized staff position, same convention as `Pitch.staffPosition`:
  /// 0 = bottom staff line, +1 per line/space upward.
  final int staffPosition;

  /// Index of the measure under the tap in `Score.measures`.
  final int measureIndex;

  /// Creates a staff target.
  const StaffTarget({required this.staffPosition, required this.measureIndex});

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
      other.measureIndex == measureIndex;

  @override
  int get hashCode => Object.hash(staffPosition, measureIndex);

  @override
  String toString() =>
      'StaffTarget(position $staffPosition, measure $measureIndex)';
}
