import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  group('DurationBase', () {
    test('denominators', () {
      expect(DurationBase.whole.denominator, 1);
      expect(DurationBase.half.denominator, 2);
      expect(DurationBase.quarter.denominator, 4);
      expect(DurationBase.eighth.denominator, 8);
      expect(DurationBase.sixteenth.denominator, 16);
    });
  });

  group('NoteDuration.fraction', () {
    test('undotted values', () {
      expect(NoteDuration.whole.fraction, (1, 1));
      expect(NoteDuration.half.fraction, (1, 2));
      expect(NoteDuration.quarter.fraction, (1, 4));
      expect(NoteDuration.eighth.fraction, (1, 8));
      expect(NoteDuration.sixteenth.fraction, (1, 16));
    });

    test('single dot adds half the value', () {
      expect(const NoteDuration(DurationBase.whole, dots: 1).fraction, (3, 2));
      expect(const NoteDuration(DurationBase.half, dots: 1).fraction, (3, 4));
      expect(
        const NoteDuration(DurationBase.quarter, dots: 1).fraction,
        (3, 8),
      );
      expect(
        const NoteDuration(DurationBase.eighth, dots: 1).fraction,
        (3, 16),
      );
    });

    test('double dot adds three quarters of the value', () {
      expect(
        const NoteDuration(DurationBase.quarter, dots: 2).fraction,
        (7, 16),
      );
      expect(const NoteDuration(DurationBase.half, dots: 2).fraction, (7, 8));
    });

    test('toFraction matches fraction', () {
      const dotted = NoteDuration(DurationBase.quarter, dots: 1);
      expect(dotted.toFraction(), Fraction(3, 8));
      // Dotted half (3/4) + quarter (1/4) fills a 4/4 measure exactly.
      expect(
        const NoteDuration(DurationBase.half, dots: 1).toFraction() +
            NoteDuration.quarter.toFraction(),
        Fraction(1, 1),
      );
    });
  });

  group('value semantics', () {
    test('equality', () {
      expect(
        const NoteDuration(DurationBase.quarter),
        NoteDuration.quarter,
      );
      expect(
        NoteDuration.quarter,
        isNot(const NoteDuration(DurationBase.quarter, dots: 1)),
      );
      expect(NoteDuration.quarter, isNot(NoteDuration.eighth));
    });

    test('toString shows dots', () {
      expect(
        const NoteDuration(DurationBase.quarter, dots: 2).toString(),
        'NoteDuration(quarter..)',
      );
    });
  });
}
