import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Text that leaks out of its field and is then read as MUSIC.
///
/// Both of these were found by the cross-format sweep on real CPDL files, and
/// both are the same shape: a metadata or annotation string carries a character
/// that ends its field, and everything after it lands in the note stream, where
/// any a-g letter parses as a note. The scores gained notes that are in no
/// source anywhere.

Score oneNote(
        {ScoreMetadata? metadata, List<Annotation> annotations = const []}) =>
    Score(
      clef: Clef.treble,
      metadata: metadata ?? const ScoreMetadata(),
      annotations: annotations,
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

int noteCount(Score s) =>
    s.measures.expand((m) => m.elements).whereType<NoteElement>().length;

void main() {
  group('kern reference records stay on one line', () {
    // A `!!!` record and a `*I"` tag each occupy exactly one line, so an
    // embedded newline does not extend them — it ENDS them and drops the rest
    // into the spine. A CPDL source whose LYR field ran over four lines left a
    // bare `C1` in the data column, and it read back as a phantom C3 whole note
    // ahead of the first real one.
    test('a multi-line lyricist does not become a note', () {
      final s = oneNote(
        metadata: const ScoreMetadata(
          lyricist: 'Promptuarii musici, sacras harmonias\n'
              'e diversis autoribus\n'
              'C1\n'
              'National Royal Library',
        ),
      );
      final kern = scoreToKern(s);
      // Every line before the spine must be a reference record.
      for (final line in kern.split('\n')) {
        if (line.startsWith('**kern')) break;
        expect(line.isEmpty || line.startsWith('!!!'), isTrue,
            reason: 'stray line in the header: "$line"');
      }
      expect(noteCount(scoreFromKern(kern)), 1);
    });

    test('a multi-line instrument name does not become a note', () {
      final s =
          oneNote(metadata: const ScoreMetadata(instrument: 'Cantus\n\nC1'));
      expect(noteCount(scoreFromKern(scoreToKern(s))), 1);
    });
  });

  group('ABC quoted strings escape their delimiter', () {
    // The delimiter is `"`, so a text carrying one closes the string early and
    // the words after it sit bare in the tune body. Brownson's "Newport" has a
    // hymn lyric quoting speech — `They say, "The Lord nor sees nor hears:"` —
    // and it gained six phantom notes from the letters in those words.
    test('a quotation mark inside an annotation is not a note', () {
      final s = oneNote(annotations: const [
        Annotation('e0', 'They say, "The Lord nor sees nor hears:" be wise'),
      ]);
      final abc = scoreToAbc(s);
      expect(noteCount(scoreFromAbc(abc)), 1,
          reason: 'the annotation text was parsed as music');
    });

    test('the text itself survives the round trip', () {
      const text = 'a "quoted" phrase';
      final back = scoreFromAbc(scoreToAbc(oneNote(
        annotations: const [Annotation('e0', text)],
      )));
      expect(back.annotations.map((a) => a.text), [text]);
    });

    test('a newline inside an annotation does not end the tune line', () {
      final s = oneNote(annotations: const [Annotation('e0', 'aa\nbb cc')]);
      expect(noteCount(scoreFromAbc(scoreToAbc(s))), 1);
    });

    test('an ordinary chord symbol is unchanged', () {
      final abc =
          scoreToAbc(oneNote(annotations: const [Annotation('e0', 'Gm7')]));
      expect(abc, contains('"Gm7"'));
    });
  });
}
