import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Lyrics on an INNER voice.
///
/// ⚠️ `\addlyrics` attaches to the staff's FIRST voice, so lyrics sitting on
/// voice 2 or 3 had nowhere to go and were silently dropped — 109 of 160 in
/// one corpus vocal score. That is not an exotic layout: two sung parts
/// sharing a staff is the ordinary way choral music is engraved.
///
/// The fix is LilyPond's own: name the voices and address them with
/// `\lyricsto`. It is applied ONLY when an inner voice actually carries
/// lyrics, so every other score's output is unchanged.
void main() {
  Score scored() => Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(
            [
              for (var i = 0; i < 4; i++)
                NoteElement(
                  id: 'a$i',
                  pitches: const [Pitch(Step.g, octave: 4)],
                  duration: const NoteDuration(DurationBase.quarter),
                ),
            ],
            voice2: [
              for (var i = 0; i < 4; i++)
                NoteElement(
                  id: 'b$i',
                  pitches: const [Pitch(Step.c, octave: 4)],
                  duration: const NoteDuration(DurationBase.quarter),
                ),
            ],
          )
        ],
        lyrics: const [
          Lyric('a0', 'up'),
          Lyric('a1', 'per'),
          Lyric('b0', 'low'),
          Lyric('b1', 'er'),
        ],
      );

  test('lyrics on voice 2 survive, on the right notes', () {
    final back = scoreFromLilyPond(scoreToLilyPond(scored()));
    final m = back.measures.single;
    final at = <String?, String>{
      for (var i = 0; i < m.elements.length; i++) m.elements[i].id: 'v1.$i',
      for (var i = 0; i < m.voice2.length; i++) m.voice2[i].id: 'v2.$i',
    };
    expect(
      {for (final l in back.lyrics) at[l.elementId]: l.text},
      {'v1.0': 'up', 'v1.1': 'per', 'v2.0': 'low', 'v2.1': 'er'},
    );
  });

  test('verses are numbered PER VOICE, not per lyric block', () {
    // ⚠️ A single counter numbered blocks in file order, so voice 2's first
    // verse continued voice 1's — six verses where the score has two.
    final src = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: scored().measures,
      lyrics: const [
        Lyric('a0', 'one', verse: 1),
        Lyric('a1', 'two', verse: 1),
        Lyric('a0', 'ONE', verse: 2),
        Lyric('b0', 'low', verse: 1),
        Lyric('b0', 'LOW', verse: 2),
      ],
    );
    final back = scoreFromLilyPond(scoreToLilyPond(src));
    expect(back.lyrics.map((l) => l.verse).toSet(), {1, 2});
    expect(back.lyrics, hasLength(5));
  });

  test('a single-voice song still uses plain \\addlyrics', () {
    final plain = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        Measure([
          NoteElement(
            id: 'a0',
            pitches: const [Pitch(Step.c, octave: 4)],
            duration: const NoteDuration(DurationBase.whole),
          )
        ])
      ],
      lyrics: const [Lyric('a0', 'sing')],
    );
    final ly = scoreToLilyPond(plain);
    expect(ly, contains(r'\addlyrics'));
    expect(ly, isNot(contains(r'\lyricsto')));
    expect(ly, isNot(contains(r'\new Voice =')));
  });

  test('inner-voice lyrics DO name the voices', () {
    final ly = scoreToLilyPond(scored());
    expect(ly, contains(r'\new Voice = "v0"'));
    expect(ly, contains(r'\new Voice = "v1"'));
    expect(ly, contains(r'\lyricsto "v1"'));
  });
}
