import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Two NEW model concepts: staccatissimo and the breath mark.
///
/// Both were chosen by measurement, not intuition. The test for a neutral model
/// concept is that SEVERAL formats express it — a mark only one format has is a
/// format quirk, and giving it a model field would just move the loss to the
/// first format boundary. Measured before adding:
///
///   staccatissimo  103 of 1,500 `.mxl` · 56 of 1,500 `.mscx`
///   breath         196 of 1,500 `.mscx` · 88 of 1,500 `.mxl`
///                  · 580 of 4,106 `.ly` (`\breathe`)
///
/// They live in `Articulation` rather than in classes of their own because that
/// is how the formats themselves model them — MusicXML puts BOTH inside
/// `<notations><articulations>`.
///
/// ⚠️ The two formats that DON'T are handled specially: MEI has no `@artic` for
/// a breath (it is a `<breath>` control event) and MuseScore models it as its
/// own `<Breath>` element that FOLLOWS its chord. Neither goes through the
/// articulation table.
void main() {
  Score sample(Articulation art) => Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.quarter),
              articulations: {art},
              id: 'a',
            ),
            NoteElement(
              pitches: const [Pitch(Step.d, octave: 4)],
              duration: const NoteDuration(DurationBase.quarter),
              id: 'b',
            ),
          ]),
        ],
      );

  bool has(Score s, Articulation art) => s.measures
      .expand((m) => m.elements)
      .whereType<NoteElement>()
      .any((e) => e.articulations.contains(art));

  for (final art in [Articulation.staccatissimo, Articulation.breath]) {
    group(art.name, () {
      // GP is a TAB format with no equivalent, so it is excluded rather than
      // pretended about.
      for (final (name, hop) in <(String, Score Function(Score))>[
        ('musicxml', _xml),
        ('mei', _mei),
        ('kern', _kern),
        ('abc', _abc),
        ('musescore', _mscx),
        ('lilypond', _ly),
      ]) {
        test('survives $name', () {
          expect(has(hop(sample(art)), art), isTrue);
        });
      }
    });
  }

  test('staccatissimo is NOT collapsed into staccato', () {
    // A format that has both means both; collapsing loses the distinction the
    // composer wrote.
    final back = _xml(sample(Articulation.staccatissimo));
    expect(has(back, Articulation.staccatissimo), isTrue);
    expect(has(back, Articulation.staccato), isFalse);
  });

  test('a note with neither mark gains neither', () {
    final plain = Score(clef: Clef.treble, measures: [
      Measure([
        NoteElement(
          pitches: const [Pitch(Step.c, octave: 4)],
          duration: const NoteDuration(DurationBase.quarter),
          id: 'a',
        ),
      ]),
    ]);
    for (final hop in [_xml, _mei, _kern, _abc, _mscx, _ly]) {
      final back = hop(plain);
      expect(has(back, Articulation.breath), isFalse);
      expect(has(back, Articulation.staccatissimo), isFalse);
    }
  });

  test('every articulation has a layout glyph', () {
    // The glyph switch is exhaustive, so a new enum value that nobody mapped
    // would not compile — but assert the names too, since a wrong-but-valid
    // SMuFL name compiles fine and renders the wrong symbol.
    expect(
      SmuflGlyph.articulationGlyph(Articulation.staccatissimo, above: true),
      'articStaccatissimoAbove',
    );
    expect(
      SmuflGlyph.articulationGlyph(Articulation.breath, above: true),
      'breathMarkComma',
    );
  });
}

Score _xml(Score s) => scoreFromMusicXml(scoreToMusicXml(s));
Score _mei(Score s) => scoreFromMei(scoreToMei(s));
Score _kern(Score s) => scoreFromKern(scoreToKern(s));
Score _abc(Score s) => scoreFromAbc(scoreToAbc(s));
Score _mscx(Score s) => scoreFromMscx(scoreToMscx(s));
Score _ly(Score s) => scoreFromLilyPond(scoreToLilyPond(s));
