import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Text annotations across the formats.
///
/// `Score.annotations` has existed all along and MusicXML carried it — but
/// LilyPond, MEI, kern and MuseScore all dropped every one. Measured on the
/// 10,000-file held ABC control: **4,150 files carry at least one** (ABC's
/// quoted `"Eb"` chord symbols land here), and one sample file lost all 25
/// through four of six formats.
///
/// Five of six carry them now. ⚠️ kern still drops them — pinned below rather
/// than pretended about.
void main() {
  Score marked() => Score(
        clef: Clef.treble,
        annotations: const [
          Annotation('a', 'Eb'),
          Annotation('b', 'quiet', placement: AnnotationPlacement.below),
        ],
        measures: [
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
        ],
      );

  group('carried', () {
    for (final (name, hop) in <(String, Score Function(Score))>[
      ('musicxml', _xml),
      ('lilypond', _ly),
      ('mei', _mei),
      ('abc', _abc),
      ('musescore', _mscx),
    ]) {
      test('$name keeps both marks', () {
        final back = hop(marked());
        expect(back.annotations.map((a) => a.text).toSet(), {'Eb', 'quiet'});
      });
    }
  });

  test('LilyPond and MEI keep the PLACEMENT', () {
    // Above vs below is the difference between a chord symbol and a
    // performance note, so losing it is not cosmetic.
    for (final hop in [_ly, _mei, _xml]) {
      final back = hop(marked());
      final quiet = back.annotations.firstWhere((a) => a.text == 'quiet');
      expect(quiet.placement, AnnotationPlacement.below);
    }
  });

  test('a quote inside a mark does not break the LilyPond string', () {
    // `^"…"` is delimited by `"`, the same trap as the ABC annotation.
    final s = Score(
      clef: Clef.treble,
      annotations: const [Annotation('a', 'say "hi"')],
      measures: [
        Measure([
          NoteElement(
            pitches: const [Pitch(Step.c, octave: 4)],
            duration: const NoteDuration(DurationBase.quarter),
            id: 'a',
          ),
        ]),
      ],
    );
    final back = _ly(s);
    expect(back.annotations.single.text, 'say "hi"');
    // And the notes must not have gained anything from the spilled text.
    expect(
      back.measures.expand((m) => m.elements).whereType<NoteElement>(),
      hasLength(1),
    );
  });

  group('kern carries them as LOCAL COMMENTS', () {
    // This used to assert that kern dropped annotations, on the belief that it
    // needed a parallel text spine. It does not: Humdrum attaches a local
    // comment (`!text`) to the NEXT data record in its spine, which is exactly
    // what a text mark on a note is. `!!` is global and `!!!` a reference
    // record, so neither is confused with it.
    test('both marks survive', () {
      expect(_kern(marked()).annotations.map((a) => a.text).toSet(),
          {'Eb', 'quiet'});
    });

    test('they land on the right notes', () {
      final back = _kern(marked());
      final ids = back.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .map((n) => n.id)
          .toList();
      expect(back.annotations.first.elementId, ids.first);
    });

    test('a LAYOUT directive is not a text mark', () {
      // ⚠️ Real corpora are made of almost nothing else: 68,161 `!LO:…`
      // directives against 58 plain local comments across 3,000 corpus files.
      // Reading them all as annotations cost 204 corpus round trips.
      final back = scoreFromKern('**kern\n*M4/4\n!LO:TX:a:t=problem\n4c\n'
          '!LO:PB:g=original\n4d\n*-\n');
      expect(back.annotations, isEmpty);
    });

    test('text that LOOKS like a directive still round-trips', () {
      // `Note: play softly` is indistinguishable from `!LO:` once written, so
      // the writer puts a space after the `!` — which no real directive has.
      final s = Score(
        clef: Clef.treble,
        measures: [
          Measure(<MusicElement>[
            NoteElement(
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.quarter),
              id: 'a',
            ),
          ]),
        ],
        annotations: const [Annotation('a', 'Note: play softly')],
      );
      expect(scoreFromKern(scoreToKern(s)).annotations.single.text,
          'Note: play softly');
    });

    test('a reference record is not read as one', () {
      // `!!!OTL: title` is metadata, not a note annotation.
      final back = scoreFromKern('!!!OTL: A Tune\n**kern\n*M4/4\n'
          '4c\n4d\n*-\n');
      expect(back.annotations, isEmpty);
    });

    test('a score with none writes no local comment', () {
      final plain = Score(
        clef: Clef.treble,
        measures: [
          Measure(<MusicElement>[
            NoteElement(
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.quarter),
              id: 'a',
            ),
          ]),
        ],
      );
      expect(
          scoreToKern(plain)
              .split('\n')
              .where((l) => l.startsWith('!') && !l.startsWith('!!')),
          isEmpty);
    });
  });
}

Score _xml(Score s) => scoreFromMusicXml(scoreToMusicXml(s));
Score _ly(Score s) => scoreFromLilyPond(scoreToLilyPond(s));
Score _mei(Score s) => scoreFromMei(scoreToMei(s));
Score _abc(Score s) => scoreFromAbc(scoreToAbc(s));
Score _kern(Score s) => scoreFromKern(scoreToKern(s));
Score _mscx(Score s) => scoreFromMscx(scoreToMscx(s));
