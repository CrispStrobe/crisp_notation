import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// v0.7.2: fingering digits stacked above the note.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
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

  group('SMuFL codepoints', () {
    // Regression: the table mapped 6-9 to ED16-ED19, which are the LETTER
    // glyphs (fingeringTUpper / PLower / TLower / ILower). SMuFL puts 0-5 at
    // ED10-ED15 and appends 6-9 at ED24-ED27, so digits 6-9 used to render as
    // T / p / t / i — invisible for piano and guitar, which only use 1-5.
    test('digits 0-9 map to the digit glyphs', () {
      const want = <int, int>{
        0: 0xED10,
        1: 0xED11,
        5: 0xED15,
        6: 0xED24,
        7: 0xED25,
        8: 0xED26,
        9: 0xED27,
      };
      for (final entry in want.entries) {
        expect(
          smuflCodepoints['fingering${entry.key}'],
          String.fromCharCode(entry.value),
          reason: 'fingering${entry.key}',
        );
      }
    });

    test('the left-hand thumb has its own glyph at ED16', () {
      expect(
        smuflCodepoints[SmuflGlyph.fingeringThumb],
        String.fromCharCode(0xED16),
      );
    });

    test('fingeringMark maps digits and the thumb, and skips nonsense', () {
      expect(SmuflGlyph.fingeringMark(3), 'fingering3');
      expect(
        SmuflGlyph.fingeringMark(kFingeringThumb),
        SmuflGlyph.fingeringThumb,
      );
      expect(SmuflGlyph.fingeringMark(-7), isNull);
      expect(SmuflGlyph.fingeringMark(12), isNull);
    });
  });

  group('thumb fingering', () {
    Score thumbScore() => Score(
          clef: Clef.bass,
          timeSignature: const TimeSignature(2, 4),
          measures: [
            Measure([
              NoteElement.note(
                const Pitch(Step.a, octave: 4),
                NoteDuration.quarter,
                fingerings: const [kFingeringThumb],
                id: 'n1',
              ),
              NoteElement.note(
                const Pitch(Step.b, octave: 4),
                NoteDuration.quarter,
                id: 'n2',
              ),
            ]),
          ],
        );

    test('draws the T glyph rather than being dropped as a non-digit', () {
      final glyphs = layoutOf(thumbScore())
          .primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.fingeringThumb)
          .toList();
      expect(glyphs, hasLength(1));
    });

    test('round-trips through MusicXML as the T that editions print', () {
      final xml = scoreToMusicXml(thumbScore());
      expect(xml, contains('<fingering>T</fingering>'));
      final back = scoreFromMusicXml(xml);
      final note = back.measures.first.elements.whereType<NoteElement>().first;
      expect(note.fingerings, [kFingeringThumb]);
    });

    test('a lower-case t reads as the thumb too', () {
      final xml = scoreToMusicXml(
        thumbScore(),
      ).replaceAll('<fingering>T</fingering>', '<fingering>t</fingering>');
      final note = scoreFromMusicXml(
        xml,
      ).measures.first.elements.whereType<NoteElement>().first;
      expect(note.fingerings, [kFingeringThumb]);
    });
  });

  group('extraFingerings (display-time channel)', () {
    Score bare() => Score(
          clef: Clef.bass,
          timeSignature: const TimeSignature(2, 4),
          measures: [
            Measure([
              NoteElement.note(
                const Pitch(Step.c, octave: 3),
                NoteDuration.quarter,
                id: 'n1',
              ),
              NoteElement.note(
                const Pitch(Step.d, octave: 3),
                NoteDuration.quarter,
                id: 'n2',
              ),
            ]),
          ],
        );

    List<String> fingeringGlyphs(ScoreLayout layout) => layout.primitives
        .whereType<GlyphPrimitive>()
        .where((g) => g.smuflName.startsWith('fingering'))
        .map((g) => g.smuflName)
        .toList();

    test('draws marks a score does not carry, without rebuilding it', () {
      final layout = const LayoutEngine().layout(
        bare(),
        settings,
        extraFingerings: const {
          'n1': [1],
          'n2': [kFingeringThumb],
        },
      );
      expect(
        fingeringGlyphs(layout),
        containsAll(['fingering1', SmuflGlyph.fingeringThumb]),
      );
    });

    test('stacks after the note own fingerings', () {
      final score = Score(
        clef: Clef.bass,
        timeSignature: const TimeSignature(2, 4),
        measures: [
          Measure([
            NoteElement.note(
              const Pitch(Step.c, octave: 3),
              NoteDuration.quarter,
              fingerings: const [2],
              id: 'n1',
            ),
          ]),
        ],
      );
      final layout = const LayoutEngine().layout(
        score,
        settings,
        extraFingerings: const {
          'n1': [3],
        },
      );
      expect(fingeringGlyphs(layout), ['fingering2', 'fingering3']);
    });

    test('an unknown id draws nothing', () {
      final layout = const LayoutEngine().layout(
        bare(),
        settings,
        extraFingerings: const {
          'nope': [1],
        },
      );
      expect(fingeringGlyphs(layout), isEmpty);
    });

    test('is display-only: the score and its MusicXML are unchanged', () {
      final score = bare();
      const LayoutEngine().layout(
        score,
        settings,
        extraFingerings: const {
          'n1': [1],
        },
      );
      expect(
        score.measures.first.elements.whereType<NoteElement>().first.fingerings,
        isEmpty,
      );
      expect(scoreToMusicXml(score), isNot(contains('<fingering>')));
    });
  });

  group('paged layout', () {
    test('extraFingerings reach a printed page, not just a screen', () {
      // The PDF path is layoutPages → layoutSystems → engine.layout; a mark that
      // is dropped anywhere along it silently prints an unfingered part.
      final score = Score.simple(
        clef: Clef.bass,
        notes: 'c3:q d3 e3 f3 | g3:q a3 b3 c4 | c3:q d3 e3 f3 | g3:q a3 b3 c4',
      );
      final ids = <String>[
        for (final measure in score.measures)
          for (final element in measure.elements)
            if (element is NoteElement && element.id != null) element.id!,
      ];
      expect(ids, isNotEmpty);

      const metrics = PageMetrics(width: 40, height: 30);
      int fingeringGlyphs(PagedLayout paged) => paged.pages
          .expand((page) => page.systems)
          .expand((positioned) => positioned.system.layout.primitives)
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName.startsWith('fingering'))
          .length;

      final bare = layoutPages(score, settings, metrics: metrics);
      final fingered = layoutPages(
        score,
        settings,
        metrics: metrics,
        extraFingerings: {
          for (final id in ids) id: const [3]
        },
      );
      expect(fingeringGlyphs(bare), 0);
      expect(fingeringGlyphs(fingered), ids.length);
    });
  });
}
