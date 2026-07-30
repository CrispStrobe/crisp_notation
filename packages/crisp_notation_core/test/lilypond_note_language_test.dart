import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Note-name languages, and the accidental CONTRACTIONS every Dutch/German
/// score actually uses.
///
/// Both were silently wrong rather than loud: the parser's note gate rejected
/// the tokens outright, so `es`, `as` and `h` were dropped as if they were not
/// notes at all. Dropping a note also drops the relative reference forward,
/// which is why a four-voice score could read its first voice correctly and
/// then drift — one corpus file reached MIDI -65, another 3300.
List<int> midi(String ly) {
  final s = scoreFromLilyPond(ly);
  return [
    for (final m in s.measures)
      for (final v in m.voices)
        for (final e in v)
          if (e is NoteElement) ...e.pitches.map((p) => p.midiNumber),
  ];
}

void main() {
  group('Dutch (the default)', () {
    test('the es/as contractions are notes, not dropped', () {
      // Before: `es` matched neither the step nor any accidental alternative,
      // so it vanished and only `d c` survived.
      expect(midi(r"\relative c' { es4 d c es }"), [63, 62, 60, 63]);
      // From C4 the nearest Ab is BELOW (a third down), not above.
      expect(midi(r"\relative c' { as4 g }"), [56, 55]);
    });

    test('the spelled-out forms still read the same', () {
      expect(midi(r"\relative c' { ees4 aes bes }"), [63, 68, 70]);
      expect(midi(r"\relative c' { es4 as bes }"), [63, 68, 70]);
    });

    test('double-flat contractions', () {
      expect(midi(r"\relative c' { eses4 }"), [62]); // Ebb = D
      expect(midi(r"\relative c' { ases4 }"), [55]); // Abb = G, a 4th below
      expect(midi(r"\relative c' { asas4 }"), [55]);
    });

    test('a bare b is B NATURAL in Dutch', () {
      expect(midi(r"\relative c' { b4 }"), [59]); // B3, a semitone below C4
    });
  });

  group('German', () {
    test('h is B natural and a bare b is B FLAT', () {
      expect(midi('\\language "deutsch" \\relative c\' { h4 b a }'),
          [59, 58, 57]); // B3, Bb3, A3
    });

    test('hes and heses are B flat and B double-flat', () {
      expect(midi('\\language "deutsch" \\relative c\' { hes4 }'), [58]);
      expect(midi('\\language "deutsch" \\relative c\' { heses4 }'), [57]);
    });

    test('his is B sharp', () {
      expect(midi('\\language "deutsch" \\relative c\' { his4 }'), [60]);
    });

    test('an \\include of the language file counts too', () {
      // Corpus files often carry only the include, with no \language line.
      expect(midi('\\include "deutsch.ly" \\relative c\' { h4 }'), [59]);
    });

    test('German is NOT applied to an undeclared source', () {
      // A plain Dutch file must keep b = B NATURAL (59), where the same source
      // read as German would give B flat (58).
      expect(midi(r"\relative c' { b4 }"), [59]);
      expect(midi('\\language "deutsch" \\relative c\' { b4 }'), [58]);
    });
  });

  group('English', () {
    test('-s and -f accidentals', () {
      expect(midi('\\language "english" \\relative c\' { cs4 df }'), [61, 61]);
    });

    test('-sharp and -flat spelled out', () {
      expect(
        midi('\\language "english" \\relative c\' { csharp4 dflat }'),
        [61, 61],
      );
    });

    test('b is B natural, and -ff is a double flat', () {
      expect(midi('\\language "english" \\relative c\' { b4 }'), [59]);
      expect(midi('\\language "english" \\relative c\' { bff4 }'), [57]);
    });
  });

  group('undeclared German', () {
    // Real files — German Wikipedia's especially — use German note names and
    // simply omit the declaration. Read as Dutch they go badly wrong, and `h`
    // is a note name in no other language, so it is decisive evidence.
    test('a note-like h implies German when nothing is declared', () {
      expect(detectLyNoteLanguage(r"\relative g' { h4 g8 e }"),
          LyNoteLanguage.deutsch);
      expect(midi(r"\relative g' { h4 g8 e }"), [71, 67, 64]);
    });

    test('an octave mark counts as evidence too', () {
      expect(detectLyNoteLanguage(r"\relative g { h' c8 }"),
          LyNoteLanguage.deutsch);
    });

    test('an explicit declaration always wins over the guess', () {
      // A file that says Dutch stays Dutch even if an `h` appears.
      expect(
          detectLyNoteLanguage('\\language "nederlands" \\relative g\' '
              '{ h4 }'),
          LyNoteLanguage.nederlands);
    });

    test('an h inside LYRICS does not trigger it', () {
      // The real defeater, found by a cross-format round-trip: an Italian
      // elision like "h'in" (for ch'in) is an `h` followed by an apostrophe,
      // indistinguishable from the note `h'`. One such syllable flipped a whole
      // C-major madrigal to German and turned every written `b` into B flat.
      expect(
        detectLyNoteLanguage(
          '\\relative c\' { b4 c }\n\\addlyrics { "Quel" "h\'in" -- "gom" }',
        ),
        LyNoteLanguage.nederlands,
      );
      // ...and the note itself must survive as B natural.
      expect(
        midi('\\relative c\' { b4 }\n\\addlyrics { "h\'in" }'),
        [59],
      );
    });

    test('an h in a header or markup does not trigger it', () {
      expect(
        detectLyNoteLanguage(
          '\\header { title = "Bach h\'in D" }\n\\relative c\' { b4 }',
        ),
        LyNoteLanguage.nederlands,
      );
    });

    test('a bare h in prose does NOT trigger it', () {
      // No octave mark and no duration, so nothing here looks like a note.
      expect(
        detectLyNoteLanguage(r'\header { title = "h is for horn" }'),
        LyNoteLanguage.nederlands,
      );
      expect(
        detectLyNoteLanguage(r'\addlyrics { ha ha hey } \relative c { c4 }'),
        LyNoteLanguage.nederlands,
      );
    });
  });

  group('contractions are language-scoped', () {
    // `es` means E FLAT in Dutch/German but E SHARP in English, so expanding
    // the contraction everywhere would flip an accidental on English scores.
    test('English es/as are sharps, not the Dutch contractions', () {
      expect(midi('\\language "english" \\relative c\' { es4 }'), [65]);
      expect(midi('\\language "english" \\relative c\' { as4 }'), [58]);
    });

    test('a lone -s on another step is not a Dutch flat', () {
      // `fs`/`cs` are English sharps; read as Dutch they must not become flats.
      expect(midi('\\language "english" \\relative c\' { fs4 }'), [66]);
      expect(midi('\\language "english" \\relative c\' { cs4 }'), [61]);
    });

    test('hes is German-only', () {
      expect(midi('\\language "deutsch" \\relative c\' { hes4 }'), [58]);
    });
  });

  group('detectLyNoteLanguage', () {
    test('reads the directive, the include, and defaults to Dutch', () {
      expect(
          detectLyNoteLanguage('\\language "deutsch"'), LyNoteLanguage.deutsch);
      expect(
          detectLyNoteLanguage('\\language "english"'), LyNoteLanguage.english);
      expect(detectLyNoteLanguage('\\include "deutsch.ly"'),
          LyNoteLanguage.deutsch);
      expect(detectLyNoteLanguage(r'\relative c { c4 }'),
          LyNoteLanguage.nederlands);
      expect(detectLyNoteLanguage('\\language "nederlands"'),
          LyNoteLanguage.nederlands);
    });
  });

  test('every pitch stays inside the MIDI range', () {
    // The corpus-wide symptom that surfaced all of this: dropped notes drag the
    // relative reference, and the drift compounds until pitches go impossible.
    final all = midi(
      '\\language "deutsch" \\relative c\'\' '
      '{ h4 b a g h b a g h b a g h b a g }',
    );
    expect(all, hasLength(16));
    expect(all.every((p) => p >= 0 && p <= 127), isTrue,
        reason: 'pitches escaped the MIDI range: $all');
  });
}
