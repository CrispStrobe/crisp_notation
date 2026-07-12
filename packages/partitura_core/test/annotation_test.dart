import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

late final SmuflMetadata metadata;
late final LayoutSettings settings;

ScoreLayout layoutOf(Score score) =>
    const LayoutEngine().layout(score, settings);

List<TextPrimitive> textsOf(ScoreLayout layout) =>
    layout.primitives.whereType<TextPrimitive>().toList();

void main() {
  setUpAll(() {
    final source = File('../partitura/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    metadata =
        SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
    settings = LayoutSettings(metadata: metadata);
  });

  group('model', () {
    test('Annotation value semantics', () {
      expect(const Annotation('e0', 'C'), const Annotation('e0', 'C'));
      expect(const Annotation('e0', 'C').hashCode,
          const Annotation('e0', 'C').hashCode);
      expect(const Annotation('e0', 'C'), isNot(const Annotation('e0', 'G7')));
      expect(const Annotation('e0', 'C'), isNot(const Annotation('e1', 'C')));
    });

    test('scores with different annotations are unequal', () {
      Score make(String chords) =>
          Score.simple(notes: 'c4:q d4', annotations: chords);
      expect(make('C G'), make('C G'));
      expect(make('C G'), isNot(make('C G7')));
    });
  });

  group('DSL', () {
    test('tokens map to voice-1 notes in reading order, * skips', () {
      final score = Score.simple(
        notes: 'c4:q r e4 | g4:h g4',
        annotations: 'C * G7/B',
      );
      expect(score.annotations, const [
        Annotation('e0', 'C'),
        Annotation('e3', 'G7/B'),
      ]);
    });

    test('more tokens than notes throws', () {
      expect(
        () => Score.simple(notes: 'c4:q', annotations: 'C G'),
        throwsFormatException,
      );
    });

    test('lyrics and annotations coexist', () {
      final score = Score.simple(
        notes: 'c4:q e4',
        lyrics: 'la li',
        annotations: 'C *',
      );
      expect(score.lyrics, hasLength(2));
      expect(score.annotations, const [Annotation('e0', 'C')]);
    });
  });

  group('layout', () {
    test('annotations render above the staff, centered on their note', () {
      final score = Score.simple(
        notes: 'c4:q e4 g4 c5',
        annotations: 'C Em G C',
      );
      final layout = layoutOf(score);
      final texts = textsOf(layout);
      expect(texts, hasLength(4));
      for (final text in texts) {
        expect(text.size, settings.annotationSize);
        expect(text.position.y, lessThan(0)); // above the top staff line
      }
      for (var i = 1; i < texts.length; i++) {
        expect(texts[i].position.x, greaterThan(texts[i - 1].position.x));
      }
    });

    test('annotations share one baseline that clears local ink', () {
      // With a chord symbol on every note, the c6 (under the second symbol)
      // lifts the whole shared row.
      final annotatedHigh = layoutOf(Score.simple(
        notes: 'c4:q c6 c4 c4',
        annotations: 'C Am F G',
      ));
      final allLow = layoutOf(Score.simple(
        notes: 'c4:q c4 c4 c4',
        annotations: 'C Am F G',
      ));
      final highYs = textsOf(annotatedHigh).map((t) => t.position.y).toSet();
      expect(highYs, hasLength(1)); // still one shared baseline
      expect(highYs.single, lessThan(textsOf(allLow).first.position.y));

      // But a high note with no annotation over it (a per-column skyline) does
      // NOT lift a distant chord symbol.
      final unannotatedHigh = layoutOf(Score.simple(
        notes: 'c4:q c6 c4 c4',
        annotations: 'C * * *',
      ));
      expect(textsOf(unannotatedHigh).single.position.y,
          greaterThan(highYs.single));
    });

    test('annotations and lyrics occupy opposite sides', () {
      final layout = layoutOf(Score.simple(
        notes: 'c4:q e4',
        lyrics: 'la li',
        annotations: 'C *',
      ));
      final texts = textsOf(layout);
      expect(texts, hasLength(3));
      final lyricYs = texts.where((t) => t.size == settings.lyricSize);
      final chordYs = texts.where((t) => t.size == settings.annotationSize);
      expect(lyricYs.every((t) => t.position.y > 4), isTrue);
      expect(chordYs.every((t) => t.position.y < 0), isTrue);
    });

    test('annotations grow the element hit region upward', () {
      final without = layoutOf(Score.simple(notes: 'c4:q d4'));
      final with_ =
          layoutOf(Score.simple(notes: 'c4:q d4', annotations: 'C *'));
      double topOf(ScoreLayout l, String id) =>
          l.regions.firstWhere((r) => r.elementId == id).bounds.top;
      expect(topOf(with_, 'e0'), lessThan(topOf(without, 'e0')));
    });

    test('unknown element id throws', () {
      final score = Score(
        clef: Clef.treble,
        measures: Score.simple(notes: 'c4:q').measures,
        annotations: const [Annotation('nope', 'C')],
      );
      expect(() => layoutOf(score), throwsArgumentError);
    });

    test('an annotation on a rest id throws', () {
      final score = Score(
        clef: Clef.treble,
        measures: Score.simple(notes: 'c4:q r').measures,
        annotations: const [Annotation('e1', 'C')],
      );
      expect(() => layoutOf(score), throwsArgumentError);
    });

    test('deterministic with annotations', () {
      final score = Score.simple(
        notes: 'c4:q e4 g4 c5',
        annotations: 'C Em G C',
      );
      expect(layoutOf(score).primitives.toString(),
          layoutOf(score).primitives.toString());
    });
  });

  group('line breaking', () {
    test('each system keeps exactly its own annotations', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5 | c5:q b4 a4 g4 | c4:w',
        annotations: 'C * * * F * * * G * * * C',
      );
      final multi = layoutSystems(score, settings, maxWidth: 35);
      expect(multi.systems.length, greaterThan(1));
      final total = multi.systems
          .map((s) => textsOf(s.layout).length)
          .reduce((a, b) => a + b);
      expect(total, score.annotations.length);
    });
  });
}
