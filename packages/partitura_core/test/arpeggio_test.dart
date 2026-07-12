import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.7.2: arpeggio (rolled chord) — a vertical wavy line left of the chord.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

NoteElement chord(Arpeggio? arpeggio) => NoteElement(
      pitches: [Pitch.parse('c4'), Pitch.parse('e4'), Pitch.parse('g4')],
      duration: NoteDuration.half,
      arpeggio: arpeggio,
      id: 'ch',
    );

Score scoreWith(Arpeggio? arpeggio) => Score(
      clef: Clef.treble,
      measures: [
        Measure([chord(arpeggio)])
      ],
    );

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

  group('model', () {
    test('arpeggio participates in value equality', () {
      expect(chord(Arpeggio.up), chord(Arpeggio.up));
      expect(chord(Arpeggio.up), isNot(chord(Arpeggio.down)));
      expect(chord(Arpeggio.up), isNot(chord(null)));
    });
  });

  group('layout', () {
    List<GlyphPrimitive> wiggles(ScoreLayout l) => l.primitives
        .whereType<GlyphPrimitive>()
        .where((g) => g.smuflName.startsWith('wiggleArpeggiato'))
        .toList();

    test('draws a tiled wavy line plus an up arrowhead, left of the chord', () {
      final layout = layoutOf(scoreWith(Arpeggio.up));
      final glyphs = wiggles(layout);
      // Several tiles + one arrowhead.
      expect(glyphs.length, greaterThanOrEqualTo(2));
      expect(
        glyphs.where((g) => g.smuflName == SmuflGlyph.wiggleArpeggiatoUpArrow),
        hasLength(1),
      );
      // Every wiggle glyph sits left of the chord's noteheads.
      final headLeft = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.noteheadHalf)
          .map((g) => g.position.x)
          .reduce((a, b) => a < b ? a : b);
      for (final g in glyphs) {
        expect(g.position.x, lessThan(headLeft));
      }
    });

    test('a downward arpeggio uses the down arrowhead', () {
      final glyphs = wiggles(layoutOf(scoreWith(Arpeggio.down)));
      expect(
        glyphs
            .where((g) => g.smuflName == SmuflGlyph.wiggleArpeggiatoDownArrow),
        hasLength(1),
      );
    });

    test('no arpeggio draws no wiggle', () {
      expect(wiggles(layoutOf(scoreWith(null))), isEmpty);
    });

    test('layout with an arpeggio is deterministic', () {
      String render() => layoutOf(scoreWith(Arpeggio.up))
          .primitives
          .map((p) => p.toString())
          .join('\n');
      expect(render(), render());
    });
  });

  group('interchange + transpose', () {
    test('MusicXML round-trips the arpeggio direction', () {
      for (final dir in Arpeggio.values) {
        final back = scoreFromMusicXml(scoreToMusicXml(scoreWith(dir)));
        expect(
          (back.measures.single.elements.single as NoteElement).arpeggio,
          dir,
        );
      }
    });

    test('transposedBy keeps the arpeggio', () {
      final up = scoreWith(Arpeggio.down).transposedBy(Interval.majorThird);
      expect(
        (up.measures.single.elements.single as NoteElement).arpeggio,
        Arpeggio.down,
      );
    });
  });
}
