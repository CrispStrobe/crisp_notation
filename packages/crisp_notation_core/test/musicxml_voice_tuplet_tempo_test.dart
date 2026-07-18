// MusicXML roundtrip regressions in two gaps the 150-score property suite
// doesn't generate (voice-2+ tuplets, and a tempo change without an initial
// tempo). Both were silent corruption of a saved score on reopen.

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

NoteElement _n(Step s, NoteDuration d) =>
    NoteElement(pitches: [Pitch(s, octave: 4)], duration: d);

const _q = NoteDuration(DurationBase.quarter);
const _e = NoteDuration(DurationBase.eighth);
const _h = NoteDuration(DurationBase.half);

void main() {
  test('voice-2 tuplet roundtrips without corrupting voice 1', () {
    // Voice 1: four quarters (a full 4/4). Voice 2: an eighth-note triplet
    // (3 eighths in the time of 2) + a dotted-half rest → also 4/4.
    final measure = Measure(
      [_n(Step.c, _q), _n(Step.d, _q), _n(Step.e, _q), _n(Step.f, _q)],
      voice2: [
        _n(Step.g, _e),
        _n(Step.a, _e),
        _n(Step.b, _e),
        RestElement(const NoteDuration(DurationBase.half, dots: 1)),
      ],
      tuplets: const [TupletSpan(0, 2, actual: 3, normal: 2, voice: 1)],
    );
    final score = Score(clef: Clef.treble, measures: [measure]);

    final back = scoreFromMusicXml(scoreToMusicXml(score));
    final m = back.measures.first;

    Fraction totalOf(int voice, int count) {
      var f = Fraction(0, 1);
      for (var i = 0; i < count; i++) {
        f = f + m.effectiveDurationAt(i, voice: voice);
      }
      return f;
    }

    // Voice 1 stays four plain quarters = 4/4; voice 2's triplet is preserved.
    expect(totalOf(0, 4), Fraction(1, 1), reason: 'voice 1 rhythm intact');
    expect(m.tupletsForVoice(0), isEmpty,
        reason: 'no tuplet leaked to voice 1');
    expect(m.tupletsForVoice(1), hasLength(1),
        reason: 'voice 2 keeps its triplet');
    expect(totalOf(1, 4), Fraction(1, 1), reason: 'voice 2 rhythm intact');
  });

  test('a tempo change with no initial tempo stays on its measure', () {
    final score = Score(
      clef: Clef.treble,
      // No initial tempo; a change takes effect on measure 1 (the 2nd bar).
      measures: [
        Measure([_n(Step.c, _h), _n(Step.d, _h)]),
        Measure(
          [_n(Step.e, _h), _n(Step.f, _h)],
          tempoChange: const Tempo(120),
        ),
      ],
    );

    final back = scoreFromMusicXml(scoreToMusicXml(score));
    expect(back.tempo, isNull, reason: 'no initial tempo invented');
    expect(back.measures[0].tempoChange, isNull);
    expect(back.measures[1].tempoChange, const Tempo(120),
        reason: 'the change stays on bar 2');
  });

  test('a real initial tempo still round-trips as the initial', () {
    final score = Score(
      clef: Clef.treble,
      tempo: const Tempo(90),
      measures: [
        Measure([_n(Step.c, _h), _n(Step.d, _h)]),
        Measure(
          [_n(Step.e, _h), _n(Step.f, _h)],
          tempoChange: const Tempo(140),
        ),
      ],
    );
    final back = scoreFromMusicXml(scoreToMusicXml(score));
    expect(back.tempo, const Tempo(90));
    expect(back.measures[1].tempoChange, const Tempo(140));
  });
}
