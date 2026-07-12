/// Key signatures on the circle of fifths.
library;

import 'pitch.dart';

/// A key signature, expressed as a count of [fifths] on the circle of
/// fifths: positive = sharps (1 = G major/E minor), negative = flats
/// (-1 = F major/D minor), 0 = C major/A minor.
class KeySignature {
  /// Sharps (positive) or flats (negative) in the signature, -7..7.
  final int fifths;

  /// Creates a key signature with [fifths] sharps (positive) or flats
  /// (negative).
  const KeySignature(this.fifths)
      : assert(fifths >= -7 && fifths <= 7, 'fifths must be -7..7');

  /// Standard order of sharps: F C G D A E B. Flats use the reverse.
  static const List<Step> _sharpOrder = [
    Step.f,
    Step.c,
    Step.g,
    Step.d,
    Step.a,
    Step.e,
    Step.b,
  ];

  /// The steps altered by this signature, in the order they are written on
  /// the staff: sharps F C G D A E B, flats B E A D G C F.
  List<Step> get alteredSteps => fifths >= 0
      ? _sharpOrder.sublist(0, fifths)
      : _sharpOrder.reversed.toList().sublist(0, -fifths);

  /// The alteration this signature applies to [step]: 1 (sharp),
  /// -1 (flat) or 0.
  int alterFor(Step step) {
    if (fifths > 0 && _sharpOrder.indexOf(step) < fifths) return 1;
    if (fifths < 0 && _sharpOrder.indexOf(step) >= 7 + fifths) return -1;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      other is KeySignature && other.fifths == fifths;

  @override
  int get hashCode => fifths.hashCode;

  @override
  String toString() => 'KeySignature(${fifths >= 0 ? '+' : ''}$fifths)';
}
