import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// The longa and the 128th/256th notes.
///
/// These were missing from [DurationBase], and the reason they stayed missing
/// is worth recording: `denominator` used to be `1 << index`, so INSERTING a
/// value silently renumbered every existing duration. Appending does not, and
/// the value/log2 tables are now explicit, so the enum's declaration order
/// carries no meaning at all.
///
/// 57 corpus files failed to parse on exactly these three types.
void main() {
  group('values', () {
    test('the new bases have the right whole-note value', () {
      expect(DurationBase.long.wholeValue, (4, 1));
      expect(DurationBase.oneHundredTwentyEighth.wholeValue, (1, 128));
      expect(DurationBase.twoHundredFiftySixth.wholeValue, (1, 256));
    });

    test('the existing bases are unchanged', () {
      expect(DurationBase.breve.wholeValue, (2, 1));
      expect(DurationBase.whole.wholeValue, (1, 1));
      expect(DurationBase.quarter.wholeValue, (1, 4));
      expect(DurationBase.sixtyFourth.wholeValue, (1, 64));
      // denominator is the historical accessor and must keep its meaning.
      expect(DurationBase.quarter.denominator, 4);
      expect(DurationBase.breve.denominator, 1);
    });

    test('log2 and flag counts', () {
      expect(DurationBase.long.log2Value, 2);
      expect(DurationBase.whole.log2Value, 0);
      expect(DurationBase.twoHundredFiftySixth.log2Value, -8);
      expect(DurationBase.oneThousandTwentyFourth.log2Value, -10);
      expect(DurationBase.oneThousandTwentyFourth.wholeValue, (1, 1024));
      // Flags: none until the eighth, then one per halving.
      expect(DurationBase.whole.flagCount, 0);
      expect(DurationBase.quarter.flagCount, 0);
      expect(DurationBase.eighth.flagCount, 1);
      expect(DurationBase.sixtyFourth.flagCount, 4);
      expect(DurationBase.twoHundredFiftySixth.flagCount, 6);
      // Longer than a whole note must not go negative.
      expect(DurationBase.breve.flagCount, 0);
      expect(DurationBase.long.flagCount, 0);
    });

    test('dots apply to the new values too', () {
      expect(NoteDuration(DurationBase.long).toFraction(), Fraction(4, 1));
      expect(NoteDuration(DurationBase.long, dots: 1).toFraction(),
          Fraction(6, 1));
      expect(
        NoteDuration(DurationBase.oneHundredTwentyEighth, dots: 1).toFraction(),
        Fraction(3, 256),
      );
    });
  });

  group('MusicXML round trip', () {
    test('reads the types that used to throw', () {
      // `<duration>` must AGREE with `<type>`: the reader deliberately trusts
      // an encoded duration over a contradicting written type, so a mismatched
      // fixture tests the disagreement path rather than the type map.
      // divisions = 256 per quarter, so quarters * 256 = duration.
      for (final (type, base, duration) in [
        ('long', DurationBase.long, 4096), // 4 wholes = 16 quarters
        ('128th', DurationBase.oneHundredTwentyEighth, 8),
        ('256th', DurationBase.twoHundredFiftySixth, 4),
        ('512th', DurationBase.fiveHundredTwelfth, 2),
        ('1024th', DurationBase.oneThousandTwentyFourth, 1),
      ]) {
        final xml = '<score-partwise><part-list><score-part id="P1">'
            '<part-name>P</part-name></score-part></part-list>'
            '<part id="P1"><measure number="1">'
            '<attributes><divisions>256</divisions></attributes>'
            '<note><pitch><step>C</step><octave>4</octave></pitch>'
            '<duration>$duration</duration><type>$type</type></note>'
            '</measure></part></score-partwise>';
        final s = scoreFromMusicXml(xml);
        final notes =
            s.measures.expand((m) => m.elements).whereType<NoteElement>();
        expect(notes, hasLength(1), reason: type);
        expect(notes.first.duration.base, base, reason: type);
      }
    });

    test('writes them back under the same names', () {
      for (final (type, base) in [
        ('long', DurationBase.long),
        ('128th', DurationBase.oneHundredTwentyEighth),
        ('256th', DurationBase.twoHundredFiftySixth),
        ('512th', DurationBase.fiveHundredTwelfth),
        ('1024th', DurationBase.oneThousandTwentyFourth),
      ]) {
        final score = Score(
          clef: Clef.treble,
          measures: [
            Measure([
              NoteElement(
                pitches: const [Pitch(Step.c, octave: 4)],
                duration: NoteDuration(base),
                id: 'e0',
              ),
            ]),
          ],
        );
        expect(scoreToMusicXml(score), contains('<type>$type</type>'),
            reason: type);
      }
    });
  });
}
