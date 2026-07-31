import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Dynamics and hairpins through LilyPond.
///
/// `DynamicMarking` and `Hairpin` have existed in the model since long before
/// this writer, and MusicXML round-trips both — but the LilyPond codec emitted
/// and read NEITHER, so ~600 corpus files lost their dynamics entirely.
void main() {
  test('dynamics read off the source', () {
    final s = scoreFromLilyPond(
      r"\score { \new Staff { c'4\p d'4\ff e'4\mf f'4 } }",
    );
    expect(s.dynamics.map((d) => d.level), [
      DynamicLevel.p,
      DynamicLevel.ff,
      DynamicLevel.mf,
    ]);
  });

  test('the aliases real files use map onto the model', () {
    // LilyPond has marks the model has no distinct level for; they map to the
    // nearest rather than being dropped.
    for (final (mark, level) in [
      ('sfz', DynamicLevel.sf),
      ('fp', DynamicLevel.f),
      ('spp', DynamicLevel.pp),
      ('ppppp', DynamicLevel.pppp),
    ]) {
      final s = scoreFromLilyPond("\\score { \\new Staff { c'4\\$mark } }");
      expect(s.dynamics.single.level, level, reason: mark);
    }
  });

  test('a hairpin spans from its opening mark to its \\!', () {
    final s = scoreFromLilyPond(
      r"\score { \new Staff { c'4\< d'4 e'4\! f'4 } }",
    );
    expect(s.hairpins, hasLength(1));
    expect(s.hairpins.single.type, HairpinType.crescendo);
  });

  test('a diminuendo is the other type', () {
    final s = scoreFromLilyPond(r"\score { \new Staff { c'4\> d'4\! } }");
    expect(s.hairpins.single.type, HairpinType.diminuendo);
  });

  test('an unmatched \\! is dropped, not guessed at', () {
    final s = scoreFromLilyPond(r"\score { \new Staff { c'4 d'4\! } }");
    expect(s.hairpins, isEmpty);
  });

  test('both survive our own round trip', () {
    final src = scoreFromLilyPond(
      r"\score { \new Staff { c'4\p d'4\< e'4 f'4\! } }",
    );
    final back = scoreFromLilyPond(scoreToLilyPond(src));
    expect(back.dynamics.map((d) => d.level), src.dynamics.map((d) => d.level));
    expect(back.hairpins, hasLength(1));
  });

  test('dynamics are NEUTRAL — every format carries them', () {
    final src = scoreFromLilyPond(r"\score { \new Staff { c'4\p d'4\ff } }");
    for (final (name, back) in [
      ('musicxml', scoreFromMusicXml(scoreToMusicXml(src))),
      ('mei', scoreFromMei(scoreToMei(src))),
      ('musescore', scoreFromMscx(scoreToMscx(src))),
      ('abc', scoreFromAbc(scoreToAbc(src))),
      ('kern', scoreFromKern(scoreToKern(src))),
      ('lilypond', scoreFromLilyPond(scoreToLilyPond(src))),
    ]) {
      expect(back.dynamics, hasLength(2), reason: name);
    }
  });

  test('hairpins: MusicXML, LilyPond and now MEI carry them', () {
    // Pinning the real state rather than pretending. MuseScore, ABC and kern
    // still do not emit `Hairpin` at all — a pre-existing gap, measured from a
    // model-built score so no reader is in the way. If someone adds one, this
    // test tells them to move it up.
    //
    // MEI joined the carriers here, verified against verovio itself rather than
    // only against our own reader — the writer emits
    // `<hairpin form="cres|dim" startid endid>` and verovio loads it clean.
    final src = Score(clef: Clef.treble, measures: [
      Measure([
        NoteElement(
          pitches: const [Pitch(Step.c, octave: 4)],
          duration: const NoteDuration(DurationBase.quarter),
          id: 'a',
        ),
        NoteElement(
          pitches: const [Pitch(Step.d, octave: 4)],
          duration: const NoteDuration(DurationBase.quarter),
          id: 'b',
        ),
      ]),
    ], hairpins: const [
      Hairpin('a', 'b', HairpinType.crescendo)
    ]);
    expect(scoreFromMusicXml(scoreToMusicXml(src)).hairpins, hasLength(1));
    expect(scoreFromLilyPond(scoreToLilyPond(src)).hairpins, hasLength(1));
    expect(scoreFromMei(scoreToMei(src)).hairpins, hasLength(1));
    for (final (name, back) in [
      ('musescore', scoreFromMscx(scoreToMscx(src))),
      ('abc', scoreFromAbc(scoreToAbc(src))),
      ('kern', scoreFromKern(scoreToKern(src))),
    ]) {
      expect(back.hairpins, isEmpty, reason: '$name now carries hairpins?');
    }
  });
}
