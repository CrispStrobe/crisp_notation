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
  });

  group('TimeSignature.beamGroups', () {
    test('simple meters are one group per beat', () {
      expect(TimeSignature.fourFour.beamGroups(),
          [Fraction(1, 4), Fraction(1, 4), Fraction(1, 4), Fraction(1, 4)]);
      expect(TimeSignature.threeFour.beamGroups(),
          [Fraction(1, 4), Fraction(1, 4), Fraction(1, 4)]);
      expect(const TimeSignature(5, 4).beamGroups(),
          List.filled(5, Fraction(1, 4)));
    });

    test('compound meters group in threes', () {
      expect(TimeSignature.sixEight.beamGroups(),
          [Fraction(3, 8), Fraction(3, 8)]);
      expect(const TimeSignature(9, 8).beamGroups(),
          [Fraction(3, 8), Fraction(3, 8), Fraction(3, 8)]);
      expect(const TimeSignature(12, 8).beamGroups(),
          List.filled(4, Fraction(3, 8)));
      // 3/8 stays a single beat group (not "> 3").
      expect(const TimeSignature(3, 8).beamGroups(),
          [Fraction(1, 8), Fraction(1, 8), Fraction(1, 8)]);
    });

    test('additive meters use their components', () {
      expect(TimeSignature.additive([3, 2], 8).beamGroups(),
          [Fraction(3, 8), Fraction(2, 8)]);
      expect(TimeSignature.additive([2, 2, 3], 8).beamGroups(),
          [Fraction(2, 8), Fraction(2, 8), Fraction(3, 8)]);
    });

    test('the groups always sum to the measure capacity', () {
      for (final ts in [
        TimeSignature.fourFour,
        TimeSignature.sixEight,
        const TimeSignature(9, 8),
        TimeSignature.additive([3, 2], 8),
      ]) {
        final sum = ts.beamGroups().reduce((a, b) => a + b);
        expect(sum, ts.toFraction());
      }
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
