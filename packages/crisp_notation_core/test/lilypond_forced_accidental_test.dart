import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A forced (`!`) or cautionary (`?`) accidental used to DELETE its note.
///
/// The note regex is `$`-anchored, and the comment above it already records
/// what that costs when a real construct is rejected: the note does not read
/// wrongly, it VANISHES. `c'4 d'!4 e'!4 f'?4` came back as ONE note.
///
/// Both marks are ordinary in engraved music — a reminder accidental after a
/// bar line, an editorial one in early music — so this was silent loss across
/// every LilyPond file that engraves carefully.
void main() {
  Score read(String body) =>
      scoreFromLilyPond('\\score { \\new Staff { $body } \\layout {} }');

  int notes(Score s) => s.measures.fold(0, (a, m) => a + m.elements.length);

  group('the note survives', () {
    test('a forced accidental', () {
      expect(notes(read(r"c'!4 d'4 e'4 f'4")), 4);
    });
    test('a cautionary accidental', () {
      expect(notes(read(r"c'?4 d'4 e'4 f'4")), 4);
    });
    test('one on an already-altered pitch', () {
      expect(notes(read(r"cis'!4 d'4 e'4 f'4")), 4);
    });
    test('several in a row — the case that read as ONE note', () {
      expect(notes(read(r"c'4 d'!4 e'!4 f'?4")), 4);
    });
    test('the pitches are right, not merely present', () {
      final ns =
          read(r"c'!4 dis'?4").measures.single.elements.cast<NoteElement>();
      expect(ns.map((n) => n.pitches.single.midiNumber), [60, 63]);
    });
    test('the duration is still read', () {
      final ns = read(r"c'!2 d'4").measures.single.elements.cast<NoteElement>();
      expect(ns.first.duration.base, DurationBase.half);
      expect(ns.last.duration.base, DurationBase.quarter);
    });
  });

  group('inside a CHORD', () {
    // ⚠️ This is where the first fix broke: it emitted `<f'! d'! g!>` — the
    // mark on every pitch — and the chord parser stores pitch texts verbatim,
    // so `_parsePitch` saw `f'!`, failed, and the whole chord collapsed to
    // three middle Cs. A writer emitting what its own reader cannot read.
    //
    // The unit test only covered single notes; the corpus sweep is what caught
    // it, on a Chopin file full of editorial accidentals.
    test('a chord with forced accidentals keeps its pitches', () {
      final s = read(r"<f'! d'! g!>4 c'4");
      final n = s.measures.single.elements.first as NoteElement;
      expect(n.pitches.map((p) => p.midiNumber).toList(), [65, 62, 55]);
    });

    test('and records that they are shown', () {
      final n =
          read(r"<f'! d'! g!>4").measures.single.elements.first as NoteElement;
      expect(n.showAccidental, isTrue);
    });

    test('an ordinary chord is unaffected', () {
      final n =
          read(r"<f' d' g>4").measures.single.elements.first as NoteElement;
      expect(n.pitches.map((p) => p.midiNumber).toList(), [65, 62, 55]);
      expect(n.showAccidental, isNull);
    });

    test('it round-trips through our own writer', () {
      final s = Score(
        clef: Clef.treble,
        measures: [
          Measure(<MusicElement>[
            NoteElement(
              id: 'e0',
              pitches: const [
                Pitch(Step.f, octave: 4),
                Pitch(Step.d, octave: 4),
                Pitch(Step.g, octave: 3),
              ],
              duration: const NoteDuration(DurationBase.quarter),
              showAccidental: true,
            ),
          ])
        ],
      );
      final back = scoreFromLilyPond(scoreToLilyPond(s));
      final n = back.measures.single.elements.first as NoteElement;
      expect(n.pitches.map((p) => p.midiNumber).toList(), [65, 62, 55]);
      expect(n.showAccidental, isTrue);
    });
  });

  group('showAccidental', () {
    test('is set by both marks — the model holds one flag', () {
      // `!` forces the accidental, `?` prints it in parentheses. Both mean
      // "print it", which is all the model can say.
      for (final mark in ['!', '?']) {
        final n = read("c'${mark}4 d'4").measures.single.elements.first
            as NoteElement;
        expect(n.showAccidental, isTrue, reason: mark);
      }
    });

    test('is not invented for an ordinary note', () {
      final n = read(r"c'4 d'4").measures.single.elements.first as NoteElement;
      expect(n.showAccidental, isNull);
    });

    test('round-trips through the writer', () {
      Score s(bool? show) => Score(
            clef: Clef.treble,
            measures: [
              Measure(<MusicElement>[
                NoteElement(
                  id: 'e0',
                  pitches: const [Pitch(Step.f, octave: 4)],
                  duration: const NoteDuration(DurationBase.quarter),
                  showAccidental: show,
                ),
              ])
            ],
          );
      expect(scoreToLilyPond(s(true)), contains("f'!4"));
      expect(scoreToLilyPond(s(null)), isNot(contains('!')));
      final back = scoreFromLilyPond(scoreToLilyPond(s(true)))
          .measures
          .single
          .elements
          .first as NoteElement;
      expect(back.showAccidental, isTrue);
    });
  });
}
