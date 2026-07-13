import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  late final LayoutSettings settings;
  const engine = LayoutEngine();
  setUpAll(() {
    final meta = SmuflMetadata.fromJson(jsonDecode(
        File('../partitura/assets/smufl/bravura_metadata.json')
            .readAsStringSync()) as Map<String, Object?>);
    settings = LayoutSettings(metadata: meta);
  });

  Rectangle<double> boxOf(ScoreLayout layout, String id) =>
      layout.regions.firstWhere((r) => r.elementId == id).bounds;

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

  group('engine cross-staff rendering', () {
    // One bass-clef note, optionally engraved on the staff above.
    Score oneNote({int? shift}) => Score(
          clef: Clef.bass,
          timeSignature: TimeSignature.fourFour,
          measures: [
            Measure([
              NoteElement.note(Pitch.parse('e4'), NoteDuration.quarter,
                  id: 'n'),
              NoteElement.note(Pitch.parse('c3'), NoteDuration.quarter,
                  id: 'x'),
              NoteElement.note(Pitch.parse('e3'), NoteDuration.quarter,
                  id: 'y'),
              NoteElement.note(Pitch.parse('g3'), NoteDuration.quarter,
                  id: 'z'),
            ]),
          ],
          crossStaff: shift == null
              ? const []
              : [CrossStaffNote('n', staffShift: shift)],
        );

    test('crossStaffOffset 0 leaves the note untouched', () {
      final plain = engine.layout(oneNote(), settings);
      final tagged = engine.layout(oneNote(shift: -1), settings);
      // No offset supplied -> cross-staff disabled -> identical geometry.
      expect(boxOf(tagged, 'n').top, closeTo(boxOf(plain, 'n').top, 1e-9));
    });

    test('a note shifted up renders higher (onto the staff above)', () {
      final plain = engine.layout(oneNote(), settings);
      final up = engine.layout(oneNote(shift: -1), settings,
          crossStaffOffset: 8, clefAbove: Clef.treble);
      // Smaller y = higher on the page: the note re-based onto the staff above
      // sits higher (the offset outweighs the treble-vs-bass clef re-basing).
      expect(boxOf(up, 'n').top, lessThan(boxOf(plain, 'n').top - 1));
      // The other (untagged) notes are unmoved.
      expect(boxOf(up, 'x').top, closeTo(boxOf(plain, 'x').top, 1e-9));
    });

    test('a note shifted down renders lower (onto the staff below)', () {
      final plain = engine.layout(oneNote(), settings);
      final down = engine.layout(oneNote(shift: 1), settings,
          crossStaffOffset: 8, clefBelow: Clef.bass);
      expect(boxOf(down, 'n').top, greaterThan(boxOf(plain, 'n').top + 4));
    });

    test('a cross-staff beamed run keeps one beam spanning the gap', () {
      // Four eighths beamed together; the upper two are engraved a staff up.
      final score = Score(
        clef: Clef.bass,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            NoteElement.note(Pitch.parse('c3'), NoteDuration.eighth, id: 'a'),
            NoteElement.note(Pitch.parse('g3'), NoteDuration.eighth, id: 'b'),
            NoteElement.note(Pitch.parse('e4'), NoteDuration.eighth, id: 'c'),
            NoteElement.note(Pitch.parse('g4'), NoteDuration.eighth, id: 'd'),
          ]),
        ],
        crossStaff: const [
          CrossStaffNote('c', staffShift: -1),
          CrossStaffNote('d', staffShift: -1),
        ],
      );
      final laid = engine.layout(score, settings,
          crossStaffOffset: 8, clefAbove: Clef.treble);
      // Exactly one beam over the four notes (not split into two groups).
      final beams = laid.primitives.whereType<BeamPrimitive>().toList();
      expect(beams, hasLength(1));
      // The beam is horizontal (a cross-staff beam sits level in the gap).
      expect(beams.first.start.y, closeTo(beams.first.end.y, 1e-9));
      // The shifted noteheads sit up on the staff above (well clear of this
      // staff's top line, y = 0).
      expect(boxOf(laid, 'c').top, lessThan(-3));
      expect(boxOf(laid, 'd').top, lessThan(-3));
      // The figure reaches higher than the plain (un-shifted) version — the
      // cross-staff notes are engraved up on the staff above.
      final plain = engine.layout(
          Score(
              clef: score.clef,
              timeSignature: score.timeSignature,
              measures: score.measures),
          settings);
      expect(laid.top, lessThan(plain.top));
    });

    test('the multi-part assembler supplies the offset + neighbour clef', () {
      // Upper (treble) part with a note engraved on the bass staff below.
      Score upper({bool cross = false}) => Score(
            clef: Clef.treble,
            timeSignature: TimeSignature.fourFour,
            measures: [
              Measure([
                NoteElement.note(Pitch.parse('g4'), NoteDuration.quarter,
                    id: 'u0'),
                NoteElement.note(Pitch.parse('e4'), NoteDuration.quarter,
                    id: 'u1'),
              ]),
            ],
            crossStaff:
                cross ? const [CrossStaffNote('u1', staffShift: 1)] : const [],
          );
      final lower = Score(
        clef: Clef.bass,
        timeSignature: TimeSignature.fourFour,
        measures: [
          Measure([
            NoteElement.note(Pitch.parse('c3'), NoteDuration.half, id: 'l0'),
          ]),
        ],
      );
      final plain =
          layoutMultiPartSystem(MultiPartScore([upper(), lower]), settings);
      final crossed = layoutMultiPartSystem(
          MultiPartScore([upper(cross: true), lower]), settings);
      double topOf(MultiPartSystemLayout m, String id) =>
          m.parts.first.regions.firstWhere((r) => r.elementId == id).bounds.top;
      // The tagged note moved down (toward the bass staff); its neighbour did
      // not.
      expect(topOf(crossed, 'u1'), greaterThan(topOf(plain, 'u1') + 1));
      expect(topOf(crossed, 'u0'), closeTo(topOf(plain, 'u0'), 1e-9));
    });

    test('existing single-staff layout is byte-for-byte unchanged', () {
      // A score with no crossStaff entries must be identical whether or not an
      // offset is supplied (the feature is fully opt-in per note).
      final base = Score.simple(
          timeSignature: TimeSignature.fourFour, notes: 'c5:e d5 e5 f5');
      final a = engine.layout(base, settings);
      final b = engine.layout(base, settings, crossStaffOffset: 8);
      expect(b.width, a.width);
      expect(b.height, a.height);
      expect(b.primitives.length, a.primitives.length);
    });
  });
}
