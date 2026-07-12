import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  group('Fraction', () {
    test('normalizes: reduces and moves the sign to the numerator', () {
      expect(Fraction(2, 4), Fraction(1, 2));
      expect(Fraction(6, 8).numerator, 3);
      expect(Fraction(6, 8).denominator, 4);
      expect(Fraction(1, -2).numerator, -1);
      expect(Fraction(1, -2).denominator, 2);
      expect(Fraction(-1, -2), Fraction(1, 2));
      expect(Fraction(0, 7), Fraction.zero);
    });

    test('rejects a zero denominator', () {
      expect(() => Fraction(1, 0), throwsArgumentError);
    });

    test('arithmetic is exact', () {
      expect(Fraction(1, 4) + Fraction(1, 8), Fraction(3, 8));
      expect(Fraction(1, 2) - Fraction(1, 4), Fraction(1, 4));
      expect(Fraction(3, 8) * Fraction(2, 3), Fraction(1, 4));
      // 4 quarters fill a 4/4 measure.
      final sum =
          List.filled(4, Fraction(1, 4)).fold(Fraction.zero, (a, b) => a + b);
      expect(sum, Fraction(1, 1));
    });

    test('comparison', () {
      expect(Fraction(1, 4) < Fraction(1, 3), isTrue);
      expect(Fraction(2, 4) <= Fraction(1, 2), isTrue);
      expect(Fraction(3, 8) > Fraction(1, 4), isTrue);
      expect(Fraction(7, 8) >= Fraction(7, 8), isTrue);
      expect(Fraction(1, 4).compareTo(Fraction(1, 4)), 0);
      expect(Fraction(-1, 2) < Fraction.zero, isTrue);
    });

    test('value semantics', () {
      expect(Fraction(2, 4), Fraction(1, 2));
      expect(Fraction(2, 4).hashCode, Fraction(1, 2).hashCode);
      expect(Fraction(3, 8).toString(), '3/8');
      expect(Fraction(1, 2).toDouble(), 0.5);
    });
  });
}
