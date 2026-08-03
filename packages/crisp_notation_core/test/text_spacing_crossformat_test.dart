import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Text-flattening must remove only what would BREAK the format.
///
/// ⚠️ The ABC and kern writers both collapsed EVERY run of whitespace to one
/// space. The motive was sound — a newline ends a `!!!` record and an ABC
/// field, so third-party prose containing one spills into the music (four
/// separate corpus bugs came from exactly that). But `\s+` also eats runs of
/// ordinary SPACES, and those are content: hymn and psalm texts use them to
/// align verse against verse. Every such lyric line came back reflowed.
void main() {
  const spaced = '1. My  God,      per - mit  my  tongue';

  final hops = <String, Score Function(Score)>{
    'musicxml': (x) => scoreFromMusicXml(scoreToMusicXml(x)),
    'mei': (x) => scoreFromMei(scoreToMei(x)),
    'kern': (x) => scoreFromKern(scoreToKern(x)),
    'abc': (x) => scoreFromAbc(scoreToAbc(x)),
    'lilypond': (x) => scoreFromLilyPond(scoreToLilyPond(x)),
    'musescore': (x) => scoreFromMscx(scoreToMscx(x)),
  };

  Score scored() => Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure([
            NoteElement(
              id: 'e0',
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.whole),
            )
          ])
        ],
        annotations: const [Annotation('e0', spaced)],
        metadata: const ScoreMetadata(title: 'A  spaced   title'),
      );

  for (final e in hops.entries) {
    test('${e.key} keeps runs of spaces in text', () {
      final back = e.value(scored());
      expect(back.annotations.single.text, spaced, reason: e.key);
      expect(back.metadata.title, 'A  spaced   title', reason: e.key);
    });

    // A newline in third-party prose spilled into the MUSIC in four separate
    // codecs, so the invariant that matters is that it cannot reach the notes.
    // The XML formats may legitimately keep it; the line-terminated ones must
    // flatten it, and either way the music is untouched.
    test('${e.key}: a NEWLINE in metadata never reaches the music', () {
      final back = e.value(Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [
          Measure([
            NoteElement(
              id: 'e0',
              pitches: const [Pitch(Step.c, octave: 4)],
              duration: const NoteDuration(DurationBase.whole),
            )
          ])
        ],
        metadata: const ScoreMetadata(title: 'Two\nlines'),
      ));
      expect(back.measures.single.elements, hasLength(1), reason: e.key);
      // kern and ABC are LINE-terminated, so they must flatten. XML and
      // LilyPond quote their strings and keep the break, which is better.
      if (const {'kern', 'abc'}.contains(e.key)) {
        expect(back.metadata.title, isNot(contains('\n')), reason: e.key);
      }
      expect(back.metadata.title, contains('Two'), reason: e.key);
      expect(back.metadata.title, contains('lines'), reason: e.key);
    });
  }
}
