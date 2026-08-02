import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A double bar and a final bar are in nearly every piece, and `Measure.barline`
/// survived only MusicXML and ABC.
///
/// Found by asking what the cross-format signature compares at MEASURE level:
/// it checked 8 of Measure's 20 fields, and `barline` was not one of them — the
/// same blindness that hid chord symbols at score level and the forced
/// accidental at note level.
void main() {
  List<MusicElement> ns() => [
        for (var i = 0; i < 4; i++)
          NoteElement(
            id: 'e$i',
            pitches: const [Pitch(Step.c, octave: 4)],
            duration: const NoteDuration(DurationBase.quarter),
          ),
      ];

  Score scored(BarlineStyle first, BarlineStyle last) => Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(ns(), barline: first),
          Measure(ns(), barline: last),
        ],
      );

  final hops = <String, Score Function(Score)>{
    'musicxml': (x) => scoreFromMusicXml(scoreToMusicXml(x)),
    'mei': (x) => scoreFromMei(scoreToMei(x)),
    'kern': (x) => scoreFromKern(scoreToKern(x)),
    'abc': (x) => scoreFromAbc(scoreToAbc(x)),
    'lilypond': (x) => scoreFromLilyPond(scoreToLilyPond(x)),
    'musescore': (x) => scoreFromMscx(scoreToMscx(x)),
  };

  for (final e in hops.entries) {
    test('${e.key} carries a mid-score double bar', () {
      final back = e.value(scored(BarlineStyle.doubleBar, BarlineStyle.normal));
      expect(back.measures.first.barline, BarlineStyle.doubleBar,
          reason: e.key);
    });

    test('${e.key} carries a final bar', () {
      final back = e.value(scored(BarlineStyle.normal, BarlineStyle.finalBar));
      expect(back.measures.last.barline, BarlineStyle.finalBar, reason: e.key);
    });

    test('${e.key} invents no barline for an ordinary bar', () {
      // kern used to close EVERY export with `==`, which is a final barline, so
      // a score that had none read back with one.
      final back = e.value(scored(BarlineStyle.normal, BarlineStyle.normal));
      for (final m in back.measures) {
        expect(m.barline, BarlineStyle.normal, reason: e.key);
      }
    });

    test('${e.key} keeps a repeat rather than the style it shares a slot with',
        () {
      // ⚠️ LilyPond is EXCLUDED, and not because of the barline work: its
      // writer emits no repeat structure at all. Its reader handles
      // `\repeat volta`, so repeats are read-only there — the mirror of the
      // `\tempo` asymmetry, and scoped separately on the board.
      if (e.key == 'lilypond') return;
      // MEI's @right, kern's `=` token and MuseScore's flags all carry the
      // repeat AND the style in one place; the repeat says more, so it wins.
      final s = Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(ns(), endRepeat: true),
          Measure(ns(), startRepeat: true),
        ],
      );
      final back = e.value(s);
      expect(back.measures.first.endRepeat, isTrue, reason: e.key);
      expect(back.measures[1].startRepeat, isTrue, reason: e.key);
    });
  }
}
