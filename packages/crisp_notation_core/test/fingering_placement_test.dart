import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

void main() {
  final metadata = SmuflMetadata.fromJson(jsonDecode(
    File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync(),
  ) as Map<String, Object?>);

  List<GlyphPrimitive> fingers(ScoreLayout layout) => layout.primitives
      .whereType<GlyphPrimitive>()
      .where((glyph) => glyph.smuflName.startsWith('fingering'))
      .toList();

  for (final below in [false, true]) {
    for (final lineCount in [1, 5, 6]) {
      test('fingerings clear local notation: below=$below, lines=$lineCount',
          () {
        final settings = LayoutSettings(
          metadata: metadata,
          fingeringPlacement: below
              ? FingeringPlacement.belowStaff
              : FingeringPlacement.aboveStaff,
        );
        final layout = const LayoutEngine().layout(
          Score.simple(
              notes: 'c4:e=1 e4:e=2 g4:e=3 c5:e=1 e5:e=2 g5:e=3 c6:e=5'),
          settings,
          staffLineCount: lineCount,
        );
        final marks = fingers(layout);
        expect(marks, hasLength(7));
        expect(marks.map((mark) => mark.position.y).toSet().length,
            greaterThan(1));
        for (final mark in marks) {
          final box = metadata.bBoxOf(mark.smuflName);
          if (below) {
            expect(mark.position.y - box.neY, greaterThan(lineCount - 1 + 0.5));
            expect(layout.top + layout.height,
                greaterThan(mark.position.y - box.swY));
          } else {
            expect(mark.position.y - box.swY, lessThan(-0.5));
            expect(layout.top, lessThan(mark.position.y - box.neY));
          }
          for (final beam in layout.primitives.whereType<BeamPrimitive>()) {
            if (mark.position.x < beam.start.x ||
                mark.position.x > beam.end.x) {
              continue;
            }
            final t =
                (mark.position.x - beam.start.x) / (beam.end.x - beam.start.x);
            final y = beam.start.y + t * (beam.end.y - beam.start.y);
            expect(
                below ? mark.position.y - box.neY : mark.position.y - box.swY,
                below
                    ? greaterThan(y + beam.thickness / 2)
                    : lessThan(y - beam.thickness / 2));
          }
        }
      });
    }
  }

  test('fingerings over a sloped beam follow its slope', () {
    for (final below in [false, true]) {
      final layout = const LayoutEngine().layout(
        Score.simple(notes: below ? 'c5:e=3 a4:e=1' : 'e4:e=1 b4:e=5'),
        LayoutSettings(
          metadata: metadata,
          fingeringPlacement: below
              ? FingeringPlacement.belowStaff
              : FingeringPlacement.aboveStaff,
        ),
      );
      final [first, second] = fingers(layout);
      expect(second.position.y,
          below ? greaterThan(first.position.y) : lessThan(first.position.y));
    }
  });

  test('a distant ledger note does not displace other fingerings', () {
    double firstFingering(String notes) => fingers(const LayoutEngine().layout(
          Score.simple(notes: notes),
          LayoutSettings(
              metadata: metadata,
              fingeringPlacement: FingeringPlacement.aboveStaff),
        )).first.position.y;
    expect(
        firstFingering('c4:w=3 | c7:w=3'), firstFingering('c4:w=3 | c4:w=3'));
  });

  test('outsideStaff selects the side by clef and stacks outward', () {
    for (final clef in [Clef.treble, Clef.bass]) {
      final layout = const LayoutEngine().layout(
        Score.simple(
            clef: clef,
            notes: clef == Clef.bass ? 'c4+e4+g4:h=5,3,1' : 'c4+e4+g4:h=1,3,5'),
        LayoutSettings(
            metadata: metadata,
            fingeringPlacement: FingeringPlacement.outsideStaff),
      );
      final marks = fingers(layout);
      expect(marks, hasLength(3));
      for (var i = 1; i < marks.length; i++) {
        final previous = marks[i - 1];
        final current = marks[i];
        final previousBox = metadata.bBoxOf(previous.smuflName);
        final currentBox = metadata.bBoxOf(current.smuflName);
        if (clef == Clef.bass) {
          expect(current.position.y - currentBox.neY,
              greaterThan(previous.position.y - previousBox.swY));
        } else {
          expect(current.position.y - currentBox.swY,
              lessThan(previous.position.y - previousBox.neY));
        }
      }
    }
  });

  test('display-time marks use the same placement without changing the score',
      () {
    final score = Score.simple(notes: 'c4:q d4:q');
    final layout = const LayoutEngine().layout(
        score,
        LayoutSettings(
            metadata: metadata,
            fingeringPlacement: FingeringPlacement.belowStaff),
        extraFingerings: const {
          'e0': [2],
          'e1': [3]
        });
    expect(fingers(layout), hasLength(2));
    expect(fingers(layout).every((mark) => mark.position.y > 4), isTrue);
    expect((score.measures.first.elements.first as NoteElement).fingerings,
        isEmpty);
  });
}
