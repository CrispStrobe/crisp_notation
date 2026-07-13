import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

Score microtonalScore(MicrotonalAccidental acc) => Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement(
            pitches: [Pitch(Step.a, microtone: acc)],
            duration: const NoteDuration(DurationBase.quarter),
            id: 'e0',
          ),
        ]),
      ],
    );

void main() {
  group('Pitch microtones (model)', () {
    test('a microtonal accidental carries a cents offset', () {
      const halfSharp =
          Pitch(Step.a, microtone: MicrotonalAccidental.halfSharp);
      expect(halfSharp.centsOffset, 50);
      expect(halfSharp.microtone, MicrotonalAccidental.halfSharp);
      // The (integer) MIDI number is the nearest semitone — unchanged.
      expect(halfSharp.midiNumber, const Pitch(Step.a).midiNumber);
    });

    test('a plain pitch has no microtone and a zero cents offset', () {
      expect(const Pitch(Step.c).centsOffset, 0);
      expect(const Pitch(Step.c).microtone, isNull);
    });

    test('equality and hashCode distinguish microtones', () {
      const a = Pitch(Step.a, microtone: MicrotonalAccidental.halfSharp);
      const b = Pitch(Step.a, microtone: MicrotonalAccidental.halfSharp);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const Pitch(Step.a)));
      expect(a,
          isNot(const Pitch(Step.a, microtone: MicrotonalAccidental.halfFlat)));
    });

    test('each accidental names its cents and default glyph', () {
      expect(MicrotonalAccidental.halfFlat.cents, -50);
      expect(MicrotonalAccidental.halfSharp.cents, 50);
      expect(MicrotonalAccidental.sesquiFlat.cents, -150);
      expect(MicrotonalAccidental.sesquiSharp.cents, 150);
      expect(MicrotonalAccidental.halfSharp.defaultGlyph,
          SmuflGlyph.accidentalQuarterToneSharpStein);
    });
  });

  group('microtonal accidentals (layout)', () {
    late final SmuflMetadata metadata;
    late final LayoutSettings settings;

    setUpAll(() {
      final source = File('../partitura/assets/smufl/bravura_metadata.json')
          .readAsStringSync();
      metadata =
          SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
      settings = LayoutSettings(metadata: metadata);
    });

    List<String> accidentalsOf(ScoreLayout layout) => layout.primitives
        .whereType<GlyphPrimitive>()
        .map((g) => g.smuflName)
        .where((n) => n.startsWith('accidental'))
        .toList();

    test('each microtonal note draws its Stein-Zimmermann glyph', () {
      const expected = {
        MicrotonalAccidental.halfSharp:
            SmuflGlyph.accidentalQuarterToneSharpStein,
        MicrotonalAccidental.halfFlat:
            SmuflGlyph.accidentalQuarterToneFlatStein,
        MicrotonalAccidental.sesquiSharp:
            SmuflGlyph.accidentalThreeQuarterTonesSharpStein,
        MicrotonalAccidental.sesquiFlat:
            SmuflGlyph.accidentalThreeQuarterTonesFlatZimmermann,
      };
      expected.forEach((acc, glyph) {
        final layout =
            const LayoutEngine().layout(microtonalScore(acc), settings);
        expect(accidentalsOf(layout), contains(glyph), reason: '$acc');
      });
    });

    test('a microtonal accidental always shows (never implied by the key)', () {
      // A4 natural in C major shows nothing, but A half-sharp must show.
      final plain = const LayoutEngine().layout(
        Score(clef: Clef.treble, measures: [
          Measure([
            NoteElement(
                pitches: [const Pitch(Step.a)],
                duration: const NoteDuration(DurationBase.quarter),
                id: 'e0'),
          ]),
        ]),
        settings,
      );
      expect(accidentalsOf(plain), isEmpty);
      final micro = const LayoutEngine()
          .layout(microtonalScore(MicrotonalAccidental.halfSharp), settings);
      expect(accidentalsOf(micro), isNotEmpty);
    });

    test('the glyph is remappable through LayoutSettings.microtonalGlyphs', () {
      final custom = LayoutSettings(
        metadata: metadata,
        microtonalGlyphs: const {
          MicrotonalAccidental.halfSharp: SmuflGlyph.accidentalSharp,
        },
      );
      final layout = const LayoutEngine()
          .layout(microtonalScore(MicrotonalAccidental.halfSharp), custom);
      expect(accidentalsOf(layout), contains(SmuflGlyph.accidentalSharp));
      expect(accidentalsOf(layout),
          isNot(contains(SmuflGlyph.accidentalQuarterToneSharpStein)));
    });
  });
}
