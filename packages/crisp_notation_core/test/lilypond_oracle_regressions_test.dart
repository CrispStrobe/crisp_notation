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
}
