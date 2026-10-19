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
    test('a fifth voice sounding with all four joins a chord, the bar intact',
        () {
      // Four voices fill the bar (4/4, 4 divisions a quarter); a fifth
      // starts a half note with voice 1's first note. No slot is free at its
      // onset: appended after one, it ran the bar long (and longer still
      // after a round trip).
      final xml = doc('<measure number="1"><attributes/>'
          '${note('C', 5, 8, 'half')}${note('D', 5, 8, 'half')}${backup(16)}'
          '${note('A', 4, 16, 'whole', voice: '2')}${backup(16)}'
          '${note('F', 4, 16, 'whole', voice: '3')}${backup(16)}'
          '${note('D', 4, 16, 'whole', voice: '4')}${backup(16)}'
          '${note('G', 5, 8, 'half', voice: '5')}'
          '</measure>');
      final score = scoreFromMusicXml(xml);
      final m = score.measures.single;
      for (var v = 0; v < 4; v++) {
        final total = m.voiceAt(v).fold<Fraction>(
            Fraction.zero, (t, e) => t + e.duration.toFraction());
        expect(total, lessThanOrEqualTo(Fraction(1, 1)), reason: 'voice $v');
      }
      final first = m.elements.first as NoteElement;
      expect(first.pitches.map((p) => p.step), containsAll([Step.c, Step.g]));
      final back = scoreFromMusicXml(scoreToMusicXml(score));
      expect(back.measures.single.elements.length, m.elements.length);
    });

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

  group('a whole rest in a longer bar', () {
    test('rests a whole note, not the bar', () {
      // Half a bar of 4/2 before a double bar: a whole rest that says it
      // lasts a whole note. It was taken for the bar rest, a breve long.
      final score = scoreFromMusicXml(doc(
          '<measure number="1"><attributes/>${note('A', 4, 8, 'breve')}'
          '</measure><measure number="2"><note><rest/><duration>4</duration>'
          '<voice>1</voice><type>whole</type></note></measure>'
          '<measure number="3">${note('A', 4, 8, 'breve')}</measure>',
          divisions: 1,
          time: '4/2'));
      expect(score.measures[1].actualDuration, Fraction(1, 1));
      expect(onsets(score).last.$2, Fraction(3, 1));
    });

    test('in a bar it fills, a whole rest is still the bar rest', () {
      final score = scoreFromMusicXml(doc(
          '<measure number="1"><attributes/><note><rest/><duration>3'
          '</duration><voice>1</voice><type>whole</type></note></measure>',
          divisions: 1,
          time: '3/4'));
      expect(score.measures.single.actualDuration, isNull);
    });
  });

  group('a rest with no type', () {
    test('that fills the bar is the bar rest', () {
      // A bar of 5/16 whose rest has no <type> and lasts five 16ths, which
      // no single rest spells: it was rounded to a quarter.
      final score = scoreFromMusicXml(doc(
          '<measure number="1"><attributes/><note><rest/><duration>5'
          '</duration><voice>1</voice></note></measure>'
          '<measure number="2">${note('C', 5, 1, '16th')}</measure>',
          time: '5/16'));
      expect(score.measures.first.elements.single.duration,
          const NoteDuration(DurationBase.whole));
      expect(onsets(score).last.$2, Fraction(5, 16));
    });
  });

  group('unpitched notes', () {
    String drum(String display, {String extra = ''}) => '<note>$extra'
        '<unpitched>$display</unpitched><duration>2</duration>'
        '<voice>1</voice><type>quarter</type></note>';

    test('with no display position sit on the middle line', () {
      // It was read as a rest.
      final score = scoreFromMusicXml(doc(
          '<measure number="1"><attributes/>${drum('')}</measure>',
          divisions: 2,
          time: '1/4'));
      expect((score.measures.single.elements.single as NoteElement).pitches,
          [const Pitch(Step.b, octave: 4)]);
    });

    test('are tones of the chord they are written in', () {
      // A snare struck with the hi-hat: the hi-hat was dropped.
      final score = scoreFromMusicXml(doc(
          '<measure number="1"><attributes/>'
          '${drum('<display-step>C</display-step>'
              '<display-octave>5</display-octave>')}'
          '${drum('<display-step>G</display-step>'
              '<display-octave>5</display-octave>', extra: '<chord/>')}'
          '</measure>',
          divisions: 2,
          time: '1/4'));
      expect((score.measures.single.elements.single as NoteElement).pitches, [
        const Pitch(Step.c, octave: 5),
        const Pitch(Step.g, octave: 5),
      ]);
    });
  });

  group('quarter-tone alters', () {
    test('read as microtonal accidentals, and write back', () {
      // <alter>-0.5</alter> was rounded to a flat: a half-flat D read as
      // D-flat.
      String micro(String step, String alter) => '<note><pitch><step>$step'
          '</step><alter>$alter</alter><octave>4</octave></pitch>'
          '<duration>1</duration><voice>1</voice><type>quarter</type></note>';
      final score = scoreFromMusicXml(doc(
          '<measure number="1"><attributes/>'
          '${micro('D', '-0.5')}${micro('E', '0.5')}${micro('C', '-1.5')}'
          '${micro('F', '1.5')}</measure>',
          divisions: 1));
      final pitches = [
        for (final e in score.measures.single.elements)
          (e as NoteElement).pitches.single,
      ];
      expect(pitches.map((p) => p.microtone), [
        MicrotonalAccidental.halfFlat,
        MicrotonalAccidental.halfSharp,
        MicrotonalAccidental.sesquiFlat,
        MicrotonalAccidental.sesquiSharp,
      ]);
      expect(pitches.map((p) => p.midiNumber), [62, 64, 60, 65]);
      final back = scoreFromMusicXml(scoreToMusicXml(score));
      expect(
          back.measures.single.elements
              .map((e) => (e as NoteElement).pitches.single),
          pitches);
    });
  });

  test('a staff in its own shorter meter is stretched to the bar', () {
    // MuseScore's local time signature: the voice in 3/2 (three halves)
    // over a piano in 9/4, both filling their meters. MuseScore plays the
    // voice's halves as dotted halves; read as written it ran short.
    String part(String id, String time, String notes) =>
        '<part id="$id"><measure number="1"><attributes><divisions>1'
        '</divisions><time><beats>${time.split('/')[0]}</beats>'
        '<beat-type>${time.split('/')[1]}</beat-type></time></attributes>'
        '$notes</measure></part>';
    String n(String step, int dur, String type) =>
        '<note><pitch><step>$step</step><octave>4</octave></pitch>'
        '<duration>$dur</duration><voice>1</voice><type>$type</type></note>';
    final xml = '<score-partwise><part-list>'
        '<score-part id="P1"><part-name>V</part-name></score-part>'
        '<score-part id="P2"><part-name>P</part-name></score-part>'
        '</part-list>'
        '${part('P1', '3/2', n('C', 2, 'half') + n('D', 2, 'half') + n('E', 2, 'half'))}'
        '${part('P2', '9/4', List.filled(3, n('G', 3, 'half') /* dotted */).join())}'
        '</score-partwise>';
    final system = staffSystemFromMusicXml(xml.replaceAll(
        '<type>half</type></note><note><pitch><step>G',
        '<type>half</type><dot/></note><note><pitch><step>G'));
    final voice = playbackTimeline(system.staves.first, expandRepeats: false);
    expect(voice.map((e) => e.start),
        [Fraction.zero, Fraction(3, 4), Fraction(3, 2)]);
    expect(system.staves.first.measures.single.totalDuration, Fraction(9, 4));
  });
}

String _time(String time) {
  if (time == 'senza') return '<time><senza-misura/></time>';
  final [beats, type] = time.split('/');
  return '<time><beats>$beats</beats><beat-type>$type</beat-type></time>';
}
