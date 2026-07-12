import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.3.6: grace notes.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<GlyphPrimitive> smallGlyphs(ScoreLayout layout) => layout.primitives
    .whereType<GlyphPrimitive>()
    .where((g) => g.scale != 1.0)
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
    test('{p} and {p,q} prefixes parse into graceNotes', () {
      final score = Score.simple(notes: '{g4}a4:q {f4,g4}a4:q b4');
      final notes = score.measures.single.elements.cast<NoteElement>();
      expect(notes[0].graceNotes, const [Pitch(Step.g)]);
      expect(notes[1].graceNotes, const [Pitch(Step.f), Pitch(Step.g)]);
      expect(notes[2].graceNotes, isEmpty);
    });

    test('grace prefixes combine with durations, ties and markers', () {
      final score = Score.simple(notes: "{d5}c5:h.~' c5:q");
      final note = score.measures.single.elements.first as NoteElement;
      expect(note.graceNotes, const [Pitch(Step.d, octave: 5)]);
      expect(note.duration, const NoteDuration(DurationBase.half, dots: 1));
      expect(note.tieToNext, isTrue);
      expect(note.articulations, {Articulation.staccato});
    });

    test('malformed grace groups are rejected', () {
      expect(() => Score.simple(notes: '{}c4:q'), throwsFormatException);
      expect(() => Score.simple(notes: '{x9}c4:q'), throwsFormatException);
      expect(() => Score.simple(notes: '{g4}r:q'), throwsFormatException);
    });

    test('graceNotes participate in value equality', () {
      expect(
        Score.simple(notes: '{g4}a4:q'),
        Score.simple(notes: '{g4}a4:q'),
      );
      expect(
        Score.simple(notes: '{g4}a4:q'),
        isNot(Score.simple(notes: 'a4:q')),
      );
      expect(
        Score.simple(notes: '{g4}a4:q')
            .measures
            .single
            .elements
            .first
            .toString(),
        contains('grace'),
      );
    });
  });

  group('layout', () {
    test('grace glyphs render small, before the host, stems up', () {
      final layout = layoutOf(Score.simple(notes: '{g4}a4:q'));
      final small = smallGlyphs(layout);
      // Small notehead + small flag.
      expect(small.map((g) => g.smuflName).toList(),
          [SmuflGlyph.noteheadBlack, SmuflGlyph.flag8thUp]);
      for (final glyph in small) {
        expect(glyph.scale, 0.6);
        expect(glyph.elementId, 'e0');
      }
      final hostHead = layout.primitives.whereType<GlyphPrimitive>().firstWhere(
          (g) => g.smuflName == SmuflGlyph.noteheadBlack && g.scale == 1.0);
      expect(small.first.position.x, lessThan(hostHead.position.x));
      // Flag above the notehead: stem up.
      expect(small[1].position.y, lessThan(small[0].position.y));
    });

    test('the first grace stem carries a slash', () {
      final layout = layoutOf(Score.simple(notes: '{f4,g4}a4:q'));
      // Diagonal tagged line = the slash (stems/ledgers are axis-aligned).
      final slashes = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) =>
              l.elementId != null && l.from.x != l.to.x && l.from.y != l.to.y)
          .toList();
      expect(slashes, hasLength(1));
      // Two grace noteheads for the pair.
      expect(
        smallGlyphs(layout)
            .where((g) => g.smuflName == SmuflGlyph.noteheadBlack),
        hasLength(2),
      );
    });

    test('grace notes outside the staff get small ledger lines', () {
      final layout = layoutOf(Score.simple(notes: '{c4}g4:q'));
      final graceHead = smallGlyphs(layout).first;
      final ledgers = layout.primitives.whereType<LinePrimitive>().where((l) =>
          l.from.y == 5.0 &&
          l.to.y == 5.0 &&
          l.thickness == settings.legerLineThickness);
      // One small ledger through the grace C4 (the host G4 needs none).
      expect(ledgers, hasLength(1));
      expect(ledgers.single.to.x - ledgers.single.from.x,
          lessThan(metadata.bBoxOf(SmuflGlyph.noteheadBlack).width + 0.9));
      expect(graceHead.position.y, 5.0);
    });

    test('grace ink widens the element and its hit region', () {
      final plain = layoutOf(Score.simple(notes: 'a4:q'));
      final graced = layoutOf(Score.simple(notes: '{f4,g4}a4:q'));
      expect(graced.width, greaterThan(plain.width));
      expect(
        graced.regions.single.bounds.width,
        greaterThan(plain.regions.single.bounds.width),
      );
    });

    test('deterministic with grace notes', () {
      String render() => layoutOf(Score.simple(notes: '{f4,g4}a4:q {d5}c5:h'))
          .primitives
          .map((p) => p.toString())
          .join('\n');
      expect(render(), render());
      expect(render(), contains('x0.6'));
    });
  });
}
