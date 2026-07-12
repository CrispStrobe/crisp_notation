import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.7.2: fingering digits stacked above the note.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('model + DSL', () {
    test('=N suffix parses a single fingering', () {
      final score = Score.simple(notes: 'c4:q=3 d4:q');
      final note = score.measures.single.elements.first as NoteElement;
      expect(note.fingerings, [3]);
      expect(
        (score.measures.single.elements[1] as NoteElement).fingerings,
        isEmpty,
      );
    });

    test('=a,b,c suffix parses a chord fingering list', () {
      final score = Score.simple(notes: 'c4+e4+g4:h=1,3,5');
      final chord = score.measures.single.elements.single as NoteElement;
      expect(chord.fingerings, [1, 3, 5]);
    });

    test('fingering coexists with articulations and a tie', () {
      final score = Score.simple(notes: 'c4:q>=2~ c4:q');
      final note = score.measures.single.elements.first as NoteElement;
      expect(note.fingerings, [2]);
      expect(note.articulations, contains(Articulation.accent));
      expect(note.tieToNext, isTrue);
    });

    test('a fingering on a rest throws', () {
      expect(
        () => Score.simple(notes: 'r:q=1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('fingerings participate in value equality', () {
      expect(Score.simple(notes: 'c4:q=1'), Score.simple(notes: 'c4:q=1'));
      expect(
        Score.simple(notes: 'c4:q=1'),
        isNot(Score.simple(notes: 'c4:q=2')),
      );
    });
  });

  group('layout', () {
    test('a fingering draws its digit glyph above the note', () {
      // A high note so "above the note" is also above the staff (y < 0).
      final layout = layoutOf(Score.simple(notes: 'g5:q=3'));
      final glyphs = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.fingeringDigit(3))
          .toList();
      expect(glyphs, hasLength(1));
      expect(glyphs.single.position.y, lessThan(0)); // above the top staff line
    });

    test('a chord fingering draws one digit per listed finger, stacked', () {
      final layout = layoutOf(Score.simple(notes: 'c4+e4+g4:h=1,3,5'));
      final fingers = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName.startsWith('fingering'))
          .toList();
      expect(fingers, hasLength(3));
      // Stacked upward: strictly decreasing y (more negative) in list order.
      final ys = fingers.map((g) => g.position.y).toList();
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], lessThan(ys[i - 1]));
      }
    });

    test('the fingering grows the layout bounding box upward', () {
      final plain = layoutOf(Score.simple(notes: 'g5:q'));
      final fingered = layoutOf(Score.simple(notes: 'g5:q=4'));
      expect(fingered.top, lessThan(plain.top));
    });

    test('layout with fingerings is deterministic', () {
      String render() => layoutOf(Score.simple(notes: 'c4:q=1 e4+g4:q=3,5'))
          .primitives
          .map((p) => p.toString())
          .join('\n');
      expect(render(), render());
    });
  });

  group('transpose preserves fingerings', () {
    test('transposedBy keeps the fingering list', () {
      final up =
          Score.simple(notes: 'c4+e4:q=1,3').transposedBy(Interval.majorSecond);
      expect(
        (up.measures.single.elements.single as NoteElement).fingerings,
        [1, 3],
      );
    });
  });
}
