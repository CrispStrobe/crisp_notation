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
      final score = scoreFromLilyPond(r'\clef bass \time 3/4 c4 d e');
      expect(score.clef, Clef.bass);
      expect(score.timeSignature?.beats, 3);
      expect(score.timeSignature?.beatUnit, 4);
    });

    test('parses tuplets and correctly assigns TupletSpans', () {
      final score = scoreFromLilyPond(
          r'{ \tuplet 3/2 { c4 d e } \times 4/5 { f8 g a b c } }');
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
      expect(score.lyrics[2].elementId, isNot(note3.id)); // skipped note 3
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

    int lowMidi(NoteElement n) =>
        n.pitches.map((p) => p.midiNumber).reduce((a, b) => a < b ? a : b);

    test(
        'relative chord: reference carries from the chord FIRST note (no drift)',
        () {
      // In \relative each following chord is placed from the previous chord's
      // FIRST note. Applying the running base to every chord note made octaves
      // climb without bound (e.g. ich_lag reached MIDI 211); all three <d a'>
      // chords must be identical.
      final s = scoreFromLilyPond(r"\relative c'' { <d a'>4 <d a'>4 <d a'>4 }");
      final notes = s.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .toList();
      expect(notes.length, 3);
      final low0 = lowMidi(notes[0]);
      for (final n in notes) {
        expect(lowMidi(n), low0, reason: 'chords must not drift upward');
      }
    });

    test(r'\repeat unfold N writes the body out N times', () {
      final s =
          scoreFromLilyPond(r"\relative c' { \repeat unfold 3 { c4 d4 } }");
      expect(
          s.measures.expand((m) => m.elements).whereType<NoteElement>().length,
          6); // (c d) x3
    });

    test(
        r'\repeat volta sounds once (LilyPond default MIDI); alternatives linear',
        () {
      // volta is NOT unfolded in LilyPond's default MIDI — body once, then every
      // alternative once, in order.
      final s = scoreFromLilyPond(
          r"\relative c' { \repeat volta 2 { c4 d4 } \alternative { { e4 } { f4 } } }");
      expect(
          s.measures.expand((m) => m.elements).whereType<NoteElement>().length,
          4); // c d (once) + e + f
    });

    test('q repeats the previous chord pitches with a new duration', () {
      // `q` is LilyPond's chord repetition: `<c e g>4 q8 q4` is three chords of
      // the same pitches. Unread, each `q` performed as a wrong note and took a
      // beat of its own.
      final s = scoreFromLilyPond(r"{ <c' e' g'>4 q8 q4 }");
      final notes = s.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .toList();
      expect(notes.length, 3);
      for (final n in notes) {
        expect(n.pitches.map((p) => p.midiNumber), containsAll([60, 64, 67]));
      }
      expect(notes[0].duration.base, DurationBase.quarter);
      expect(notes[1].duration.base, DurationBase.eighth);
      expect(notes[2].duration.base, DurationBase.quarter);
    });

    test(r'\skip is a hidden rest that keeps the running duration', () {
      // Unread, `\skip 4`'s duration was a sibling word and its time was
      // lost: every later bar shifted left.
      final s = scoreFromLilyPond(r"{ c'8 \skip 4 d' e' f' g' a' }");
      final els = s.measures.first.elements;
      expect(els[1], isA<RestElement>());
      expect((els[1] as RestElement).hidden, isTrue);
      expect(els[1].duration.base, DurationBase.quarter);
      // `d'` after the skip is still an eighth, like the `c'8` before it.
      expect(els[2].duration.base, DurationBase.eighth);
      expect(s.measures.length, 1);
    });

    test(r'\skip 1*2 is two bars of spacer', () {
      final s = scoreFromLilyPond(r"{ \time 4/4 \skip 1*2 c'1 }");
      expect(s.measures.length, 3);
      expect(s.measures[2].elements.single, isA<NoteElement>());
    });

    test(r'\skip in lyrics holds a note without a syllable', () {
      final s = scoreFromLilyPond(r'''
\score { << \new Voice = "v" { c'4 d' e' f' }
  \new Lyrics \lyricsto "v" { one \skip 4 three four } >> }''');
      final notes = s.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .toList();
      final textOf = {for (final l in s.lyrics) l.elementId: l.text};
      expect(textOf[notes[0].id], 'one');
      expect(textOf[notes[1].id], isNull);
      expect(textOf[notes[2].id], 'three');
      expect(textOf[notes[3].id], 'four');
    });

    test('q repeats the last chord, not a single note in between', () {
      final s = scoreFromLilyPond(r"{ <c' e' g'>4 d'4 q2 }");
      final notes = s.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .toList();
      expect(notes.length, 3);
      expect(notes[2].pitches.map((p) => p.midiNumber), [60, 64, 67]);
      expect(notes[2].duration.base, DurationBase.half);
    });

    test(r'a score-level \transposition in \midi reaches every staff', () {
      // LilyPond writes a guitar duo as `\midi { \transposition c }` at Score
      // level. The staff reader never sees that command, so without lifting it
      // out of the `\midi` block the parts read at written pitch — an octave
      // above what LilyPond's MIDI plays.
      const ly = r'''
\score {
  \context StaffGroup <<
    \new Staff = "one" { \clef treble c'4 }
    \new Staff = "two" { \clef bass c'4 }
  >>
  \midi { \transposition c }
}
''';
      final mp = multiPartFromLilyPond(ly);
      expect(mp.parts.length, 2);
      for (final p in mp.parts) {
        expect(p.transposition, isNotNull);
        final note =
            p.atConcertPitch().measures.first.elements.first as NoteElement;
        // Written c' sounds one octave lower (MIDI 48), as LilyPond's MIDI does.
        expect(note.pitches.single.midiNumber, 48);
      }
    });

    test(r'a staff keeps its own \transposition over a score-level one', () {
      const ly = r'''
\score {
  \context StaffGroup <<
    \new Staff = "clar" { \transposition bes c'4 }
    \new Staff = "two" { c'4 }
  >>
  \midi { \transposition c }
}
''';
      final mp = multiPartFromLilyPond(ly);
      // The clarinet keeps its B-flat transposition (written c' sounds bes);
      // the plain staff takes the score-level octave.
      final clar = mp.parts[0].atConcertPitch().measures.first.elements.first
          as NoteElement;
      expect(clar.pitches.single.midiNumber, 58); // B-flat 3
      final two = mp.parts[1].atConcertPitch().measures.first.elements.first
          as NoteElement;
      expect(two.pitches.single.midiNumber, 48);
    });
  });
}
