/// Diatonic intervals up to an octave.
library;

import 'pitch.dart';

/// Quality of an [Interval].
enum IntervalQuality {
  /// One semitone narrower than minor/perfect.
  diminished,

  /// One semitone narrower than major (seconds, thirds, sixths, sevenths).
  minor,

  /// Unisons, fourths, fifths and octaves in their pure form.
  perfect,

  /// The wider of the two common sizes (seconds, thirds, sixths, sevenths).
  major,

  /// One semitone wider than major/perfect.
  augmented,
}

/// A diatonic interval: a [quality] and a [number] from 1 (unison) to
/// 8 (octave).
///
/// Perfect-class numbers (1, 4, 5, 8) take diminished/perfect/augmented
/// qualities; the others (2, 3, 6, 7) take diminished/minor/major/augmented.
class Interval {
  /// The interval quality.
  final IntervalQuality quality;

  /// The diatonic number, 1 (unison) to 8 (octave).
  final int number;

  /// Creates an interval; asserts that [number] is 1–8 and that [quality]
  /// is valid for the number's class (see class docs).
  const Interval(this.quality, this.number)
      : assert(number >= 1 && number <= 8, 'number must be 1..8'),
        assert(
          (number == 1 || number == 4 || number == 5 || number == 8)
              ? (quality != IntervalQuality.major &&
                  quality != IntervalQuality.minor)
              : quality != IntervalQuality.perfect,
          'quality is invalid for this interval number',
        );

  /// Perfect unison (0 semitones).
  static const Interval perfectUnison = Interval(IntervalQuality.perfect, 1);

  /// Minor second (1 semitone).
  static const Interval minorSecond = Interval(IntervalQuality.minor, 2);

  /// Major second (2 semitones).
  static const Interval majorSecond = Interval(IntervalQuality.major, 2);

  /// Minor third (3 semitones).
  static const Interval minorThird = Interval(IntervalQuality.minor, 3);

  /// Major third (4 semitones).
  static const Interval majorThird = Interval(IntervalQuality.major, 3);

  /// Perfect fourth (5 semitones).
  static const Interval perfectFourth = Interval(IntervalQuality.perfect, 4);

  /// Augmented fourth / tritone (6 semitones).
  static const Interval augmentedFourth =
      Interval(IntervalQuality.augmented, 4);

  /// Diminished fifth / tritone (6 semitones).
  static const Interval diminishedFifth =
      Interval(IntervalQuality.diminished, 5);

  /// Perfect fifth (7 semitones).
  static const Interval perfectFifth = Interval(IntervalQuality.perfect, 5);

  /// Augmented fifth (8 semitones).
  static const Interval augmentedFifth = Interval(IntervalQuality.augmented, 5);

  /// Minor sixth (8 semitones).
  static const Interval minorSixth = Interval(IntervalQuality.minor, 6);

  /// Major sixth (9 semitones).
  static const Interval majorSixth = Interval(IntervalQuality.major, 6);

  /// Diminished seventh (9 semitones) — the seventh of a fully-diminished
  /// seventh chord (e.g. B–A♭).
  static const Interval diminishedSeventh =
      Interval(IntervalQuality.diminished, 7);

  /// Minor seventh (10 semitones).
  static const Interval minorSeventh = Interval(IntervalQuality.minor, 7);

  /// Major seventh (11 semitones).
  static const Interval majorSeventh = Interval(IntervalQuality.major, 7);

  /// Perfect octave (12 semitones).
  static const Interval perfectOctave = Interval(IntervalQuality.perfect, 8);

  /// Semitone spans of the perfect/major intervals, indexed by `number - 1`.
  static const List<int> _baseSemitones = [0, 2, 4, 5, 7, 9, 11, 12];

  static bool _isPerfectClass(int number) =>
      number == 1 || number == 4 || number == 5 || number == 8;

  /// The interval between two pitches, at most an octave apart. The order of
  /// the arguments does not matter; the interval is measured from the lower
  /// pitch (by diatonic index) to the higher.
  ///
  /// Throws an [ArgumentError] if the pitches span more than an octave or
  /// the interval has no name in the supported quality range, e.g. C4–G𝄪4.
  factory Interval.between(Pitch a, Pitch b) {
    var low = a;
    var high = b;
    if (high.diatonicIndex < low.diatonicIndex ||
        (high.diatonicIndex == low.diatonicIndex &&
            high.midiNumber < low.midiNumber)) {
      low = b;
      high = a;
    }
    final diatonicSpan = high.diatonicIndex - low.diatonicIndex;
    if (diatonicSpan > 7) {
      throw ArgumentError('$a and $b are more than an octave apart');
    }
    final number = diatonicSpan + 1;
    final offset =
        high.midiNumber - low.midiNumber - _baseSemitones[number - 1];
    final quality = _isPerfectClass(number)
        ? switch (offset) {
            -1 => IntervalQuality.diminished,
            0 => IntervalQuality.perfect,
            1 => IntervalQuality.augmented,
            _ => null,
          }
        : switch (offset) {
            -2 => IntervalQuality.diminished,
            -1 => IntervalQuality.minor,
            0 => IntervalQuality.major,
            1 => IntervalQuality.augmented,
            _ => null,
          };
    if (quality == null) {
      throw ArgumentError('The interval $a–$b is not representable');
    }
    return Interval(quality, number);
  }

  /// The size of this interval in semitones (major third: 4, perfect
  /// fifth: 7, …).
  int get semitones {
    final base = _baseSemitones[number - 1];
    return base +
        switch (quality) {
          IntervalQuality.perfect || IntervalQuality.major => 0,
          IntervalQuality.minor => -1,
          IntervalQuality.augmented => 1,
          IntervalQuality.diminished => _isPerfectClass(number) ? -1 : -2,
        };
  }

  @override
  bool operator ==(Object other) =>
      other is Interval && other.quality == quality && other.number == number;

  @override
  int get hashCode => Object.hash(quality, number);

  @override
  String toString() {
    const letters = {
      IntervalQuality.diminished: 'd',
      IntervalQuality.minor: 'm',
      IntervalQuality.perfect: 'P',
      IntervalQuality.major: 'M',
      IntervalQuality.augmented: 'A',
    };
    return '${letters[quality]}$number';
  }
}
