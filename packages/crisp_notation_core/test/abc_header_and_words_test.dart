import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Two bugs a single hand-written ABC tune exposed, both invisible to the
/// corpus: our 1,892 `.abc` files carry neither trailing `%` comments on header
/// fields nor any lyrics at all.
///
///   X:1                        % tune no 1
///   T:Dusty Miller (commented) % title
///   C:Trad.                    % traditional
///   …
///   W:Hey, the dusty miller, and his dusty coat;
///
/// 1. A `%` comment is legal at the end of ANY line, header fields included.
///    We took the whole rest of the line, so the title came back as
///    "Dusty Miller (commented) % title" and the composer as
///    "Trad.                    % traditional".
/// 2. `W:` (uppercase) was dropped entirely.
void main() {
  const dusty = '''
X:1                        % tune no 1
T:Dusty Miller (commented) % title
T:Binny's Jig              % an alternative title
C:Trad.                    % traditional
O:English                  % origin
M:3/4                      % meter
K:G                        % key
B>cd BAG|FA Ac BA|B>cd BAG|DG GB AG:|
W:Hey, the dusty miller, and his dusty coat;
W:He will win a shilling, or he spend a groat.
W:Dusty was the coat, dusty was the colour;
W:Dusty was the kiss, that I got frae the miller.
''';

  test('a trailing % comment is not part of the field value', () {
    final s = scoreFromAbc(dusty);
    expect(s.metadata.title, 'Dusty Miller (commented)');
    expect(s.metadata.composer, 'Trad.');
  });

  test('the meter and key still parse with a comment after them', () {
    final s = scoreFromAbc(dusty);
    expect(s.timeSignature, const TimeSignature(3, 4));
    expect(s.keySignature.fifths, 1); // G major
  });

  test('W: verse text is kept, one entry per line', () {
    final s = scoreFromAbc(dusty);
    expect(s.metadata.words, hasLength(4));
    expect(
        s.metadata.words.first, 'Hey, the dusty miller, and his dusty coat;');
  });

  test('W: is NOT turned into aligned lyrics', () {
    // `W:` carries no note alignment — a four-verse song has four lines and
    // nothing saying which note each word falls on. Inventing an alignment
    // would be worse than keeping it as verse text.
    expect(scoreFromAbc(dusty).lyrics, isEmpty);
  });

  test('the words round-trip through our own writer', () {
    final src = scoreFromAbc(dusty);
    final back = scoreFromAbc(scoreToAbc(src));
    expect(back.metadata.words, src.metadata.words);
  });

  test('the notes are unaffected', () {
    final s = scoreFromAbc(dusty);
    expect(
      s.measures.expand((m) => m.elements).whereType<NoteElement>(),
      isNotEmpty,
    );
  });

  test('an escaped %% survives as a literal in a lyric', () {
    // `%` starts a comment, so the writer escapes it — otherwise a syllable
    // containing one is truncated on reread. (The hostile-text matrix caught
    // this as a regression the moment header comment-stripping went in.)
    final score = Score(
      clef: Clef.treble,
      lyrics: const [Lyric('e0', '100% sure')],
      measures: [
        Measure([
          NoteElement(
            pitches: const [Pitch(Step.c, octave: 4)],
            duration: const NoteDuration(DurationBase.whole),
            id: 'e0',
          ),
        ]),
      ],
    );
    expect(scoreFromAbc(scoreToAbc(score)).lyrics.single.text, '100% sure');
  });
}
