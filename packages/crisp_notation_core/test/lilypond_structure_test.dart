import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// LilyPond score STRUCTURE: how contexts, variables, transpositions, repeats
/// and simultaneous music turn into parts, voices and bars.
///
/// Every case here was found by comparing the reader with LilyPond's own MIDI
/// output over the Mutopia corpus (374 files). A note-count check passes most
/// of them: the failures were music read twice as long, an octave off, or a
/// staff that read as silence.
List<int> midi(List<MusicElement> voice) => [
      for (final e in voice)
        if (e is NoteElement) ...e.pitches.map((p) => p.midiNumber),
    ];

List<int> allNotes(Score s) =>
    [for (final m in s.measures) ...midi(m.elements)];

int noteCount(Score s) => [
      for (final m in s.measures)
        for (var v = 0; v < 4; v++)
          for (final e in m.voiceAt(v))
            if (e is NoteElement) e,
    ].length;

void main() {
  group('lexing', () {
    test('a Scheme list is one token and does not derail the music', () {
      final s = scoreFromLilyPond(r'''
hide = #(define-music-function (m) (ly:music?) #{ \once \omit Accidental $m #})
\relative c' { c4 d e f }''');
      expect(allNotes(s), [60, 62, 64, 65]);
    });

    test('an identifier may contain an underscore', () {
      final s = scoreFromLilyPond(r'''
guitar_staff = \new Staff { c'4 d' e' f' }
\score { \guitar_staff }''');
      expect(allNotes(s), [60, 62, 64, 65]);
    });
  });

  group('rests', () {
    test('R and s are rests that keep time; R1*N spans N bars', () {
      final s = scoreFromLilyPond(r"{ R1*2 s1 c'1 }");
      expect(s.measures, hasLength(4));
      expect(allNotes(s), [60]);
    });
  });

  group(r'\transpose', () {
    test('moves the notes by the interval', () {
      expect(
          allNotes(scoreFromLilyPond(r"\transpose c d { c'4 e' }")), [62, 66]);
    });

    test('octave marks in the pair count', () {
      expect(allNotes(scoreFromLilyPond(r"\transpose c' c { c'4 }")), [48]);
    });

    test('moves the key with the notes', () {
      final s = scoreFromLilyPond(r"\transpose g f { \key c \major g'4 }");
      expect(allNotes(s), [65]);
      expect(s.keySignature.fifths, -2); // C up to B-flat major
    });

    test('a key past seven accidentals wraps to its enharmonic', () {
      // C major moved to F-flat major would be -8 flats; the model holds
      // -7..7, so it reads as the enharmonic E major (+4).
      final s = scoreFromLilyPond(r"\transpose c fes { \key c \major c'4 }");
      expect(s.keySignature.fifths, 4);
    });

    test('a wrapper around the whole score reaches every staff', () {
      final mp = multiPartFromLilyPond(r'''
\score { \transpose c' b \new ChoirStaff <<
  \new Staff { c'4 }
  \new Staff { e4 }
>> }''');
      expect(mp.parts, hasLength(2));
      expect(allNotes(mp.parts[0]), [59]);
      expect(allNotes(mp.parts[1]), [51]);
    });
  });

  group(r'\transposition', () {
    test('tags the part and keeps the written pitch', () {
      final s = scoreFromLilyPond(r"{ \transposition c c''4 d'' }");
      // The pitch argument is not a note.
      expect(allNotes(s), [72, 74]);
      expect(s.transposition, isNotNull);
      expect(allNotes(s.atConcertPitch()), [60, 62]);
    });

    test('survives a LilyPond round trip', () {
      for (final t in [
        Transposition.bFlat,
        Transposition.eFlat,
        const Transposition(Interval.perfectUnison, octaves: 1),
        const Transposition(Interval.perfectFourth, down: false),
      ]) {
        final s = Score(
          clef: Clef.treble,
          timeSignature: const TimeSignature(4, 4),
          transposition: t,
          measures: [
            Measure([
              NoteElement(
                id: 'n',
                pitches: const [Pitch(Step.d, octave: 5)],
                duration: const NoteDuration(DurationBase.whole),
              )
            ])
          ],
        );
        final back = scoreFromLilyPond(scoreToLilyPond(s));
        expect(allNotes(back), [74], reason: '$t');
        expect(allNotes(back.atConcertPitch()), allNotes(s.atConcertPitch()),
            reason: '$t');
      }
    });

    test('a B-flat instrument sounds a tone lower', () {
      final s = scoreFromLilyPond(r"{ \transposition bes d''4 }");
      expect(allNotes(s.atConcertPitch()), [72]);
    });
  });

  group('simultaneous music', () {
    test(r'\partcombine sounds its two parts together', () {
      final s = scoreFromLilyPond(r"\partcombine { c''1 } { e'1 }");
      expect(s.measures, hasLength(1));
      expect(midi(s.measures[0].elements), [72]);
      expect(midi(s.measures[0].voice2), [64]);
    });

    test('plain expressions that carry notes are parallel voices', () {
      final s = scoreFromLilyPond(r"<< { c''1 } { e'1 } >>");
      expect(s.measures, hasLength(1));
      expect(midi(s.measures[0].voice2), [64]);
    });

    test(r'explicit \new Voice contexts are parallel voices', () {
      final s = scoreFromLilyPond(
          r"\new Staff << \new Voice { c''1 } \new Voice { e'1 } >>");
      expect(s.measures, hasLength(1));
      expect(midi(s.measures[0].voice2), [64]);
    });

    test(r'\simultaneous and \sequential are << >> and { }', () {
      final s = scoreFromLilyPond(
          r"\sequential { \simultaneous { { c''1 } { e'1 } } d''1 }");
      expect(s.measures, hasLength(2));
      expect(midi(s.measures[0].voice2), [64]);
      expect(midi(s.measures[1].elements), [74]);
    });

    test('a note-less global of spacers does not push the music back', () {
      final s = scoreFromLilyPond(r'''
global = { \time 3/4 \key g \major s2.*2 \bar "|." }
\new Staff << \global { d''2. e'' } >>''');
      expect(s.measures, hasLength(2));
      expect(s.keySignature.fifths, 1);
      expect(s.timeSignature?.beats, 3);
    });

    test(r'a \new Voice of spacers is settings, not voice 1', () {
      final s = scoreFromLilyPond(r'''
global = { \time 4/4 s1*2 }
\new Staff << \new Voice \global \new Voice = "v" { c''1 d'' } >>''');
      expect(s.measures, hasLength(2));
      expect(midi(s.measures[0].elements), [72]);
      expect(s.measures[0].voice2, isEmpty);
    });

    test("a music function's argument is not a part of its own", () {
      final s = scoreFromLilyPond(r'''
incipit = #(define-music-function (m) (ly:music?) #{ #})
inc = { e''2. }
\new Staff << \incipit \inc { c''1 } >>''');
      expect(s.measures.every((m) => m.voice2.isEmpty), isTrue);
    });

    test('lyrics and figures keep their spacers', () {
      final s = scoreFromLilyPond(r'''
\score { <<
  \new FiguredBass \figuremode { <6>4 s4 <6 4>4 s4 }
  \new Staff { c4 c c c }
>> }''');
      expect([for (final f in s.figuredBass) f.figures.length], [1, 2]);
    });
  });

  group(r'\relative through << >> follows TEXT order (LilyPond 2.24)', () {
    test('after the split the reference is the last branch', () {
      // LilyPond MIDI: 72 71 72 74 76 67 66 74 71.
      final s = scoreFromLilyPond(
          r"\relative c'' { c16 b c d << e4 \\ { g,8 fis } >> | d'8 b }");
      final all = [for (final m in s.measures) ...midi(m.elements)];
      expect(all.sublist(all.length - 2), [74, 71]);
    });

    test('relative accepts a command body', () {
      final s = scoreFromLilyPond(
          r'''mel = \relative c'' \new Voice = "m" { c4 d e f }
\score { \new Staff \mel }''');
      expect(allNotes(s), [72, 74, 76, 77]);
    });
  });

  group('repeats', () {
    test(r'\repeat volta writes its music once, with repeat barlines', () {
      final s = scoreFromLilyPond(r"{ \repeat volta 2 { c'1 d' } e'1 }");
      expect(s.measures, hasLength(3));
      expect(s.measures[0].startRepeat, isTrue);
      expect(s.measures[1].endRepeat, isTrue);
      expect(s.measures[2].endRepeat, isFalse);
      // Performance order plays the repeated bars twice.
      expect(playbackTimeline(s).length, 5);
    });

    test(r'\alternative endings become volta brackets', () {
      final s = scoreFromLilyPond(
          r"{ \repeat volta 2 { c'1 } \alternative { { d'1 } { e'1 } } f'1 }");
      expect(s.measures.map((m) => m.volta), [null, 1, 2, null]);
      expect(s.measures[0].startRepeat, isTrue);
      expect(s.measures[1].endRepeat, isTrue);
      expect(s.measures[2].endRepeat, isFalse);
      final pitchOf = {
        for (final m in s.measures)
          for (final e in m.elements)
            if (e is NoteElement) e.id: e.pitches.first.midiNumber,
      };
      final order = [
        for (final n in playbackTimeline(s)) pitchOf[n.elementId],
      ];
      expect(order, [60, 62, 60, 64, 65]);
    });

    test(r'a full pickup bar closes before the repeat opens', () {
      final s = scoreFromLilyPond(r"{ \partial 4 g4 \repeat volta 2 { c'1 } }");
      expect(s.measures[0].startRepeat, isFalse);
      expect(s.measures[1].startRepeat, isTrue);
    });
  });

  group('staves', () {
    test(r'\parallelMusic defines its variables bar by bar', () {
      final mp = multiPartFromLilyPond(r'''
\parallelMusic #'(up down) {
  c''1 |
  c1 |
  d''1 |
  d1 |
}
\score { << \new Staff \up \new Staff \down >> }''');
      expect(mp.parts, hasLength(2));
      expect(allNotes(mp.parts[0]), [72, 74]);
      expect(allNotes(mp.parts[1]), [48, 50]);
    });

    test('bare voices in a staff group are one staff each', () {
      final mp = multiPartFromLilyPond(r'''
\score { \new StaffGroup <<
  \new Voice = "a" { c''1 }
  \new Lyrics \lyricsto "a" { la }
  \new Voice = "b" { e'1 }
  \new Voice = "c" { c1 }
>> }''');
      expect(mp.parts, hasLength(3));
      expect([for (final p in mp.parts) noteCount(p)], [1, 1, 1]);
    });

    test('a Lyrics context does not swallow the next staff', () {
      final mp = multiPartFromLilyPond(r'''
\score { <<
  \new Staff { c''1 }
  \new Lyrics \lyricmode { la }
  \new Staff { c1 }
>> }''');
      expect(mp.parts, hasLength(2));
    });

    test('a MIDI-only score beside a layout score adds no parts', () {
      final mp = multiPartFromLilyPond(r'''
music = << \new Staff { c''1 } \new Staff { c1 } >>
\score { \music \layout { } }
\score { \unfoldRepeats \music \midi { } }''');
      expect(mp.parts, hasLength(2));
    });

    test('scoreFromLilyPond of a multi-staff file is its first staff', () {
      final s = scoreFromLilyPond(
          r"\score { << \new Staff { c''1 } \new Staff { c1 } >> }");
      expect(allNotes(s), [72]);
    });

    test(r'a \new Dynamics line lands on the staff above it', () {
      final mp = multiPartFromLilyPond(r'''
\score { <<
  \new Staff { c''2 d'' e''1 }
  \new Dynamics { s2\p s2 s1\f }
  \new Staff { c1 c }
>> }''');
      expect(mp.parts, hasLength(2));
      final dyn = mp.parts[0].dynamics;
      expect(dyn.map((d) => d.level), [DynamicLevel.p, DynamicLevel.f]);
      final ids = [
        for (final m in mp.parts[0].measures) ...m.elements.map((e) => e.id)
      ];
      expect(dyn.map((d) => d.elementId), [ids[0], ids[2]]);
    });
  });

  group('note languages', () {
    test('solfège names read in italiano', () {
      final s = scoreFromLilyPond(
          r'''\language "italiano" \relative do' { do4 re mi fad }''');
      expect(allNotes(s), [60, 62, 64, 66]);
    });

    test('svenska spells sharps -iss and flats -ess', () {
      final s =
          scoreFromLilyPond(r'''\language "svenska" { ciss'4 ess' h' }''');
      expect(allNotes(s), [61, 63, 71]);
    });
  });
}
