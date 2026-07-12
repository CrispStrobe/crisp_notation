import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Phase 2.4: pickup (anacrusis) measures + anacrusis-aware measure numbering.
void main() {
  group('detection', () {
    test('a short opening bar under a known meter is a pickup', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'g4:q | c5:q d5 e5 f5 | g5:w',
      );
      expect(score.measures[0].pickup, isTrue);
      expect(score.measures[1].pickup, isFalse);
      expect(score.measures[2].pickup, isFalse);
    });

    test('a full opening bar is not a pickup', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:q d5 e5 f5 | g5:w',
      );
      expect(score.measures.every((m) => !m.pickup), isTrue);
    });

    test('no meter → no detection', () {
      final score = Score.simple(notes: 'g4:q | c5:q d5 e5 f5');
      expect(score.measures[0].pickup, isFalse);
    });

    test('a single short measure is not a pickup', () {
      final score =
          Score.simple(timeSignature: TimeSignature.fourFour, notes: 'g4:q');
      expect(score.measures.single.pickup, isFalse);
    });

    test('ABC import flags a short opening bar', () {
      final score = scoreFromAbc('X:1\nM:4/4\nL:1/4\nK:C\nG|c d e f|g4|\n');
      expect(score.measures[0].pickup, isTrue);
      expect(score.measures[0].totalDuration, Fraction(1, 4));
      expect(score.measures[1].pickup, isFalse);
    });
  });

  group('interchange', () {
    Score pickupScore() => Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: 'g4:q | c5:q d5 e5 f5 | g5:w',
        );

    test('MusicXML writes the pickup as implicit and renumbers', () {
      final xml = scoreToMusicXml(pickupScore());
      expect(xml, contains('<measure number="0" implicit="yes">'));
      expect(xml, contains('<measure number="1">'));
      expect(xml, contains('<measure number="2">'));
      expect(xml, isNot(contains('<measure number="3">')));
    });

    test('MusicXML round-trips the pickup flag', () {
      final score = pickupScore();
      final back = scoreFromMusicXml(scoreToMusicXml(score));
      expect(back, score);
      expect(back.measures[0].pickup, isTrue);
    });

    test('ABC round-trips the pickup (re-detected from the short bar)', () {
      final score = scoreFromAbc('X:1\nM:4/4\nL:1/4\nK:C\nG|c d e f|g4|\n');
      final back = scoreFromAbc(scoreToAbc(score));
      expect(back.measures[0].pickup, isTrue);
    });

    test('transposedBy keeps the pickup flag', () {
      final up = pickupScore().transposedBy(Interval.majorSecond);
      expect(up.measures[0].pickup, isTrue);
      expect(up.measures[1].pickup, isFalse);
    });
  });

  group('measure numbering overlay', () {
    late final LayoutSettings settings;
    setUpAll(() {
      final meta = SmuflMetadata.fromJson(jsonDecode(
          File('../partitura/assets/smufl/bravura_metadata.json')
              .readAsStringSync()) as Map<String, Object?>);
      settings = LayoutSettings(metadata: meta);
    });

    List<String> numbers(Score score) => (const LayoutEngine())
        .layout(score, settings, showMeasureNumbers: true)
        .primitives
        .whereType<TextPrimitive>()
        .map((t) => t.text)
        .toList();

    test('off by default', () {
      final score = Score.simple(
          timeSignature: TimeSignature.fourFour, notes: 'c5:q d5 e5 f5 | g5:w');
      final texts = (const LayoutEngine())
          .layout(score, settings)
          .primitives
          .whereType<TextPrimitive>();
      expect(texts, isEmpty);
    });

    test('numbers every measure from 1', () {
      final score = Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: 'c5:q d5 e5 f5 | g5:w | a5:w');
      expect(numbers(score), ['1', '2', '3']);
    });

    test('a pickup is unnumbered; the first full bar reads 1', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'g4:q | c5:q d5 e5 f5 | g5:w',
      );
      expect(numbers(score), ['1', '2']);
    });
  });
}
