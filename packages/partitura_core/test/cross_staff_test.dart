import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  group('CrossStaffNote', () {
    test('defaults to one staff down', () {
      const cs = CrossStaffNote('e0');
      expect(cs.noteId, 'e0');
      expect(cs.staffShift, 1);
    });

    test('a zero shift is rejected', () {
      expect(() => CrossStaffNote('e0', staffShift: 0), throwsA(isA<Error>()));
    });

    test('value semantics', () {
      expect(const CrossStaffNote('e0', staffShift: -1),
          const CrossStaffNote('e0', staffShift: -1));
      expect(const CrossStaffNote('e0', staffShift: -1).hashCode,
          const CrossStaffNote('e0', staffShift: -1).hashCode);
      expect(const CrossStaffNote('e0'),
          isNot(const CrossStaffNote('e0', staffShift: -1)));
      expect(const CrossStaffNote('e0'), isNot(const CrossStaffNote('e1')));
    });

    test('toString names the id and shift', () {
      expect(const CrossStaffNote('e3', staffShift: -1).toString(),
          contains('e3'));
      expect(const CrossStaffNote('e3', staffShift: -1).toString(),
          contains('-1'));
    });
  });

  group('Score.crossStaff', () {
    Score piano() => Score(
          clef: Clef.bass,
          timeSignature: TimeSignature.fourFour,
          measures: [
            Measure([
              NoteElement.note(Pitch.parse('c3'), NoteDuration.eighth,
                  id: 'e0'),
              NoteElement.note(Pitch.parse('e4'), NoteDuration.eighth,
                  id: 'e1'),
              NoteElement.note(Pitch.parse('g4'), NoteDuration.eighth,
                  id: 'e2'),
              NoteElement.note(Pitch.parse('c5'), NoteDuration.eighth,
                  id: 'e3'),
            ]),
          ],
          crossStaff: const [
            // The upper three eighths are engraved on the staff above.
            CrossStaffNote('e1', staffShift: -1),
            CrossStaffNote('e2', staffShift: -1),
            CrossStaffNote('e3', staffShift: -1),
          ],
        );

    test('defaults to empty', () {
      expect(Score.simple(notes: 'c4:q').crossStaff, isEmpty);
    });

    test('is carried on the model with value semantics', () {
      expect(piano().crossStaff, hasLength(3));
      expect(piano(), piano());
      expect(piano().hashCode, piano().hashCode);
    });

    test('differing cross-staff assignments break equality', () {
      final a = piano();
      final b = Score(
        clef: a.clef,
        timeSignature: a.timeSignature,
        measures: a.measures,
        crossStaff: const [CrossStaffNote('e1', staffShift: -1)],
      );
      expect(a, isNot(b));
    });

    test('survives transposition (ids are stable)', () {
      final up = piano().transposedBy(Interval.majorSecond);
      expect(up.crossStaff, piano().crossStaff);
    });
  });
}
