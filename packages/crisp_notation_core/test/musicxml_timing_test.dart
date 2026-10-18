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

  group('hidden notes', () {
    test('keep their time at the end of the bar', () {
      // Eight eighths, the first and last unprinted: the bar still lasts a
      // whole note, so the next bar starts on time.
      final hidden = note('B', 4, 2, 'eighth', attrs: ' print-object="no"');
      final drawn = [for (var i = 0; i < 6; i++) note('B', 4, 2, 'eighth')];
      final score = scoreFromMusicXml(doc('<measure number="1"><attributes/>'
          '$hidden${drawn.join()}$hidden</measure>'
          '<measure number="2">${note('C', 5, 16, 'whole')}</measure>'));
      final first = score.measures.first.elements;
      expect(first.whereType<NoteElement>(), hasLength(6));
      expect((first.first as RestElement).hidden, isTrue);
      expect((first.last as RestElement).hidden, isTrue);
      expect(onsets(score).last.$2, Fraction(1, 1));
    });

    test('keep the tuplet they open', () {
      // A triplet of quarters whose first note is unprinted and carries the
      // <tuplet> start: the other two still sound a third of a half each.
      String quarter(String marks, {String attrs = ''}) =>
          note('B', 4, 4, 'quarter',
              attrs: attrs,
              extra: '<time-modification><actual-notes>3</actual-notes>'
                  '<normal-notes>2</normal-notes></time-modification>$marks');
      final score = scoreFromMusicXml(doc(
          '<measure number="1"><attributes/>'
          '${quarter('<notations><tuplet type="start"/></notations>', attrs: ' print-object="no"')}'
          '${quarter('')}'
          '${quarter('<notations><tuplet type="stop"/></notations>')}'
          '${note('C', 5, 12, 'half')}'
          '</measure>',
          divisions: 6));
      expect(score.measures.single.tuplets.single.endIndex, 2);
      expect(onsets(score).map((o) => o.$2),
          [Fraction(1, 6), Fraction(1, 3), Fraction(1, 2)]);
    });

    test('a voice past 4 that only hidden rests play takes no slot', () {
      // Voices 1, 3 and 4 are drawn; voice 5 only rests, unprinted; voice 6
      // has a whole note. Voice 5 took the free slot, and voice 6's whole
      // note went after voice 4's half note.
      final score = scoreFromMusicXml(doc('<measure number="1"><attributes/>'
          '${note('C', 5, 16, 'whole')}${backup(16)}'
          '${note('A', 4, 16, 'whole', voice: '3')}${backup(16)}'
          '${note('F', 4, 8, 'half', voice: '4')}${backup(8)}'
          '<note print-object="no"><rest/><duration>16</duration>'
          '<voice>5</voice><type>whole</type></note>${backup(16)}'
          '${note('C', 4, 16, 'whole', voice: '6')}'
          '</measure>'));
      expect(score.measures.single.voice2.single, isA<NoteElement>());
      expect(onsets(score).map((o) => o.$2), everyElement(Fraction.zero));
    });
  });

  group('more voices than slots', () {
    test('a fifth voice goes to a slot that is free at its onset', () {
      // Voices 1-4 hold the four slots; voice 5's quarter on beat 3 found its
      // slot (voice 4's) still sounding and went after it, past the bar.
      // Voice 2 is silent from beat 3, so the quarter goes there.
      final score = scoreFromMusicXml(doc('<measure number="1"><attributes/>'
          '${note('C', 6, 16, 'whole')}${backup(16)}'
          '${note('A', 5, 8, 'half', voice: '2')}${backup(8)}'
          '${note('F', 5, 16, 'whole', voice: '3')}${backup(16)}'
          '${note('D', 5, 16, 'whole', voice: '4')}${backup(16)}'
          '<forward><duration>8</duration></forward>'
          '${note('C', 4, 4, 'quarter', voice: '5')}'
          '</measure>'));
      final m = score.measures.single;
      expect(m.voice4, hasLength(1));
      expect(m.voice2.whereType<NoteElement>(), hasLength(2));
      expect(onsets(score).where((o) => o.$1 == 1).map((o) => o.$2),
          [Fraction.zero, Fraction(1, 2)]);
    });
  });

  group('bar rests', () {
    test('an unmetered bar rest lasts what it says', () {
      // A senza-misura bar of three eighths, then a bar rest of 3 quarters:
      // with no meter to fill it was taken for a whole note.
      final score = scoreFromMusicXml(doc(
          '<measure number="1"><attributes/>'
          '${note('B', 4, 1, 'eighth')}${note('B', 4, 1, 'eighth')}'
          '${note('B', 4, 1, 'eighth')}</measure>'
          '<measure number="2"><note><rest measure="yes"/>'
          '<duration>6</duration><voice>1</voice></note></measure>',
          divisions: 2,
          time: 'senza'));
      expect(score.measures.last.actualDuration, Fraction(3, 4));
    });

    test('beside another voice, it lasts what it says', () {
      // A one-quarter bar before a repeat, in 4/4: voice 1 rests a quarter
      // and voice 2's bar rest says a quarter too. It filled the meter.
      final score = scoreFromMusicXml(doc('<measure number="1"><attributes/>'
          '<note><rest/><duration>4</duration><voice>1</voice>'
          '<type>quarter</type></note>${backup(4)}'
          '<note><rest measure="yes"/><duration>4</duration><voice>2</voice>'
          '</note></measure>'));
      expect(score.measures.single.actualDuration, Fraction(1, 4));
    });
  });
}

String _time(String time) {
  if (time == 'senza') return '<time><senza-misura/></time>';
  final [beats, type] = time.split('/');
  return '<time><beats>$beats</beats><beat-type>$type</beat-type></time>';
}
