import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.7.2: single-note tremolo — strokes through the stem.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

Score scoreWith(int? tremolo, {NoteDuration duration = NoteDuration.half}) =>
    Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement.note(Pitch.parse('b4'), duration,
              tremolo: tremolo, id: 'n'),
        ]),
      ],
    );

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<GlyphPrimitive> tremolos(ScoreLayout l) => l.primitives
    .whereType<GlyphPrimitive>()
    .where((g) => g.smuflName.startsWith('tremolo'))
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
    test('tremolo participates in value equality', () {
      expect(scoreWith(3), scoreWith(3));
      expect(scoreWith(3), isNot(scoreWith(2)));
      expect(scoreWith(3), isNot(scoreWith(null)));
    });

    test('tremoloStrokes rejects out-of-range counts', () {
      expect(() => SmuflGlyph.tremoloStrokes(0), throwsArgumentError);
      expect(() => SmuflGlyph.tremoloStrokes(6), throwsArgumentError);
    });
  });

  group('layout', () {
    test('draws the tremolo glyph for the requested stroke count', () {
      final glyphs = tremolos(layoutOf(scoreWith(3)));
      expect(glyphs, hasLength(1));
      expect(glyphs.single.smuflName, SmuflGlyph.tremoloStrokes(3));
    });

    test('no tremolo draws nothing', () {
      expect(tremolos(layoutOf(scoreWith(null))), isEmpty);
    });

    test('a stemless (whole) note carries no tremolo', () {
      expect(
        tremolos(layoutOf(scoreWith(3, duration: NoteDuration.whole))),
        isEmpty,
      );
    });

    test('layout with a tremolo is deterministic', () {
      String render() =>
          layoutOf(scoreWith(2)).primitives.map((p) => p.toString()).join('\n');
      expect(render(), render());
    });
  });

  group('interchange + transpose', () {
    test('MusicXML round-trips the stroke count', () {
      for (final n in [1, 3, 5]) {
        final back = scoreFromMusicXml(scoreToMusicXml(scoreWith(n)));
        expect(
          (back.measures.single.elements.single as NoteElement).tremolo,
          n,
        );
      }
    });

    test('tremolo coexists with an ornament through MusicXML', () {
      final score = Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement.note(Pitch.parse('b4'), NoteDuration.quarter,
                tremolo: 2, ornament: Ornament.trill, id: 'n'),
          ]),
        ],
      );
      final back = scoreFromMusicXml(scoreToMusicXml(score));
      final note = back.measures.single.elements.single as NoteElement;
      expect(note.tremolo, 2);
      expect(note.ornament, Ornament.trill);
    });

    test('transposedBy keeps the tremolo', () {
      final up = scoreWith(4).transposedBy(Interval.majorSecond);
      expect(
        (up.measures.single.elements.single as NoteElement).tremolo,
        4,
      );
    });
  });
}
