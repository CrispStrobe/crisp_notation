import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.3.3: tuplets.
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
    test('3[...] produces a span with default normal 2', () {
      final score = Score.simple(notes: '3[c4:e d4 e4] f4:q');
      final measure = score.measures.single;
      expect(measure.tuplets, [const TupletSpan(0, 2, actual: 3, normal: 2)]);
    });

    test('explicit and default ratios', () {
      expect(
        Score.simple(notes: '5:4[c4:s d4 e4 f4 g4]')
            .measures
            .single
            .tuplets
            .single,
        const TupletSpan(0, 4, actual: 5, normal: 4),
      );
      // Default for 5 is 4; for 6 is 4; for 2 (duplet) it is 3.
      expect(
        Score.simple(notes: '5[c4:s d4 e4 f4 g4]')
            .measures
            .single
            .tuplets
            .single
            .normal,
        4,
      );
      expect(
        Score.simple(notes: '6[c4:s d4 e4 f4 g4 a4]')
            .measures
            .single
            .tuplets
            .single
            .normal,
        4,
      );
      expect(
        Score.simple(notes: '2[c4:e d4]').measures.single.tuplets.single.normal,
        3,
      );
    });

    test('rests may sit inside a tuplet', () {
      final score = Score.simple(notes: '3[c4:e r e4]');
      expect(score.measures.single.tuplets.single.endIndex, 2);
      expect(
        score.measures.single.elements[1],
        isA<RestElement>(),
      );
    });

    test('effective durations: a triplet of eighths fills one quarter', () {
      final measure = Score.simple(notes: '3[c4:e d4 e4]').measures.single;
      expect(measure.effectiveDurationAt(0), Fraction(1, 12));
      expect(measure.totalDuration, Fraction(1, 4));
      // A full 4/4 measure: triplet + dotted half.
      final full = Score.simple(notes: '3[c4:e d4 e4] g4:h.').measures.single;
      expect(full.totalDuration, Fraction(1, 1));
    });

    test('malformed tuplets are rejected', () {
      expect(() => Score.simple(notes: '3[c4:e d4'), throwsFormatException);
      expect(() => Score.simple(notes: 'c4:e] d4'), throwsFormatException);
      expect(
        () => Score.simple(notes: '3[c4:e 3[d4:e e4] f4]'),
        throwsFormatException,
      );
      expect(() => Score.simple(notes: '1[c4:e d4]'), throwsFormatException);
      expect(
        () => Score.simple(notes: '3[c4:e d4 | e4]'),
        throwsFormatException,
      );
    });

    test('value semantics of TupletSpan and Measure', () {
      expect(
        const TupletSpan(0, 2, actual: 3, normal: 2),
        const TupletSpan(0, 2, actual: 3, normal: 2),
      );
      expect(
        const TupletSpan(0, 2, actual: 3, normal: 2),
        isNot(const TupletSpan(0, 2, actual: 5, normal: 4)),
      );
      expect(
        Score.simple(notes: '3[c4:e d4 e4]'),
        Score.simple(notes: '3[c4:e d4 e4]'),
      );
      expect(
        Score.simple(notes: '3[c4:e d4 e4]'),
        isNot(Score.simple(notes: 'c4:e d4 e4')),
      );
    });
  });

  group('layout', () {
    List<GlyphPrimitive> digitGlyphs(ScoreLayout layout) => layout.primitives
        .whereType<GlyphPrimitive>()
        .where((g) => g.smuflName.startsWith('tuplet'))
        .toList();

    test('a triplet beams as one group and shows the digit 3', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '3[c5:e d5 e5] g4:q g4:h',
      ));
      expect(layout.primitives.whereType<BeamPrimitive>(), hasLength(1));
      final digit = digitGlyphs(layout).single;
      expect(digit.smuflName, 'tuplet3');
    });

    test('bracket sits on the stem side', () {
      // Stems down (high notes) -> bracket below the group.
      final below = layoutOf(Score.simple(notes: '3[c5:e d5 e5]'));
      final belowDigit = digitGlyphs(below).single;
      expect(belowDigit.position.y, greaterThan(4));
      // Stems up (low notes) -> bracket above.
      final above = layoutOf(Score.simple(notes: '3[c4:e d4 e4]'));
      final aboveDigit = digitGlyphs(above).single;
      expect(aboveDigit.position.y, lessThan(0.5));
    });

    test('the bracket spans the group with hooks', () {
      final layout = layoutOf(Score.simple(notes: '3[c4:q d4 e4]'));
      final thickness =
          metadata.engravingDefault('tupletBracketThickness', orElse: 0.16);
      final bracketLines = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) =>
              l.thickness == thickness &&
              l.elementId == null &&
              // Exclude barlines (full-staff verticals) and staff lines.
              !(l.from.y == 0 && l.to.y == 4) &&
              !(l.from.y == l.to.y && l.from.x == 0))
          .toList();
      // Two horizontal segments (digit gap) + two vertical hooks.
      expect(bracketLines, hasLength(4));
      final horizontal = bracketLines.where((l) => l.from.y == l.to.y).toList();
      final hooks = bracketLines.where((l) => l.from.x == l.to.x).toList();
      expect(horizontal, hasLength(2));
      expect(hooks, hasLength(2));
      expect(horizontal[0].to.x, lessThan(horizontal[1].from.x),
          reason: 'gap for the digit');
    });

    test('quintuplet renders tuplet5 and fills one quarter of spacing', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '5[c5:s d5 e5 f5 g5] c5:q c5:h',
      ));
      expect(digitGlyphs(layout).single.smuflName, 'tuplet5');
      // All five sixteenths sit in beat 1: one beam group.
      final beams = layout.primitives.whereType<BeamPrimitive>().toList();
      expect(beams, hasLength(2)); // primary + secondary
    });

    test('beams never join tuplet and non-tuplet eighths (regression)', () {
      // Without the tuplet-boundary rule, the half-measure merge welded
      // the c5-e5 triplet to the following low c4 eighth, flipping the
      // whole group's stems.
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '3[c5:e d5 e5] c4:e c4:e c4:h',
      ));
      final beams = layout.primitives.whereType<BeamPrimitive>().toList();
      // Triplet beam + the c4-c4 pair beam.
      expect(beams, hasLength(2));
      // The triplet (all above the middle line) stems down: beam below.
      expect(beams.first.start.y, greaterThan(4.0));
      final stems = layout.primitives.whereType<LinePrimitive>().where(
          (l) => l.from.x == l.to.x && l.thickness == settings.stemThickness);
      expect(stems, hasLength(6));
    });

    test('tuplet members are spaced tighter than plain members', () {
      double gap(String notes) {
        final layout = layoutOf(Score.simple(notes: notes));
        final heads = layout.primitives
            .whereType<GlyphPrimitive>()
            .where((g) => g.smuflName == SmuflGlyph.noteheadBlack)
            .toList();
        return heads[1].position.x - heads[0].position.x;
      }

      expect(gap('3[c4:q d4 e4]'), lessThan(gap('c4:q d4 e4')));
    });

    test('overlapping or out-of-range spans fail loudly', () {
      Score withSpans(List<TupletSpan> spans) => Score(
            clef: Clef.treble,
            measures: [
              Measure(
                [
                  for (var i = 0; i < 3; i++)
                    NoteElement.note(const Pitch(Step.c), NoteDuration.eighth,
                        id: 'n$i'),
                ],
                tuplets: spans,
              ),
            ],
          );
      expect(
        () => layoutOf(withSpans([
          const TupletSpan(0, 1, actual: 3, normal: 2),
          const TupletSpan(1, 2, actual: 3, normal: 2),
        ])),
        throwsArgumentError,
      );
      expect(
        () =>
            layoutOf(withSpans([const TupletSpan(0, 5, actual: 3, normal: 2)])),
        throwsArgumentError,
      );
    });

    test('deterministic with tuplets', () {
      String render() => layoutOf(Score.simple(
            timeSignature: TimeSignature.twoFour,
            notes: '3[c5:e d5 e5] 5[c4:s d4 e4 f4 g4]',
          )).primitives.map((p) => p.toString()).join('\n');
      expect(render(), render());
      expect(render(), contains('tuplet3'));
      expect(render(), contains('tuplet5'));
    });

    test('a tuplet on voice 2 scales that voice, not voice 1', () {
      // A triplet of eighths in voice 2 (three eighths in the time of two).
      final m = Measure(
        [
          for (final s in ['c', 'd'])
            NoteElement(
                pitches: [Pitch(Step.values.byName(s), octave: 5)],
                duration: NoteDuration.half,
                id: 'a$s'),
        ],
        voice2: [
          for (final s in ['e', 'f', 'g'])
            NoteElement(
                pitches: [Pitch(Step.values.byName(s), octave: 4)],
                duration: NoteDuration.quarter,
                id: 'b$s'),
        ],
        tuplets: const [TupletSpan(0, 2, actual: 3, normal: 2, voice: 1)],
      );
      // Voice 1 unaffected (a half note is still 1/2).
      expect(m.effectiveDurationAt(0, voice: 0), Fraction(1, 2));
      // Voice 2's three quarters scale to 1/3 whole each → the bar sums to 1.
      expect(m.effectiveDurationAt(0, voice: 1), Fraction(1, 6));
      expect(m.tupletsForVoice(1), hasLength(1));
      expect(m.tupletsForVoice(0), isEmpty);
    });

    test('an inner-voice tuplet draws its bracket digit', () {
      int digits(Score s) => layoutOf(s)
          .primitives
          .where((p) => p.toString().contains('tuplet'))
          .length;
      Score withVoice2Tuplet({required bool tuplet}) => Score(
            clef: Clef.treble,
            timeSignature: TimeSignature.fourFour,
            measures: [
              Measure(
                [
                  NoteElement(
                      pitches: [const Pitch(Step.c, octave: 5)],
                      duration: NoteDuration.half,
                      id: 'a'),
                  NoteElement(
                      pitches: [const Pitch(Step.d, octave: 5)],
                      duration: NoteDuration.half,
                      id: 'b'),
                ],
                voice2: [
                  for (final s in ['e', 'f', 'g'])
                    NoteElement(
                        pitches: [Pitch(Step.values.byName(s), octave: 4)],
                        duration: NoteDuration.quarter,
                        id: 'v$s'),
                ],
                tuplets: tuplet
                    ? const [TupletSpan(0, 2, actual: 3, normal: 2, voice: 1)]
                    : const [],
              ),
            ],
          );
      // The tuplet adds a "3" bracket digit that the plain measure lacks.
      expect(digits(withVoice2Tuplet(tuplet: true)),
          greaterThan(digits(withVoice2Tuplet(tuplet: false))));
    });
  });
}
