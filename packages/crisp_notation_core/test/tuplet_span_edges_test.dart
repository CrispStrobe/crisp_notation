import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Two corpus-found defects that a note-count check cannot see.
///
/// Both were found by the cross-format sweep once it started comparing SOUNDING
/// duration; both leave every note in place and change what you hear.

List<Fraction> sounding(Score s, {int voice = 0}) {
  final out = <Fraction>[];
  for (final m in s.measures) {
    final scale = <int, Fraction>{};
    for (final t in m.tuplets) {
      if (t.voice != voice) continue;
      for (var i = t.startIndex; i <= t.endIndex; i++) {
        scale[i] = Fraction(t.normal, t.actual);
      }
    }
    final elements = m.voices[voice];
    for (var i = 0; i < elements.length; i++) {
      final e = elements[i];
      if (e is! NoteElement) continue;
      out.add(e.duration.toFraction() * (scale[i] ?? Fraction(1, 1)));
    }
  }
  return out;
}

void main() {
  test('a kern tuplet member that notates as a plain value keeps its ratio',
      () {
    // Chopin Op. 7/12: the triplet runs eighth, dotted-eighth, sixteenth, and
    // the middle member sounds exactly one eighth — which kern writes as the
    // ordinary `8`. Ratios are derived per note from the note's own reciprocal,
    // so that splits the run into two runs of ONE, and requiring at least two
    // elements per span dropped both neighbours' ratios and made them a third
    // too long.
    final kern = '**kern\n*M2/4\n12cc\n8c\n24d\n*-\n';
    final s = scoreFromKern(kern);
    expect(sounding(s), [Fraction(1, 12), Fraction(1, 8), Fraction(1, 24)]);
    // ...and it survives being written back out.
    expect(sounding(scoreFromKern(scoreToKern(s))), sounding(s));
  });

  group('MusicXML voice slots are stable across bars', () {
    // The reader built its voice order PER MEASURE, so in a bar where voice 1
    // is silent the first label seen was `2` and its notes landed in voice 1 —
    // the inner part jumped to the outer one for that bar and back afterwards.
    // In Greene's "Thou visitest the Earth" that moved two notes and shifted
    // every comparison after it.
    NoteElement n(int midi, String id) => NoteElement(
          pitches: [Pitch.fromMidi(midi)],
          duration: const NoteDuration(DurationBase.quarter),
          id: id,
        );

    Score twoBars() => Score(clef: Clef.treble, measures: [
          Measure([n(72, 'a')], voice2: [n(60, 'b')]),
          // Voice 1 silent, voice 2 alone.
          Measure(const [], voice2: [n(62, 'c')]),
        ]);

    test('a bar whose voice 1 is silent does not promote voice 2', () {
      final back = scoreFromMusicXml(scoreToMusicXml(twoBars()));
      expect(back.measures[1].elements.whereType<NoteElement>(), isEmpty,
          reason: 'voice 2 was promoted into voice 1');
      expect(
        back.measures[1].voice2
            .whereType<NoteElement>()
            .map((e) => e.pitches.first.midiNumber),
        [62],
      );
    });

    test('labels 1-4 map to their own slot', () {
      const xml = '<score-partwise><part-list><score-part id="P1">'
          '<part-name>P</part-name></score-part></part-list>'
          '<part id="P1"><measure number="1">'
          '<attributes><divisions>1</divisions></attributes>'
          '<note><pitch><step>C</step><octave>4</octave></pitch>'
          '<duration>1</duration><voice>3</voice><type>quarter</type></note>'
          '</measure></part></score-partwise>';
      final s = scoreFromMusicXml(xml);
      expect(s.measures[0].elements, isEmpty);
      expect(s.measures[0].voice2, isEmpty);
      expect(s.measures[0].voice3.whereType<NoteElement>(), hasLength(1));
    });

    test('labels outside 1-4 keep the first-seen fallback', () {
      // A piano part's second staff conventionally uses 5 and 6.
      const xml = '<score-partwise><part-list><score-part id="P1">'
          '<part-name>P</part-name></score-part></part-list>'
          '<part id="P1"><measure number="1">'
          '<attributes><divisions>1</divisions></attributes>'
          '<note><pitch><step>C</step><octave>4</octave></pitch>'
          '<duration>1</duration><voice>5</voice><type>quarter</type></note>'
          '<backup><duration>1</duration></backup>'
          '<note><pitch><step>E</step><octave>4</octave></pitch>'
          '<duration>1</duration><voice>6</voice><type>quarter</type></note>'
          '</measure></part></score-partwise>';
      final s = scoreFromMusicXml(xml);
      expect(s.measures[0].elements.whereType<NoteElement>(), hasLength(1));
      expect(s.measures[0].voice2.whereType<NoteElement>(), hasLength(1));
    });
  });
}
