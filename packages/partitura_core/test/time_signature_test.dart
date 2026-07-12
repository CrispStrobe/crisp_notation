import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  group('TimeSignature.measureCapacity', () {
    test('reduces to a fraction of a whole note', () {
      expect(TimeSignature.fourFour.measureCapacity, (1, 1));
      expect(TimeSignature.threeFour.measureCapacity, (3, 4));
      expect(TimeSignature.twoFour.measureCapacity, (1, 2));
      expect(TimeSignature.sixEight.measureCapacity, (3, 4));
      expect(const TimeSignature(2, 2).measureCapacity, (1, 1));
      expect(const TimeSignature(5, 4).measureCapacity, (5, 4));
      expect(const TimeSignature(9, 8).measureCapacity, (9, 8));
    });

    test('toFraction matches', () {
      expect(TimeSignature.threeFour.toFraction(), Fraction(3, 4));
      expect(TimeSignature.fourFour.toFraction(), Fraction(1, 1));
    });

    test('a full 4/4 measure of quarters sums to the capacity', () {
      final sum = List.filled(4, NoteDuration.quarter.toFraction())
          .fold(Fraction.zero, (a, b) => a + b);
      expect(sum, TimeSignature.fourFour.toFraction());
    });
  });

  test('value semantics', () {
    expect(const TimeSignature(4, 4), TimeSignature.fourFour);
    expect(const TimeSignature(4, 4), isNot(const TimeSignature(2, 2)));
    expect(TimeSignature.threeFour.toString(), '3/4');
  });
}
