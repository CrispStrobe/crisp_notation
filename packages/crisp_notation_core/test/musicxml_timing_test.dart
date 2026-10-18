import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// MusicXML timing the Verovio onset oracle found misread: each group is a
/// bar (or two) a corpus file wrote, cut down to what went wrong.
void main() {
  // One part, [divisions] per quarter, [time] the meter ('senza' for an
  // unmetered one). The first `<attributes/>` in [measures] receives them.
  String doc(String measures, {int divisions = 4, String time = '4/4'}) =>
      '<score-partwise><part-list><score-part id="P1"><part-name>P'
      '</part-name></score-part></part-list><part id="P1">'
      '${measures.replaceFirst('<attributes/>', '<attributes>'
          '<divisions>$divisions</divisions>${_time(time)}</attributes>')}'
      '</part></score-partwise>';

  String note(String step, int octave, int duration, String type,
          {String voice = '1', String extra = '', String attrs = ''}) =>
      '<note$attrs><pitch><step>$step</step><octave>$octave</octave></pitch>'
      '<duration>$duration</duration><voice>$voice</voice><type>$type</type>'
      '$extra</note>';

  String backup(int d) => '<backup><duration>$d</duration></backup>';

  // (voice, onset in whole notes) of [score]'s notes and rests with ids.
  List<(int, Fraction)> onsets(Score score) => [
        for (final n in playbackTimeline(score, expandRepeats: false))
          (n.voice, n.start),
      ];

  group('voice slots', () {
    test('a voice labelled past 4 takes a slot voices 1-4 leave free', () {
      // Voice 1 holds the bar; voice 5 (a piano's lower voice) has four
      // quarters on the same staff. It took voice 1's slot, after the whole
      // note, and the bar ran to two whole notes.
      final score = scoreFromMusicXml(doc('<measure number="1"><attributes/>'
          '${note('C', 5, 16, 'whole')}${backup(16)}'
          '${note('E', 4, 4, 'quarter', voice: '5')}'
          '${note('F', 4, 4, 'quarter', voice: '5')}'
          '${note('G', 4, 4, 'quarter', voice: '5')}'
          '${note('A', 4, 4, 'quarter', voice: '5')}'
          '</measure>'));
      final m = score.measures.single;
      expect(m.elements, hasLength(1));
      expect(m.voice2, hasLength(4));
      expect(onsets(score).where((o) => o.$1 == 1).map((o) => o.$2), [
        Fraction.zero,
        Fraction(1, 4),
        Fraction(1, 2),
        Fraction(3, 4),
      ]);
    });
  });

  group('a time-modification with no tuplet', () {
    // A half-note tremolo: two halves, each sounding a quarter (2:1), with no
    // <tuplet> bracket; then a half note.
    const twoToOne = '<time-modification><actual-notes>2</actual-notes>'
        '<normal-notes>1</normal-notes></time-modification>';
    String tremolo() => doc('<measure number="1"><attributes/>'
        '${note('C', 5, 4, 'half', extra: twoToOne)}'
        '${note('E', 5, 4, 'half', extra: twoToOne)}'
        '${note('G', 4, 8, 'half')}'
        '</measure>');

    test('times its notes by a hidden span', () {
      final score = scoreFromMusicXml(tremolo());
      final span = score.measures.single.tuplets.single;
      expect((span.startIndex, span.endIndex), (0, 1));
      expect((span.actual, span.normal, span.hidden), (2, 1, true));
      expect(onsets(score).map((o) => o.$2),
          [Fraction.zero, Fraction(1, 4), Fraction(1, 2)]);
    });

    test('round-trips without gaining a bracket', () {
      final xml = scoreToMusicXml(scoreFromMusicXml(tremolo()));
      expect(xml, contains('<time-modification>'));
      expect(xml, isNot(contains('<tuplet')));
      expect(
          scoreFromMusicXml(xml).measures.single.tuplets.single.hidden, isTrue);
    });

    test('a bracketed group keeps its visible span', () {
      String eighth(String step, String marks) => note(step, 4, 1, 'eighth',
          extra: '<time-modification><actual-notes>3</actual-notes>'
              '<normal-notes>2</normal-notes></time-modification>$marks');
      final score = scoreFromMusicXml(doc(
          '<measure number="1"><attributes/>'
          '${eighth('C', '<notations><tuplet type="start"/></notations>')}'
          '${eighth('D', '')}'
          '${eighth('E', '<notations><tuplet type="stop"/></notations>')}'
          '</measure>',
          divisions: 2,
          time: '1/4'));
      expect(score.measures.single.tuplets.single.hidden, isFalse);
    });
  });
}

String _time(String time) {
  if (time == 'senza') return '<time><senza-misura/></time>';
  final [beats, type] = time.split('/');
  return '<time><beats>$beats</beats><beat-type>$type</beat-type></time>';
}
