import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
    test('Lyric value semantics', () {
      expect(const Lyric('e0', 'la'), const Lyric('e0', 'la'));
      expect(
          const Lyric('e0', 'la').hashCode, const Lyric('e0', 'la').hashCode);
      expect(const Lyric('e0', 'la'),
          isNot(const Lyric('e0', 'la', hyphenToNext: true)));
      expect(const Lyric('e0', 'la'),
          isNot(const Lyric('e0', 'la', extender: true)));
      expect(const Lyric('e0', 'la'), isNot(const Lyric('e1', 'la')));
    });

    test('scores with different lyrics are unequal', () {
      Score make(String lyricText) => Score.simple(
            notes: 'c4:q d4',
            lyrics: lyricText,
          );
      expect(make('la la'), make('la la'));
      expect(make('la la'), isNot(make('la li')));
    });
  });

  group('DSL', () {
    test('tokens map to voice-1 notes in reading order, skipping rests', () {
      final score = Score.simple(
        notes: 'c4:q r d4 | e4:h f4',
        lyrics: 'one two three four',
      );
      expect(score.lyrics, const [
        Lyric('e0', 'one'),
        Lyric('e2', 'two'),
        Lyric('e3', 'three'),
        Lyric('e4', 'four'),
      ]);
    });

    test('trailing - marks a hyphen, trailing _ an extender, * skips', () {
      final score = Score.simple(
        notes: 'c4:q d4 e4 f4',
        lyrics: 'twin- kle * star_',
      );
      expect(score.lyrics, const [
        Lyric('e0', 'twin', hyphenToNext: true),
        Lyric('e1', 'kle'),
        Lyric('e3', 'star', extender: true),
      ]);
    });

    test('voice-2 notes never receive lyrics', () {
      final score = Score.simple(
        notes: 'c5:q d5 ; c4:h',
        lyrics: 'la li',
      );
      expect(score.lyrics.map((l) => l.elementId), ['e0', 'e1']);
    });

    test('more tokens than notes throws', () {
      expect(
        () => Score.simple(notes: 'c4:q', lyrics: 'la li'),
        throwsFormatException,
      );
    });

    test('a lone - or _ is a literal syllable', () {
      final score = Score.simple(notes: 'c4:q d4', lyrics: '- _');
      expect(score.lyrics, const [Lyric('e0', '-'), Lyric('e1', '_')]);
    });
  });

  group('layout', () {
    test('syllables render as text primitives centered under their note', () {
      final score = Score.simple(
        notes: 'c4:q d4 e4 f4',
        lyrics: 'do re mi fa',
      );
      final layout = layoutOf(score);
      final texts = textsOf(layout);
      expect(texts, hasLength(4));
      for (final (i, text) in texts.indexed) {
        expect(text.elementId, 'e$i');
        expect(text.size, settings.lyricSize);
        // Centered under the notehead: the anchor sits inside the
        // element's pre-lyric horizontal extent.
        final region = layout.regions
            .firstWhere((r) => r.elementId == text.elementId)
            .bounds;
        expect(text.position.x, greaterThan(region.left));
        expect(text.position.x, lessThan(region.right));
      }
      // Reading order: anchors strictly increase.
      for (var i = 1; i < texts.length; i++) {
        expect(texts[i].position.x, greaterThan(texts[i - 1].position.x));
      }
    });

    test('all syllables share one baseline below the staff', () {
      final layout = layoutOf(Score.simple(
        notes: 'c4:q c6 c4 c6',
        lyrics: 'do re mi fa',
      ));
      final ys = textsOf(layout).map((t) => t.position.y).toSet();
      expect(ys, hasLength(1));
      expect(ys.single, greaterThan(4)); // below the bottom staff line
    });

    test('the baseline clears low ink (notes below the staff)', () {
      final low = layoutOf(Score.simple(
        clef: Clef.treble,
        notes: 'c3:q c3 c3 c3', // far below the staff, many ledger lines
        lyrics: 'do re mi fa',
      ));
      final high = layoutOf(Score.simple(
        notes: 'c6:q c6 c6 c6',
        lyrics: 'do re mi fa',
      ));
      expect(low, isNotNull);
      expect(
        textsOf(low).first.position.y,
        greaterThan(textsOf(high).first.position.y),
      );
    });

    test('a deep note with no syllable does not push the words down', () {
      // Only the first note carries a lyric; the deep c2 later has none. With
      // a per-column skyline the words clear only the ink under themselves.
      Score withLast(Pitch last) => Score(
            clef: Clef.treble,
            measures: [
              Measure([
                NoteElement.note(
                    const Pitch(Step.c, octave: 5), NoteDuration.quarter,
                    id: 'e0'),
                NoteElement.note(
                    const Pitch(Step.c, octave: 5), NoteDuration.quarter,
                    id: 'e1'),
                NoteElement.note(last, NoteDuration.half, id: 'e2'),
              ]),
            ],
            lyrics: const [Lyric('e0', 'la')],
          );
      final deep = layoutOf(withLast(const Pitch(Step.c, octave: 2)));
      final level = layoutOf(withLast(const Pitch(Step.c, octave: 5)));
      // The distant deep note does not lower the lyric baseline.
      expect(textsOf(deep).single.position.y,
          closeTo(textsOf(level).single.position.y, 0.01));
    });

    test('lyrics grow the element hit region downward', () {
      final without = layoutOf(Score.simple(notes: 'c5:q d5'));
      final with_ = layoutOf(Score.simple(notes: 'c5:q d5', lyrics: 'la li'));
      double bottomOf(ScoreLayout l, String id) =>
          l.regions.firstWhere((r) => r.elementId == id).bounds.bottom;
      expect(bottomOf(with_, 'e0'), greaterThan(bottomOf(without, 'e0')));
    });

    test('hyphen dash drawn between hyphenated syllables', () {
      final plain = layoutOf(Score.simple(
        notes: 'c4:h d4:h',
        lyrics: 'twin kle',
      ));
      final hyphened = layoutOf(Score.simple(
        notes: 'c4:h d4:h',
        lyrics: 'twin- kle',
      ));
      final extra = hyphened.primitives.whereType<LinePrimitive>().length -
          plain.primitives.whereType<LinePrimitive>().length;
      expect(extra, 1);
      // The dash sits horizontally between the two anchors.
      final texts = textsOf(hyphened);
      final dash = hyphened.primitives.whereType<LinePrimitive>().firstWhere(
          (l) =>
              l.elementId == 'e0' && l.from.y == l.to.y && l.thickness == 0.1);
      expect(dash.from.x, greaterThan(texts[0].position.x));
      expect(dash.to.x, lessThan(texts[1].position.x));
    });

    test('extender line runs under the melisma', () {
      final score = Score.simple(
        notes: 'c4:q d4 e4 f4',
        lyrics: 'ah_ * * la',
      );
      final layout = layoutOf(score);
      final texts = textsOf(layout);
      final extender = layout.primitives.whereType<LinePrimitive>().firstWhere(
          (l) =>
              l.elementId == 'e0' && l.from.y == l.to.y && l.thickness == 0.1);
      // Along the shared baseline, ending under e2 (the last note without
      // its own syllable), before the 'la' on e3.
      expect(extender.from.y, texts.first.position.y);
      expect(extender.from.x, greaterThan(texts.first.position.x));
      final e2 = layout.regions.firstWhere((r) => r.elementId == 'e2').bounds;
      expect(extender.to.x, greaterThanOrEqualTo(e2.left));
      expect(extender.to.x, lessThan(texts.last.position.x));
    });

    test('no extender when the next note carries a syllable', () {
      final layout = layoutOf(Score.simple(
        notes: 'c4:q d4',
        lyrics: 'ah_ la',
      ));
      final extenders = layout.primitives.whereType<LinePrimitive>().where(
          (l) =>
              l.elementId == 'e0' && l.from.y == l.to.y && l.thickness == 0.1);
      expect(extenders, isEmpty);
    });

    test('unknown element id throws', () {
      final score = Score(
        clef: Clef.treble,
        measures: Score.simple(notes: 'c4:q').measures,
        lyrics: const [Lyric('nope', 'la')],
      );
      expect(() => layoutOf(score), throwsArgumentError);
    });

    test('a lyric on a rest id throws', () {
      final score = Score(
        clef: Clef.treble,
        measures: Score.simple(notes: 'c4:q r').measures,
        lyrics: const [Lyric('e1', 'la')],
      );
      expect(() => layoutOf(score), throwsArgumentError);
    });

    test('deterministic with lyrics', () {
      final score = Score.simple(
        notes: 'c4:q d4 e4 f4',
        lyrics: 'twin- kle lit- tle',
      );
      final a = layoutOf(score);
      final b = layoutOf(score);
      expect(a.primitives.toString(), b.primitives.toString());
    });

    test('layout without lyrics is unchanged by the feature', () {
      final layout = layoutOf(Score.simple(notes: 'c4:q d4 e4 f4'));
      expect(textsOf(layout), isEmpty);
    });
  });

  group('line breaking', () {
    test('each system keeps exactly its own syllables', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5 | c5:q b4 a4 g4 | c4:w',
        lyrics: 'one two three four five six sev- en eight nine ten e- lev',
      );
      final multi = layoutSystems(score, settings, maxWidth: 35);
      expect(multi.systems.length, greaterThan(1));
      final total = multi.systems
          .map((s) => textsOf(s.layout).length)
          .reduce((a, b) => a + b);
      expect(total, score.lyrics.length);
      // Syllables stay attached to their element ids.
      for (final system in multi.systems) {
        for (final text in textsOf(system.layout)) {
          final within =
              system.layout.regions.any((r) => r.elementId == text.elementId);
          expect(within, isTrue);
        }
      }
    });
  });

  group('geometry sanity', () {
    test('text anchors sit within the layout bounds', () {
      final layout = layoutOf(Score.simple(
        notes: 'c4:q d4 e4 f4',
        lyrics: 'do re mi fa',
      ));
      for (final text in textsOf(layout)) {
        expect(text.position.x, greaterThan(0));
        expect(text.position.x, lessThan(layout.width));
        expect(text.position.y, lessThan(layout.top + layout.height));
      }
      // Bounding box includes the lyric line.
      expect(layout.top + layout.height,
          greaterThan(max(6.5, 4.0) /* baseline floor */));
    });
  });
}
