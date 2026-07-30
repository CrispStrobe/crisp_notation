// A BARRE — one finger laid across several strings — is a left-hand instruction
// Guitar Pro states explicitly and we used to drop on import.
//
// It is a distinct fact from the fingering digits: a barre chord's digits
// already come out right (every string at the hand's fret is finger 1), but
// "1, 1, 1" does not say that ONE finger lies across them, and that is what a
// player reads.
//
// The schema asserted here was read off real files, not guessed:
//   <Property name="BarreFret"><Fret>3</Fret></Property>
//   <Property name="BarreString"><String>1</String></Property>
// both on a <Beat>, because a barre describes the hand for the whole chord.
import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

Score _chord({TabBarre? barre}) => Score(
      clef: Clef.treble,
      measures: [
        Measure([
          NoteElement(
            pitches: [Pitch.fromMidi(53), Pitch.fromMidi(60)],
            duration: NoteDuration.quarter,
            id: 'n0',
          ),
        ]),
      ],
      tabBarres: [if (barre != null) barre],
    );

void main() {
  final t = Tuning.standardGuitar;

  test('a barre survives a GPIF round trip', () {
    final gpif = scoreToGpif(
      _chord(barre: const TabBarre('n0', 3, lowestString: 1)),
      tuning: t,
    );
    expect(gpif, contains('BarreFret'));

    final back = scoreFromGpif(gpif);
    expect(back.tabBarres, hasLength(1));
    expect(back.tabBarres.single.fret, 3);
    expect(back.tabBarres.single.lowestString, 1);
  });

  test('…and through the binary container too', () {
    final back = scoreFromGpif(
      readGpifFromGp(
        writeGpFromGpif(
          scoreToGpif(_chord(barre: const TabBarre('n0', 5)), tuning: t),
        ),
      ),
    );
    expect(back.tabBarres, hasLength(1));
    expect(back.tabBarres.single.fret, 5);
    expect(
      back.tabBarres.single.lowestString,
      isNull,
      reason: 'a file that gives only a fret must not gain a string from us',
    );
  });

  test('a score with no barre gains none — the field is additive', () {
    final back = scoreFromGpif(scoreToGpif(_chord(), tuning: t));
    expect(back.tabBarres, isEmpty);
  });

  test('the barre is anchored to the note the chord became', () {
    // The reader assigns its own element ids, so the anchor must be the id of
    // the note it actually built — not a stale one from the source score.
    final back = scoreFromGpif(
      scoreToGpif(_chord(barre: const TabBarre('n0', 2)), tuning: t),
    );
    final note =
        back.measures.expand((m) => m.elements).whereType<NoteElement>().single;
    expect(back.tabBarres.single.noteId, note.id);
  });

  test('reading the documented GPIF shape directly', () {
    // Belt and braces: our writer could agree with our reader while both
    // disagreed with Guitar Pro. This asserts the literal element names seen in
    // real files, so a schema drift on either side fails here.
    final gpif = scoreToGpif(
      _chord(barre: const TabBarre('n0', 7, lowestString: 2)),
      tuning: t,
    );
    expect(gpif, contains('<Property name="BarreFret"><Fret>7</Fret>'));
    expect(gpif, contains('<Property name="BarreString"><String>2</String>'));
  });

  group(
    'TabBarre.roman — one printed form, shared by engraver and editors',
    () {
      test('the numerals across a fretboard', () {
        const cases = <int, String>{
          1: 'I',
          2: 'II',
          3: 'III',
          4: 'IV',
          5: 'V',
          7: 'VII',
          9: 'IX',
          10: 'X',
          12: 'XII',
          14: 'XIV',
          19: 'XIX',
          24: 'XXIV',
        };
        for (final e in cases.entries) {
          expect(TabBarre('n', e.key).roman, e.value, reason: 'fret ${e.key}');
        }
      });

      test(
        'a fret off the neck falls back to the number, not a wrong numeral',
        () {
          expect(const TabBarre('n', 0).roman, '0');
          expect(const TabBarre('n', 30).roman, '30');
        },
      );
    },
  );
}
