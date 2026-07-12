import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.3.1: ties.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<CurvePrimitive> curvesOf(ScoreLayout layout) =>
    layout.primitives.whereType<CurvePrimitive>().toList();

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('model + DSL', () {
    test('~ suffix sets tieToNext, with or without a duration', () {
      final score = Score.simple(notes: 'c4:q~ c4 d4:h~ d4:q');
      final notes = score.measures.single.elements.cast<NoteElement>();
      expect(notes[0].tieToNext, isTrue);
      expect(notes[1].tieToNext, isFalse);
      expect(notes[2].tieToNext, isTrue);
      expect(notes[2].duration, NoteDuration.half);
      expect(notes[3].tieToNext, isFalse);
    });

    test('a chord token can be tied', () {
      final score = Score.simple(notes: 'c4+e4:h~ c4+e4:h');
      expect(
        (score.measures.single.elements.first as NoteElement).tieToNext,
        isTrue,
      );
    });

    test('a tied rest is rejected', () {
      expect(() => Score.simple(notes: 'r:q~'), throwsFormatException);
    });

    test('tieToNext participates in value equality', () {
      expect(
        NoteElement.note(const Pitch(Step.c), NoteDuration.quarter,
            tieToNext: true),
        isNot(NoteElement.note(const Pitch(Step.c), NoteDuration.quarter)),
      );
      expect(
        NoteElement.note(const Pitch(Step.c), NoteDuration.quarter,
                tieToNext: true)
            .toString(),
        contains('tied'),
      );
    });
  });

  group('layout', () {
    test('a tie yields one curve between the two noteheads', () {
      final layout = layoutOf(Score.simple(notes: 'c5:q~ c5:q'));
      final curve = curvesOf(layout).single;
      final heads = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.noteheadBlack)
          .toList();
      expect(curve.start.x, greaterThan(heads[0].position.x));
      expect(curve.end.x, lessThan(heads[1].position.x + 1.5));
      expect(curve.end.x, greaterThan(curve.start.x));
    });

    test('curve side is opposite the stem', () {
      // A4 stems up -> tie below (curve y greater than notehead y = 2.5).
      final below = curvesOf(layoutOf(Score.simple(notes: 'a4:q~ a4'))).single;
      expect(below.start.y, greaterThan(2.5));
      expect(below.control1.y, greaterThan(below.start.y));
      // C5 stems down -> tie above (curve y less than notehead y = 1.5).
      final above = curvesOf(layoutOf(Score.simple(notes: 'c5:q~ c5'))).single;
      expect(above.start.y, lessThan(1.5));
      expect(above.control1.y, lessThan(above.start.y));
    });

    test('whole notes tie on the position-derived side', () {
      // C5 (position 5 >= 4): treated like stems-down -> tie above.
      final above = curvesOf(layoutOf(Score.simple(notes: 'c5:w~ | c5:w')));
      expect(above.single.start.y, lessThan(1.5));
    });

    test('ties cross barlines', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:w~ | c5:w',
      ));
      expect(curvesOf(layout), hasLength(1));
      // The curve spans the barline.
      final barlineX = layout.primitives
          .whereType<LinePrimitive>()
          .firstWhere((l) =>
              l.from.x == l.to.x &&
              l.from.y == 0 &&
              l.thickness == settings.thinBarlineThickness)
          .from
          .x;
      final curve = curvesOf(layout).single;
      expect(curve.start.x, lessThan(barlineX));
      expect(curve.end.x, greaterThan(barlineX));
    });

    test('chord ties: one curve per matching pitch', () {
      expect(
        curvesOf(layoutOf(Score.simple(notes: 'c4+e4:q~ c4+e4:q'))),
        hasLength(2),
      );
      // Partial match: only the shared C4 ties.
      expect(
        curvesOf(layoutOf(Score.simple(notes: 'c4+e4:q~ c4+g4:q'))),
        hasLength(1),
      );
      // Different octave/alteration is not the same pitch.
      expect(
        curvesOf(layoutOf(Score.simple(notes: 'c4:q~ c5:q'))),
        isEmpty,
      );
      expect(
        curvesOf(layoutOf(Score.simple(notes: 'f4:q~ f#4:q'))),
        isEmpty,
      );
    });

    test('ties into rests or the score end draw nothing', () {
      expect(curvesOf(layoutOf(Score.simple(notes: 'c5:q~ r:q'))), isEmpty);
      expect(curvesOf(layoutOf(Score.simple(notes: 'c5:q~'))), isEmpty);
    });

    test('tie ink stays inside the layout bounds', () {
      final layout = layoutOf(Score.simple(notes: 'a3:q~ a3 c6:q~ c6'));
      expect(curvesOf(layout), hasLength(2));
      for (final curve in curvesOf(layout)) {
        for (final p in [
          curve.start,
          curve.control1,
          curve.control2,
          curve.end
        ]) {
          expect(layout.bounds.containsPoint(p), isTrue, reason: '$curve');
        }
      }
    });

    test('deterministic with ties', () {
      String render() =>
          layoutOf(Score.simple(notes: 'c4+e4:q~ c4+e4 g4:h~ | g4:w'))
              .primitives
              .map((p) => p.toString())
              .join('\n');
      expect(render(), render());
      expect(render(), contains('Curve('));
    });
  });
}
