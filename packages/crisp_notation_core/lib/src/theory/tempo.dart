/// Metronome / tempo marks.
library;

import 'duration.dart';

/// A metronome mark: [bpm] beats per minute, where one beat is a [beatUnit]
/// note (with [dots] augmentation dots). Lives in its own file so both `Score`
/// (initial tempo) and `Measure` (mid-score [Measure.tempoChange]) can carry it
/// without a circular import.
class Tempo {
  /// Beats per minute (the [beatUnit] note gets this many per minute).
  final double bpm;

  /// The note value of one beat (default a quarter).
  final DurationBase beatUnit;

  /// Augmentation dots on the beat unit (0–2; a dotted-quarter beat is 1).
  final int dots;

  /// Whether the score prints it as a metronome mark. A tempo that is only a
  /// playback setting (MusicXML `<sound tempo>` with no `<metronome>`) still
  /// times playback but draws nothing: "♩ = 45.5" printed over a song whose
  /// score says only "Lent et triste".
  final bool printed;

  /// Creates a metronome mark of [bpm] per [beatUnit] note.
  const Tempo(this.bpm,
      {this.beatUnit = DurationBase.quarter,
      this.dots = 0,
      this.printed = true})
      : assert(dots >= 0 && dots <= 2, 'dots must be 0..2');

  /// This mark expressed in **quarter notes per minute** (normalizing the
  /// [beatUnit] and [dots]) — the convention `secondsFor` / `TempoMap` use. So
  /// a quarter at 120 → 120, a dotted-quarter at 80 → 120, a half at 60 → 120.
  double get quarterBpm {
    final beat = NoteDuration(beatUnit, dots: dots).toFraction();
    return bpm * beat.numerator / beat.denominator * 4;
  }

  @override
  bool operator ==(Object other) =>
      other is Tempo &&
      other.bpm == bpm &&
      other.beatUnit == beatUnit &&
      other.dots == dots &&
      other.printed == printed;

  @override
  int get hashCode => Object.hash(bpm, beatUnit, dots, printed);

  @override
  String toString() =>
      'Tempo($bpm, ${beatUnit.name}${'.' * dots}${printed ? '' : ', unprinted'})';
}
