import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

Score withOttava(String notes, List<Ottava> ottavas, {Clef? clef}) {
  final base = Score.simple(clef: clef ?? Clef.treble, notes: notes);
  return Score(
    clef: base.clef,
    keySignature: base.keySignature,
    timeSignature: base.timeSignature,
    measures: base.measures,
    ottavas: ottavas,
  );
}

double headY(ScoreLayout layout, String id) => layout.primitives
    .whereType<GlyphPrimitive>()
    .firstWhere((g) => g.elementId == id && g.smuflName.startsWith('notehead'))
    .position
    .y;

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('octave clefs', () {
    test('treble8vb draws pitches an octave higher on the staff', () {
      // Sounding C3 sits where C4 would on plain treble.
      final vocal = layoutOf(Score.simple(
        clef: Clef.treble8vb,
        notes: 'c3:q',
      ));
      final plain = layoutOf(Score.simple(notes: 'c4:q'));
      expect(headY(vocal, 'e0'), headY(plain, 'e0'));
      // And the clef glyph carries the 8.
      expect(
        vocal.primitives
            .whereType<GlyphPrimitive>()
            .any((g) => g.smuflName == SmuflGlyph.gClef8vb),
        isTrue,
      );
    });

    test('treble8va and bass8vb anchor like their base clefs', () {
      final picc = layoutOf(Score.simple(clef: Clef.treble8va, notes: 'c6:q'));
      final plain = layoutOf(Score.simple(notes: 'c5:q'));
      expect(headY(picc, 'e0'), headY(plain, 'e0'));
      final contra = layoutOf(Score.simple(clef: Clef.bass8vb, notes: 'c2:q'));
      final bass = layoutOf(Score.simple(clef: Clef.bass, notes: 'c3:q'));
      expect(headY(contra, 'e0'), headY(bass, 'e0'));
    });

    test('DSL !clef= accepts octave clefs mid-score', () {
      final score = Score.simple(notes: 'c4:q | !clef=treble8vb c3:q');
      expect(score.measures[1].clefChange, Clef.treble8vb);
      expect(() => layoutOf(score), returnsNormally);
    });

    test('octave clefs round trip through MusicXML', () {
      for (final clef in [Clef.treble8va, Clef.treble8vb, Clef.bass8vb]) {
        final score = Score.simple(clef: clef, notes: 'c4:q');
        expect(scoreFromMusicXml(scoreToMusicXml(score)).clef, clef,
            reason: clef.name);
      }
    });
  });

  group('ottava brackets', () {
    test('8va draws spanned notes an octave lower with a dashed bracket', () {
      final score = withOttava('c6:q d6 e6 f6', const [Ottava('e1', 'e2')]);
      final layout = layoutOf(score);
      final plain = layoutOf(Score.simple(notes: 'c6:q d6 e6 f6'));
      // Spanned notes drop 3.5 spaces (7 positions); others match.
      expect(headY(layout, 'e0'), headY(plain, 'e0'));
      expect(headY(layout, 'e1'), headY(plain, 'e1') + 3.5);
      expect(headY(layout, 'e2'), headY(plain, 'e2') + 3.5);
      expect(headY(layout, 'e3'), headY(plain, 'e3'));
      // Label + dashes + hook above the staff.
      final label = layout.primitives
          .whereType<TextPrimitive>()
          .firstWhere((t) => t.text == '8va');
      expect(label.position.y, lessThan(0));
      final dashes = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) => l.thickness == 0.12)
          .toList();
      expect(dashes.length, greaterThanOrEqualTo(2));
    });

    test('8vb raises spanned notes and sits below the staff', () {
      final score = withOttava(
        'c2:q d2',
        const [Ottava('e0', 'e1', down: true)],
        clef: Clef.bass,
      );
      final layout = layoutOf(score);
      final plain = layoutOf(Score.simple(clef: Clef.bass, notes: 'c2:q d2'));
      expect(headY(layout, 'e0'), headY(plain, 'e0') - 3.5);
      final label = layout.primitives
          .whereType<TextPrimitive>()
          .firstWhere((t) => t.text == '8vb');
      expect(label.position.y, greaterThan(4));
    });

    test('unknown or backwards spans throw', () {
      expect(() => layoutOf(withOttava('c4:q', const [Ottava('e0', 'nope')])),
          throwsArgumentError);
      expect(() => layoutOf(withOttava('c4:q d4', const [Ottava('e1', 'e0')])),
          throwsArgumentError);
    });

    test('ottavas round trip through MusicXML', () {
      final score = withOttava(
        'c6:q d6 e6 f6',
        const [Ottava('e1', 'e2')],
      );
      expect(scoreFromMusicXml(scoreToMusicXml(score)), score);
      final down = withOttava(
        'c3:q d3',
        const [Ottava('e0', 'e1', down: true)],
      );
      expect(scoreFromMusicXml(scoreToMusicXml(down)), down);
    });

    test('deterministic', () {
      final score = withOttava('c6:q d6 e6 f6', const [Ottava('e0', 'e3')]);
      expect(layoutOf(score).primitives.toString(),
          layoutOf(score).primitives.toString());
    });
  });
}
