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
  breve,

  /// Longa, worth 4 whole notes. Appears in Renaissance and early-music
  /// sources, which is where the corpus meets it.
  long,

  /// 128th note/rest, 1/128.
  oneHundredTwentyEighth,

  /// 256th note/rest, 1/256.
  twoHundredFiftySixth,

  /// 512th note/rest, 1/512.
  fiveHundredTwelfth,

  /// 1024th note/rest, 1/1024 — the shortest MusicXML defines.
  oneThousandTwentyFourth;

  /// The undotted value as an exact fraction of a whole note.
  ///
  /// Deliberately an explicit table rather than something derived from
  /// [index]: values longer than a whole note do not fit `1 << index` at all,
  /// and keying on declaration order silently renumbers every existing
  /// duration the moment one is inserted.
  (int num, int den) get wholeValue => switch (this) {
        DurationBase.long => (4, 1),
        DurationBase.breve => (2, 1),
        DurationBase.whole => (1, 1),
        DurationBase.half => (1, 2),
        DurationBase.quarter => (1, 4),
        DurationBase.eighth => (1, 8),
        DurationBase.sixteenth => (1, 16),
        DurationBase.thirtySecond => (1, 32),
        DurationBase.sixtyFourth => (1, 64),
        DurationBase.oneHundredTwentyEighth => (1, 128),
        DurationBase.twoHundredFiftySixth => (1, 256),
        DurationBase.fiveHundredTwelfth => (1, 512),
        DurationBase.oneThousandTwentyFourth => (1, 1024),
      };

  /// The base-2 logarithm of the undotted value: a whole note is 0, a quarter
  /// -2, a breve +1. Layout spaces notes on this scale and derives flag/beam
  /// counts from it, which is what [index] used to be pressed into doing.
  int get log2Value => switch (this) {
        DurationBase.long => 2,
        DurationBase.breve => 1,
        DurationBase.whole => 0,
        DurationBase.half => -1,
        DurationBase.quarter => -2,
        DurationBase.eighth => -3,
        DurationBase.sixteenth => -4,
        DurationBase.thirtySecond => -5,
        DurationBase.sixtyFourth => -6,
        DurationBase.oneHundredTwentyEighth => -7,
        DurationBase.twoHundredFiftySixth => -8,
        DurationBase.fiveHundredTwelfth => -9,
        DurationBase.oneThousandTwentyFourth => -10,
      };

  /// Number of flags (or beams) the value carries: 1 for an eighth, 2 for a
  /// sixteenth, and 0 for anything a quarter or longer.
  int get flagCount {
    final f = -log2Value - 2;
    return f < 0 ? 0 : f;
  }

  /// The denominator of the undotted value as a fraction of a whole note.
  /// 1 for the breve and longa, whose values are 2/1 and 4/1 — use
  /// [wholeValue] or [NoteDuration.fraction] when the numerator matters.
  int get denominator => wholeValue.$2;
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
    final (bn, bd) = base.wholeValue;
    if (bn != 1) {
      // Longer than a whole note (breve, longa), so the numerator carries it.
      final reduced = Fraction(bn * dotNumerator, bd * dotDenominator);
      return (reduced.numerator, reduced.denominator);
    }
    return (dotNumerator, bd << dots);
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
