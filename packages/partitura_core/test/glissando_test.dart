import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// v0.7.2: glissando/slide — a straight line between two notes.
late final SmuflMetadata metadata;
late final LayoutSettings settings;

Score scoreWith(List<Glissando> glissandos) => Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          NoteElement.note(Pitch.parse('c4'), NoteDuration.half, id: 'a'),
          NoteElement.note(Pitch.parse('g4'), NoteDuration.half, id: 'b'),
        ]),
      ],
      glissandos: glissandos,
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
    test('glissando value semantics', () {
      expect(const Glissando('a', 'b'), const Glissando('a', 'b'));
      expect(const Glissando('a', 'b'), isNot(const Glissando('a', 'c')));
    });

    test('glissando participates in Score equality', () {
      expect(scoreWith(const [Glissando('a', 'b')]),
          scoreWith(const [Glissando('a', 'b')]));
      expect(
          scoreWith(const [Glissando('a', 'b')]), isNot(scoreWith(const [])));
    });
  });

  group('layout', () {
    // The line is the diagonal between the two note centers: not vertical,
    // not horizontal, and distinct from the barlines/stems.
    LinePrimitive glissLine(ScoreLayout l) =>
        l.primitives.whereType<LinePrimitive>().firstWhere(
            (line) => line.from.x != line.to.x && line.from.y != line.to.y);

    test('draws a diagonal line rising from the lower note to the higher', () {
      final layout = layoutOf(scoreWith(const [Glissando('a', 'b')]));
      final line = glissLine(layout);
      // c4 is lower on the staff (larger y) than g4 (smaller y): the line
      // runs up-and-to-the-right.
      expect(line.to.x, greaterThan(line.from.x));
      expect(line.to.y, lessThan(line.from.y));
    });

    test('no glissando draws no diagonal line', () {
      final layout = layoutOf(scoreWith(const []));
      final diagonals = layout.primitives.whereType<LinePrimitive>().where(
          (line) => line.from.x != line.to.x && line.from.y != line.to.y);
      expect(diagonals, isEmpty);
    });

    test('an unknown id throws', () {
      expect(
        () => layoutOf(scoreWith(const [Glissando('a', 'zzz')])),
        throwsArgumentError,
      );
    });

    test('a reversed glissando throws', () {
      expect(
        () => layoutOf(scoreWith(const [Glissando('b', 'a')])),
        throwsArgumentError,
      );
    });
  });

  group('interchange + transpose', () {
    test('MusicXML round-trips the glissando', () {
      final back = scoreFromMusicXml(
          scoreToMusicXml(scoreWith(const [Glissando('a', 'b')])));
      // Ids are re-minted on import (e0, e1); the span still links the two.
      expect(back.glissandos, hasLength(1));
      final ids = back.measures.single.elements.map((e) => e.id).toList();
      expect(back.glissandos.single.startId, ids[0]);
      expect(back.glissandos.single.endId, ids[1]);
    });

    test('transposedBy keeps the glissando', () {
      final up = scoreWith(const [Glissando('a', 'b')])
          .transposedBy(Interval.perfectFourth);
      expect(up.glissandos, const [Glissando('a', 'b')]);
    });
  });
}
