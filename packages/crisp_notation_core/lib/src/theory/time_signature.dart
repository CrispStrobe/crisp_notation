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

  /// An **interchangeable** (alternating) meter's companion signature, drawn
  /// beside this one at the start (e.g. 3/4 with a 2/4 alternate). Display-only:
  /// [measureCapacity]/[beamGroups] use this (primary) signature; individual
  /// measures switch meter through their own change. Null for a plain meter, and
  /// never itself carries a further [alternate].
  final TimeSignature? alternate;

  /// Creates a time signature of [beats] over [beatUnit], optionally drawn
  /// with a [symbol] glyph, additive [components], or an interchangeable
  /// [alternate] companion.
  const TimeSignature(this.beats, this.beatUnit,
      {this.symbol = TimeSymbol.numeric, this.components, this.alternate})
      : assert(beats >= 1, 'beats must be >= 1'),
        assert(
          beatUnit >= 1 && beatUnit <= 16 && (beatUnit & (beatUnit - 1)) == 0,
          'beatUnit must be a power of two between 1 and 16',
        );

  /// [beats]/[beatUnit], or null when the values are out of range — [beats] < 1,
  /// or [beatUnit] not a power of two in 1…16. Interchange readers use this to
  /// reject a malformed meter with a [FormatException] instead of tripping the
  /// constructor's asserts (or, in release, building an invalid meter).
  static TimeSignature? tryParse(int beats, int beatUnit,
      {TimeSymbol symbol = TimeSymbol.numeric}) {
    if (beats < 1) return null;
    if (beatUnit < 1 || beatUnit > 16 || (beatUnit & (beatUnit - 1)) != 0) {
      return null;
    }
    return TimeSignature(beats, beatUnit, symbol: symbol);
  }

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

  /// The beam-group lengths in one measure, each a whole-note [Fraction] —
  /// the metric units notes beam within. An additive meter uses its
  /// [components] (`[3, 2]/8` → 3/8 + 2/8); a compound meter (an eighth- or
  /// sixteenth-note beat unit with [beats] a multiple of three and greater
  /// than three, e.g. 6/8, 9/8, 12/8) groups in threes; every other meter is
  /// one group per beat. Their sum is always [toFraction].
  List<Fraction> beamGroups() {
    final unit = Fraction(1, beatUnit);
    final groups = components;
    if (groups != null) {
      return [for (final g in groups) unit * Fraction(g, 1)];
    }
    if ((beatUnit == 8 || beatUnit == 16) && beats > 3 && beats % 3 == 0) {
      return [for (var i = 0; i < beats ~/ 3; i++) unit * Fraction(3, 1)];
    }
    return [for (var i = 0; i < beats; i++) unit];
  }

  @override
  bool operator ==(Object other) =>
      other is TimeSignature &&
      other.beats == beats &&
      other.beatUnit == beatUnit &&
      other.symbol == symbol &&
      _sameComponents(other.components, components) &&
      other.alternate == alternate;

  static bool _sameComponents(List<int>? a, List<int>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(beats, beatUnit, symbol,
      Object.hashAll(components ?? const []), alternate);

  @override
  String toString() {
    final self = switch (symbol) {
      TimeSymbol.common => 'C',
      TimeSymbol.cut => 'C|',
      TimeSymbol.numeric => '${components?.join('+') ?? beats}/$beatUnit',
    };
    return alternate == null ? self : '$self~$alternate';
  }
}
