import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Every dynamic level and every navigation mark, in all six formats.
///
/// ⚠️ LilyPond carried neither properly and both failures were silent.
///
/// Dynamics: the writer emitted `\${level.name}`, which produces `\sffz`, `\fz`
/// and `\rf` — none of which LilyPond defines, so those files did not compile.
/// The reader meanwhile collapsed five distinct marks onto three (`sfz`→sf,
/// `fp`→f, `rfz`→sf), so what did survive came back weaker and less specific
/// than it went in. The corpus settles which spellings are real: `\sf` 631,
/// `\fp` 171, `\fz` 107, `\rfz` 12, `\sfz` 11. The two the model has that
/// LilyPond does not define are emitted as `make-dynamic-script` definitions in
/// the preamble, so the music itself still reads `\fz`.
///
/// Navigation: nothing was written at all — no segno, coda, D.C., D.S. or Fine.
void main() {
  List<MusicElement> ns(String p) => [
        for (var i = 0; i < 4; i++)
          NoteElement(
            id: '$p$i',
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
    for (final level in DynamicLevel.values) {
      test('${e.key} keeps ${level.name}', () {
        final back = e.value(Score(
          clef: Clef.treble,
          timeSignature: const TimeSignature(4, 4),
          measures: [Measure(ns('a'))],
          dynamics: [DynamicMarking('a0', level)],
        ));
        expect(back.dynamics.single.level, level, reason: e.key);
      });
    }

    for (final mark in NavigationMark.values) {
      test('${e.key} keeps ${mark.name}', () {
        final back = e.value(Score(
          clef: Clef.treble,
          timeSignature: const TimeSignature(4, 4),
          measures: [Measure(ns('a')), Measure(ns('b'), navigation: mark)],
        ));
        expect(back.measures[1].navigation, mark, reason: e.key);
      });
    }
  }

  test('a non-standard dynamic is DEFINED before it is used', () {
    final ly = scoreToLilyPond(Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [Measure(ns('a'))],
      dynamics: const [DynamicMarking('a0', DynamicLevel.fz)],
    ));
    expect(ly, contains('fz = #(make-dynamic-script "fz")'));
    expect(ly.indexOf('make-dynamic-script'), lessThan(ly.indexOf(r'\fz')));
  });

  test('a standard one needs no definition', () {
    final ly = scoreToLilyPond(Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [Measure(ns('a'))],
      dynamics: const [DynamicMarking('a0', DynamicLevel.sfz)],
    ));
    expect(ly, isNot(contains('make-dynamic-script')));
    expect(ly, contains(r'\sfz'));
  });
}
