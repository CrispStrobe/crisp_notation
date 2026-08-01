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

  test('kern still DROPS annotations', () {
    // Stating the real state so whoever closes it is told to move it up.
    // kern would need a parallel spine for text, which is a bigger change than
    // the sibling-element pattern the other five use.
    expect(_kern(marked()).annotations, isEmpty);
  });
}

Score _xml(Score s) => scoreFromMusicXml(scoreToMusicXml(s));
Score _ly(Score s) => scoreFromLilyPond(scoreToLilyPond(s));
Score _mei(Score s) => scoreFromMei(scoreToMei(s));
Score _abc(Score s) => scoreFromAbc(scoreToAbc(s));
Score _kern(Score s) => scoreFromKern(scoreToKern(s));
Score _mscx(Score s) => scoreFromMscx(scoreToMscx(s));
