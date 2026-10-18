import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// The maxima: eight whole notes, the longest value MusicXML, LilyPond, MEI
/// and Humdrum define. With no [DurationBase] for it, MusicXML read it as a
/// breve (a quarter of its length), LilyPond and kern as a longa (half).
void main() {
  NoteElement note(NoteDuration d, [String id = 'e0']) => NoteElement(
      pitches: const [Pitch(Step.c, octave: 5)], duration: d, id: id);
  Score one(MusicElement e, {int beats = 16}) => Score(
        clef: Clef.treble,
        timeSignature: TimeSignature(beats, 2),
        measures: [
          Measure([e])
        ],
      );
  const maxima = NoteDuration(DurationBase.maxima);

  test('worth eight whole notes; dots add four and two', () {
    expect(DurationBase.maxima.wholeValue, (8, 1));
    expect(DurationBase.maxima.log2Value, 3);
    expect(DurationBase.maxima.flagCount, 0);
    expect(maxima.toFraction(), Fraction(8, 1));
    expect(const NoteDuration(DurationBase.maxima, dots: 1).toFraction(),
        Fraction(12, 1));
    expect(const NoteDuration(DurationBase.maxima, dots: 2).toFraction(),
        Fraction(14, 1));
  });

  // Measures 1, 3 and 5 of the MusicXML test suite's 03a-Rhythm-Durations:
  // the plain, dotted and double-dotted maxima, each filling its bar.
  String xml03a() {
    String bar(int n, int beats, int duration, int dots) =>
        '<measure number="$n">'
        '<attributes>${n == 1 ? '<divisions>1024</divisions>' : ''}'
        '<time><beats>$beats</beats><beat-type>2</beat-type></time>'
        '${n == 1 ? '<clef><sign>G</sign><line>2</line></clef>' : ''}'
        '</attributes>'
        '<note><pitch><step>C</step><octave>5</octave></pitch>'
        '<duration>$duration</duration><voice>1</voice>'
        '<type>maxima</type>${'<dot/>' * dots}</note></measure>';
    return '<?xml version="1.0"?><score-partwise version="4.0">'
        '<part-list><score-part id="P1"><part-name>P</part-name>'
        '</score-part></part-list><part id="P1">'
        '${bar(1, 16, 32768, 0)}${bar(2, 24, 49152, 1)}'
        '${bar(3, 28, 57344, 2)}</part></score-partwise>';
  }

  List<NoteDuration> durations(Score s) => [
        for (final m in s.measures)
          for (final e in m.elements)
            if (e is NoteElement) e.duration
      ];

  test('MusicXML (03a): reads the maxima as 8 whole notes and writes it back',
      () {
    final score = scoreFromMusicXml(xml03a());
    expect(durations(score), const [
      NoteDuration(DurationBase.maxima),
      NoteDuration(DurationBase.maxima, dots: 1),
      NoteDuration(DurationBase.maxima, dots: 2),
    ]);
    expect(durations(score).first.toFraction(), Fraction(8, 1));
    final written = scoreToMusicXml(score);
    expect('<type>maxima</type>'.allMatches(written), hasLength(3));
    expect(durations(scoreFromMusicXml(written)), durations(score));
  });

  final suite03a = File('/mnt/volume1/notation-corpus/musicxml-testsuite/'
      'lilypond/03a-Rhythm-Durations.xml');
  test('MusicXML: the test suite file itself, when the corpus is present', () {
    final score = scoreFromMusicXml(suite03a.readAsStringSync());
    final first = durations(score).first;
    expect(first, maxima);
    expect(first.toFraction(), Fraction(8, 1));
    final back = durations(scoreFromMusicXml(scoreToMusicXml(score)));
    expect(back, durations(score));
  },
      skip: suite03a.existsSync()
          ? null
          : 'the MusicXML test suite is not in the local corpus');

  test(r'LilyPond: \maxima reads and writes', () {
    final score = scoreFromLilyPond(r"{ \time 16/2 c''\maxima }");
    expect(durations(score), [maxima]);
    final ly = scoreToLilyPond(score);
    expect(ly, contains(r'\maxima'));
    expect(durations(scoreFromLilyPond(ly)), [maxima]);
  });

  test('MEI: dur="maxima" reads and writes', () {
    final mei = scoreToMei(one(note(maxima)));
    expect(mei, contains('dur="maxima"'));
    expect(durations(scoreFromMei(mei)), [maxima]);
  });

  test('kern: 000 reads and writes', () {
    final kern = scoreToKern(one(note(maxima)));
    expect(kern, contains('000c'));
    expect(durations(scoreFromKern(kern)), [maxima]);
  });

  test('MuseScore: written as a longa, its longest value, not a quarter', () {
    expect(scoreToMscx(one(note(maxima))),
        contains('<durationType>long</durationType>'));
  });

  test('playback holds it for eight whole notes', () {
    final notes = playbackTimeline(one(note(maxima)));
    expect(notes.single.duration, Fraction(8, 1));
  });

  group('layout', () {
    late LayoutSettings settings;
    setUpAll(() {
      settings = LayoutSettings(
          metadata: SmuflMetadata.fromJson(jsonDecode(
              File('../crisp_notation/assets/smufl/bravura_metadata.json')
                  .readAsStringSync()) as Map<String, Object?>));
    });

    test('a maxima draws its wide head and no stem', () {
      final l = const LayoutEngine().layout(one(note(maxima)), settings);
      final heads = [
        for (final p in l.primitives.whereType<GlyphPrimitive>())
          if (p.elementId == 'e0') p.smuflName
      ];
      expect(heads, contains('mensuralNoteheadMaximaWhite'));
      expect(smuflCodepoints, contains('mensuralNoteheadMaximaWhite'));
      final stems = [
        for (final p in l.primitives.whereType<LinePrimitive>())
          if (p.elementId == 'e0' && p.from.x == p.to.x) p
      ];
      expect(stems, isEmpty);
    });

    test('a maxima rest draws restMaxima', () {
      // Not alone in its bar, where it would draw as a whole-bar rest.
      final score = Score(
        clef: Clef.treble,
        timeSignature: TimeSignature(20, 2),
        measures: [
          Measure([
            RestElement(maxima, id: 'r0'),
            note(const NoteDuration(DurationBase.breve), 'b'),
          ])
        ],
      );
      final l = const LayoutEngine().layout(score, settings);
      expect(
          l.primitives
              .whereType<GlyphPrimitive>()
              .where((p) => p.elementId == 'r0')
              .map((p) => p.smuflName),
          contains('restMaxima'));
    });

    test('it takes more room than a longa', () {
      double gap(DurationBase base) {
        final score = Score(
          clef: Clef.treble,
          timeSignature: TimeSignature(24, 2),
          measures: [
            Measure([
              note(NoteDuration(base), 'a'),
              note(const NoteDuration(DurationBase.whole), 'b'),
            ])
          ],
        );
        final l = const LayoutEngine().layout(score, settings);
        double x(String id) => l.primitives
            .whereType<GlyphPrimitive>()
            .firstWhere((p) => p.elementId == id)
            .position
            .x;
        return x('b') - x('a');
      }

      expect(gap(DurationBase.maxima), greaterThan(gap(DurationBase.long)));
    });
  });
}
