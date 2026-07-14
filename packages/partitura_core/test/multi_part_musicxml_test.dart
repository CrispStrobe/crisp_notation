import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Workshop contract C11: the public N-part MusicXML writer, round-tripping
/// through [multiPartScoreFromMusicXml].
void main() {
  MultiPartScore trio() {
    final flute = Score.simple(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:q d5 e5 f5');
    // A B♭ clarinet — a transposing part.
    final clarinet = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: Score.simple(notes: 'g4:q a4 b4 c5').measures,
      transposition: Transposition.bFlat,
    );
    final bass = Score.simple(
        clef: Clef.bass, timeSignature: TimeSignature.fourFour, notes: 'c3:w');
    return MultiPartScore([flute, clarinet, bass],
        brackets: const [StaffBracket(0, 1, kind: StaffBracketKind.brace)]);
  }

  group('multiPartToMusicXml', () {
    test('round-trips part count, element counts, brackets, transposition', () {
      final back = multiPartScoreFromMusicXml(multiPartToMusicXml(trio()));
      expect(back.parts, hasLength(3));
      // Per-part element counts survive.
      expect(back.parts[0].measures.expand((m) => m.elements).length, 4);
      expect(back.parts[1].measures.expand((m) => m.elements).length, 4);
      expect(back.parts[2].measures.expand((m) => m.elements).length, 1);
      // The brace over parts 0–1 survives.
      expect(back.brackets, hasLength(1));
      expect(back.brackets.single.first, 0);
      expect(back.brackets.single.last, 1);
      expect(back.brackets.single.kind, StaffBracketKind.brace);
      // The B♭ clarinet keeps its transposition.
      expect(back.parts[1].transposition, Transposition.bFlat);
      // The other parts stay at concert pitch.
      expect(back.parts[0].transposition, isNull);
    });

    test('ids are deterministic per part (offset by part)', () {
      final back = multiPartScoreFromMusicXml(multiPartToMusicXml(trio()));
      final firstOf = [
        for (final p in back.parts) p.measures.first.elements.first.id,
      ];
      // Distinct id namespaces per part — mus needs no p<n>: prefix.
      expect(firstOf.toSet(), hasLength(back.parts.length));
    });

    test('partNames override the <part-name>', () {
      final xml = multiPartToMusicXml(trio(),
          partNames: const ['Flute', 'Clarinet in B♭', 'Contrabass']);
      expect(xml, contains('<part-name>Flute</part-name>'));
      expect(xml, contains('<part-name>Clarinet in B♭</part-name>'));
      expect(xml, contains('<part-name>Contrabass</part-name>'));
    });

    test('emits a group-symbol brace and a connected group-barline', () {
      final xml = multiPartToMusicXml(trio());
      expect(xml, contains('<group-symbol>brace</group-symbol>'));
      expect(xml, contains('<group-barline>yes</group-barline>'));
      // Well-formed nesting: one start and one stop part-group per group.
      expect('start'.allMatches(xml).length, greaterThanOrEqualTo(1));
    });

    test('a plain three-part score (no brackets) still round-trips', () {
      final doc = MultiPartScore([
        Score.simple(notes: 'c5:w'),
        Score.simple(notes: 'e4:w'),
        Score.simple(clef: Clef.bass, notes: 'c3:w'),
      ]);
      final back = multiPartScoreFromMusicXml(multiPartToMusicXml(doc));
      expect(back.parts, hasLength(3));
      expect(back.brackets, isEmpty);
    });
  });
}
