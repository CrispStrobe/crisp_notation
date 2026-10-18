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
}
