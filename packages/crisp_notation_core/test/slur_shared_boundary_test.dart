import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A note that ENDS one slur and STARTS the next — `e)(` in LilyPond — is the
/// same phrase shape that broke hairpins in four codecs, and it broke slurs
/// too.
///
/// LilyPond had it on BOTH sides: the writer emitted `()` (open then close,
/// opening a slur and killing it on the spot), and the reader took the open
/// first, where `??=` is a no-op because a slur is already running, then let
/// the close clear it. Only the first of a chained pair survived.
void main() {
  Score scored(List<Slur> slurs) => Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(<MusicElement>[
            for (var i = 0; i < 5; i++)
              NoteElement(
                id: 'e$i',
                pitches: const [Pitch(Step.c, octave: 4)],
                duration: const NoteDuration(DurationBase.quarter),
              ),
          ])
        ],
        slurs: slurs,
      );

  test('LilyPond writes the close before the open', () {
    final ly =
        scoreToLilyPond(scored(const [Slur('e0', 'e2'), Slur('e2', 'e4')]));
    expect(ly, contains(')('));
    expect(ly, isNot(contains('()')));
  });

  /// MusicXML, MEI and MuseScore number or nest their slurs, so they were
  /// already correct; they are here to keep it that way.
  for (final e in <String, Score Function(Score)>{
    'musicxml': (x) => scoreFromMusicXml(scoreToMusicXml(x)),
    'mei': (x) => scoreFromMei(scoreToMei(x)),
    'lilypond': (x) => scoreFromLilyPond(scoreToLilyPond(x)),
    'musescore': (x) => scoreFromMscx(scoreToMscx(x)),
  }.entries) {
    test('${e.key} keeps BOTH slurs across a shared boundary note', () {
      final back = e.value(scored(const [Slur('e0', 'e2'), Slur('e2', 'e4')]));
      expect(back.slurs, hasLength(2), reason: e.key);
      expect(back.slurs[0].endId, back.slurs[1].startId,
          reason: '${e.key}: the boundary note must anchor both');
    });

    test('${e.key} keeps two disjoint slurs', () {
      final back = e.value(scored(const [Slur('e0', 'e1'), Slur('e3', 'e4')]));
      expect(back.slurs, hasLength(2), reason: e.key);
    });
  }

  test('a lone slur is unaffected everywhere', () {
    for (final hop in <Score Function(Score)>[
      (x) => scoreFromMusicXml(scoreToMusicXml(x)),
      (x) => scoreFromMei(scoreToMei(x)),
      (x) => scoreFromKern(scoreToKern(x)),
      (x) => scoreFromAbc(scoreToAbc(x)),
      (x) => scoreFromLilyPond(scoreToLilyPond(x)),
      (x) => scoreFromMscx(scoreToMscx(x)),
    ]) {
      expect(hop(scored(const [Slur('e0', 'e2')])).slurs, hasLength(1));
    }
  });
}
