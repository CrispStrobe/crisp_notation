/// Time signatures.
library;

import 'fraction.dart';

/// How a [TimeSignature] is drawn.
enum TimeSymbol {
  /// Stacked numerals (the default).
  numeric,

  /// The common-time C glyph (4/4).
  common,

  /// The cut-time ¢ glyph (2/2, alla breve).
  cut,
}

/// A simple-meter time signature such as 4/4 or 3/4.
class TimeSignature {
  /// Beats per measure (the upper number).
  final int beats;

  /// The note value of one beat as a denominator (the lower number):
  /// 4 = quarter note. Must be a power of two between 1 and 16.
  final int beatUnit;

  /// How the signature is rendered — as numerals, or the common/cut glyph.
  /// A [TimeSymbol.common] signature is 4/4 drawn as C; [TimeSymbol.cut] is
  /// 2/2 drawn as ¢. The numeric meaning (beats/beatUnit) is unchanged.
  final TimeSymbol symbol;

  /// For an additive/composite meter, the beat groups drawn with `+` between
  /// them (e.g. `[3, 2]` for 3+2/8); null for a simple meter. When set, [beats]
  /// is their sum.
  final List<int>? components;

  /// Creates a time signature of [beats] over [beatUnit], optionally drawn
  /// with a [symbol] glyph or additive [components].
  const TimeSignature(this.beats, this.beatUnit,
      {this.symbol = TimeSymbol.numeric, this.components})
      : assert(beats >= 1, 'beats must be >= 1'),
        assert(
          beatUnit >= 1 && beatUnit <= 16 && (beatUnit & (beatUnit - 1)) == 0,
          'beatUnit must be a power of two between 1 and 16',
        );

  /// An additive meter such as 3+2/8, drawn with its groups separated by `+`.
  /// [beats] is the sum of [groups].
  factory TimeSignature.additive(List<int> groups, int beatUnit) {
    assert(groups.isNotEmpty, 'additive meter needs at least one group');
    final beats = groups.reduce((a, b) => a + b);
    return TimeSignature(beats, beatUnit,
        components: List.unmodifiable(groups));
  }

  /// Common time, 4/4.
  static const TimeSignature fourFour = TimeSignature(4, 4);

  /// Common time drawn as the C glyph (4/4).
  static const TimeSignature commonTime =
      TimeSignature(4, 4, symbol: TimeSymbol.common);

  /// Cut time / alla breve drawn as the ¢ glyph (2/2).
  static const TimeSignature cutTime =
      TimeSignature(2, 2, symbol: TimeSymbol.cut);

  /// Waltz time, 3/4.
  static const TimeSignature threeFour = TimeSignature(3, 4);

  /// March time, 2/4.
  static const TimeSignature twoFour = TimeSignature(2, 4);

  /// Compound duple time, 6/8.
  static const TimeSignature sixEight = TimeSignature(6, 8);

  /// The total duration a full measure holds, as a reduced fraction of a
  /// whole note: 4/4 == (1, 1), 3/4 == (3, 4), 6/8 == (3, 4).
  (int, int) get measureCapacity {
    final f = toFraction();
    return (f.numerator, f.denominator);
  }

  /// The measure capacity as a [Fraction] of a whole note.
  Fraction toFraction() => Fraction(beats, beatUnit);

  @override
  bool operator ==(Object other) =>
      other is TimeSignature &&
      other.beats == beats &&
      other.beatUnit == beatUnit &&
      other.symbol == symbol &&
      _sameComponents(other.components, components);

  static bool _sameComponents(List<int>? a, List<int>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
      beats, beatUnit, symbol, Object.hashAll(components ?? const []));

  @override
  String toString() => switch (symbol) {
        TimeSymbol.common => 'C',
        TimeSymbol.cut => 'C|',
        TimeSymbol.numeric => '${components?.join('+') ?? beats}/$beatUnit',
      };
}
