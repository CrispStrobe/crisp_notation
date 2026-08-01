import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// `\tempo` was WRITE-ONLY: the writer had always emitted it and the reader
/// had no case for it at all, so every LilyPond file in the corpus lost its
/// tempo on import.
///
/// A round trip of our own output cannot see a write-only field unless
/// something compares it, and nothing did — the cross-format signature checks
/// notes, and under `--rich` the mark channels, but never `Score.tempo`.
void main() {
  Score read(String body) =>
      scoreFromLilyPond('\\score { \\new Staff { $body } \\layout {} }');

  group('reads a tempo mark', () {
    test('bare', () {
      final s = read(r'\tempo 4 = 96 c4 d4 e4 f4');
      expect(s.tempo?.bpm, 96);
      expect(s.tempo?.beatUnit, DurationBase.quarter);
      expect(s.tempo?.dots, 0);
    });

    test('with a text label, where the mark is a SIBLING not an argument', () {
      // The parser's sibling split: the label takes the argument slot, so the
      // `4 = 96` assignment lands as the next node instead.
      final s = read(r'\tempo "Allegro" 4 = 96 c4 d4 e4 f4');
      expect(s.tempo?.bpm, 96);
      expect(s.tempo?.beatUnit, DurationBase.quarter);
    });

    test('a dotted beat unit keeps its dot', () {
      // A dotted quarter at 60 is not a quarter at 60 — dropping the dot makes
      // the piece half again too slow.
      final s = read(r'\tempo 4. = 60 c4 d4 e4 f4');
      expect(s.tempo?.beatUnit, DurationBase.quarter);
      expect(s.tempo?.dots, 1);
      expect(s.tempo?.quarterBpm, 90);
    });

    test('a half-note beat unit', () {
      final s = read(r'\tempo 2 = 40 c4 d4 e4 f4');
      expect(s.tempo?.beatUnit, DurationBase.half);
      expect(s.tempo?.quarterBpm, 80);
    });

    test('a label alone sets no metronome mark', () {
      // `\tempo "Andante"` states no bpm, and inventing one would be worse
      // than leaving it unset.
      expect(read(r'\tempo "Andante" c4 d4 e4 f4').tempo, isNull);
    });

    test('a later mark is a measure tempo change, not the initial tempo', () {
      final s = read(r'\time 4/4 c4 d4 e4 f4 | \tempo 2 = 40 g4 a4 b4 c4');
      expect(s.tempo, isNull);
      expect(s.measures[1].tempoChange?.bpm, 40);
      expect(s.measures[0].tempoChange, isNull);
    });

    test('notes are unaffected', () {
      expect(read(r'\tempo 4 = 96 c4 d4 e4 f4').measures.single.elements,
          hasLength(4));
    });
  });

  test('a tempo survives a round trip', () {
    final s = Score(
      clef: Clef.treble,
      tempo: const Tempo(96, beatUnit: DurationBase.quarter, dots: 1),
      measures: [
        Measure(<MusicElement>[
          NoteElement(
              id: 'e0',
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.quarter)),
        ]),
      ],
    );
    final back = scoreFromLilyPond(scoreToLilyPond(s));
    expect(back.tempo?.quarterBpm, s.tempo!.quarterBpm);
  });
}
