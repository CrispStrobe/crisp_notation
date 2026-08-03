import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// The common (C) and cut (¢) glyphs, in every format that spells them.
///
/// MuseScore was the last hold-out, and the encoding was deliberately NOT
/// guessed at until the corpus supplied it: 644 `<TimeSig>` blocks reading
/// `4/4 subtype=1` and 39 reading `2/2 subtype=2`, i.e. MuseScore's TimeSigType
/// (1 = FOUR_FOUR, 2 = ALLA_BREVE, absent = plain numerals). Inventing one
/// would have round-tripped with ourselves while matching no real file.
void main() {
  final hops = <String, Score Function(Score)>{
    'musicxml': (x) => scoreFromMusicXml(scoreToMusicXml(x)),
    'mei': (x) => scoreFromMei(scoreToMei(x)),
    'kern': (x) => scoreFromKern(scoreToKern(x)),
    'abc': (x) => scoreFromAbc(scoreToAbc(x)),
    'lilypond': (x) => scoreFromLilyPond(scoreToLilyPond(x)),
    'musescore': (x) => scoreFromMscx(scoreToMscx(x)),
  };

  Score scored(TimeSignature t) => Score(
        clef: Clef.treble,
        timeSignature: t,
        measures: [
          Measure([RestElement(NoteDuration.whole, id: 'r0')])
        ],
      );

  for (final e in hops.entries) {
    for (final t in const [
      (TimeSignature(4, 4, symbol: TimeSymbol.common), TimeSymbol.common),
      (TimeSignature(2, 2, symbol: TimeSymbol.cut), TimeSymbol.cut),
      (TimeSignature(3, 4), TimeSymbol.numeric),
    ]) {
      test('${e.key} keeps ${t.$2.name} time', () {
        final back = e.value(scored(t.$1)).timeSignature;
        expect(back?.symbol, t.$2, reason: e.key);
        expect(back?.beats, t.$1.beats, reason: e.key);
        expect(back?.beatUnit, t.$1.beatUnit, reason: e.key);
      });
    }
  }
}
