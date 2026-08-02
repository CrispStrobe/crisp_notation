import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Fingering reached only MusicXML, and it is ordinary in piano, string and
/// pedagogical scores — exactly the repertoire this app is for.
///
/// Found by asking what the rich sweep's largest bucket actually contains: the
/// plain signature is 15,960/15,960, so pitch and rhythm are clean and every
/// `note` divergence is a note-ATTACHED mark. Articulations, ornaments and
/// grace notes were fine everywhere; fingering, arpeggio and notehead were not.
void main() {
  Score scored(List<int> fingerings) => Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(<MusicElement>[
            NoteElement(
              id: 'e0',
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.quarter),
              fingerings: fingerings,
            ),
            for (var i = 1; i < 4; i++)
              NoteElement(
                id: 'e$i',
                pitches: const [Pitch(Step.d, octave: 4)],
                duration: const NoteDuration(DurationBase.quarter),
              ),
          ])
        ],
      );

  NoteElement first(Score s) =>
      s.measures.single.elements.whereType<NoteElement>().first;

  for (final e in <String, Score Function(Score)>{
    'musicxml': (x) => scoreFromMusicXml(scoreToMusicXml(x)),
    'mei': (x) => scoreFromMei(scoreToMei(x)),
    'lilypond': (x) => scoreFromLilyPond(scoreToLilyPond(x)),
    'musescore': (x) => scoreFromMscx(scoreToMscx(x)),
  }.entries) {
    test('${e.key} carries a finger number', () {
      expect(first(e.value(scored([3]))).fingerings, [3], reason: e.key);
    });

    test('${e.key} carries several on one note', () {
      // A chord fingered 1-3-5 is one element with three numbers.
      expect(first(e.value(scored([1, 3, 5]))).fingerings, [1, 3, 5],
          reason: e.key);
    });

    test('${e.key} invents none when there are none', () {
      expect(first(e.value(scored([]))).fingerings, isEmpty, reason: e.key);
    });
  }

  test('LilyPond writes it as -N on the note', () {
    // ⚠️ `-` is a symbol prefix in the lexer, so `c4-1` used to split into a
    // note, a `-` and a stray `1`, dropping the finger number entirely — the
    // whole mark, silently.
    expect(scoreToLilyPond(scored([3])), contains('-3'));
    expect(
        scoreFromLilyPond(r"\score { \new Staff { c'4-2 d'4 } }")
            .measures
            .single
            .elements
            .whereType<NoteElement>()
            .first
            .fingerings,
        [2]);
  });

  test('a fingering does not disturb an articulation on the same note', () {
    final s = Score(
      clef: Clef.treble,
      measures: [
        Measure(<MusicElement>[
          NoteElement(
            id: 'e0',
            pitches: const [Pitch(Step.c, octave: 4)],
            duration: const NoteDuration(DurationBase.quarter),
            fingerings: const [1],
            articulations: const {Articulation.staccato},
          ),
        ])
      ],
    );
    for (final hop in <Score Function(Score)>[
      (x) => scoreFromMusicXml(scoreToMusicXml(x)),
      (x) => scoreFromMei(scoreToMei(x)),
      (x) => scoreFromLilyPond(scoreToLilyPond(x)),
      (x) => scoreFromMscx(scoreToMscx(x)),
    ]) {
      final n = first(hop(s));
      expect(n.fingerings, [1]);
      expect(n.articulations, contains(Articulation.staccato));
    }
  });
}
