import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  group('Score.transposedBy', () {
    test('moves every pitch, both voices, chords and grace notes', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '{b3}c4:q e4+g4:h d4:q ; c3:w',
      );
      final up = score.transposedBy(Interval.majorSecond);
      final melody = up.measures.single.elements.cast<NoteElement>();
      expect(melody[0].pitches.single, const Pitch(Step.d));
      expect(melody[0].graceNotes.single,
          const Pitch(Step.c, alter: 1, octave: 4));
      expect(melody[1].pitches,
          [const Pitch(Step.f, alter: 1), const Pitch(Step.a)]);
      expect(melody[2].pitches.single, const Pitch(Step.e));
      expect(
        (up.measures.single.voice2.single as NoteElement).pitches.single,
        const Pitch(Step.d, octave: 3),
      );
    });

    test('descending transposition', () {
      final down = Score.simple(notes: 'd4:q')
          .transposedBy(Interval.majorSecond, descending: true);
      expect(
        (down.measures.single.elements.single as NoteElement).pitches.single,
        const Pitch(Step.c),
      );
    });

    test('rhythm, ids, spans, lyrics and structure are untouched', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '!repeat c4:q( d4) 3[e4:e f4 g4] a4:q~ !endrepeat | a4:w',
        lyrics: 'la li lu * * la_ *',
      );
      final up = score.transposedBy(Interval.perfectFourth);
      expect(up.slurs, score.slurs);
      expect(up.lyrics, score.lyrics);
      expect(up.timeSignature, score.timeSignature);
      expect(up.measures[0].tuplets, score.measures[0].tuplets);
      expect(up.measures[0].startRepeat, isTrue);
      expect(
        up.measures[0].elements.map((e) => e.id),
        score.measures[0].elements.map((e) => e.id),
      );
      expect(
        up.measures[0].elements.map((e) => e.duration),
        score.measures[0].elements.map((e) => e.duration),
      );
      final tied = up.measures[0].elements.last as NoteElement;
      expect(tied.tieToNext, isTrue);
    });

    test('key signature follows the transposition', () {
      Score inKey(int fifths) => Score.simple(
            keySignature: KeySignature(fifths),
            notes: 'c4:q',
          );
      // C -> D major.
      expect(inKey(0).transposedBy(Interval.majorSecond).keySignature,
          const KeySignature(2));
      // G -> C major (down a fifth = up a fourth).
      expect(inKey(1).transposedBy(Interval.perfectFourth).keySignature,
          const KeySignature(0));
      // F -> Eb major, descending M2.
      expect(
          inKey(-1)
              .transposedBy(Interval.majorSecond, descending: true)
              .keySignature,
          const KeySignature(-3));
      // A (3 sharps) up a minor third -> C major.
      expect(inKey(3).transposedBy(Interval.minorThird).keySignature,
          const KeySignature(0));
    });

    test('out-of-range keys wrap enharmonically', () {
      // F# major (6 sharps) up a major second would be G# major
      // (8 sharps) -> written as Ab major (4 flats).
      final up = Score.simple(
        keySignature: const KeySignature(6),
        notes: 'f#4:q',
      ).transposedBy(Interval.majorSecond);
      expect(up.keySignature, const KeySignature(-4));
    });

    test('mid-score key changes transpose too', () {
      final score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:w | !key=1 g4:w',
      );
      final up = score.transposedBy(Interval.majorSecond);
      expect(up.measures[1].keyChange, const KeySignature(3));
    });

    test('unison round trip is identity', () {
      final score = Score.simple(
        keySignature: const KeySignature(-2),
        timeSignature: TimeSignature.fourFour,
        notes: 'bb3:q c4 d4 eb4',
        annotations: 'Bb * * *',
      );
      expect(score.transposedBy(Interval.perfectUnison), score);
    });

    test('preserves notehead shapes, barline styles and jazz marks', () {
      final base = Score.simple(notes: 'c4:q d4');
      final score = Score(
        clef: base.clef,
        measures: [
          Measure(
            [
              NoteElement.note(
                  const Pitch(Step.c, octave: 4), NoteDuration.quarter,
                  notehead: NoteheadShape.diamond, id: 'e0'),
              NoteElement.note(
                  const Pitch(Step.d, octave: 4), NoteDuration.quarter,
                  id: 'e1'),
            ],
            barline: BarlineStyle.doubleBar,
          ),
        ],
        jazzMarks: const [JazzMark('e0', JazzArticulation.scoop)],
      );
      final up = score.transposedBy(Interval.majorSecond);
      final note0 = up.measures.single.elements.first as NoteElement;
      expect(note0.notehead, NoteheadShape.diamond);
      expect(up.measures.single.barline, BarlineStyle.doubleBar);
      expect(up.jazzMarks, const [JazzMark('e0', JazzArticulation.scoop)]);
    });

    test('up then down a fifth is identity', () {
      final score = Score.simple(
        keySignature: const KeySignature(1),
        notes: 'g4:q( a4 b4) d5',
        lyrics: 'so la ti re',
      );
      final roundTrip = score
          .transposedBy(Interval.perfectFifth)
          .transposedBy(Interval.perfectFifth, descending: true);
      expect(roundTrip, score);
    });

    test('transposed scores lay out and round-trip MusicXML', () {
      final score = Score.simple(
        keySignature: const KeySignature(0),
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q e4 g4 c5',
      ).transposedBy(Interval.minorThird);
      expect(scoreFromMusicXml(scoreToMusicXml(score)), score);
      expect(playbackTimeline(score), hasLength(4));
    });
  });
}
