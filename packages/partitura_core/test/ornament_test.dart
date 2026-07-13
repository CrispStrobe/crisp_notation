import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<GlyphPrimitive> ornamentsOf(ScoreLayout layout) => layout.primitives
    .whereType<GlyphPrimitive>()
    .where((g) => g.smuflName.startsWith('ornament'))
    .toList();

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('model and DSL', () {
    test('markers parse to the four ornaments', () {
      final score = Score.simple(notes: r'c4:q% d4$ e4& f4?');
      final notes = score.measures.single.elements.cast<NoteElement>();
      expect(notes.map((n) => n.ornament), [
        Ornament.trill,
        Ornament.shortTrill,
        Ornament.mordent,
        Ornament.turn,
      ]);
    });

    test('ornament participates in value equality', () {
      expect(Score.simple(notes: 'c4:q%'), isNot(Score.simple(notes: 'c4:q&')));
      expect(Score.simple(notes: 'c4:q%'), Score.simple(notes: 'c4:q%'));
    });

    test('combinable with articulations and ties', () {
      final note = Score.simple(notes: "c4:q%'~")
          .measures
          .single
          .elements
          .single as NoteElement;
      expect(note.ornament, Ornament.trill);
      expect(note.articulations, {Articulation.staccato});
      expect(note.tieToNext, isTrue);
    });

    test('transposition keeps the ornament', () {
      final up =
          Score.simple(notes: 'c4:q%').transposedBy(Interval.majorSecond);
      expect((up.measures.single.elements.single as NoteElement).ornament,
          Ornament.trill);
    });
  });

  group('layout', () {
    test('each ornament draws its glyph above the staff', () {
      final layout = layoutOf(Score.simple(notes: r'c4:q% d4$ e4& f4?'));
      final glyphs = ornamentsOf(layout);
      expect(glyphs.map((g) => g.smuflName), [
        SmuflGlyph.ornamentTrill,
        SmuflGlyph.ornamentShortTrill,
        SmuflGlyph.ornamentMordent,
        SmuflGlyph.ornamentTurn,
      ]);
      for (final glyph in glyphs) {
        expect(glyph.position.y, lessThan(0));
        expect(glyph.elementId, isNotNull);
      }
    });

    test('the ornament sits above a fermata on the same note', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q@%'));
      final ornament = ornamentsOf(layout).single;
      final fermata = layout.primitives
          .whereType<GlyphPrimitive>()
          .firstWhere((g) => g.smuflName.startsWith('fermata'));
      expect(ornament.position.y, lessThan(fermata.position.y));
    });

    test('ornaments grow the element hit region upward', () {
      final without = layoutOf(Score.simple(notes: 'c4:q d4'));
      final with_ = layoutOf(Score.simple(notes: 'c4:q% d4'));
      double topOf(ScoreLayout l) =>
          l.regions.firstWhere((r) => r.elementId == 'e0').bounds.top;
      expect(topOf(with_), lessThan(topOf(without)));
    });

    test('ornaments center on the notehead column', () {
      final layout = layoutOf(Score.simple(notes: 'c5:h%'));
      final head = layout.primitives
          .whereType<GlyphPrimitive>()
          .firstWhere((g) => g.smuflName.startsWith('notehead'));
      final headBox = metadata.bBoxOf(head.smuflName);
      final headCenter = head.position.x + headBox.swX + headBox.width / 2;
      final ornament = ornamentsOf(layout).single;
      final box = metadata.bBoxOf(ornament.smuflName);
      final ornamentCenter = ornament.position.x + box.swX + box.width / 2;
      expect(ornamentCenter, closeTo(headCenter, 0.05));
    });
  });

  group('baroque variants', () {
    NoteElement orn(Ornament o, String id) => NoteElement(
          pitches: const [Pitch(Step.c, octave: 5)],
          duration: NoteDuration.quarter,
          ornament: o,
          id: id,
        );

    test('inverted turn and trill-with-accidental draw their glyphs', () {
      final layout = layoutOf(Score(
        clef: Clef.treble,
        measures: [
          Measure(
              [orn(Ornament.invertedTurn, 'a'), orn(Ornament.trillSharp, 'b')])
        ],
      ));
      final names = ornamentsOf(layout).map((g) => g.smuflName).toSet();
      expect(names, contains(SmuflGlyph.ornamentTurnInverted));
      expect(names, contains(SmuflGlyph.ornamentTrill)); // base of trillSharp
      // A small sharp is drawn above the trill.
      final sharps = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.accidentalSharp)
          .toList();
      expect(sharps, hasLength(1));
      expect(sharps.single.scale, lessThan(1.0));
    });

    test('all four baroque variants round-trip through MusicXML', () {
      final score = Score(
        clef: Clef.treble,
        measures: [
          Measure([
            orn(Ornament.invertedTurn, 'a'),
            orn(Ornament.trillSharp, 'b'),
            orn(Ornament.trillFlat, 'c'),
            orn(Ornament.trillNatural, 'd'),
          ])
        ],
      );
      final xml = scoreToMusicXml(score);
      expect(xml, contains('<inverted-turn/>'));
      expect(xml, contains('<accidental-mark placement="above">sharp'));
      final back = scoreFromMusicXml(xml);
      expect(
          back.measures.single.elements.map((e) => (e as NoteElement).ornament),
          [
            Ornament.invertedTurn,
            Ornament.trillSharp,
            Ornament.trillFlat,
            Ornament.trillNatural,
          ]);
    });
  });

  group('MusicXML', () {
    test('all four ornaments round trip', () {
      final score = Score.simple(notes: r'c4:q% d4$ e4& f4?');
      expect(scoreFromMusicXml(scoreToMusicXml(score)), score);
    });
  });
}
