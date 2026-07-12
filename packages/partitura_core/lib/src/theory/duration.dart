/// Rhythmic durations: note/rest values with augmentation dots.
library;

import 'fraction.dart';

/// Undotted note/rest duration bases supported in v0.1.
enum DurationBase {
  /// Whole note/rest (ganze Note), 1/1.
  whole,

  /// Half note/rest (halbe Note), 1/2.
  half,

  /// Quarter note/rest (Viertelnote), 1/4.
  quarter,

  /// Eighth note/rest (Achtelnote), 1/8.
  eighth,

  /// Sixteenth note/rest (Sechzehntelnote), 1/16.
  sixteenth,

  /// Thirty-second note/rest (Zweiunddreißigstelnote), 1/32.
  thirtySecond,

  /// Sixty-fourth note/rest (Vierundsechzigstelnote), 1/64.
  sixtyFourth,

  /// Breve / double whole note (Brevis), worth 2 whole notes. Its
  /// [denominator] is 1; use [NoteDuration.fraction] for the exact value.
  breve;

  /// The denominator of the undotted value as a fraction of a whole note:
  /// 1, 2, 4, 8, 16, 32 or 64 (and 1 for the breve, whose value is 2/1).
  int get denominator => this == DurationBase.breve ? 1 : 1 << index;
}

/// A rhythmic duration: a base value plus 0–2 augmentation dots.
class NoteDuration {
  /// The undotted base value.
  final DurationBase base;

  /// Number of augmentation dots (0–2). Each dot adds half of the previous
  /// value: a dotted quarter is 3/8, a double-dotted quarter is 7/16.
  final int dots;

  /// Creates a duration from [base] and optional [dots].
  const NoteDuration(this.base, {this.dots = 0})
      : assert(dots >= 0 && dots <= 2, 'dots must be 0..2');

  /// An undotted whole note.
  static const NoteDuration whole = NoteDuration(DurationBase.whole);

  /// An undotted half note.
  static const NoteDuration half = NoteDuration(DurationBase.half);

  /// An undotted quarter note.
  static const NoteDuration quarter = NoteDuration(DurationBase.quarter);

  /// An undotted eighth note.
  static const NoteDuration eighth = NoteDuration(DurationBase.eighth);

  /// An undotted sixteenth note.
  static const NoteDuration sixteenth = NoteDuration(DurationBase.sixteenth);

  /// This duration as an exact fraction of a whole note, fully reduced:
  /// quarter == (1, 4), dotted quarter == (3, 8), breve == (2, 1).
  (int num, int den) get fraction {
    final dotNumerator = (1 << (dots + 1)) - 1;
    final dotDenominator = 1 << dots;
    if (base == DurationBase.breve) {
      final reduced = Fraction(2 * dotNumerator, dotDenominator);
      return (reduced.numerator, reduced.denominator);
    }
    return (dotNumerator, base.denominator << dots);
  }

  /// This duration as a [Fraction] of a whole note.
  Fraction toFraction() {
    final (num, den) = fraction;
    return Fraction(num, den);
  }

  @override
  bool operator ==(Object other) =>
      other is NoteDuration && other.base == base && other.dots == dots;

  @override
  int get hashCode => Object.hash(base, dots);

  @override
  String toString() => 'NoteDuration(${base.name}${'.' * dots})';
}
