import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.3.4: articulations.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<GlyphPrimitive> articGlyphs(ScoreLayout layout) => layout.primitives
    .whereType<GlyphPrimitive>()
    .where((g) =>
        g.smuflName.startsWith('artic') || g.smuflName.startsWith('fermata'))
    .toList();

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('model + DSL', () {
    test('markers parse and combine', () {
      final score = Score.simple(notes: "c4:q' d4_ e4> f4^ | g4@ a4>'");
      final notes = [
        for (final m in score.measures) ...m.elements.cast<NoteElement>(),
      ];
      expect(notes[0].articulations, {Articulation.staccato});
      expect(notes[1].articulations, {Articulation.tenuto});
      expect(notes[2].articulations, {Articulation.accent});
      expect(notes[3].articulations, {Articulation.marcato});
      expect(notes[4].articulations, {Articulation.fermata});
      expect(
        notes[5].articulations,
        {Articulation.accent, Articulation.staccato},
      );
    });

    test('a staccato marker after a dotted duration still parses', () {
      final score = Score.simple(notes: "c4:q.'");
      final note = score.measures.single.elements.single as NoteElement;
      expect(note.duration, const NoteDuration(DurationBase.quarter, dots: 1));
      expect(note.articulations, {Articulation.staccato});
    });

    test('markers work together with ties and slurs', () {
      final score = Score.simple(notes: "c4:q>( d4 e4)'~ e4");
      final notes = score.measures.single.elements.cast<NoteElement>();
      expect(notes[0].articulations, {Articulation.accent});
      expect(score.slurs, [const Slur('e0', 'e2')]);
      expect(notes[2].articulations, {Articulation.staccato});
      expect(notes[2].tieToNext, isTrue);
    });

    test('rests cannot carry articulations', () {
      expect(() => Score.simple(notes: "r:q'"), throwsFormatException);
      expect(() => Score.simple(notes: 'r:q@'), throwsFormatException);
    });

    test('articulations participate in value equality (set semantics)', () {
      final a = NoteElement.note(const Pitch(Step.c), NoteDuration.quarter,
          articulations: const {Articulation.staccato, Articulation.accent});
      final b = NoteElement.note(const Pitch(Step.c), NoteDuration.quarter,
          articulations: const {Articulation.accent, Articulation.staccato});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(NoteElement.note(const Pitch(Step.c), NoteDuration.quarter)),
      );
      expect(a.toString(), contains('staccato'));
    });
  });

  group('layout', () {
    test('marks go on the notehead side, opposite the stem', () {
      // A4 stems up -> Below variant under the notehead (y > 2.5).
      final up = articGlyphs(layoutOf(Score.simple(notes: "a4:q'"))).single;
      expect(up.smuflName, 'articStaccatoBelow');
      expect(up.position.y, greaterThan(2.5));
      // C5 stems down -> Above variant over the notehead (y < 1.5).
      final down = articGlyphs(layoutOf(Score.simple(notes: "c5:q'"))).single;
      expect(down.smuflName, 'articStaccatoAbove');
      expect(down.position.y, lessThan(1.5));
    });

    test('multiple marks stack outward in enum order', () {
      final layout = layoutOf(Score.simple(notes: "c5:q>'_"));
      final glyphs = articGlyphs(layout);
      expect(glyphs.map((g) => g.smuflName).toList(), [
        'articStaccatoAbove',
        'articTenutoAbove',
        'articAccentAbove',
      ]);
      // Above side: each further mark sits higher (smaller y).
      expect(glyphs[1].position.y, lessThan(glyphs[0].position.y));
      expect(glyphs[2].position.y, lessThan(glyphs[1].position.y));
    });

    test('fermata always sits above, outside the staff', () {
      // Even for a stem-up note whose other marks go below.
      final layout = layoutOf(Score.simple(notes: "a4:q'@"));
      final glyphs = articGlyphs(layout);
      final staccato =
          glyphs.firstWhere((g) => g.smuflName == 'articStaccatoBelow');
      final fermata = glyphs.firstWhere((g) => g.smuflName == 'fermataAbove');
      expect(staccato.position.y, greaterThan(2.5));
      expect(fermata.position.y, lessThan(-0.5));
    });

    test('chord marks anchor on the outer notehead of the free side', () {
      final layout = layoutOf(Score.simple(notes: "c4+g4:q'"));
      // Stems up (both below middle) -> staccato under the bottom note C4.
      final mark = articGlyphs(layout).single;
      expect(mark.position.y, greaterThan(5.0));
    });

    test('beamed notes still get notehead-side marks', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: "c5:e' d5' e5' f5' g4:h",
      ));
      final marks = articGlyphs(layout);
      expect(marks, hasLength(4));
      for (final mark in marks) {
        expect(mark.smuflName, 'articStaccatoAbove');
        expect(mark.position.y, lessThan(2.0));
      }
    });

    test('articulation ink grows the element hit region', () {
      final plain = layoutOf(Score.simple(notes: 'c5:q'));
      final marked = layoutOf(Score.simple(notes: 'c5:q@'));
      final plainTop = plain.regions.single.bounds.top;
      final markedTop = marked.regions.single.bounds.top;
      expect(markedTop, lessThan(plainTop));
    });

    test('deterministic with articulations', () {
      String render() => layoutOf(Score.simple(notes: "c4:q>' d4_@ | c5+e5:h^"))
          .primitives
          .map((p) => p.toString())
          .join('\n');
      expect(render(), render());
      expect(render(), contains('articAccent'));
      expect(render(), contains('fermataAbove'));
    });
  });

  group('bowing', () {
    Score bowed(Pitch pitch, Articulation bow) => Score(
          clef: Clef.treble,
          measures: [
            Measure([
              NoteElement.note(pitch, NoteDuration.quarter,
                  articulations: {bow}, id: 'e0'),
            ]),
          ],
        );

    List<GlyphPrimitive> bowGlyphs(ScoreLayout layout) => layout.primitives
        .whereType<GlyphPrimitive>()
        .where((g) => g.smuflName.startsWith('strings'))
        .toList();

    test('up-bow / down-bow use the right glyphs', () {
      expect(
          bowGlyphs(layoutOf(
                  bowed(const Pitch(Step.c, octave: 5), Articulation.upBow)))
              .single
              .smuflName,
          'stringsUpBow');
      expect(
          bowGlyphs(layoutOf(
                  bowed(const Pitch(Step.c, octave: 5), Articulation.downBow)))
              .single
              .smuflName,
          'stringsDownBow');
    });

    test('bowing always sits above the staff, even for a stem-up note', () {
      // A4 stems up; a staccato would go below, but the bow stays above.
      final glyph = bowGlyphs(layoutOf(
              bowed(const Pitch(Step.a, octave: 4), Articulation.downBow)))
          .single;
      expect(glyph.position.y, lessThan(-0.5));
    });
  });
}
