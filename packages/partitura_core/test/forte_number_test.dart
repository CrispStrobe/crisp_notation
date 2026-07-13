import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  test('famous set classes (anchors)', () {
    expect(forteNumber({0, 3, 7}), '3-11'); // minor triad
    expect(forteNumber({0, 4, 7}), '3-11'); // major triad = same class
    expect(forteNumber({0, 4, 8}), '3-12'); // augmented triad
    expect(forteNumber({0, 3, 6}), '3-10'); // diminished triad
    expect(forteNumber({0, 4, 7, 10}), '4-27'); // dominant seventh
    expect(forteNumber({0, 3, 6, 9}), '4-28'); // fully-diminished seventh
    expect(forteNumber({0, 1, 4, 6}), '4-Z15');
    expect(forteNumber({0, 1, 3, 7}), '4-Z29');
    expect(forteNumber({0, 2, 4, 7, 9}), '5-35'); // pentatonic
    expect(forteNumber({0, 2, 4, 6, 8}), '5-33'); // whole-tone pentad
    // Derived from complements (Forte's shared-ordinal convention):
    expect(forteNumber({0, 2, 4, 5, 7, 9, 11}), '7-35'); // major scale
    expect(forteNumber({0, 1, 3, 4, 6, 7, 9, 10}), '8-28'); // octatonic
    expect(
        forteNumber({0, 2, 4, 6, 8, 10}), isNull); // whole-tone = 6-35, uncat.
    expect(forteNumber({0, 6}), '2-6'); // tritone
    expect(forteNumber({0}), '1-1');
    expect(forteNumber(const <int>{}), isNull);
  });

  test('completeness: every catalogued set class has a number; counts match',
      () {
    final byCard = <int, Set<String>>{};
    for (var mask = 1; mask < (1 << 12); mask++) {
      final pcs = {
        for (var i = 0; i < 12; i++)
          if (mask & (1 << i) != 0) i,
      };
      final card = pcs.length;
      final number = forteNumber(pcs);
      if (card == 6) {
        expect(number, isNull); // hexachords intentionally uncatalogued
        continue;
      }
      expect(number, isNotNull,
          reason: 'no Forte number for prime ${primeForm(pcs)} (card $card)');
      (byCard[card] ??= <String>{}).add(number!);
    }
    // Forte's count of distinct set classes per cardinality.
    const counts = {
      1: 1,
      2: 6,
      3: 12,
      4: 29,
      5: 38,
      7: 38,
      8: 29,
      9: 12,
      10: 6,
      11: 1,
      12: 1,
    };
    counts.forEach((card, n) {
      expect(byCard[card]!.length, n, reason: 'cardinality $card class count');
    });
  });
}
