import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Arpeggio, notehead shape and tremolo — the note-attached marks that reached
/// only MusicXML.
///
/// kern and ABC have no standard spelling for any of them and are left out.
void main() {
  Score scored(NoteElement first) => Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(<MusicElement>[
            first,
            for (var i = 1; i < 4; i++)
              NoteElement(
                id: 'e$i',
                pitches: const [Pitch(Step.d, octave: 4)],
                duration: const NoteDuration(DurationBase.quarter),
              ),
          ])
        ],
      );

  NoteElement note({
    Arpeggio? arpeggio,
    int? tremolo,
    NoteheadShape notehead = NoteheadShape.normal,
  }) =>
      NoteElement(
        id: 'e0',
        pitches: const [Pitch(Step.c, octave: 4)],
        duration: const NoteDuration(DurationBase.quarter),
        arpeggio: arpeggio,
        tremolo: tremolo,
        notehead: notehead,
      );

  NoteElement first(Score s) =>
      s.measures.single.elements.whereType<NoteElement>().first;

  final hops = <String, Score Function(Score)>{
    'musicxml': (x) => scoreFromMusicXml(scoreToMusicXml(x)),
    'mei': (x) => scoreFromMei(scoreToMei(x)),
    'lilypond': (x) => scoreFromLilyPond(scoreToLilyPond(x)),
    'musescore': (x) => scoreFromMscx(scoreToMscx(x)),
  };

  for (final e in hops.entries) {
    test('${e.key} keeps an arpeggio and its DIRECTION', () {
      for (final d in Arpeggio.values) {
        expect(first(e.value(scored(note(arpeggio: d)))).arpeggio, d,
            reason: '${e.key} $d');
      }
    });

    test('${e.key} keeps a tremolo slash count', () {
      for (final n in [1, 2, 3]) {
        expect(first(e.value(scored(note(tremolo: n)))).tremolo, n,
            reason: '${e.key} $n');
      }
    });

    test('${e.key} keeps every notehead shape', () {
      for (final h in NoteheadShape.values) {
        expect(first(e.value(scored(note(notehead: h)))).notehead, h,
            reason: '${e.key} $h');
      }
    });

    test('${e.key} invents none of them', () {
      final back = first(e.value(scored(note())));
      expect(back.arpeggio, isNull, reason: e.key);
      expect(back.tremolo, isNull, reason: e.key);
      expect(back.notehead, NoteheadShape.normal, reason: e.key);
    });
  }

  group('LilyPond spellings', () {
    test('a tremolo is a duration SUFFIX, not a script', () {
      // `c4:32` — the subdivision it is beamed at, 2^(2+slashes).
      expect(scoreToLilyPond(scored(note(tremolo: 3))), contains(':32'));
    });

    test('a chord in \\chordmode is NOT read as a tremolo', () {
      // ⚠️ `c:7` is a dominant seventh and `c:9` a ninth. Matching a bare `:N`
      // turned every chord in a chord track into a note carrying a tremolo.
      // Only the powers of two from 8 up are subdivisions, and no chord
      // modifier (5, 6, 7, 9, 11, 13) is one.
      final s = scoreFromLilyPond(r'\score { << '
          r'\new ChordNames \chordmode { c4:7 d4:9 } '
          r"\new Staff { c'4 d'4 } >> \layout {} }");
      expect(s.chordSymbols.map(chordName), ['C7', 'D9']);
      expect(
          s.measures.single.elements
              .whereType<NoteElement>()
              .every((n) => n.tremolo == null),
          isTrue);
    });

    test('the arrow direction is a sticky CONTEXT property', () {
      expect(scoreToLilyPond(scored(note(arpeggio: Arpeggio.down))),
          contains('arpeggioArrowDown'));
    });
  });
}
