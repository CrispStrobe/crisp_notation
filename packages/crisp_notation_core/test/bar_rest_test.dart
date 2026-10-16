import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A whole-bar rest fills its bar whatever the meter. Reading one as a long
/// (16 quarters) or a whole (4) in 9/8 put every later note of a song's voice
/// part late — found by comparing onsets with Verovio on the Lieder corpus.
void main() {
  String xml(String time, String bars) => '''
<score-partwise version="3.1"><part-list><score-part id="P1">
<part-name>P</part-name></score-part></part-list><part id="P1">
<measure number="1"><attributes><divisions>2</divisions>
<time>$time</time><clef><sign>G</sign><line>2</line></clef></attributes>
$bars
</part></score-partwise>''';
  const c5 = '<note><pitch><step>C</step><octave>5</octave></pitch>'
      '<duration>1</duration><voice>1</voice><type>eighth</type></note>';

  Fraction firstNote(Score s) => playbackTimeline(s, expandRepeats: false)
      .firstWhere((n) => !n.isRest)
      .start;

  test('a typeless bar rest in 9/8 lasts the bar', () {
    final score = scoreFromMusicXml(xml(
        '<beats>9</beats><beat-type>8</beat-type>',
        '<note><rest measure="yes"/><duration>9</duration><voice>1</voice>'
            '</note></measure><measure number="2">$c5</measure>'));
    final rest = score.measures.first.elements.single as RestElement;
    expect(rest.duration, const NoteDuration(DurationBase.whole));
    expect(firstNote(score), Fraction(9, 8));
  });

  test('a bar rest typed whole in 6/8 stays a whole rest', () {
    final score = scoreFromMusicXml(xml(
        '<beats>6</beats><beat-type>8</beat-type>',
        '<note><rest measure="yes"/><duration>6</duration><voice>1</voice>'
            '<type>whole</type></note></measure>'
            '<measure number="2">$c5</measure>'));
    final rest = score.measures.first.elements.single as RestElement;
    expect(rest.duration, const NoteDuration(DurationBase.whole));
    expect(firstNote(score), Fraction(3, 4));
  });

  test('a bar rest shorter than the meter keeps its written length', () {
    // The bar before a repeat whose upbeat completes it: 5/8 of a 6/8 bar.
    final score = scoreFromMusicXml(xml(
        '<beats>6</beats><beat-type>8</beat-type>',
        '<note><rest measure="yes"/><duration>5</duration><voice>1</voice>'
            '</note></measure><measure number="2">$c5</measure>'));
    expect(score.measures.first.actualDuration, Fraction(5, 8));
    expect(firstNote(score), Fraction(5, 8));
  });

  test('a duration snapped to a long is a long', () {
    // 16 quarters with no type: the nearest value is a long, which the snap
    // once measured as four quarters.
    final score = scoreFromMusicXml(xml(
        '<beats>16</beats><beat-type>4</beat-type>',
        '<note><pitch><step>C</step><octave>5</octave></pitch>'
            '<duration>31</duration><voice>1</voice></note></measure>'));
    final note = score.measures.first.elements.single as NoteElement;
    expect(note.duration.base, DurationBase.long);
  });

  test('MusicXML writes a bar rest with the bar\'s length and reads it back',
      () {
    final score = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(9, 8),
      measures: [
        Measure([RestElement(NoteDuration.whole, id: 'r')]),
        Measure([
          NoteElement.note(const Pitch(Step.c, octave: 5),
              const NoteDuration(DurationBase.half, dots: 1),
              id: 'n1'),
          NoteElement.note(const Pitch(Step.c, octave: 5),
              const NoteDuration(DurationBase.quarter, dots: 1),
              id: 'n2'),
        ]),
      ],
    );
    final out = scoreToMusicXml(score);
    expect(out, contains('<rest measure="yes"/><duration>'));
    final back = scoreFromMusicXml(out);
    expect(
        back.measures.first.elements.single,
        isA<RestElement>().having((r) => r.duration, 'duration',
            const NoteDuration(DurationBase.whole)));
    expect(firstNote(back), Fraction(9, 8));
  });
}
