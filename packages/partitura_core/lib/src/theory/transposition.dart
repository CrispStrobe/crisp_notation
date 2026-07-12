/// Transposing-instrument support.
library;

import 'interval.dart';

/// How a transposing instrument's **written** pitch relates to its **sounding**
/// (concert) pitch. Mirrors MusicXML `<transpose>`: to get the sounding pitch,
/// move a written pitch by [interval] (in the [down] direction) plus [octaves]
/// whole octaves. A B♭ trumpet, for instance, sounds a major second below what
/// is written ([Transposition.bFlat]).
///
/// A non-transposing (concert-pitch) part carries no transposition at all
/// (`Score.transposition == null`).
class Transposition {
  /// The interval between written and sounding pitch (≤ an octave; larger
  /// transpositions add [octaves]).
  final Interval interval;

  /// Whether the sounding pitch is **below** the written pitch — the usual
  /// case (B♭/E♭/F instruments all sound lower than written).
  final bool down;

  /// Extra whole octaves added in the same direction as [down] (e.g. a tenor
  /// saxophone sounds a major ninth lower: a major second + one octave).
  final int octaves;

  /// Creates a transposition of [interval] (defaulting to sounding-below-written
  /// by [octaves] extra octaves).
  const Transposition(this.interval, {this.down = true, this.octaves = 0})
      : assert(octaves >= 0, 'octaves must be >= 0');

  /// B♭ instruments (trumpet, clarinet, tenor/soprano sax): down a major 2nd.
  static const Transposition bFlat = Transposition(Interval.majorSecond);

  /// A instruments (A clarinet): down a minor 3rd.
  static const Transposition a = Transposition(Interval.minorThird);

  /// E♭ instruments (alto sax, alto clarinet): down a major 6th.
  static const Transposition eFlat = Transposition(Interval.majorSixth);

  /// F instruments (French horn, English horn): down a perfect 5th.
  static const Transposition f = Transposition(Interval.perfectFifth);

  /// B♭ tenor saxophone: down a major 9th (a major 2nd plus an octave).
  static const Transposition bFlatTenor =
      Transposition(Interval.majorSecond, octaves: 1);

  @override
  bool operator ==(Object other) =>
      other is Transposition &&
      other.interval == interval &&
      other.down == down &&
      other.octaves == octaves;

  @override
  int get hashCode => Object.hash(interval, down, octaves);

  @override
  String toString() =>
      'Transposition(${down ? '-' : '+'}$interval${octaves == 0 ? '' : ' +${octaves}va'})';
}
