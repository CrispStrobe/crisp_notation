/// Exact rational arithmetic for duration math.
library;

/// An exact rational number with a normalized [numerator] and [denominator].
///
/// Duration arithmetic (e.g. "do the notes in this measure sum to the time
/// signature's capacity?") must be exact; floating point would accumulate
/// error. The denominator is always positive and the fraction is always
/// fully reduced, so equal values compare equal and hash identically.
class Fraction implements Comparable<Fraction> {
  /// The reduced numerator; carries the sign.
  final int numerator;

  /// The reduced denominator; always positive.
  final int denominator;

  const Fraction._(this.numerator, this.denominator);

  /// Creates the fraction [numerator]/[denominator], normalizing the sign
  /// onto the numerator and reducing by the greatest common divisor.
  ///
  /// Throws an [ArgumentError] if [denominator] is zero.
  factory Fraction(int numerator, int denominator) {
    if (denominator == 0) {
      throw ArgumentError.value(
        denominator,
        'denominator',
        'must not be zero',
      );
    }
    final sign = denominator.isNegative ? -1 : 1;
    final g = _gcd(numerator.abs(), denominator.abs());
    return Fraction._(sign * numerator ~/ g, denominator.abs() ~/ g);
  }

  /// The fraction 0/1.
  static const Fraction zero = Fraction._(0, 1);

  static int _gcd(int a, int b) {
    while (b != 0) {
      final t = a % b;
      a = b;
      b = t;
    }
    return a == 0 ? 1 : a;
  }

  /// The sum of this fraction and [other].
  Fraction operator +(Fraction other) => Fraction(
        numerator * other.denominator + other.numerator * denominator,
        denominator * other.denominator,
      );

  /// The difference of this fraction and [other].
  Fraction operator -(Fraction other) => Fraction(
        numerator * other.denominator - other.numerator * denominator,
        denominator * other.denominator,
      );

  /// The product of this fraction and [other].
  Fraction operator *(Fraction other) => Fraction(
        numerator * other.numerator,
        denominator * other.denominator,
      );

  /// Whether this fraction is strictly less than [other].
  bool operator <(Fraction other) => compareTo(other) < 0;

  /// Whether this fraction is less than or equal to [other].
  bool operator <=(Fraction other) => compareTo(other) <= 0;

  /// Whether this fraction is strictly greater than [other].
  bool operator >(Fraction other) => compareTo(other) > 0;

  /// Whether this fraction is greater than or equal to [other].
  bool operator >=(Fraction other) => compareTo(other) >= 0;

  /// This fraction as a (possibly lossy) double.
  double toDouble() => numerator / denominator;

  @override
  int compareTo(Fraction other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);

  @override
  bool operator ==(Object other) =>
      other is Fraction &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => '$numerator/$denominator';
}
