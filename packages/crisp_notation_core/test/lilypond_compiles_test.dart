import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Output LilyPond itself will accept.
///
/// `\tempo 4 = 91.99980000000001` is not a tempo LilyPond renders imprecisely —
/// it is a SYNTAX ERROR ("unexpected REAL") and the whole file fails to
/// compile. Any score whose tempo was not a whole number produced a `.ly`
/// nobody could open, and a MuseScore tempo of 1.5333 quarters/second arrives
/// as 91.9998, so it was not a rare shape.
///
/// Our own reader parses the float happily, which is exactly why no round trip
/// could see it. LilyPond 2.24 refusing the file is what surfaced it — the one
/// class of defect only a third-party implementation can find.
void main() {
  String tempoOf(double bpm) {
    final ly = scoreToLilyPond(Score(
      clef: Clef.treble,
      tempo: Tempo(bpm),
      measures: [
        Measure([
          NoteElement(
            pitches: const [Pitch(Step.c, octave: 4)],
            duration: const NoteDuration(DurationBase.quarter),
            id: 'a',
          ),
        ]),
      ],
    ));
    final line = ly
        .split('\n')
        .firstWhere((l) => l.contains('\\tempo'), orElse: () => '');
    return RegExp(r'\\tempo [^ ]+ = (\S+)').firstMatch(line)?[1] ?? '';
  }

  test('a fractional tempo is written as an integer', () {
    // Rounding loses at most half a beat per minute. An uncompilable file
    // loses everything.
    expect(tempoOf(91.99980000000001), '92');
    expect(tempoOf(92.5), '93');
    expect(tempoOf(60.4), '60');
  });

  test('a whole tempo is unchanged', () {
    expect(tempoOf(120), '120');
    expect(tempoOf(60), '60');
  });

  test('no tempo we write ever contains a decimal point', () {
    for (final bpm in [
      91.99980000000001,
      33.333333,
      144.00000000000003,
      0.5,
      207.9,
    ]) {
      expect(tempoOf(bpm), isNot(contains('.')), reason: '$bpm');
    }
  });
}
