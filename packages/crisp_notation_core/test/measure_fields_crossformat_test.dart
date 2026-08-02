import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Pickup bars and mid-score tempo changes, across every codec.
///
/// Both were carried by MusicXML alone. `Measure` has 20 fields and the
/// cross-format signature compared 8, so neither was ever checked — the same
/// blindness that hid chord symbols at score level and the forced accidental at
/// note level.
void main() {
  List<MusicElement> ns(int n) => [
        for (var i = 0; i < n; i++)
          NoteElement(
            id: 'e$i',
            pitches: const [Pitch(Step.c, octave: 4)],
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

  for (final e in hops.entries) {
    test('${e.key} keeps a pickup bar flagged as one', () {
      // LilyPond wrote `\partial` and its reader used it to preload elapsed
      // time — the anacrusis landed in the right place and then lost the flag
      // saying it WAS one, so the writer could not mark it again.
      final back = e.value(Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [Measure(ns(1), pickup: true), Measure(ns(4))],
      ));
      expect(back.measures.first.pickup, isTrue, reason: e.key);
      expect(back.measures[1].pickup, isFalse, reason: e.key);
    });

    test('${e.key} carries a mid-score tempo change', () {
      // ⚠️ ABC is excluded: its mid-tune `Q:` is injected into the body TEXT
      // stream as an annotation, so it has no measure to attach to at read
      // time. Scoped on the board.
      if (e.key == 'abc') return;
      final back = e.value(Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(ns(4)),
          Measure(ns(4), tempoChange: const Tempo(132)),
        ],
      ));
      expect(back.measures[1].tempoChange?.quarterBpm, 132, reason: e.key);
      expect(back.measures.first.tempoChange, isNull, reason: e.key);
    });

    test('${e.key} tells a mid-score tempo from the score tempo by POSITION',
        () {
      // A piece whose ONLY marking is a mid-score change has no earlier one,
      // so "is this the first tempo I have seen?" files it as the score tempo.
      if (e.key == 'abc') return;
      final back = e.value(Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(ns(4)),
          Measure(ns(4), tempoChange: const Tempo(132)),
        ],
      ));
      expect(back.tempo, isNull, reason: e.key);
    });

    test('${e.key} keeps both an initial tempo and a later change', () {
      if (e.key == 'abc') return;
      final back = e.value(Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        tempo: const Tempo(60),
        measures: [
          Measure(ns(4)),
          Measure(ns(4), tempoChange: const Tempo(132)),
        ],
      ));
      expect(back.tempo?.quarterBpm, 60, reason: e.key);
      expect(back.measures[1].tempoChange?.quarterBpm, 132, reason: e.key);
    });
  }
}
