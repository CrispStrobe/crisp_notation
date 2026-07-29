// test/copy_with_test.dart
//
// `copyWith` on the model's three big value types.
//
// The danger with a hand-written `copyWith` over a 44-field class is not that it
// is wrong today — it is that someone adds a field next month, the code still
// compiles, and every `copyWith` call silently drops it. So the first test here
// does not check behaviour at all: it READS THE SOURCE, pulls the constructor's
// parameter names and the copyWith's parameter names, and fails when they differ.
// That is the test that keeps working after we stop looking.

import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Named (and leading positional) parameter names of `class`'s constructor.
Set<String> _ctorParams(String source, String className) {
  final start = source.indexOf('class $className');
  final match = RegExp(
    '\\n  (?:const )?$className\\((.*?)\\n  \\}\\)',
    dotAll: true,
  ).firstMatch(source.substring(start));
  expect(match, isNotNull, reason: '$className constructor not found');
  final body = match!.group(1)!;
  return {
    for (final m in RegExp(r'(?:this|super)\.(\w+)').allMatches(body))
      m.group(1)!,
  };
}

/// Parameter names of `class`'s `copyWith`.
Set<String> _copyWithParams(String source, String className) {
  final start = source.indexOf('class $className');
  final match = RegExp(
    '\\n  $className copyWith\\(\\{(.*?)\\n  \\}\\)',
    dotAll: true,
  ).firstMatch(source.substring(start));
  expect(match, isNotNull, reason: '$className.copyWith not found');
  return {
    for (final m in RegExp(
      r'\n    [\w<>,\?\s]+? (\w+),',
    ).allMatches(match!.group(1)!))
      m.group(1)!,
  };
}

void main() {
  group('copyWith covers every constructor parameter', () {
    for (final (file, className) in const [
      ('lib/src/model/element.dart', 'NoteElement'),
      ('lib/src/model/measure.dart', 'Measure'),
      ('lib/src/model/score.dart', 'Score'),
      ('lib/src/model/score.dart', 'ScoreMetadata'),
    ]) {
      test(className, () {
        final source = File(file).readAsStringSync();
        final ctor = _ctorParams(source, className);
        final copy = _copyWithParams(source, className);
        expect(ctor, isNotEmpty);
        expect(
          ctor.difference(copy),
          isEmpty,
          reason: '$className.copyWith is missing parameters that the '
              'constructor has — a copyWith call would silently drop them',
        );
        expect(
          copy.difference(ctor),
          isEmpty,
          reason: '$className.copyWith has parameters the constructor does not',
        );
      });
    }
  });

  group('NoteElement', () {
    final note = NoteElement(
      pitches: const [Pitch(Step.c, octave: 3), Pitch(Step.e, octave: 3)],
      duration: NoteDuration.quarter,
      showAccidental: true,
      tieToNext: true,
      articulations: const {Articulation.staccato},
      graceNotes: const [Pitch(Step.d, octave: 3)],
      graceStyle: GraceStyle.appoggiatura,
      ornament: Ornament.trill,
      fingerings: const [2],
      arpeggio: Arpeggio.up,
      tremolo: 2,
      notehead: NoteheadShape.diamond,
      velocity: 90,
      id: 'n1',
    );

    test('an empty copyWith changes nothing', () {
      // Every field is set to a non-default above, so this catches a dropped
      // field as an inequality rather than as a silent default.
      expect(note.copyWith(), note);
    });

    test('one field changes, the rest survive', () {
      final fingered = note.copyWith(fingerings: const [kFingeringThumb]);
      expect(fingered.fingerings, const [kFingeringThumb]);
      expect(fingered.copyWith(fingerings: note.fingerings), note);
    });
  });

  group('Score', () {
    final score = Score.simple(
      notes: 'c4:q d4 e4 f4',
      lyrics: 'la la la la',
    ).copyWith(clef: Clef.bass, keySignature: const KeySignature(2));

    test('an empty copyWith changes nothing', () {
      expect(score.copyWith(), score);
    });

    test('replacing the measures keeps everything else', () {
      final shorter = score.copyWith(measures: [score.measures.first]);
      expect(shorter.measures, hasLength(1));
      expect(shorter.clef, Clef.bass);
      expect(shorter.keySignature.fifths, 2);
      expect(shorter.lyrics, score.lyrics);
    });

    test('a fingering written through the model reaches MusicXML', () {
      // The point of Score.copyWith for us: fingerings computed after the fact
      // can be written INTO a score, which is what an exported file needs (the
      // layout-only channel cannot reach a file).
      final fingered = score.copyWith(
        measures: [
          for (final measure in score.measures)
            measure.copyWith(
              elements: [
                for (final element in measure.elements)
                  element is NoteElement
                      ? element.copyWith(fingerings: const [3])
                      : element,
              ],
            ),
        ],
      );
      expect(scoreToMusicXml(fingered), contains('<fingering>3</fingering>'));
      expect(scoreToMusicXml(score), isNot(contains('<fingering>')));
    });
  });
}
