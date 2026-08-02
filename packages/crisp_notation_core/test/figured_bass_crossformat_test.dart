import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Figured bass — thoroughbass, the continuo notation of the Baroque — reached
/// only MusicXML. The corpus has real continuo, so this is repertoire the app
/// actually holds.
///
/// ABC is absent: it has no figured-bass notation.
void main() {
  Score scored(List<FiguredBass> fb) => Score(
        clef: Clef.bass,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(<MusicElement>[
            for (var i = 0; i < 4; i++)
              NoteElement(
                id: 'e$i',
                pitches: const [Pitch(Step.c, octave: 3)],
                duration: const NoteDuration(DurationBase.quarter),
              ),
          ])
        ],
        figuredBass: fb,
      );

  final hops = <String, Score Function(Score)>{
    'musicxml': (x) => scoreFromMusicXml(scoreToMusicXml(x)),
    'mei': (x) => scoreFromMei(scoreToMei(x)),
    'kern': (x) => scoreFromKern(scoreToKern(x)),
    'lilypond': (x) => scoreFromLilyPond(scoreToLilyPond(x)),
    'musescore': (x) => scoreFromMscx(scoreToMscx(x)),
  };

  for (final e in hops.entries) {
    test('${e.key} carries a single figure', () {
      final back = e.value(scored(const [
        FiguredBass('e0', ['6'])
      ]));
      expect(back.figuredBass, hasLength(1), reason: e.key);
      expect(back.figuredBass.single.figures, ['6'], reason: e.key);
    });

    test('${e.key} carries a STACK of figures in order', () {
      // `6 4` is one stack on one bass note, top to bottom — not two marks.
      final back = e.value(scored(const [
        FiguredBass('e0', ['6', '4'])
      ]));
      expect(back.figuredBass.single.figures, ['6', '4'], reason: e.key);
    });

    test('${e.key} keeps two stacks on the right notes', () {
      final back = e.value(scored(const [
        FiguredBass('e0', ['6']),
        FiguredBass('e2', ['6', '4']),
      ]));
      expect(
          back.figuredBass.map((f) => f.figures),
          [
            ['6'],
            ['6', '4'],
          ],
          reason: e.key);
      final ids = back.measures.single.elements
          .whereType<NoteElement>()
          .map((n) => n.id)
          .toList();
      expect(back.figuredBass.first.noteId, ids[0], reason: e.key);
      expect(back.figuredBass.last.noteId, ids[2], reason: e.key);
    });

    test('${e.key} invents none', () {
      expect(e.value(scored(const [])).figuredBass, isEmpty, reason: e.key);
    });
  }

  test('a chord symbol and a figure are told apart in MEI', () {
    // ⚠️ MEI spells BOTH with `<harm>` — a chord label is text inside it, a
    // figure an `<fb>` element. Same element, two concepts.
    final s = Score(
      clef: Clef.bass,
      measures: [
        Measure(<MusicElement>[
          NoteElement(
            pitches: const [Pitch(Step.c, octave: 3)],
            duration: const NoteDuration(DurationBase.quarter),
            id: 'a',
          ),
          NoteElement(
            pitches: const [Pitch(Step.d, octave: 3)],
            duration: const NoteDuration(DurationBase.quarter),
            id: 'b',
          ),
        ])
      ],
      figuredBass: const [
        FiguredBass('a', ['6'])
      ],
      chordSymbols: [
        ChordSymbol('b', const Pitch(Step.g, octave: 3),
            ChordSymbolKind.dominantSeventh),
      ],
    );
    final back = scoreFromMei(scoreToMei(s));
    expect(back.figuredBass.single.figures, ['6']);
    expect(back.chordSymbols.map(chordName), ['G7']);
  });
}
