import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A note that ENDS one hairpin and STARTS the next — an ordinary phrase shaped
/// `<` then `>` — was written `\>\!`: open, then close.
///
/// `\!` terminates the hairpin currently running, so that opened a new one and
/// killed it on the spot, while the hairpin that should have ended there was
/// left dangling and dropped. Measured across 250 corpus `.ly` files: 8 of 213
/// hairpins were lost on a LilyPond round trip through our own writer.
void main() {
  /// The same shared boundary, through every format that carries hairpins.
  ///
  /// It broke in FOUR codecs for three different reasons: LilyPond wrote
  /// `\>\!` (open before close); MusicXML emitted no `number`, so the new
  /// start overwrote the old one in the reader's number-keyed map; MuseScore's
  /// reader held ONE pending hairpin where the note carries two `<Spanner>`
  /// siblings. kern and ABC carry no hairpins at all — a genuine unimplemented
  /// channel, not a defect.
  void crossFormat() {
    Score shared() => Score(
          clef: Clef.treble,
          timeSignature: const TimeSignature(4, 4),
          measures: [
            Measure(<MusicElement>[
              for (var i = 0; i < 5; i++)
                NoteElement(
                  id: 'e$i',
                  pitches: const [Pitch(Step.c, octave: 4)],
                  duration: const NoteDuration(DurationBase.quarter),
                ),
            ])
          ],
          hairpins: const [
            Hairpin('e0', 'e2', HairpinType.crescendo),
            Hairpin('e2', 'e4', HairpinType.diminuendo),
          ],
        );

    for (final e in <String, Score Function(Score)>{
      'musicxml': (x) => scoreFromMusicXml(scoreToMusicXml(x)),
      'mei': (x) => scoreFromMei(scoreToMei(x)),
      'lilypond': (x) => scoreFromLilyPond(scoreToLilyPond(x)),
      'musescore': (x) => scoreFromMscx(scoreToMscx(x)),
    }.entries) {
      test('${e.key} keeps BOTH hairpins across a shared boundary note', () {
        final back = e.value(shared());
        expect(back.hairpins, hasLength(2), reason: e.key);
        expect(back.hairpins.map((h) => h.type).toList(),
            [HairpinType.crescendo, HairpinType.diminuendo],
            reason: e.key);
        expect(back.hairpins[0].endId, back.hairpins[1].startId,
            reason: '${e.key}: the boundary note must anchor both');
      });
    }
  }

  crossFormat();

  Score phrase() {
    final notes = <MusicElement>[
      for (var i = 0; i < 5; i++)
        NoteElement(
          id: 'e$i',
          pitches: [Pitch(Step.values[i % 7], octave: 4)],
          duration: const NoteDuration(DurationBase.quarter),
        ),
    ];
    return Score(
      clef: Clef.treble,
      measures: [Measure(notes)],
      // e2 ends the crescendo AND starts the diminuendo.
      hairpins: const [
        Hairpin('e0', 'e2', HairpinType.crescendo),
        Hairpin('e2', 'e4', HairpinType.diminuendo),
      ],
    );
  }

  test('the close is written before the open', () {
    expect(scoreToLilyPond(phrase()), contains(r'\!\>'));
    expect(scoreToLilyPond(phrase()), isNot(contains(r'\>\!')));
  });

  test('both hairpins survive the round trip', () {
    final back = scoreFromLilyPond(scoreToLilyPond(phrase()));
    expect(back.hairpins, hasLength(2));
    expect(back.hairpins.map((h) => h.type),
        [HairpinType.crescendo, HairpinType.diminuendo]);
  });

  test('the shared note really is the boundary of both', () {
    final back = scoreFromLilyPond(scoreToLilyPond(phrase()));
    expect(back.hairpins[0].endId, back.hairpins[1].startId);
  });

  test('a lone hairpin is unaffected', () {
    final s = Score(
      clef: Clef.treble,
      measures: [
        Measure(<MusicElement>[
          for (var i = 0; i < 3; i++)
            NoteElement(
              id: 'e$i',
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.quarter),
            ),
        ])
      ],
      hairpins: const [Hairpin('e0', 'e2', HairpinType.crescendo)],
    );
    expect(scoreFromLilyPond(scoreToLilyPond(s)).hairpins, hasLength(1));
  });
}
