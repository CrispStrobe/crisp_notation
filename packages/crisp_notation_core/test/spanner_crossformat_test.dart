import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A glissando used to survive only MusicXML — and there only because the
/// writer emitted `<slide>` and the reader read `<slide>` back, which is
/// self-consistent and wrong.
///
/// MEI has `<gliss>`, MuseScore a `Glissando` spanner and LilyPond
/// `\glissando`, so four of the six formats can carry it. kern and ABC have no
/// notation for one, which is a format limit rather than a gap.
void main() {
  Score scored(List<Glissando> gliss) => Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure(<MusicElement>[
            for (var i = 0; i < 4; i++)
              NoteElement(
                id: 'e$i',
                pitches: [Pitch(Step.values[i], octave: 4)],
                duration: const NoteDuration(DurationBase.quarter),
              ),
          ]),
        ],
        glissandos: gliss,
      );

  final hops = <String, Score Function(Score)>{
    'musicxml': (s) => scoreFromMusicXml(scoreToMusicXml(s)),
    'mei': (s) => scoreFromMei(scoreToMei(s)),
    'lilypond': (s) => scoreFromLilyPond(scoreToLilyPond(s)),
    'musescore': (s) => scoreFromMscx(scoreToMscx(s)),
  };

  for (final e in hops.entries) {
    test('${e.key} carries a glissando', () {
      final back = e.value(scored(const [Glissando('e0', 'e1')]));
      expect(back.glissandos, hasLength(1), reason: e.key);
      final ids = back.measures.single.elements
          .whereType<NoteElement>()
          .map((n) => n.id)
          .toList();
      expect(back.glissandos.single.startId, ids[0], reason: e.key);
      expect(back.glissandos.single.endId, ids[1], reason: e.key);
    });

    test('${e.key} carries two of them', () {
      final back =
          e.value(scored(const [Glissando('e0', 'e1'), Glissando('e2', 'e3')]));
      expect(back.glissandos, hasLength(2), reason: e.key);
    });

    test('${e.key} invents none when there are none', () {
      expect(e.value(scored(const [])).glissandos, isEmpty, reason: e.key);
    });
  }

  group('ottavas and pedals reach the same four formats', () {
    Score span(
            {List<Ottava> ottavas = const [], List<Pedal> pedals = const []}) =>
        Score(
          clef: Clef.treble,
          timeSignature: const TimeSignature(4, 4),
          measures: [
            Measure(<MusicElement>[
              for (var i = 0; i < 4; i++)
                NoteElement(
                  id: 'e$i',
                  pitches: const [Pitch(Step.c, octave: 4)],
                  duration: const NoteDuration(DurationBase.quarter),
                ),
            ]),
          ],
          ottavas: ottavas,
          pedals: pedals,
        );

    for (final e in hops.entries) {
      test('${e.key} carries an ottava with its direction', () {
        for (final down in [true, false]) {
          final back = e.value(span(ottavas: [Ottava('e0', 'e2', down: down)]));
          expect(back.ottavas, hasLength(1), reason: '${e.key} down=$down');
          expect(back.ottavas.single.down, down, reason: '${e.key} down=$down');
        }
      });

      test('${e.key} carries a pedal', () {
        final back = e.value(span(pedals: const [Pedal('e0', 'e2')]));
        expect(back.pedals, hasLength(1), reason: e.key);
      });
    }

    test('a negative Scheme literal survives the LilyPond lexer', () {
      // `\\ottava #-1` split into `#`, `-` and `1`, so the octave shift read as
      // nothing at all and the bracket was dropped. `-` is an articulation
      // shorthand elsewhere, so the sign is only glued inside `#…`.
      expect(scoreToLilyPond(span(ottavas: const [Ottava('e0', 'e2')])),
          contains(r'\ottava #-1'));
      expect(
          scoreFromLilyPond(
                  scoreToLilyPond(span(ottavas: const [Ottava('e0', 'e2')])))
              .ottavas,
          hasLength(1));
    });
  });

  group('extended trills', () {
    Score trilled({bool ornament = false}) => Score(
          clef: Clef.treble,
          timeSignature: const TimeSignature(4, 4),
          measures: [
            Measure(<MusicElement>[
              NoteElement(
                id: 'e0',
                pitches: const [Pitch(Step.c, octave: 4)],
                duration: const NoteDuration(DurationBase.quarter),
                ornament: ornament ? Ornament.trill : null,
              ),
              for (var i = 1; i < 4; i++)
                NoteElement(
                  id: 'e$i',
                  pitches: const [Pitch(Step.c, octave: 4)],
                  duration: const NoteDuration(DurationBase.quarter),
                ),
            ]),
          ],
          trillExtensions: const [TrillExtension('e0', 'e2')],
        );

    for (final e in hops.entries) {
      test('${e.key} carries the span', () {
        for (final ornament in [false, true]) {
          final back = e.value(trilled(ornament: ornament));
          expect(back.trillExtensions, hasLength(1),
              reason: '${e.key} ornament=$ornament');
        }
      });

      test('${e.key} does not ALSO leave a trill ornament on the note', () {
        // An extended trill is the span ALONE: each of these formats draws the
        // "tr" as part of the span, so keeping the ornament too prints the sign
        // twice. All four normalise to the same form, which is what makes a
        // chain through several of them stable.
        for (final ornament in [false, true]) {
          final back = e.value(trilled(ornament: ornament));
          final first = back.measures.single.elements.first as NoteElement;
          expect(first.ornament, isNull, reason: '${e.key} ornament=$ornament');
        }
      });
    }

    test('a plain trill ornament with no span is untouched', () {
      final plain = Score(
        clef: Clef.treble,
        measures: [
          Measure(<MusicElement>[
            NoteElement(
              id: 'e0',
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.quarter),
              ornament: Ornament.trill,
            ),
          ]),
        ],
      );
      for (final e in hops.entries) {
        final back = e.value(plain);
        final first = back.measures.single.elements.first as NoteElement;
        expect(first.ornament, Ornament.trill, reason: e.key);
        expect(back.trillExtensions, isEmpty, reason: e.key);
      }
    });
  });

  test('MuseScore builds its span index even with no other spanner', () {
    // The writer used to early-out of building the onset map unless the score
    // had a slur, hairpin, pedal or ottava — so a score carrying ONLY
    // glissandi emitted no spans at all, with the emitting code correct.
    final xml = scoreToMscx(scored(const [Glissando('e0', 'e1')]));
    expect(xml, contains('type="Glissando"'));
  });
}
