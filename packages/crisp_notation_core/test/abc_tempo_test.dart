import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A `Q:` used to be VISIBLE and INAUDIBLE.
///
/// The reader rendered it as a text annotation — which is what the layout
/// draws, since nothing in it draws [Tempo] — but never set `Score.tempo`, and
/// the writer emitted no `Q:` at all. So an imported ABC tune printed its
/// metronome mark and then played at the default tempo, and an export dropped
/// the mark entirely.
void main() {
  Score read(String q) =>
      scoreFromAbc('X:1\n${q.isEmpty ? '' : '$q\n'}L:1/4\nK:C\nC D E F|\n');

  group('Q: reaches the model', () {
    test('a plain metronome mark', () {
      expect(read('Q:1/4=120').tempo, const Tempo(120));
    });

    test('a bare number is a quarter, which is what ABC says it is', () {
      expect(read('Q:120').tempo, const Tempo(120));
    });

    test('a labelled mark keeps the mark', () {
      expect(read('Q:"Allegro" 1/4=120').tempo, const Tempo(120));
    });

    test('3/8 is a DOTTED QUARTER, not three eighths', () {
      // Three eighths is not a beat unit the model can name, and rounding it
      // to an eighth would make the piece three times too fast.
      final t = read('Q:3/8=60').tempo!;
      expect(t.beatUnit, DurationBase.quarter);
      expect(t.dots, 1);
      expect(t.quarterBpm, 90);
    });

    test('no Q: sets no tempo', () {
      expect(read('').tempo, isNull);
    });
  });

  group('the printed mark is unchanged', () {
    test('the display annotation still says what it always said', () {
      expect(read('Q:1/4=120').annotations.map((a) => a.text), ['♩ = 120']);
      expect(read('Q:"Allegro" 1/4=120').annotations.map((a) => a.text),
          ['Allegro ♩ = 120']);
    });
  });

  group('the writer emits Q: without printing the mark twice', () {
    String qLine(String q) => scoreToAbc(read(q))
        .split('\n')
        .firstWhere((l) => l.startsWith('Q:'), orElse: () => '');

    test('a tempo becomes a Q: field', () {
      expect(qLine('Q:1/4=120'), 'Q:1/4=120');
      expect(qLine('Q:3/8=60'), 'Q:3/8=60');
    });

    test('a bare number is normalised to the explicit form', () {
      expect(qLine('Q:120'), 'Q:1/4=120');
    });

    test('the label survives the round trip through Q:', () {
      // `Tempo` cannot hold the label, so it rides in the Q: field itself
      // rather than being left behind in the annotation.
      expect(qLine('Q:"Allegro" 1/4=120'), 'Q:"Allegro" 1/4=120');
    });

    test('the derived annotation is NOT also written into the body', () {
      // It is regenerated on the next read; writing it too would print the
      // metronome mark twice, once from Q: and once as body text.
      final abc = scoreToAbc(read('Q:1/4=120'));
      expect(abc, isNot(contains('"♩ = 120"')));
      expect(abc, isNot(contains(r'"^♩ = 120"')));
    });

    test('an ordinary annotation on the first note is NOT suppressed', () {
      final s = scoreFromAbc('X:1\nQ:1/4=120\nL:1/4\nK:C\n"^rit."C D E F|\n');
      final abc = scoreToAbc(s);
      expect(abc, contains('Q:1/4=120'));
      expect(abc, contains('rit.'));
    });

    test('a score with no tempo writes no Q:', () {
      expect(qLine(''), '');
    });
  });

  _multipleAnnotationsTest();

  test('tempo and annotations are both stable over a round trip', () {
    for (final q in [
      'Q:1/4=120',
      'Q:"Allegro" 1/4=120',
      'Q:3/8=60',
      'Q:120',
      '',
    ]) {
      final once = read(q);
      final twice = scoreFromAbc(scoreToAbc(once));
      expect(twice.tempo, once.tempo, reason: q);
      expect(twice.annotations.map((a) => a.text),
          once.annotations.map((a) => a.text),
          reason: q);
    }
  });
}

void _multipleAnnotationsTest() {
  test('a note carrying SEVERAL annotations keeps them all', () {
    // The writer's map was keyed id -> String, so a second annotation on the
    // same note overwrote the first. A note with both a tempo mark and a
    // direction on it is the ordinary case that makes it visible.
    final s = Score(
      clef: Clef.treble,
      measures: [
        Measure(<MusicElement>[
          NoteElement(
              id: 'e0',
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.quarter)),
        ]),
      ],
      annotations: const [
        Annotation('e0', 'rit.'),
        Annotation('e0', 'dolce'),
      ],
    );
    final back = scoreFromAbc(scoreToAbc(s));
    expect(back.annotations.map((a) => a.text), ['rit.', 'dolce']);
  });
}
