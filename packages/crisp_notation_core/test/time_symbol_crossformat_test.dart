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

  // 🛑 A FORMAT LIMIT, and the reason the tests above could not see it: they
  // use only the CONVENTIONAL pairings (4/4 drawn as C, 2/2 as cut-C), which
  // is precisely where LilyPond's inference and the written truth agree.
  //
  // LilyPond does not record which glyph was chosen. `\defaultTimeSignature`
  // asks it to draw C where the fraction warrants one, and it derives that
  // from the fraction alone — there is no way to put a cut-C on a 4/4 without
  // a custom stencil. So an UNCONVENTIONAL pairing is not expressible, and the
  // corpus has them: early-American psalm collections routinely write cut-C
  // over 4/4 (`RutlandBillings1781bpr.mxl`).
  //
  // The other three formats state the glyph and keep it. Recorded rather than
  // papered over — the alternative would be inventing an encoding LilyPond
  // does not read.
  test('LilyPond DERIVES the glyph from the fraction (documented limit)', () {
    Score scored(TimeSignature t) => Score(
          clef: Clef.treble,
          timeSignature: t,
          measures: [
            Measure([RestElement(NoteDuration.whole, id: 'r0')])
          ],
        );
    for (final (written, drawn) in [
      (TimeSignature(4, 4, symbol: TimeSymbol.cut), TimeSymbol.common),
      (TimeSignature(2, 2, symbol: TimeSymbol.common), TimeSymbol.cut),
    ]) {
      expect(
          scoreFromLilyPond(scoreToLilyPond(scored(written)))
              .timeSignature
              ?.symbol,
          drawn,
          reason: 'LilyPond redraws \$written as what the fraction implies');
      // The others state it, so they keep it.
      for (final hop in [
        scoreFromMusicXml(scoreToMusicXml(scored(written))),
        scoreFromMei(scoreToMei(scored(written))),
        scoreFromMscx(scoreToMscx(scored(written))),
      ]) {
        expect(hop.timeSignature?.symbol, written.symbol);
      }
    }
  });
}
