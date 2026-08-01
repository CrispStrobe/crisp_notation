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
        {ScoreMetadata? metadata,
        List<Annotation> annotations = const [],
        List<ChordSymbol> chordSymbols = const []}) =>
    Score(
      clef: Clef.treble,
      metadata: metadata ?? const ScoreMetadata(),
      annotations: annotations,
      chordSymbols: chordSymbols,
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
      final abc = scoreToAbc(oneNote(chordSymbols: [
        ChordSymbol(
            'e0', const Pitch(Step.g, octave: 4), ChordSymbolKind.minorSeventh),
      ]));
      expect(abc, contains('"Gm7"'));
    });

    test('an ANNOTATION that reads as a chord is shielded', () {
      // Bare is the chord channel, so "Gm7" written bare would come back as
      // harmony rather than as the text it was.
      final s = oneNote(annotations: const [Annotation('e0', 'Gm7')]);
      final abc = scoreToAbc(s);
      expect(abc, contains('"^Gm7"'));
      final back = scoreFromAbc(abc);
      expect(back.annotations.map((a) => a.text), ['Gm7']);
      expect(back.chordSymbols, isEmpty);
    });
  });

  group('ABC lyric lines stay on one line', () {
    // A `w:` line ends at the newline, so a syllable carrying one splits the
    // line and everything after it lands in the TUNE BODY. A NIFC kern file
    // whose lyrics hold stray tokens gained four phantom notes that way — the
    // spilled text `8a/ 8cc 4dd 4cc` is perfectly good ABC.
    Score sung(String syllable) => Score(
          clef: Clef.treble,
          lyrics: [Lyric('e0', syllable)],
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

    test('a syllable with a newline does not become notes', () {
      final abc = scoreToAbc(sung('ex\n8a/ 8cc 4dd 4cc'));
      expect(noteCount(scoreFromAbc(abc)), 1,
          reason: 'the lyric spilled into the tune body:\n$abc');
    });

    test('the w: line is the last line of the tune', () {
      final abc = scoreToAbc(sung('a\nb\nc'));
      final body = abc.split('\n').where((l) => l.trim().isNotEmpty).toList();
      expect(body.where((l) => l.startsWith('w:')), hasLength(1));
      expect(body.last, startsWith('w:'));
    });

    test('an all-whitespace syllable is written as a skip', () {
      final abc = scoreToAbc(sung('   '));
      expect(noteCount(scoreFromAbc(abc)), 1);
    });

    test('an ordinary syllable is unchanged', () {
      expect(scoreToAbc(sung('pa')), contains('w:pa'));
    });
  });

  group('LilyPond quoted strings resolve every escape', () {
    // The lexer honoured `\\"` but not `\\\\`. Our own writer emits a syllable
    // ending in a backslash as `"1F\\\\"`, so the second backslash stayed live,
    // ate the closing quote, and the string ran on — swallowing the following
    // `_` skips into the lyric. A NIFC kern file's syllables inflated 82 -> 158
    // that way, and the mangled text then spilled out of ABC's `w:` line as
    // four phantom notes.
    Score sung(String syllable) => Score(
          clef: Clef.treble,
          lyrics: [Lyric('e0', syllable), const Lyric('e1', 'pa')],
          measures: [
            Measure([
              NoteElement(
                pitches: const [Pitch(Step.c, octave: 4)],
                duration: const NoteDuration(DurationBase.quarter),
                id: 'e0',
              ),
              NoteElement(
                pitches: const [Pitch(Step.d, octave: 4)],
                duration: const NoteDuration(DurationBase.quarter),
                id: 'e1',
              ),
            ]),
          ],
        );

    /// Syllables in NOTE ORDER. Ids are regenerated by every reader, so
    /// comparing them across a round trip compares nothing.
    List<String> byNote(Score s) {
      final byId = {for (final l in s.lyrics) l.elementId: l.text};
      return [
        for (final m in s.measures)
          for (final e in m.elements)
            if (e is NoteElement) byId[e.id] ?? '*',
      ];
    }

    for (final syllable in [r'1F\', 'a"b', r'back\slash', r'\', 'plain']) {
      test('a syllable ${jsonish(syllable)} survives', () {
        final s = sung(syllable);
        final back = scoreFromLilyPond(scoreToLilyPond(s));
        expect(back.lyrics, hasLength(2),
            reason: 'the string ran past its closing quote');
        expect(byNote(back), byNote(s));
      });
    }
  });
}

/// A readable label for a test name.
String jsonish(String s) => '"${s.replaceAll(r'\', r'\\')}"';
