import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A `\time` after the first one is a CHANGE, not the score's signature.
///
/// `_time` is the RUNNING meter — it measures each bar's capacity — so reading
/// the score's signature off it takes whatever the last change happened to be.
/// Brahms' Schicksalslied opens in 4/4 and moves to 3/4, and came back
/// declaring 3/4; re-barring the whole piece at 3/4 turned 1,624 bars into
/// 1,752.
void main() {
  List<int> barLengths(Score s) =>
      [for (final m in s.measures) m.elements.length];

  test('the score keeps the FIRST meter, not the last', () {
    final s = scoreFromLilyPond(
      r"\score { \new Staff { \time 4/4 c'1 | \time 3/4 d'2. | } }",
    );
    // Compared by VALUE, not identity: LilyPond draws a bare `\time 4/4` as
    // the C glyph, so the symbol is `common` — which is what these tests were
    // incidentally asserting and is pinned properly below.
    expect(s.timeSignature?.beats, 4);
    expect(s.timeSignature?.beatUnit, 4);
  });

  group('the C and cut-C glyphs', () {
    // ⚠️ LilyPond draws 4/4 as C and 2/2 as cut-C BY DEFAULT; the numerals
    // appear only after `\numericTimeSignature`, which is STICKY until
    // `\defaultTimeSignature`. The reader ignored both, so every common-time
    // score — most 4/4 music there is — came back numeric and lost its glyph.
    test('a bare \\time 4/4 is the C glyph', () {
      final s = scoreFromLilyPond(r"\score { \new Staff { \time 4/4 c'1 | } }");
      expect(s.timeSignature?.symbol, TimeSymbol.common);
    });

    test('a bare \\time 2/2 is cut-C', () {
      final s = scoreFromLilyPond(r"\score { \new Staff { \time 2/2 c'1 | } }");
      expect(s.timeSignature?.symbol, TimeSymbol.cut);
    });

    test('\\numericTimeSignature forces numerals', () {
      final s = scoreFromLilyPond(
          r"\score { \new Staff { \numericTimeSignature \time 4/4 c'1 | } }");
      expect(s.timeSignature?.symbol, TimeSymbol.numeric);
    });

    test('it is STICKY until \\defaultTimeSignature', () {
      final s = scoreFromLilyPond(r'\score { \new Staff { '
          r"\numericTimeSignature \time 4/4 c'1 | \time 2/2 d'1 | } }");
      expect(s.measures[1].timeChange?.symbol, TimeSymbol.numeric,
          reason: 'still numeric — nothing turned it off');
    });

    test('and \\defaultTimeSignature turns it back off', () {
      final s = scoreFromLilyPond(r'\score { \new Staff { '
          r"\numericTimeSignature \time 4/4 c'1 | "
          r"\defaultTimeSignature \time 2/2 d'1 | } }");
      expect(s.measures[1].timeChange?.symbol, TimeSymbol.cut);
    });

    test('3/4 is numeric either way — there is no glyph for it', () {
      final s =
          scoreFromLilyPond(r"\score { \new Staff { \time 3/4 c'2. | } }");
      expect(s.timeSignature?.symbol, TimeSymbol.numeric);
    });

    test('both glyphs round-trip through our own writer', () {
      for (final t in [
        const TimeSignature(4, 4, symbol: TimeSymbol.common),
        const TimeSignature(2, 2, symbol: TimeSymbol.cut),
        const TimeSignature(4, 4),
      ]) {
        final s = Score(
          clef: Clef.treble,
          timeSignature: t,
          measures: [
            Measure(<MusicElement>[
              NoteElement(
                id: 'e0',
                pitches: const [Pitch(Step.c, octave: 4)],
                duration: const NoteDuration(DurationBase.whole),
              ),
            ])
          ],
        );
        expect(scoreFromLilyPond(scoreToLilyPond(s)).timeSignature?.symbol,
            t.symbol,
            reason: '$t');
      }
    });
  });

  test('the change lands on the bar it opens', () {
    final s = scoreFromLilyPond(
      r"\score { \new Staff { \time 4/4 c'1 | \time 3/4 d'2. | } }",
    );
    expect(s.measures[0].timeChange, isNull);
    expect(s.measures[1].timeChange, const TimeSignature(3, 4));
  });

  test('a \\time written at the END of the previous bar still lands right', () {
    // A source may put the change either before the bar it applies to or after
    // the last note of the one before. Both mean the same bar, and attaching it
    // to whichever measure closes next gets the second form wrong by one.
    final s = scoreFromLilyPond(
      r"\score { \new Staff { \time 4/4 c'1 \time 3/4 | d'2. | } }",
    );
    // Compared by VALUE, not identity: LilyPond draws a bare `\time 4/4` as
    // the C glyph, so the symbol is `common` — which is what these tests were
    // incidentally asserting and is pinned properly below.
    expect(s.timeSignature?.beats, 4);
    expect(s.timeSignature?.beatUnit, 4);
    expect(barLengths(s), [1, 1]);
    expect(s.measures[0].timeChange, isNull);
    expect(s.measures[1].timeChange, const TimeSignature(3, 4),
        reason: 'the change was attached one bar too early');
  });

  test('the meter survives a round trip through our own writer', () {
    const src = r"\score { \new Staff { \time 4/4 c'1 | \time 3/4 d'2. | "
        r"\time 4/4 e'1 | } }";
    final want = scoreFromLilyPond(src);
    final back = scoreFromLilyPond(scoreToLilyPond(want));
    expect(back.timeSignature, want.timeSignature);
    expect(barLengths(back), barLengths(want));
    expect(
      [for (final m in back.measures) m.timeChange?.toString()],
      [for (final m in want.measures) m.timeChange?.toString()],
    );
  });

  test('a bar that is not full still ends where the source ended it', () {
    // The writer emitted a barcheck only after a voice split, so any measure
    // that did not fill exactly merged into the next on reread. Schicksalslied
    // is full of short bars and lost 61 of them through our own writer.
    final want = scoreFromLilyPond(
      r"\score { \new Staff { \time 4/4 c'4 d'4 | e'1 | } }",
    );
    expect(barLengths(want), [2, 1]);
    final back = scoreFromLilyPond(scoreToLilyPond(want));
    expect(barLengths(back), [2, 1], reason: 'the short bar merged');
  });
}
