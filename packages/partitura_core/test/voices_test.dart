import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.4.1: two voices per staff.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<LinePrimitive> stemsOf(ScoreLayout layout) => layout.primitives
    .whereType<LinePrimitive>()
    .where((l) => l.from.x == l.to.x && l.thickness == settings.stemThickness)
    .toList();

GlyphPrimitive headOf(ScoreLayout layout, String id) => layout.primitives
    .whereType<GlyphPrimitive>()
    .firstWhere((g) => g.elementId == id && g.smuflName.startsWith('notehead'));

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('model + DSL', () {
    test('a ; splits the measure into two voices', () {
      final score = Score.simple(notes: 'c5:q d5 e5 f5 ; c4:h e4:h');
      final measure = score.measures.single;
      expect(measure.elements, hasLength(4));
      expect(measure.voice2, hasLength(2));
      expect(measure.voice2Duration, Fraction(1, 1));
      // Ids keep counting across voices.
      expect(measure.voice2.first.id, 'e4');
    });

    test('up to four voices, then it throws', () {
      final quartet = Score.simple(notes: 'c5:q ; a4:q ; e4:q ; c4:q');
      final measure = quartet.measures.single;
      expect(measure.voices, hasLength(4));
      expect(measure.voice3.single.id, 'e2');
      expect(measure.voice4.single.id, 'e3');
      // A fifth voice is over the notation maximum.
      expect(
        () => Score.simple(notes: 'c5:q ; a4:q ; e4:q ; c4:q ; g3:q'),
        throwsFormatException,
      );
    });

    test('directives and tuplets stay voice-1 only', () {
      expect(
        () => Score.simple(notes: 'c5:q ; !clef=bass c4:q'),
        throwsFormatException,
      );
      expect(
        () => Score.simple(notes: 'c5:q ; 3[c4:e d4 e4]'),
        throwsFormatException,
      );
      // The guard applies to voices 3 and 4 as well.
      expect(
        () => Score.simple(notes: 'c5:q ; c4:q ; !clef=bass g3:q'),
        throwsFormatException,
      );
    });

    test('voice2 participates in Measure equality', () {
      expect(
        Score.simple(notes: 'c5:q ; c4:q'),
        Score.simple(notes: 'c5:q ; c4:q'),
      );
      expect(
        Score.simple(notes: 'c5:q ; c4:q'),
        isNot(Score.simple(notes: 'c5:q')),
      );
    });
  });

  group('layout: stems and columns', () {
    test('voice 1 stems up, voice 2 stems down — even against the rule', () {
      // c5 alone would stem down; a4 alone would stem up.
      final layout = layoutOf(Score.simple(notes: 'c5:q ; a4:q'));
      final stems = stemsOf(layout);
      expect(stems, hasLength(2));
      final v1 = stems.reduce((a, b) => a.from.y < b.from.y ? a : b);
      final v2 = stems.firstWhere((s) => !identical(s, v1));
      expect(v1.to.y, lessThan(v1.from.y), reason: 'voice 1 up');
      expect(v2.to.y, greaterThan(v2.from.y), reason: 'voice 2 down');
    });

    test('elements sharing an onset align in one column', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:q d5 e5 f5 ; e4:q f4 g4 a4',
      ));
      for (var i = 0; i < 4; i++) {
        expect(
          headOf(layout, 'e$i').position.x,
          closeTo(headOf(layout, 'e${i + 4}').position.x, 0.01),
          reason: 'beat ${i + 1}',
        );
      }
    });

    test('a long voice-2 note spans several voice-1 columns', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:q d5 e5 f5 ; c4:h e4:h',
      ));
      // Voice-2 half notes align with beats 1 and 3.
      expect(headOf(layout, 'e4').position.x,
          closeTo(headOf(layout, 'e0').position.x, 0.01));
      expect(headOf(layout, 'e5').position.x,
          closeTo(headOf(layout, 'e2').position.x, 0.01));
      // And the voice-1 quarters advance strictly.
      final xs = [for (var i = 0; i < 4; i++) headOf(layout, 'e$i').position.x];
      for (var i = 1; i < 4; i++) {
        expect(xs[i], greaterThan(xs[i - 1]));
      }
    });

    test('offset voices place columns at the union of onsets', () {
      // Voice 2 enters on the off-beat eighth.
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.twoFour,
        notes: 'c5:q d5:q ; r:e e4:e f4:q',
      ));
      // e4 (onset 1/8) sits strictly between c5 (0) and d5 (1/4).
      final e4x = headOf(layout, 'e3').position.x;
      expect(e4x, greaterThan(headOf(layout, 'e0').position.x));
      expect(e4x, lessThan(headOf(layout, 'e1').position.x));
      // f4 (onset 1/4) aligns with d5.
      expect(headOf(layout, 'e4').position.x,
          closeTo(headOf(layout, 'e1').position.x, 0.01));
    });

    test('cross-voice unison/second shifts voice 2 to the right', () {
      final unison = layoutOf(Score.simple(notes: 'c4:q ; c4:q'));
      expect(headOf(unison, 'e1').position.x,
          greaterThan(headOf(unison, 'e0').position.x + 0.5));
      final second = layoutOf(Score.simple(notes: 'c4:q ; b3:q'));
      expect(headOf(second, 'e1').position.x,
          greaterThan(headOf(second, 'e0').position.x + 0.5));
      // A third does not shift.
      final third = layoutOf(Score.simple(notes: 'e4:q ; c4:q'));
      expect(headOf(third, 'e1').position.x,
          closeTo(headOf(third, 'e0').position.x, 0.01));
    });
  });

  group('layout: rests, beams, ties', () {
    test('rests displace vertically per voice', () {
      final layout = layoutOf(Score.simple(notes: 'r:q c5:q ; c4:q r:q'));
      final rests = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.restQuarter)
          .toList();
      expect(rests, hasLength(2));
      // Voice 1 rest sits higher (y=1), voice 2 lower (y=3).
      expect(rests[0].position.y, 1.0);
      expect(rests[1].position.y, 3.0);
    });

    test('beams stay per voice with forced directions', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.twoFour,
        notes: 'c5:e d5 e5 f5 ; c4:e d4 e4 f4',
      ));
      final beams = layout.primitives.whereType<BeamPrimitive>().toList();
      expect(beams, hasLength(2));
      // Voice-1 beam above its noteheads (stems up), voice-2 beam below.
      expect(beams[0].start.y, lessThan(0.5));
      expect(beams[1].start.y, greaterThan(4.0));
    });

    test('ties bind within a voice, not across voices', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:h~ c5:h ; c4:q c4 c4 c4',
      ));
      final curves = layout.primitives.whereType<CurvePrimitive>().toList();
      expect(curves, hasLength(1));
      // The tie spans from the first c5 to the second (beats 1 -> 3).
      expect(
          curves.single.start.x, greaterThan(headOf(layout, 'e0').position.x));
      expect(
          curves.single.end.x, lessThan(headOf(layout, 'e1').position.x + 1.5));
    });

    test('accidental state is shared across voices', () {
      // Voice 1 writes F#; voice 2's later F# in the same octave is
      // implied and needs no accidental.
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'f#4:h r:h ; r:h f#4:h',
      ));
      final tagged = layout.primitives.whereType<GlyphPrimitive>().where(
          (g) => g.smuflName.startsWith('accidental') && g.elementId != null);
      expect(tagged, hasLength(1));
    });
  });

  group('determinism and bounds', () {
    test('two-voice layouts are deterministic and inside bounds', () {
      String render() => layoutOf(Score.simple(
            timeSignature: TimeSignature.fourFour,
            notes: "c5:q( d5 e5) f5' ; c4:h~ c4:h | g4+b4:w ; g3:w",
          )).primitives.map((p) => p.toString()).join('\n');
      expect(render(), render());
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: "c5:q( d5 e5) f5' ; c4:h~ c4:h | g4+b4:w ; g3:w",
      ));
      for (final region in layout.regions) {
        expect(layout.bounds.containsRectangle(region.bounds), isTrue,
            reason: region.elementId);
      }
      expect(layout.regions, hasLength(8));
    });

    test('both voices\' accidentals in one column are laid out jointly', () {
      // f#5 (voice 1) and d#5 (voice 2) sound together, a third apart — too
      // close to share an accidental column. Their two sharps must take
      // separate zig-zag columns (no overlap) and the noteheads align at one x.
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'f#5:w ; d#5:w',
      ));
      final sharps = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == 'accidentalSharp')
          .toList();
      expect(sharps, hasLength(2));
      // The two sharps sit in different horizontal columns (no overlap).
      final width = metadata.bBoxOf('accidentalSharp').width;
      expect((sharps[0].position.x - sharps[1].position.x).abs(),
          greaterThan(width * 0.5));
      // The noteheads align on one x.
      expect(headOf(layout, 'e0').position.x,
          closeTo(headOf(layout, 'e1').position.x, 0.01));
    });
  });
}
