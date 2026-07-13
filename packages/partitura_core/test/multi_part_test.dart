import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  MultiPartScore quartet() => MultiPartScore([
        Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5 | g5:h a5:h'),
        Score.simple(clef: Clef.treble, notes: 'g4:q g4 g4 g4 | b4:h c5:h'),
        Score.simple(clef: Clef.alto, notes: 'e4:q f4 g4 a4 | d4:h e4:h'),
        Score.simple(clef: Clef.bass, notes: 'c3:q b2 a2 g2 | g2:h c3:h'),
      ], brackets: const [
        StaffBracket(0, 3)
      ], barlineGroups: const [
        BarlineGroup(0, 1),
        BarlineGroup(2, 3),
      ]);

  group('BarlineGroup', () {
    test('contains is inclusive of both ends', () {
      const g = BarlineGroup(1, 3);
      expect(g.contains(0), isFalse);
      expect(g.contains(1), isTrue);
      expect(g.contains(2), isTrue);
      expect(g.contains(3), isTrue);
      expect(g.contains(4), isFalse);
    });

    test('value semantics', () {
      expect(const BarlineGroup(0, 2), const BarlineGroup(0, 2));
      expect(
          const BarlineGroup(0, 2).hashCode, const BarlineGroup(0, 2).hashCode);
      expect(const BarlineGroup(0, 2), isNot(const BarlineGroup(0, 3)));
    });

    test('a single-part group is valid', () {
      expect(const BarlineGroup(2, 2).contains(2), isTrue);
    });
  });

  group('MultiPartScore', () {
    test('exposes its parts and shared measure count', () {
      final doc = quartet();
      expect(doc.parts, hasLength(4));
      expect(doc.measureCount, 2);
    });

    test('effectiveBarlineGroups returns the explicit groups when given', () {
      expect(quartet().effectiveBarlineGroups,
          const [BarlineGroup(0, 1), BarlineGroup(2, 3)]);
    });

    test('effectiveBarlineGroups defaults to one group over all parts', () {
      final doc = MultiPartScore([
        Score.simple(notes: 'c4:w'),
        Score.simple(clef: Clef.bass, notes: 'c3:w'),
        Score.simple(clef: Clef.bass, notes: 'c2:w'),
      ]);
      expect(doc.barlineGroups, isEmpty);
      expect(doc.effectiveBarlineGroups, const [BarlineGroup(0, 2)]);
    });

    test('atConcertPitch transposes each part and preserves grouping', () {
      final clarinet = Score.simple(notes: 'd5:w');
      final written = MultiPartScore([
        // A B-flat clarinet: written a major second above sounding.
        Score(
          clef: clarinet.clef,
          measures: clarinet.measures,
          transposition: Transposition.bFlat,
        ),
        Score.simple(clef: Clef.bass, notes: 'c3:w'),
      ], brackets: const [
        StaffBracket(0, 1)
      ], barlineGroups: const [
        BarlineGroup(0, 1)
      ]);
      final concert = written.atConcertPitch();
      // The transposing part sounds a major second lower (d5 -> c5).
      expect(concert.parts.first, written.parts.first.atConcertPitch());
      expect(concert.parts.first.transposition, isNull);
      // The non-transposing part is unchanged.
      expect(concert.parts[1], written.parts[1]);
      // Grouping metadata is carried through.
      expect(concert.brackets, written.brackets);
      expect(concert.barlineGroups, written.barlineGroups);
    });

    test('value semantics', () {
      MultiPartScore make() => MultiPartScore([
            Score.simple(notes: 'c4:w'),
            Score.simple(clef: Clef.bass, notes: 'c3:w'),
          ], brackets: const [
            StaffBracket(0, 1, kind: StaffBracketKind.brace)
          ], barlineGroups: const [
            BarlineGroup(0, 1)
          ]);
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
      // Differing barline grouping breaks equality.
      final other = MultiPartScore([
        Score.simple(notes: 'c4:w'),
        Score.simple(clef: Clef.bass, notes: 'c3:w'),
      ], brackets: const [
        StaffBracket(0, 1, kind: StaffBracketKind.brace)
      ]);
      expect(make(), isNot(other));
    });

    test('toString names the part count', () {
      expect(quartet().toString(), contains('4 parts'));
    });
  });
}
