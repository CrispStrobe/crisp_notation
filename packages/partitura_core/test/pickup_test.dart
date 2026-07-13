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

    test('measureNumberInterval labels bar 1 and every Nth (2.7)', () {
      final score = Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: 'c5:w | c5:w | c5:w | c5:w | c5:w | c5:w');
      List<String> at(int n) => (const LayoutEngine())
          .layout(score, settings,
              showMeasureNumbers: true, measureNumberInterval: n)
          .primitives
          .whereType<TextPrimitive>()
          .map((t) => t.text)
          .toList();
      expect(at(5), ['1', '5']); // first + every 5th
      expect(at(2), ['1', '2', '4', '6']); // first + every even bar
      expect(at(1), ['1', '2', '3', '4', '5', '6']); // default = every bar
    });

    test('a pickup is unnumbered; the first full bar reads 1', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'g4:q | c5:q d5 e5 f5 | g5:w',
      );
      expect(numbers(score), ['1', '2']);
    });
  });

  group('Score.barNumberAt (C9)', () {
    test('numbers full bars from 1', () {
      final score = Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: 'c5:q d5 e5 f5 | g5:w | a5:w');
      expect([for (var i = 0; i < 3; i++) score.barNumberAt(i)], [1, 2, 3]);
    });

    test('a pickup is null; the first full bar reads 1', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'g4:q | c5:q d5 e5 f5 | g5:w',
      );
      expect(score.barNumberAt(0), isNull); // pickup
      expect(score.barNumberAt(1), 1);
      expect(score.barNumberAt(2), 2);
    });

    test('agrees with the overlay and the MEI writer', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'g4:q | c5:q d5 e5 f5 | g5:w | a5:w',
      );
      // Non-null bar numbers, in order, match the overlay labels.
      final fromHelper = [
        for (var i = 0; i < score.measures.length; i++)
          if (score.barNumberAt(i) case final n?) '$n',
      ];
      expect(fromHelper, ['1', '2', '3']);
      // The MEI writer stamps the same numbers (pickup as n="0").
      final mei = scoreToMei(score);
      expect(mei, contains('<measure n="0"')); // the pickup
      expect(mei, contains('<measure n="1"'));
      expect(mei, contains('<measure n="3"'));
    });
  });

  group('explicit actual-vs-nominal length (irregular bars)', () {
    test('capacityGiven prefers the explicit actualDuration over the meter', () {
      final regular = Measure([
        NoteElement.note(const Pitch(Step.c), NoteDuration.quarter),
      ]);
      expect(regular.capacityGiven(TimeSignature.fourFour), Fraction(1, 1));
      // An inserted 5/4 bar in a 4/4 piece, without a meter change.
      final irregular = Measure([
        NoteElement.note(const Pitch(Step.c), NoteDuration.whole),
      ], actualDuration: Fraction(5, 4));
      expect(irregular.capacityGiven(TimeSignature.fourFour), Fraction(5, 4));
      // Unmetered and unset → null.
      expect(regular.capacityGiven(null), isNull);
    });

    test('equality and copyWith carry actualDuration', () {
      final a = Measure(const [], actualDuration: Fraction(3, 8));
      expect(a, Measure(const [], actualDuration: Fraction(3, 8)));
      expect(a, isNot(Measure(const [], actualDuration: Fraction(5, 8))));
      expect(a.copyWith(pickup: true).actualDuration, Fraction(3, 8));
    });

    test('an explicitly-sized opening bar is not auto-detected as a pickup', () {
      // Short first bar that would normally be flagged a pickup, but its
      // explicit actual length marks it intentional.
      final measures = withDetectedPickup([
        Measure([
          NoteElement.note(const Pitch(Step.c), NoteDuration.quarter),
        ], actualDuration: Fraction(1, 4)),
        Measure([
          NoteElement.note(const Pitch(Step.d), NoteDuration.whole),
        ]),
      ], TimeSignature.fourFour);
      expect(measures.first.pickup, isFalse);
    });
  });
}
