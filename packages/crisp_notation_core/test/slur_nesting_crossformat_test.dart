import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Slurs of every shape, in all six formats.
///
/// ⚠️ `(` and `)` carry no identity of their own, so a format that marks slurs
/// with them alone cannot say WHICH slur a mark belongs to. Two failure modes,
/// both silent and both found here: a NESTED pair lost its outer slur (the
/// inner close consumed the outer start), and a CHAIN sharing a boundary note
/// collapsed to a slur from that note to itself.
///
/// Both formats provide the answer and neither was using it — kern's `&(`/`&)`
/// and LilyPond's `\=1(`/`\=1)`. Levels are assigned by [slurLevels] on STRICT
/// overlap only: merely touching needs no number, because every reader takes
/// the closes in a token before the opens.
///
/// MuseScore failed differently and more sharply: it STATES the distance to
/// each slur's end and the reader was pairing starts to ends by document
/// position instead, which crosses a nested pair outright (`e0-e3` around
/// `e1-e2` read back as `e0-e2` and `e1-e3`).
void main() {
  List<MusicElement> bar(int base) => [
        for (var i = 0; i < 4; i++)
          NoteElement(
            id: 'e${base + i}',
            pitches: [Pitch(Step.values[i % 7], octave: 4)],
            duration: const NoteDuration(DurationBase.quarter),
          ),
      ];

  final hops = <String, Score Function(Score)>{
    'musicxml': (x) => scoreFromMusicXml(scoreToMusicXml(x)),
    'mei': (x) => scoreFromMei(scoreToMei(x)),
    'kern': (x) => scoreFromKern(scoreToKern(x)),
    'abc': (x) => scoreFromAbc(scoreToAbc(x)),
    'lilypond': (x) => scoreFromLilyPond(scoreToLilyPond(x)),
    'musescore': (x) => scoreFromMscx(scoreToMscx(x)),
  };

  final shapes = <String, List<Slur>>{
    'within one bar': [const Slur('e0', 'e2')],
    'across the barline': [const Slur('e2', 'e5')],
    'the whole piece': [const Slur('e0', 'e7')],
    'nested': [const Slur('e0', 'e3'), const Slur('e1', 'e2')],
    // ⚠️ ABC cannot express this one. Its `(` precedes the first note and `)`
    // follows the last, so a note that is BOTH the last of one slur and the
    // first of the next would need a mark on either side of itself and the two
    // merge into one long slur. A true format limit, not a defect: unlike kern
    // and LilyPond, ABC has no numbered slur to fall back on.
    'chained on a shared boundary note': [
      const Slur('e0', 'e2'),
      const Slur('e2', 'e5'),
    ],
  };

  for (final shape in shapes.entries) {
    for (final e in hops.entries) {
      if (e.key == 'abc' && shape.key.startsWith('chained')) continue;
      test('${e.key}: ${shape.key}', () {
        final score = Score(
          clef: Clef.treble,
          timeSignature: const TimeSignature(4, 4),
          measures: [Measure(bar(0)), Measure(bar(4))],
          slurs: shape.value,
        );
        String key(Iterable<Slur> ss) =>
            (ss.map((s) => '${s.startId}-${s.endId}').toList()..sort())
                .join(',');
        expect(key(e.value(score).slurs), key(shape.value), reason: e.key);
      });
    }
  }

  test('a chain needs no numbered slur — close before open resolves it', () {
    final score = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [Measure(bar(0)), Measure(bar(4))],
      slurs: const [Slur('e0', 'e2'), Slur('e2', 'e5')],
    );
    expect(slurLevels(score), [0, 0]);
    expect(scoreToLilyPond(score), contains(')('));
  });

  test('a nested pair DOES need one', () {
    final score = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [Measure(bar(0))],
      slurs: const [Slur('e0', 'e3'), Slur('e1', 'e2')],
    );
    expect(slurLevels(score), [0, 1]);
    expect(scoreToLilyPond(score), contains(r'\=1('));
    expect(scoreToKern(score), contains('&('));
  });
}
