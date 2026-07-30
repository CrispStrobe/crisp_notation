import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Tuplets must survive a round trip by how long they SOUND.
///
/// Every one of these was green under the old comparison, which looked at the
/// notated value and ignored the [TupletSpan] entirely. That is blind in the
/// only direction that matters: dropping or mis-deriving a ratio leaves the
/// notated value untouched and changes the music. Four real defects hid behind
/// it, and each has a test below.
///
/// The dual trap is a false alarm. Neither `**kern` nor ABC records a tuplet
/// BRACKET, so a reader has to re-derive one, and it may legitimately come back
/// respelled — a septuplet of eighths in the time of 8 is the same sound as the
/// conventional 7:4 of quarters. Comparing sounding duration accepts that and
/// still catches a wrong ratio.

/// Sounding duration of every note: the notated value scaled by its tuplet.
List<Fraction> sounding(Score s) {
  final out = <Fraction>[];
  for (final m in s.measures) {
    final scale = <int, Fraction>{};
    for (final t in m.tuplets) {
      if (t.voice != 0) continue;
      for (var i = t.startIndex; i <= t.endIndex; i++) {
        scale[i] = Fraction(t.normal, t.actual);
      }
    }
    for (var i = 0; i < m.elements.length; i++) {
      final e = m.elements[i];
      if (e is! NoteElement) continue;
      out.add(e.duration.toFraction() * (scale[i] ?? Fraction(1, 1)));
    }
  }
  return out;
}

Score tupletScore(int actual, int normal, DurationBase base, {int dots = 0}) =>
    Score(clef: Clef.treble, measures: [
      Measure([
        for (var i = 0; i < actual; i++)
          NoteElement(
            pitches: const [Pitch(Step.c, octave: 4)],
            duration: NoteDuration(base, dots: dots),
            id: 'e$i',
          ),
      ], tuplets: [
        TupletSpan(0, actual - 1, actual: actual, normal: normal)
      ]),
    ]);

/// A single note with no tuplet, for testing a duration on its own.
Score plainScore(DurationBase base) => Score(clef: Clef.treble, measures: [
      Measure([
        NoteElement(
          pitches: const [Pitch(Step.c, octave: 4)],
          duration: NoteDuration(base),
          id: 'e0',
        ),
      ]),
    ]);

const codecs = ['kern', 'mei', 'abc', 'musicxml', 'lilypond'];

Score through(String format, Score s) => switch (format) {
      'kern' => scoreFromKern(scoreToKern(s)),
      'mei' => scoreFromMei(scoreToMei(s)),
      'abc' => scoreFromAbc(scoreToAbc(s)),
      'musicxml' => scoreFromMusicXml(scoreToMusicXml(s)),
      _ => scoreFromLilyPond(scoreToLilyPond(s)),
    };

void main() {
  // Ratios that actually occur, plus the ones no format handled: the
  // "augmenting" duplet/quadruplet families where the group sounds LONGER than
  // it is written, and the odd primes.
  const ratios = [
    (3, 2),
    (5, 4),
    (5, 2),
    (5, 3),
    (6, 4),
    (7, 4),
    (7, 8),
    (9, 8),
    (2, 3),
    (4, 3),
    (4, 6),
    (3, 4),
    (10, 8),
    (11, 8),
    (12, 8),
    (13, 8),
    (15, 8),
  ];
  const bases = [
    DurationBase.half,
    DurationBase.quarter,
    DurationBase.eighth,
    DurationBase.sixteenth,
    DurationBase.thirtySecond,
    DurationBase.sixtyFourth,
    DurationBase.oneHundredTwentyEighth,
  ];

  group('every ratio survives every format, by sounding duration', () {
    for (final name in codecs) {
      test(name, () {
        for (final (actual, normal) in ratios) {
          for (final base in bases) {
            for (final dots in [0, 1, 2]) {
              final src = tupletScore(actual, normal, base, dots: dots);
              final label = '$actual:$normal ${base.name}+$dots -> $name';
              expect(sounding(through(name, src)), sounding(src),
                  reason: label);
            }
          }
        }
      });
    }
  });

  group('kern encodes the sounding duration exactly', () {
    // The writer used to fall back to the PLAIN reciprocal whenever the
    // tuplet-scaled value was not an integer, which discarded the tuplet and
    // changed the music rather than merely respelling it.
    test('an augmenting tuplet becomes a dotted value, not a plain one', () {
      // A 2:3 duplet quarter sounds 3/8 of a whole — a dotted quarter. It was
      // written `4`, i.e. a plain quarter, two thirds of its real length.
      final kern = scoreToKern(tupletScore(2, 3, DurationBase.quarter));
      expect(kern, contains('4.'));
      expect(sounding(scoreFromKern(kern)).first, Fraction(3, 8));
    });

    test('a ratio no dotted value reaches uses the rational form', () {
      // 7:8 of a quarter is 2/7 of a whole. No note value is 2/7, so this needs
      // Humdrum's `N%M` reciprocal — a duration of M/N whole notes.
      final kern = scoreToKern(tupletScore(7, 8, DurationBase.quarter));
      expect(kern, contains('7%2'));
      expect(sounding(scoreFromKern(kern)).first, Fraction(2, 7));
    });

    test('the rational form is not read as its leading digits', () {
      // `8%9` is NINE EIGHTHS of a whole note. Taking the `8` for an eighth
      // (the plain-reciprocal fast path ran first) made it 64x too short.
      final score = tupletScore(4, 6, DurationBase.half, dots: 1);
      expect(sounding(score).first, Fraction(9, 8));
      expect(sounding(scoreFromKern(scoreToKern(score))).first, Fraction(9, 8));
    });

    test('the early-music values still parse', () {
      // `0`/`00`/`000` are keys in the reciprocal table but not positive
      // integers, so a `%` check written against a parsed numerator broke them.
      for (final (recip, base) in [
        ('0', DurationBase.breve),
        ('00', DurationBase.long),
      ]) {
        final s = scoreFromKern('**kern\n${recip}c\n*-\n');
        final n = s.measures.expand((m) => m.elements).whereType<NoteElement>();
        expect(n.single.duration.base, base, reason: recip);
      }
    });

    test('a 128th is written as a number, not the text "null"', () {
      // Absent from the reciprocal table, it fell through string interpolation.
      final kern = scoreToKern(plainScore(DurationBase.oneHundredTwentyEighth));
      expect(kern, isNot(contains('null')));
      expect(kern, contains('128'));
    });
  });

  group('ABC records the tuplet ratio', () {
    // `(p` does NOT mean "p in the time of p-1": ABC gives each p a default q,
    // 2 for everything but 2/4/8. The writer emitted the bare form for every
    // ratio, so all of them but 3:2 and 6:4 read back re-timed.
    test('a quintuplet in the time of 4 is not written as the default 5:2', () {
      final abc = scoreToAbc(tupletScore(5, 4, DurationBase.quarter));
      expect(abc, contains('(5:4:5'));
      expect(sounding(scoreFromAbc(abc)).first, Fraction(1, 5));
    });

    test('the bare form is kept where it is unambiguous', () {
      expect(
          scoreToAbc(tupletScore(3, 2, DurationBase.eighth)), contains('(3'));
      expect(
        scoreToAbc(tupletScore(3, 2, DurationBase.eighth)),
        isNot(contains('(3:')),
      );
    });

    test('5, 7 and 9 always take the explicit form', () {
      // Their default q depends on whether the METER is compound, so the bare
      // mark is not portable even when q happens to match ours.
      for (final p in [5, 7, 9]) {
        expect(scoreToAbc(tupletScore(p, 2, DurationBase.eighth)),
            contains('($p:2:$p'),
            reason: '$p');
      }
    });
  });

  test('MEI writes the short values it has @dur codes for', () {
    // 128th and below were missing from the map, so the note was written with
    // no duration at all and read back as a whole note — 128x too long.
    for (final (base, dur) in [
      (DurationBase.oneHundredTwentyEighth, '128'),
      (DurationBase.twoHundredFiftySixth, '256'),
      (DurationBase.fiveHundredTwelfth, '512'),
      (DurationBase.oneThousandTwentyFourth, '1024'),
    ]) {
      final src = plainScore(base);
      expect(scoreToMei(src), contains('dur="$dur"'), reason: dur);
      expect(sounding(scoreFromMei(scoreToMei(src))), sounding(src),
          reason: dur);
    }
  });
}
