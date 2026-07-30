import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Voice splits that do NOT occupy a whole bar.
///
/// `_processParallelVoices` used to close the measure after every `<< … >>`
/// group, which invented a barline: `<< … >> r4 << … >>` is ONE bar of 4/4 and
/// read as three. Bars now end only when they fill.
///
/// The offsets below are the part with no prior coverage, and their absence is
/// why an earlier attempt at this shipped green while corrupting real files.
/// `\partial` implements an anacrusis by PRELOADING elapsed time, so a branch
/// rewound to zero silently gets a whole bar to fill and swallows the notes
/// after the pickup.
List<int> v(List<MusicElement> voice) => [
      for (final e in voice)
        if (e is NoteElement) e.pitches.first.midiNumber,
    ];

/// Rests included, as positions — an inner voice starting mid-bar must be
/// padded or its notes land at the wrong beat.
List<String> shape(List<MusicElement> voice) => [
      for (final e in voice)
        if (e is NoteElement) 'n' else if (e is RestElement) 'r',
    ];

void main() {
  test('two splits in one bar stay in one bar', () {
    // 2 beats + 1 rest + 1 beat = a single 4/4 bar.
    final s = scoreFromLilyPond(
      r"\relative c' { << { c4 d } \\ { e4 f } >> r4 << { g4 } \\ { a4 } >> }",
    );
    expect(s.measures, hasLength(1), reason: 'a mid-bar split invented a bar');
    expect(v(s.measures[0].elements), [60, 62, 67]);
    // The second split's `a` resolves DOWN from d (a fourth below beats a
    // fifth above), so A3 — not A4.
    expect(v(s.measures[0].voice2), [64, 65, 57]);
  });

  test('a split that starts mid-bar is padded to the right beat', () {
    final s = scoreFromLilyPond(
      r"\relative c' { c4 d4 << { e4 f } \\ { g4 a } >> }",
    );
    expect(s.measures, hasLength(1));
    expect(v(s.measures[0].elements), [60, 62, 64, 65]);
    // Voice 2 is silent for the first half, so it must carry two rests before
    // its notes — otherwise g/a sound on beats 1-2.
    expect(shape(s.measures[0].voice2), ['r', 'r', 'n', 'n']);
    expect(v(s.measures[0].voice2), [67, 69]);
  });

  test('a whole-bar split still fills exactly one bar', () {
    final s = scoreFromLilyPond(
      r"\relative c' { << { c4 d e f } \\ { g4 a b c } >> "
      r"<< { c4 d e f } \\ { g4 a b c } >> }",
    );
    expect(s.measures, hasLength(2));
    expect(v(s.measures[0].elements), [60, 62, 64, 65]);
    expect(v(s.measures[0].voice2), [55, 57, 59, 60]); // g is a 4th below c'
    expect(v(s.measures[1].voice2), hasLength(4));
  });

  group('anacrusis', () {
    // \partial preloads elapsed time rather than shortening the bar, so every
    // branch has to be rewound to that preloaded position.
    const src = r'''
      \relative c' {
        \time 4/4
        \partial 4
        << { d4 } \\ { d4 } >>
        << { b'4 d, c' d, } \\ { g4 d fis d } >>
      }''';

    test('the pickup bar holds only the pickup, in BOTH voices', () {
      final s = scoreFromLilyPond(src);
      expect(s.measures.length, greaterThanOrEqualTo(2));
      expect(v(s.measures[0].elements), hasLength(1),
          reason: 'voice 1 pickup bar');
      expect(v(s.measures[0].voice2), hasLength(1),
          reason: 'voice 2 swallowed the next bar — the \\partial preload was '
              'lost when the branch rewound');
    });

    test('the bar after the pickup is intact in both voices', () {
      final s = scoreFromLilyPond(src);
      expect(v(s.measures[1].elements), hasLength(4));
      expect(v(s.measures[1].voice2), hasLength(4));
    });
  });

  test('an inner voice longer than voice 1 keeps its own voice', () {
    final s = scoreFromLilyPond(
      r"\relative c' { << { c4 } \\ { e4 f g a b c } >> }",
    );
    final inner = [
      for (final m in s.measures) ...v(m.voice2),
    ];
    expect(inner, hasLength(6), reason: 'overflow was dropped or promoted');
    for (final m in s.measures.skip(1)) {
      expect(v(m.elements), isEmpty,
          reason: 'inner-voice overflow leaked into voice 1');
    }
  });
}
