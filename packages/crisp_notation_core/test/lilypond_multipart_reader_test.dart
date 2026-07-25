// Tests for multiPartFromLilyPond — reading a LilyPond source with several
// staves into a MultiPartScore (one part per staff), the inverse of
// multiPartToLilyPond. Covers writer↔reader round-trips (notes, clefs,
// instrument names, header, lyrics), hand-written multi-staff sources,
// `\new Staff \variable` references, and the single-staff degradation.

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// All note pitches of a part, flattened across measures (chords → each pitch).
List<Pitch> _pitches(Score part) => [
      for (final m in part.measures)
        for (final e in m.elements)
          if (e is NoteElement) ...e.pitches,
    ];

NoteElement _n(Step s, int octave) => NoteElement(
      pitches: [Pitch(s, octave: octave)],
      duration: NoteDuration.quarter,
    );

void main() {
  group('multiPartFromLilyPond — writer round-trips', () {
    final flute = Score(clef: Clef.treble, measures: [
      Measure([_n(Step.g, 5), _n(Step.a, 5), _n(Step.b, 5), _n(Step.c, 6)]),
    ]);
    final cello = Score(clef: Clef.bass, measures: [
      Measure([_n(Step.c, 3), _n(Step.d, 3), _n(Step.e, 3), _n(Step.f, 3)]),
    ]);

    test('two parts round-trip: count, clefs, notes, instrument names', () {
      final ly = multiPartToLilyPond(
        MultiPartScore([flute, cello]),
        partNames: ['Flute', 'Cello'],
      );
      final back = multiPartFromLilyPond(ly);

      expect(back.parts, hasLength(2));
      expect(back.parts[0].clef, Clef.treble);
      expect(back.parts[1].clef, Clef.bass);

      // Notes survive per part (pitch class + octave).
      expect(
        _pitches(back.parts[0]).map((p) => (p.step, p.octave)),
        [(Step.g, 5), (Step.a, 5), (Step.b, 5), (Step.c, 6)],
      );
      expect(
        _pitches(back.parts[1]).map((p) => (p.step, p.octave)),
        [(Step.c, 3), (Step.d, 3), (Step.e, 3), (Step.f, 3)],
      );

      // Instrument names come back from `\with { instrumentName = … }`.
      expect(back.parts[0].metadata.instrument, 'Flute');
      expect(back.parts[1].metadata.instrument, 'Cello');
    });

    test('header (title/composer) lands on the first part', () {
      final titled = Score(
        clef: Clef.treble,
        measures: flute.measures,
        metadata: const ScoreMetadata(
          title: 'Duet in C',
          composer: 'A. Composer',
        ),
      );
      final ly = multiPartToLilyPond(MultiPartScore([titled, cello]));
      final back = multiPartFromLilyPond(ly);

      expect(back.parts, hasLength(2));
      expect(back.parts[0].metadata.title, 'Duet in C');
      expect(back.parts[0].metadata.composer, 'A. Composer');
    });

    test('three parts → three parts', () {
      final alto = Score(clef: Clef.alto, measures: [
        Measure([_n(Step.e, 4), _n(Step.f, 4)]),
      ]);
      final ly = multiPartToLilyPond(
        MultiPartScore([flute, alto, cello]),
        partNames: ['Fl', 'Va', 'Vc'],
      );
      final back = multiPartFromLilyPond(ly);
      expect(back.parts, hasLength(3));
      expect(back.parts.map((p) => p.metadata.instrument), ['Fl', 'Va', 'Vc']);
    });

    test('per-part lyrics round-trip and align to that staff', () {
      // Element ids match the lyric ids so the writer emits `\addlyrics`.
      final withIds = Score(
        clef: Clef.treble,
        measures: [
          Measure([
            NoteElement(
                pitches: [const Pitch(Step.c, octave: 5)],
                duration: NoteDuration.quarter,
                id: 'e0'),
            NoteElement(
                pitches: [const Pitch(Step.d, octave: 5)],
                duration: NoteDuration.quarter,
                id: 'e1'),
            NoteElement(
                pitches: [const Pitch(Step.e, octave: 5)],
                duration: NoteDuration.quarter,
                id: 'e2'),
          ]),
        ],
        lyrics: const [
          Lyric('e0', 'Do'),
          Lyric('e1', 'Re'),
          Lyric('e2', 'Mi'),
        ],
      );

      final ly = multiPartToLilyPond(MultiPartScore([withIds, cello]));
      expect(ly, contains('\\addlyrics'));
      final back = multiPartFromLilyPond(ly);

      expect(back.parts, hasLength(2));
      // The lyrics attach to the FIRST staff (not the cello), in order.
      final texts = back.parts[0].lyrics.map((l) => l.text).toList();
      expect(texts, containsAllInOrder(['Do', 'Re', 'Mi']));
      // The cello has no lyrics.
      expect(back.parts[1].lyrics, isEmpty);
    });
  });

  group('multiPartFromLilyPond — hand-written sources', () {
    test('a bare \\score with two \\new Staff blocks', () {
      const ly = r'''
\score {
  <<
    \new Staff { \clef treble c'4 d' e' f' }
    \new Staff { \clef bass c4 d e f }
  >>
}
''';
      final mp = multiPartFromLilyPond(ly);
      expect(mp.parts, hasLength(2));
      expect(mp.parts[0].clef, Clef.treble);
      expect(mp.parts[1].clef, Clef.bass);
      expect(_pitches(mp.parts[0]).map((p) => p.step),
          [Step.c, Step.d, Step.e, Step.f]);
      expect(_pitches(mp.parts[1]), hasLength(4));
    });

    test('a StaffGroup wrapping the staves', () {
      const ly = r'''
\score {
  \new StaffGroup <<
    \new Staff { c'4 d' }
    \new Staff { e'4 f' }
    \new Staff { g'4 a' }
  >>
}
''';
      expect(multiPartFromLilyPond(ly).parts, hasLength(3));
    });

    test('\\new Staff \\variable references resolve per part', () {
      const ly = r'''
soprano = { c'4 d' e' f' }
alto = { c4 d e f }
\score {
  <<
    \new Staff \soprano
    \new Staff \alto
  >>
}
''';
      final mp = multiPartFromLilyPond(ly);
      expect(mp.parts, hasLength(2));
      expect(_pitches(mp.parts[0]), hasLength(4));
      expect(_pitches(mp.parts[1]), hasLength(4));
      // The two staves carry DIFFERENT music (not the collapse bug).
      expect(_pitches(mp.parts[0]).first.octave,
          isNot(_pitches(mp.parts[1]).first.octave));
    });

    test('a PianoStaff (grand staff) reads as two parts', () {
      const ly = r'''
\score {
  \new PianoStaff <<
    \new Staff { \clef treble c'4 e' }
    \new Staff { \clef bass c4 g, }
  >>
}
''';
      final mp = multiPartFromLilyPond(ly);
      expect(mp.parts, hasLength(2));
      expect(mp.parts[0].clef, Clef.treble);
      expect(mp.parts[1].clef, Clef.bass);
    });
  });

  group('multiPartFromLilyPond — single-staff degradation', () {
    test('a lone \\new Staff is one part', () {
      const ly = r"\score { \new Staff { c'4 d' e' f' } }";
      final mp = multiPartFromLilyPond(ly);
      expect(mp.parts, hasLength(1));
      expect(_pitches(mp.parts[0]), hasLength(4));
    });

    test('bare music (no \\new Staff) is one part, matching scoreFromLilyPond',
        () {
      const ly = r"{ c'4 d' e' f' }";
      final mp = multiPartFromLilyPond(ly);
      expect(mp.parts, hasLength(1));
      expect(
        _pitches(mp.parts[0]).length,
        _pitches(scoreFromLilyPond(ly)).length,
      );
    });

    test('simultaneous voices in one staff do NOT split into parts', () {
      // `<< { … } \\ { … } >>` is two voices of ONE staff, not two parts.
      const ly = r"\new Staff << { c'4 d' } \\ { e4 f } >>";
      expect(multiPartFromLilyPond(ly).parts, hasLength(1));
    });
  });
}
