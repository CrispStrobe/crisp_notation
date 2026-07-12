import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

late final SmuflMetadata metadata;
late final LayoutSettings settings;

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

  group('model and DSL', () {
    test('!mrest=N parses to Measure.multiRest', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:w | !mrest=8 | d4:w',
      );
      expect(score.measures[1].multiRest, 8);
      expect(score.measures[1].elements, isEmpty);
    });

    test('!mrest with notes throws; mrest < 2 throws', () {
      expect(() => Score.simple(notes: '!mrest=4 c4:q'), throwsFormatException);
      expect(() => Score.simple(notes: '!mrest=1'), throwsFormatException);
    });

    test('multiRest participates in equality', () {
      expect(Score.simple(notes: 'c4:w | !mrest=4'),
          isNot(Score.simple(notes: 'c4:w | !mrest=5')));
    });
  });

  group('layout', () {
    test('draws the H-bar with end caps and the count above', () {
      final layout = layoutOf(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:w | !mrest=12 | d4:w',
      ));
      // The thick middle-line bar.
      final bar = layout.primitives.whereType<LinePrimitive>().firstWhere(
          (l) => l.thickness == 0.5 && l.from.y == 2 && l.to.y == 2);
      // Two vertical end caps at the bar's ends.
      final caps = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) =>
              l.from.x == l.to.x &&
              (l.from.x == bar.from.x || l.from.x == bar.to.x) &&
              l.from.y == 1 &&
              l.to.y == 3)
          .toList();
      expect(caps, hasLength(2));
      // Digits 1 and 2 above the staff.
      final digits = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName.startsWith('timeSig'))
          .where((g) => g.position.y < 0)
          .toList();
      expect(digits.map((g) => g.smuflName),
          [SmuflGlyph.timeSigDigit(1), SmuflGlyph.timeSigDigit(2)]);
      // The measure region spans the bar.
      final region = layout.measureRegions[1];
      expect(region.startX, lessThan(bar.from.x));
      expect(region.endX, greaterThan(bar.to.x));
    });

    test('deterministic and layout-safe inside systems', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | !mrest=4 | g4:q a4 b4 c5 | c4:w',
      );
      expect(layoutOf(score).primitives.toString(),
          layoutOf(score).primitives.toString());
      final multi = layoutSystems(score, settings, maxWidth: 30);
      final total =
          multi.systems.map((s) => s.layout.measureRegions.length).reduce(
                (a, b) => a + b,
              );
      expect(total, 4);
    });
  });

  group('playback', () {
    test('a multi-rest advances N measures of time', () {
      final timeline = playbackTimeline(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:w | !mrest=8 | d4:w',
      ));
      expect(timeline, hasLength(2));
      expect(timeline.last.start, Fraction(9, 1)); // 1 + 8 whole notes
    });
  });

  group('MusicXML', () {
    test('multi-rest round trips via measure-style', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:w | !mrest=6 | d4:w',
      );
      final xml = scoreToMusicXml(score);
      expect(xml, contains('<multiple-rest>6</multiple-rest>'));
      expect(scoreFromMusicXml(xml), score);
    });
  });
}
