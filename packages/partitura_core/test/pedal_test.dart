import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.7.2: sustain-pedal marks ("Ped." … release star) below the staff.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

Score scoreWith(List<Pedal> pedals) => Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          NoteElement.note(Pitch.parse('c4'), NoteDuration.quarter, id: 'a'),
          NoteElement.note(Pitch.parse('e4'), NoteDuration.quarter, id: 'b'),
          NoteElement.note(Pitch.parse('g4'), NoteDuration.quarter, id: 'c'),
          NoteElement.note(Pitch.parse('c5'), NoteDuration.quarter, id: 'd'),
        ]),
      ],
      pedals: pedals,
    );

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<GlyphPrimitive> pedalGlyphs(ScoreLayout l) => l.primitives
    .whereType<GlyphPrimitive>()
    .where((g) => g.smuflName.startsWith('keyboardPedal'))
    .toList();

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('model', () {
    test('pedal value semantics', () {
      expect(const Pedal('a', 'd'), const Pedal('a', 'd'));
      expect(const Pedal('a', 'd'), isNot(const Pedal('a', 'c')));
    });

    test('pedal participates in Score equality', () {
      expect(scoreWith(const [Pedal('a', 'd')]),
          scoreWith(const [Pedal('a', 'd')]));
      expect(scoreWith(const [Pedal('a', 'd')]), isNot(scoreWith(const [])));
    });
  });

  group('layout', () {
    test('draws Ped. under the start and the release star under the end', () {
      final layout = layoutOf(scoreWith(const [Pedal('a', 'd')]));
      final glyphs = pedalGlyphs(layout);
      expect(glyphs.map((g) => g.smuflName).toSet(), {
        SmuflGlyph.keyboardPedalPed,
        SmuflGlyph.keyboardPedalUp,
      });
      final ped =
          glyphs.firstWhere((g) => g.smuflName == SmuflGlyph.keyboardPedalPed);
      final up =
          glyphs.firstWhere((g) => g.smuflName == SmuflGlyph.keyboardPedalUp);
      // "Ped." precedes the release star, and both sit below the staff.
      expect(ped.position.x, lessThan(up.position.x));
      expect(ped.position.y, greaterThan(4));
      expect(up.position.y, greaterThan(4));
    });

    test('no pedal draws nothing', () {
      expect(pedalGlyphs(layoutOf(scoreWith(const []))), isEmpty);
    });

    test('an unknown id throws', () {
      expect(() => layoutOf(scoreWith(const [Pedal('a', 'zzz')])),
          throwsArgumentError);
    });

    test('a reversed pedal throws', () {
      expect(() => layoutOf(scoreWith(const [Pedal('d', 'a')])),
          throwsArgumentError);
    });
  });

  group('interchange + transpose', () {
    test('MusicXML round-trips the pedal span', () {
      final back = scoreFromMusicXml(
          scoreToMusicXml(scoreWith(const [Pedal('a', 'd')])));
      expect(back.pedals, hasLength(1));
      final ids = back.measures.single.elements.map((e) => e.id).toList();
      expect(back.pedals.single.startId, ids.first);
      expect(back.pedals.single.endId, ids.last);
    });

    test('transposedBy keeps the pedal', () {
      final up = scoreWith(const [Pedal('a', 'd')])
          .transposedBy(Interval.perfectFifth);
      expect(up.pedals, const [Pedal('a', 'd')]);
    });
  });
}
