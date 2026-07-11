import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

Fraction f(int numerator, int denominator) => Fraction(numerator, denominator);

void main() {
  group('timeline basics', () {
    test('onsets and durations accumulate in whole-note fractions', () {
      final timeline = playbackTimeline(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4:e e4:e f4:h | g4:w',
      ));
      expect(timeline.map((n) => n.elementId), ['e0', 'e1', 'e2', 'e3', 'e4']);
      expect(timeline[0].start, f(0, 1));
      expect(timeline[0].duration, f(1, 4));
      expect(timeline[1].start, f(1, 4));
      expect(timeline[1].duration, f(1, 8));
      expect(timeline[2].start, f(3, 8));
      expect(timeline[3].start, f(1, 2));
      expect(timeline[3].duration, f(1, 2));
      // Measure 2 starts after one whole note.
      expect(timeline[4].start, f(1, 1));
      expect(timeline[4].measureIndex, 1);
    });

    test('rests are entries flagged isRest', () {
      final timeline = playbackTimeline(Score.simple(notes: 'c4:q r:q d4:h'));
      expect(timeline[1].isRest, isTrue);
      expect(timeline[1].duration, f(1, 4));
      expect(timeline[2].start, f(1, 2));
    });

    test('chords are one entry', () {
      final timeline = playbackTimeline(Score.simple(notes: 'c4+e4+g4:h g4:h'));
      expect(timeline, hasLength(2));
      expect(timeline[0].duration, f(1, 2));
    });

    test('dotted durations are exact', () {
      final timeline = playbackTimeline(Score.simple(notes: 'c4:q. d4:e'));
      expect(timeline[0].duration, f(3, 8));
      expect(timeline[1].start, f(3, 8));
    });

    test('tuplets use effective (scaled) durations', () {
      final timeline = playbackTimeline(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '3[c4:e d4 e4] f4:q c4:h',
      ));
      // Triplet eighths: each 1/12; the quarter starts at 1/4.
      expect(timeline[0].duration, f(1, 12));
      expect(timeline[1].start, f(1, 12));
      expect(timeline[2].start, f(1, 6));
      expect(timeline[3].start, f(1, 4));
    });

    test('tied notes stay separate entries', () {
      final timeline = playbackTimeline(Score.simple(notes: 'c4:h~ c4:h'));
      expect(timeline, hasLength(2));
      expect(timeline[0].end, timeline[1].start);
    });

    test('grace notes carry no separate time', () {
      final timeline = playbackTimeline(Score.simple(notes: '{g4}a4:q b4:q'));
      expect(timeline, hasLength(2));
      expect(timeline[1].start, f(1, 4));
    });
  });

  group('voices', () {
    test('voice 2 runs in parallel from the measure start', () {
      final timeline = playbackTimeline(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:q d5 e5 f5 ; c4:h e4:h | g5:w ; g4:w',
      ));
      final voice2 = timeline.where((n) => n.voice == 1).toList();
      expect(voice2[0].start, f(0, 1));
      expect(voice2[0].duration, f(1, 2));
      expect(voice2[1].start, f(1, 2));
      // Measure 2 aligns for both voices.
      final m2 = timeline.where((n) => n.measureIndex == 1);
      expect(m2.map((n) => n.start).toSet(), {f(1, 1)});
      // Same-onset sort puts voice 1 first.
      final atZero = timeline.where((n) => n.start == f(0, 1)).toList();
      expect(atZero.map((n) => n.voice), [0, 1]);
    });
  });

  group('repeats and voltas', () {
    test('a repeat segment plays twice', () {
      final timeline = playbackTimeline(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '!repeat c4:w !endrepeat | d4:w',
      ));
      expect(timeline.map((n) => n.elementId), ['e0', 'e0', 'e1']);
      expect(timeline.map((n) => n.start), [f(0, 1), f(1, 1), f(2, 1)]);
    });

    test('voltas pick their pass', () {
      final timeline = playbackTimeline(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '!repeat c4:w | !volta=1 d4:w !endrepeat | !volta=2 e4:w |'
            'f4:w',
      ));
      // Pass 1: c d; pass 2: c (skip volta 1) e; then f.
      expect(timeline.map((n) => n.elementId), ['e0', 'e1', 'e0', 'e2', 'e3']);
      expect(timeline.map((n) => n.start),
          [f(0, 1), f(1, 1), f(2, 1), f(3, 1), f(4, 1)]);
    });

    test('expandRepeats: false keeps document order', () {
      final timeline = playbackTimeline(
        Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: '!repeat c4:w !endrepeat | d4:w',
        ),
        expandRepeats: false,
      );
      expect(timeline.map((n) => n.elementId), ['e0', 'e1']);
    });

    test('empty measures advance by the current meter', () {
      final score = Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(3, 4),
        measures: [
          Measure(Score.simple(notes: 'c4:h.').measures.single.elements),
          Measure(const []),
          Measure(Score.simple(notes: 'd4:h.').measures.single.elements),
        ],
      );
      final timeline = playbackTimeline(score);
      expect(timeline.last.start, f(3, 2)); // 3/4 + 3/4
    });
  });

  group('navigation jumps', () {
    List<String> ids(String notes) =>
        playbackTimeline(Score.simple(notes: notes))
            .map((n) => n.elementId)
            .toList();

    test('D.C. replays the whole score once', () {
      expect(ids('c4:w | d4:w !nav=daCapo'), ['e0', 'e1', 'e0', 'e1']);
    });

    test('D.C. al Fine returns to the top and stops at Fine', () {
      expect(
        ids('c4:w | !nav=fine d4:w | e4:w !nav=daCapoAlFine'),
        ['e0', 'e1', 'e2', 'e0', 'e1'],
      );
    });

    test('Fine is inert until an al Fine jump arms it', () {
      // No al Fine instruction: the Fine mark is ignored, plays straight.
      expect(ids('c4:w | !nav=fine d4:w | e4:w'), ['e0', 'e1', 'e2']);
    });

    test('D.S. returns to the segno', () {
      expect(
        ids('c4:w | !nav=segno d4:w | e4:w !nav=dalSegno'),
        ['e0', 'e1', 'e2', 'e1', 'e2'],
      );
    });

    test('D.S. al Fine returns to the segno and stops at Fine', () {
      expect(
        ids('!nav=segno c4:w | !nav=fine d4:w | e4:w !nav=dalSegnoAlFine'),
        ['e0', 'e1', 'e2', 'e0', 'e1'],
      );
    });

    test('D.S. al Coda: segno, then To Coda jumps to the coda', () {
      expect(
        ids('!nav=segno c4:w | d4:w !nav=toCoda | e4:w !nav=dalSegnoAlCoda | '
            '!nav=coda f4:w'),
        ['e0', 'e1', 'e2', 'e0', 'e1', 'e3'],
      );
    });

    test('D.C. al Coda: top, then To Coda jumps to the coda', () {
      expect(
        ids('c4:w | d4:w !nav=toCoda | e4:w !nav=daCapoAlCoda | '
            '!nav=coda f4:w'),
        ['e0', 'e1', 'e2', 'e0', 'e1', 'e3'],
      );
    });

    test('To Coda is inert until an al Coda jump arms it', () {
      expect(ids('c4:w !nav=toCoda | !nav=coda d4:w'), ['e0', 'e1']);
    });

    test('a jump instruction fires only once (terminates)', () {
      // The D.S. is encountered twice but only jumps the first time.
      final timeline = ids('!nav=segno c4:w | d4:w !nav=dalSegno | e4:w');
      expect(timeline, ['e0', 'e1', 'e0', 'e1', 'e2']);
    });

    test('D.S. with no segno throws', () {
      expect(
        () =>
            playbackTimeline(Score.simple(notes: 'c4:w | d4:w !nav=dalSegno')),
        throwsArgumentError,
      );
    });

    test('al Coda with no coda target throws', () {
      expect(
        () => playbackTimeline(Score.simple(
            notes: 'c4:w | d4:w !nav=toCoda | e4:w !nav=daCapoAlCoda')),
        throwsArgumentError,
      );
    });

    test('expandRepeats: false ignores navigation marks', () {
      final timeline = playbackTimeline(
        Score.simple(notes: 'c4:w | d4:w !nav=daCapo'),
        expandRepeats: false,
      );
      expect(timeline.map((n) => n.elementId), ['e0', 'e1']);
    });

    test('start times are continuous across a jump', () {
      final timeline =
          playbackTimeline(Score.simple(notes: 'c4:w | d4:w !nav=daCapo'));
      expect(
          timeline.map((n) => n.start), [f(0, 1), f(1, 1), f(2, 1), f(3, 1)]);
    });
  });

  group('helpers', () {
    test('secondsFor maps whole notes to seconds at a quarter BPM', () {
      expect(secondsFor(f(1, 4), quarterBpm: 60), 1.0);
      expect(secondsFor(f(1, 1), quarterBpm: 120), 2.0);
      expect(secondsFor(f(3, 8), quarterBpm: 90), closeTo(1.0, 1e-9));
    });

    test('soundingAt returns ids under the cursor, rests excluded', () {
      final timeline = playbackTimeline(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:h r:q d5:q ; c4:w',
      ));
      expect(soundingAt(timeline, f(0, 1)), {'e0', 'e3'});
      expect(soundingAt(timeline, f(1, 4)), {'e0', 'e3'});
      expect(soundingAt(timeline, f(1, 2)), {'e3'}); // rest in voice 1
      expect(soundingAt(timeline, f(3, 4)), {'e2', 'e3'});
      expect(soundingAt(timeline, f(1, 1)), isEmpty); // past the end
    });

    test('value semantics of PlaybackNote', () {
      final a = playbackTimeline(Score.simple(notes: 'c4:q')).single;
      final b = playbackTimeline(Score.simple(notes: 'c4:q')).single;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('timeline of an imported MusicXML score works end to end', () {
      final score = scoreFromMusicXml(scoreToMusicXml(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | g4:w',
      )));
      final timeline = playbackTimeline(score);
      expect(timeline, hasLength(5));
      expect(timeline.last.start, f(1, 1));
    });
  });
}
