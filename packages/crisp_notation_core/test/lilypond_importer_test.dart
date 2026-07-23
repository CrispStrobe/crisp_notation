import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

void main() {
  group('LilyPond Importer', () {
    test('parses simple absolute notes and durations', () {
      final score = scoreFromLilyPond(r"{ c'4 d'8 e'8 f'2 }");
      expect(score.measures.length, 1);
      final m = score.measures.first;
      expect(m.elements.length, 4);

      final c = m.elements[0] as NoteElement;
      expect(c.pitches.single.step, Step.c);
      expect(c.pitches.single.octave, 4);
      expect(c.duration, NoteDuration.quarter);

      final f = m.elements[3] as NoteElement;
      expect(f.pitches.single.step, Step.f);
      expect(f.pitches.single.octave, 4);
      expect(f.duration, NoteDuration.half);
    });

    test('parses relative mode and handles octave shifts', () {
      final score = scoreFromLilyPond(r"\relative c' { c4 d e f g a b c }");
      // c' is C4. C->D->E->F->G->A->B->C (C5)
      expect(score.measures.length,
          2); // 4/4 time signature means 8 quarters is 2 measures
      final m1 = score.measures[0];
      final m2 = score.measures[1];
      expect(m1.elements.length, 4);
      expect(m2.elements.length, 4);

      final c4 = m1.elements[0] as NoteElement;
      expect(c4.pitches.single.octave, 4);

      final c5 = m2.elements[3] as NoteElement;
      expect(c5.pitches.single.octave, 5);
      expect(c5.pitches.single.step, Step.c);
    });

    test('parses chords and rests', () {
      final score = scoreFromLilyPond(r"{ <c' e' g'>4. r8 }");
      expect(score.measures.length, 1);
      final m = score.measures.first;

      final chord = m.elements[0] as NoteElement;
      expect(chord.pitches.length, 3);
      expect(chord.duration.base, DurationBase.quarter);
      expect(chord.duration.dots, 1);

      final rest = m.elements[1] as RestElement;
      expect(rest.duration.base, DurationBase.eighth);
    });

    test('parses time signature and clef commands', () {
      final score = scoreFromLilyPond(r"\clef bass \time 3/4 c4 d e");
      expect(score.clef, Clef.bass);
      expect(score.timeSignature?.beats, 3);
      expect(score.timeSignature?.beatUnit, 4);
    });

    test('parses tuplets and correctly assigns TupletSpans', () {
      final score = scoreFromLilyPond(
          r"{ \tuplet 3/2 { c4 d e } \times 4/5 { f8 g a b c } }");
      expect(score.measures.length, 1);
      final m = score.measures.first;

      expect(m.tuplets.length, 2);
      expect(m.tuplets[0].actual, 3);
      expect(m.tuplets[0].normal, 2);
      expect(m.tuplets[0].startIndex, 0);
      expect(m.tuplets[0].endIndex, 2);

      expect(m.tuplets[1].actual, 5);
      expect(m.tuplets[1].normal, 4);
      expect(m.tuplets[1].startIndex, 3);
      expect(m.tuplets[1].endIndex, 7);
    });

    test('parses lyrics with hyphens, melismas, skips, and variables', () {
      final score = scoreFromLilyPond(r"""
        myLyrics = \lyricmode { Al -- le _ Jah -- re __ }
        \score {
          <<
            \new Staff { c'4 d'4 e'4 f'4 g'4 a'4 }
            \addlyrics { \myLyrics }
          >>
        }
      """);

      expect(score.lyrics.length, 4); // "Al", "le", "Jah", "re"

      expect(score.lyrics[0].text, 'Al');
      expect(score.lyrics[0].hyphenToNext, true);
      expect(score.lyrics[0].extender, false);
      expect(score.lyrics[0].verse, 1);

      expect(score.lyrics[1].text, 'le');
      expect(score.lyrics[1].hyphenToNext, false);

      // The '_' skipped the third note (e'4). So 'Jah' aligns to the fourth note.
      final note3 = score.measures.first.elements[2] as NoteElement;
      final note4 = score.measures.first.elements[3] as NoteElement;
      expect(score.lyrics[2].elementId, note4.id);
      expect(score.lyrics[2].text, 'Jah');
      expect(score.lyrics[2].hyphenToNext, true);

      expect(score.lyrics[3].text, 're');
      expect(score.lyrics[3].hyphenToNext, false);
      expect(score.lyrics[3].extender, true);
    });

    test(
        'reads key / partial and skips a ChordNames chord track '
        '(Ebersberger structure)', () {
      // A song sheet with a \chordmode chord track above the melody, an explicit
      // key, and a pickup — the shape used across the Ebersberger Liedersammlung.
      const ly = r'''
akkorde = \chordmode { c2 g2 c2 g2 }
melodie = \relative c'' {
  \clef "treble"
  \time 2/4
  \key f\major
  \partial 8
  c8 d8 c8 bes8 g8 f8 a8 a4
}
\score {
  <<
    \new ChordNames { \akkorde }
    \new Voice = "Lied" { \melodie }
  >>
}
''';
      final score = scoreFromLilyPond(ly);

      // \key f\major must be honoured (was dropped -> 0 before the fix).
      expect(score.keySignature.fifths, -1);
      expect(score.timeSignature?.beats, 2);
      expect(score.timeSignature?.beatUnit, 4);

      // The chord track must NOT be counted as melody notes: exactly the 8
      // melodie notes, none of the 4 \chordmode chords.
      final notes = score.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .toList();
      expect(notes.length, 8);

      // \relative c'' -> first melody note is C5.
      expect(notes.first.pitches.single.step, Step.c);
      expect(notes.first.pitches.single.octave, 5);
      // bes in F major stays B-flat (alter -1).
      final bes = notes[3];
      expect(bes.pitches.single.step, Step.b);
      expect(bes.pitches.single.alter, -1);
    });

    test('minor key signature', () {
      final score = scoreFromLilyPond(r"\key a \minor { c'4 }");
      expect(score.keySignature.fifths, 0); // A minor
      final score2 = scoreFromLilyPond(r"\key d \minor { c'4 }");
      expect(score2.keySignature.fifths, -1); // D minor
    });
  });
}
