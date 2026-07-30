import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Every text field, every codec, against text that fights the format.
///
/// Four separate escaping defects turned up in this codebase by CORPUS ACCIDENT
/// — a four-line CPDL lyricist field, a hymn lyric quoting speech, a kern
/// `**text` spine holding stray tokens, a syllable ending in a backslash. Each
/// time, text escaped its own field and the remainder was parsed as MUSIC, and
/// each time the existing tests were blind because our own writers never
/// generate metadata containing a newline, a quote or a backslash.
///
/// This makes that systematic: the note content must be untouched no matter what
/// the text says. It is deliberately a MATRIX rather than four one-off cases, so
/// a fifth codec or a fifth delimiter is covered before a corpus file finds it.
void main() {
  // Characters that terminate a field somewhere in this matrix: a newline ends
  // a kern reference record and an ABC `w:`/`T:` line; `"` delimits an ABC
  // annotation and a LilyPond string; `\` escapes in LilyPond; the rest are
  // structural in one format or another.
  const hostile = <String, String>{
    'newline': 'ex\n8a/ 8cc 4dd 4cc',
    'crlf': 'ex\r\nC1',
    'double quote': r'They say, "The Lord nor sees" be wise',
    'trailing backslash': r'1F\',
    'lone backslash': r'\',
    'escaped quote': r'a\"b',
    'abc barline': 'la | la |: la :|',
    'abc tuplet mark': '(3 abc',
    'kern spine end': '*-\n**kern\nc4',
    'lilypond block': r'} \addlyrics { c d e }',
    'xml angle brackets': '<note><pitch>C</pitch></note>',
    'xml entity': '&amp; &lt; &#67;',
    'mei tag': '</layer></staff>',
    'tab and spaces': 'a\tb   c',
    'percent comment': '% not a comment',
    'unicode': 'Grüße — ünïcodé ♩♪',
  };

  const codecs = <String, (String Function(Score), Score Function(String))>{
    'musicxml': (scoreToMusicXml, scoreFromMusicXml),
    'mei': (scoreToMei, scoreFromMei),
    'kern': (scoreToKern, scoreFromKern),
    'abc': (scoreToAbc, scoreFromAbc),
    'lilypond': (scoreToLilyPond, scoreFromLilyPond),
    'musescore': (scoreToMscx, scoreFromMscx),
  };

  /// Three notes whose pitches are unmistakable, so any text read as music
  /// shows up immediately as a count or pitch change.
  List<MusicElement> notes() => [
        for (final (i, midi) in [60, 62, 64].indexed)
          NoteElement(
            pitches: [Pitch.fromMidi(midi)],
            duration: const NoteDuration(DurationBase.quarter),
            id: 'e$i',
          ),
      ];

  List<int> pitches(Score s) => [
        for (final m in s.measures)
          for (final e in m.elements)
            if (e is NoteElement) ...e.pitches.map((p) => p.midiNumber),
      ];

  const want = [60, 62, 64];

  group('a hostile LYRIC never becomes music', () {
    codecs.forEach((codec, fns) {
      hostile.forEach((label, text) {
        test('$codec / $label', () {
          final score = Score(
            clef: Clef.treble,
            lyrics: [Lyric('e0', text)],
            measures: [Measure(notes())],
          );
          final back = fns.$2(fns.$1(score));
          expect(pitches(back), want, reason: '$codec mangled by: $text');
        });
      });
    });
  });

  group('a hostile ANNOTATION never becomes music', () {
    codecs.forEach((codec, fns) {
      hostile.forEach((label, text) {
        test('$codec / $label', () {
          final score = Score(
            clef: Clef.treble,
            annotations: [Annotation('e0', text)],
            measures: [Measure(notes())],
          );
          final back = fns.$2(fns.$1(score));
          expect(pitches(back), want, reason: '$codec mangled by: $text');
        });
      });
    });
  });

  group('hostile METADATA never becomes music', () {
    codecs.forEach((codec, fns) {
      hostile.forEach((label, text) {
        test('$codec / $label', () {
          final score = Score(
            clef: Clef.treble,
            metadata: ScoreMetadata(
              title: text,
              composer: text,
              lyricist: text,
              copyright: text,
              instrument: text,
            ),
            measures: [Measure(notes())],
          );
          final back = fns.$2(fns.$1(score));
          expect(pitches(back), want, reason: '$codec mangled by: $text');
        });
      });
    });
  });

  group('the text itself survives where the format carries it', () {
    // Note safety is the floor; this is the ceiling. Two ABC losses showed up
    // only here: a `|` inside a `w:` syllable cut it short (`|` advances to the
    // next bar), and an annotation starting with `^ _ < > @` lost that
    // character to the position-marker strip.
    //
    // The exceptions below are format-inherent, not defects, and are listed so
    // a REGRESSION still shows up:
    //  * kern and ABC are line-oriented and separate syllables by whitespace,
    //    so ANY whitespace run inside a syllable — newline, tab, several
    //    spaces — collapses to one space. Neither format can hold it;
    //  * MEI, kern, LilyPond and MuseScore carry no annotations at all here.
    const carriesAnnotations = {'musicxml', 'abc'};
    const lineOriented = {'kern', 'abc'};

    codecs.forEach((codec, fns) {
      hostile.forEach((label, text) {
        // Not just newlines: a tab or a run of spaces collapses too.
        final collapses = lineOriented.contains(codec) &&
            text != text.replaceAll(RegExp(r'\s+'), ' ');

        test('$codec / $label / lyric', () {
          final score = Score(
            clef: Clef.treble,
            lyrics: [Lyric('e0', text)],
            measures: [Measure(notes())],
          );
          final got = fns.$2(fns.$1(score)).lyrics.single.text;
          expect(got, collapses ? text.replaceAll(RegExp(r'\s+'), ' ') : text,
              reason: '$codec lost lyric text');
        });

        if (!carriesAnnotations.contains(codec)) return;
        test('$codec / $label / annotation', () {
          final score = Score(
            clef: Clef.treble,
            annotations: [Annotation('e0', text)],
            measures: [Measure(notes())],
          );
          final got = fns.$2(fns.$1(score)).annotations.single.text;
          expect(got, collapses ? text.replaceAll(RegExp(r'\s+'), ' ') : text,
              reason: '$codec lost annotation text');
        });
      });
    });
  });
}
