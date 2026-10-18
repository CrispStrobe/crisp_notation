import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Reader bugs found by comparing against LilyPond's own MIDI
/// (lilypond_oracle_test.dart), each pinned on a minimal source.
void main() {
  /// Every struck pitch as (onset in quarters, MIDI number), sorted.
  List<(double, int)> onsets(Score s) {
    final byId = <String, NoteElement>{};
    for (final m in s.measures) {
      for (var v = 0; v < 4; v++) {
        for (final e in m.voiceAt(v)) {
          if (e is NoteElement && e.id != null) byId[e.id!] = e;
        }
      }
    }
    return [
      for (final n in playbackTimeline(s))
        if (byId[n.elementId] case final e?)
          for (final p in e.pitches) (n.start.toDouble() * 4, p.midiNumber),
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2 - b.$2);
  }

  group('a pickup set in voice 1 times every voice', () {
    test('\\partcombine with the \\partial in the upper part', () {
      final s = scoreFromLilyPond(r"""
\new Staff \partcombine
  { \time 3/4 \partial 4 e'4 f' g' a' }
  { c'4 d' e' f' }
""");
      expect(onsets(s), [
        (0.0, 60), (0.0, 64), //
        (1.0, 62), (1.0, 65),
        (2.0, 64), (2.0, 67),
        (3.0, 65), (3.0, 69),
      ]);
    });

    test('a shared \\global carrying \\partial before two voices', () {
      final s = scoreFromLilyPond(r"""
global = { \time 4/4 \partial 4 }
\new Staff <<
  \global
  \new Voice { \voiceOne e'4 f' g' a' b' }
  \new Voice { \voiceTwo c'4 d' e' f' g' }
>>
""");
      final got = onsets(s);
      expect(got.where((o) => o.$2 == 62).single.$1, 1.0);
      expect(got.where((o) => o.$2 == 67).map((o) => o.$1), [2.0, 4.0]);
      // The pickup bar is one beat; the inner voice does not pad it.
      expect(s.measures.length, 2);
    });
  });

  test('a pickup stated in one staff times the others', () {
    final mp = multiPartFromLilyPond(r"""
upper = { \time 3/4 \partial 4 g'4 | c''2. | e''2 }
lower = { c4 | c2. | g,2 }
\score { << \new Staff \upper \new Staff { \clef bass \lower } >> }
""");
    expect(mp.parts, hasLength(2));
    final low = mp.parts[1];
    expect(onsets(low), [(0.0, 48), (1.0, 48), (4.0, 43)]);
    expect(low.measures.first.pickup, isTrue);
    expect(low.timeSignature, mp.parts[0].timeSignature);
  });

  test('a zero-length skip (s1*0) takes no time', () {
    final s = scoreFromLilyPond(
      r"""{ s1*0^\markup { Slowly } a'2 a' | \skip 2*0 b'1 }""",
    );
    expect(onsets(s), [(0.0, 69), (2.0, 69), (4.0, 71)]);
    expect(s.measures, hasLength(2));
  });

  group('a voice\'s own inner voices survive a second voice beside it', () {
    test('in a bar that is already closed', () {
      final s = scoreFromLilyPond(r"""
\new Staff <<
  \new Voice { \voiceOne c''4 << { e''4 } \\ { g'4 } >> d''2 | c''1 }
  \new Voice { \voiceTwo c4 d e2 | c1 }
>>
""");
      expect(onsets(s), [
        (0.0, 48), (0.0, 72), //
        (1.0, 50), (1.0, 67), (1.0, 76),
        (2.0, 52), (2.0, 74),
        (4.0, 48), (4.0, 72),
      ]);
    });

    test('in the bar still open when the voices end', () {
      final s = scoreFromLilyPond(r"""
\new Staff <<
  \new Voice { \voiceOne c''2 << { e''2 } \\ { g'2 } >> }
  \new Voice { \voiceTwo c1 }
>>
""");
      expect(onsets(s), [(0.0, 48), (0.0, 72), (2.0, 67), (2.0, 76)]);
    });
  });

  test('a mid-piece \\partial starts a short bar of its own', () {
    final s = scoreFromLilyPond(r"""
\new Staff { \time 2/4
  << { c''4 d'' \partial 8*3 e''4 r8 } \\ { c'4 d' e'4 r8 } >>
}
""");
    expect(onsets(s), [
      (0.0, 60), (0.0, 72), //
      (1.0, 62), (1.0, 74),
      (2.0, 64), (2.0, 76),
    ]);
    expect(s.measures, hasLength(2));
  });

  test('staves behind \\relative wrappers are staves, at its octaves', () {
    final mp = multiPartFromLilyPond(r"""
\score {
  \new ChoirStaff \relative a' <<
    \new Staff { a4 b c d }
    \relative a \new Staff { \clef bass a4 b c d }
  >>
}
""");
    expect(mp.parts, hasLength(2));
    expect(onsets(mp.parts[0]), [(0.0, 69), (1.0, 71), (2.0, 72), (3.0, 74)]);
    expect(onsets(mp.parts[1]), [(0.0, 57), (1.0, 59), (2.0, 60), (3.0, 62)]);
  });

  test('\\unfoldRepeats writes every repeat out, as LilyPond 2.24 plays it',
      () {
    // Pitches checked against LilyPond's MIDI for this source: relative
    // octaves are those of the written text, and the first alternative
    // serves the passes that have none of their own.
    final s = scoreFromLilyPond(r"""
\score {
  \unfoldRepeats \new Staff \relative c' {
    \repeat volta 3 { c4 e g } \alternative { { c4 } { e4 } } d4
  }
  \midi { }
}
""");
    expect(onsets(s).map((o) => o.$2), [
      60, 64, 67, 72, //
      60, 64, 67, 72,
      60, 64, 67, 76,
      74,
    ]);
    expect(onsets(s).last.$1, 12.0);
  });

  test('a pitched rest (e4\\rest) is silent but anchors \\relative', () {
    // LilyPond's MIDI for this: 72 at 0, 67 at 2, 72 at 3 — the rest at e'
    // is what the g after it is reckoned from.
    final s = scoreFromLilyPond(r"""\relative c'' { c4 e,\rest g c }""");
    expect(onsets(s), [(0.0, 72), (2.0, 67), (3.0, 72)]);
    expect(s.measures.single.elements[1], isA<RestElement>());
  });

  test('\\repeat unfold repeats the body at its written octaves', () {
    // LilyPond's MIDI: 60 64 67 72 60 64 67 72 74.
    final s = scoreFromLilyPond(
      r"""\relative c' { \repeat unfold 2 { c4 e g c } d }""",
    );
    expect(onsets(s).map((o) => o.$2), [60, 64, 67, 72, 60, 64, 67, 72, 74]);
  });

  test('a chord may join pitches without a space (<b,g>)', () {
    final s = scoreFromLilyPond(r"""\relative c'' { <b,g>4 d <fis'!a>2 }""");
    // LilyPond's MIDI for this source.
    expect(onsets(s), [(0.0, 55), (0.0, 59), (1.0, 62), (2.0, 78), (2.0, 81)]);
  });

  test('\\relative with no start pitch reckons from f', () {
    // contrapunctusXI's soprano: `\relative { r4 a' e' d }` starts on A4.
    final s = scoreFromLilyPond(r"""\relative { r4 a' e' d | c,1 }""");
    expect(onsets(s).map((o) => o.$2), [69, 76, 74, 60]);
  });

  group('playback: reads the score LilyPond plays', () {
    const twoScores = r"""
music = { c'4 d' e' f' }
\score { \new Staff \music \layout { } }
\score { \new Staff { s2 \music } \midi { } }
""";

    test('the engraved score by default', () {
      expect(onsets(scoreFromLilyPond(twoScores)).first, (0.0, 60));
    });

    test('the \\midi-only score with playback: true', () {
      expect(
        onsets(scoreFromLilyPond(twoScores, playback: true)).first,
        (2.0, 60),
      );
      final mp = multiPartFromLilyPond(twoScores, playback: true);
      expect(onsets(mp.parts.single).first, (2.0, 60));
    });

    test('a source with one score reads the same either way', () {
      const one = r"""\score { \new Staff { c'4 d' } \layout { } \midi { } }""";
      expect(
        onsets(scoreFromLilyPond(one, playback: true)),
        onsets(scoreFromLilyPond(one)),
      );
    });
  });

  test('a meter change in voice 1 bars every voice', () {
    // Voice 2 used to start in voice 1's LAST meter, 3/4, and bar its
    // quarters three to a bar against voice 1's 2/4.
    final s = scoreFromLilyPond(r"""
\new Staff <<
  { \time 2/4 c''2 c''2 \time 3/4 c''2. c''2. }
  \\
  { e'4 e' e' e' e' e' e' e' e' e' }
>>
""");
    expect(
      onsets(s).where((o) => o.$2 == 64).map((o) => o.$1),
      [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0],
    );
    expect(onsets(s).where((o) => o.$2 == 72).map((o) => o.$1),
        [0.0, 2.0, 4.0, 7.0]);
  });

  group('a note crossing the barline is cut into tied notes', () {
    test('in one voice only: the voices stay together', () {
      // Voice 2's bar used to close early, before g'2; from there each of
      // its bars was paired with the next one of voice 1.
      final s = scoreFromLilyPond(r"""
\new Staff << { c''1 d''1 e''1 } \\ { a'2. g'2 f'4 e'2 d'2 } >>
""");
      expect(s.measures, hasLength(3));
      final first = s.measures[0].voice2.last as NoteElement;
      final rest = s.measures[1].voice2.first as NoteElement;
      expect(first.pitches.single.midiNumber, 67);
      expect(first.duration, NoteDuration.quarter);
      expect(first.tieToNext, isTrue);
      expect(rest.pitches.single.midiNumber, 67);
      expect(rest.duration, NoteDuration.quarter);
      expect(rest.tieToNext, isFalse);
      expect(onsets(s), [
        (0.0, 69), (0.0, 72), (3.0, 67), //
        (4.0, 67), (4.0, 74), (5.0, 65), (6.0, 64),
        (8.0, 62), (8.0, 76),
      ]);
    });

    test('the second piece takes no syllable', () {
      final s = scoreFromLilyPond(r"""
\new Staff { \time 3/4 c'2 d'2 e'2 f'2. }
\addlyrics { one two three four }
""");
      final notes = [
        for (final m in s.measures) ...m.elements.whereType<NoteElement>(),
      ];
      expect(
        notes.map((n) => n.pitches.single.midiNumber),
        [60, 62, 62, 64, 65],
      );
      final text = {for (final l in s.lyrics) l.elementId: l.text};
      expect(
        [for (final n in notes) text[n.id]],
        ['one', 'two', null, 'three', 'four'],
      );
    });
  });

  test('a duration ends a note: d8cis is two notes', () {
    final s = scoreFromLilyPond(
      r"""\relative c' { d2~ d8cis d e r4.d8 f4 g }""",
    );
    expect(onsets(s).where((o) => o.$1 > 0), [
      (2.0, 62), (2.5, 61), (3.0, 62), (3.5, 64), //
      (5.5, 62), (6.0, 65), (7.0, 67),
    ]);
  });

  test('a grace\'s duration carries on to the notes after it', () {
    final s = scoreFromLilyPond(r"""
\relative c'' { \time 2/4 g4 \acciaccatura { g8 } f f d4 | \grace { c16 } e e e4 | c2 }
""");
    expect(onsets(s), [
      (0.0, 67), (1.0, 65), (1.5, 65), (2.0, 62), //
      (3.0, 64), (3.25, 64), (3.5, 64), (4.5, 60),
    ]);
  });

  test('a grace spacer or grace chord takes no time', () {
    final s = scoreFromLilyPond(r"""
\relative c'' { \time 3/4 \appoggiatura <a a'>16 <c g'>4 \grace s8 r4 c4 |
  \grace <e g>8 f4 f f }
""");
    expect(onsets(s), [
      (0.0, 72), (0.0, 79), (2.0, 72), //
      (3.0, 77), (4.0, 77), (5.0, 77),
    ]);
    final f = s.measures[1].elements.first as NoteElement;
    expect(f.graceNotes.map((p) => p.midiNumber), [76, 79]);
  });

  test('a repeat body need not be braced: \\repeat unfold 4 c8', () {
    final s = scoreFromLilyPond(r"""\relative c' { \repeat unfold 4 c8 d2 }""");
    expect(onsets(s), [(0.0, 60), (0.5, 60), (1.0, 60), (1.5, 60), (2.0, 62)]);
  });

  test('\\unfoldRepeats writes a tremolo out', () {
    final s = scoreFromLilyPond(r"""
\score { \unfoldRepeats \new Staff \relative c'' {
  \repeat tremolo 4 e16 f4 \repeat tremolo 2 { g16 a } b4 | c1 } }
""");
    expect(onsets(s), [
      (0.0, 76), (0.25, 76), (0.5, 76), (0.75, 76), (1.0, 77), //
      (2.0, 79), (2.25, 81), (2.5, 79), (2.75, 81), (3.0, 83),
      (4.0, 84),
    ]);
  });

  test('\\unfoldRepeats inside a variable unfolds its music', () {
    final s = scoreFromLilyPond(r"""
piano = \relative c'' { \repeat volta 2 { c4 d } \repeat tremolo 2 { e8 f } }
midiPiano = { \unfoldRepeats \piano }
\score { \new Staff \midiPiano \midi { } }
""");
    expect(s.measures.any((m) => m.endRepeat || m.startRepeat), isFalse);
    expect(onsets(s), [
      (0.0, 72), (1.0, 74), (2.0, 72), (3.0, 74), //
      (4.0, 76), (4.5, 77), (5.0, 76), (5.5, 77),
    ]);
  });

  test('a tremolo lasts its repeats: \\repeat tremolo 8 e32 is e4:32', () {
    final s = scoreFromLilyPond(r"""
\relative c'' { \repeat tremolo 8 e32 f4 \repeat tremolo 4 { g16 a } |
  \repeat tremolo 3 { c8 } d4 r2 | c1 }
""");
    expect(onsets(s), [
      (0.0, 76), (1.0, 77), (2.0, 79), (3.0, 81), //
      (4.0, 84), (5.5, 86), (8.5, 84),
    ]);
    final e = s.measures.first.elements.first as NoteElement;
    expect(e.duration, NoteDuration.quarter);
    expect(e.tremolo, 3);
  });

  test('a percent repeat takes its time and sounds once, as LilyPond plays it',
      () {
    final s = scoreFromLilyPond(r"""
\relative c'' { \time 3/4 \repeat percent 3 { c4 d e }
  \repeat percent 2 { f8 g } a4 | b2. }
""");
    expect(onsets(s), [
      (0.0, 72), (1.0, 74), (2.0, 76), //
      (9.0, 77), (9.5, 79), (11.0, 81), (12.0, 83),
    ]);
    // A whole bar repeated is drawn as the measure-repeat sign.
    expect(s.measures.map((m) => m.measureRepeat), [null, 1, 1, null, null]);
  });

  group('an octave mark or ! ends a note: e\'d is two notes', () {
    test('in music', () {
      final s = scoreFromLilyPond(
        r"""\relative c'' { c8 e'd c cis!d b,a | g1 }""",
      );
      expect(onsets(s), [
        (0.0, 72), (0.5, 88), (1.0, 86), (1.5, 84), //
        (2.0, 85), (2.5, 86), (3.0, 71), (3.5, 69), (4.0, 67),
      ]);
    });

    test('but not in lyrics, where d\'a is an elision', () {
      final s = scoreFromLilyPond(r"""
\new Staff { c'4 d' e' f' }
\addlyrics { d'a se -- ra }
""");
      expect(s.lyrics.map((l) => l.text), ["d'a", 'se', 'ra']);
    });
  });
}
