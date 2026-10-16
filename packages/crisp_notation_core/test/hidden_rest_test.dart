import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

import 'support/layout_lint.dart';

/// Hidden rests (spacers): a voice's time where nothing is printed. MusicXML
/// `<forward>` was ignored and `print-object="no"` rests dropped, so in 60%
/// of the real MusicXML corpus a voice's notes after a gap were read too
/// early — wrong on the page and in playback.
void main() {
  final settings = LayoutSettings(
      metadata: SmuflMetadata.fromJson(jsonDecode(
          File('../crisp_notation/assets/smufl/bravura_metadata.json')
              .readAsStringSync()) as Map<String, Object?>));

  String xml(String body) => '''
<score-partwise version="3.1"><part-list><score-part id="P1">
<part-name>P</part-name></score-part></part-list><part id="P1">
<measure number="1"><attributes><divisions>2</divisions>
<time><beats>3</beats><beat-type>4</beat-type></time>
<clef><sign>F</sign><line>4</line></clef></attributes>$body</measure>
</part></score-partwise>''';

  // The Debussy bass of bar 1: a dotted-half chord in voice 1, and voice 2
  // waiting two beats (`<forward>`) before its quarter on beat 3.
  const debussyBass = '''
<note><pitch><step>C</step><octave>2</octave></pitch><duration>6</duration>
<voice>1</voice><type>half</type><dot/></note>
<backup><duration>6</duration></backup>
<forward><duration>2</duration><voice>2</voice></forward>
<forward><duration>2</duration><voice>2</voice></forward>
<note><pitch><step>E</step><octave>3</octave></pitch><duration>2</duration>
<voice>2</voice><type>quarter</type></note>''';

  Fraction startOf(Score s, Pitch p) => playbackTimeline(s).firstWhere((n) {
        final e = s.measures
            .expand((m) => m.voices.expand((v) => v))
            .firstWhere((e) => e.id == n.elementId);
        return e is NoteElement && e.pitches.contains(p);
      }).start;

  group('MusicXML', () {
    test('<forward> holds a voice in time', () {
      final score = scoreFromMusicXml(xml(debussyBass));
      final voice2 = score.measures.single.voice2;
      expect(voice2.first, isA<RestElement>());
      expect((voice2.first as RestElement).hidden, isTrue);
      expect(voice2.first.duration, const NoteDuration(DurationBase.half));
      // E3 sounds on beat 3 (half a whole note in), not on beat 1.
      expect(startOf(score, const Pitch(Step.e, octave: 3)), Fraction(1, 2));
    });

    test('a print-object="no" rest is kept, hidden', () {
      final score = scoreFromMusicXml(xml('''
<note print-object="no"><rest/><duration>2</duration><voice>1</voice>
<type>quarter</type></note>
<note><pitch><step>D</step><octave>3</octave></pitch><duration>4</duration>
<voice>1</voice><type>half</type></note>'''));
      final elements = score.measures.single.elements;
      expect(elements, hasLength(2));
      expect((elements.first as RestElement).hidden, isTrue);
      expect(startOf(score, const Pitch(Step.d, octave: 3)), Fraction(1, 4));
    });

    test('a hidden note gives its time to the next one', () {
      final score = scoreFromMusicXml(xml('''
<note print-object="no"><pitch><step>C</step><octave>3</octave></pitch>
<duration>2</duration><voice>1</voice><type>quarter</type></note>
<note><pitch><step>D</step><octave>3</octave></pitch><duration>4</duration>
<voice>1</voice><type>half</type></note>'''));
      expect(startOf(score, const Pitch(Step.d, octave: 3)), Fraction(1, 4));
    });

    test('a bar of only hidden rest keeps its length', () {
      final score = scoreFromMusicXml(xml('''
<note print-object="no"><rest measure="yes"/><duration>6</duration>
<voice>1</voice></note>'''));
      final rests = score.measures.single.elements.cast<RestElement>();
      expect(rests.every((r) => r.hidden), isTrue);
      expect(
          rests.fold<Fraction>(
              Fraction.zero, (sum, r) => sum + r.duration.toFraction()),
          Fraction(3, 4));
    });

    test('spacers take no id: later notes keep theirs', () {
      final plain = scoreFromMusicXml(xml('''
<note><pitch><step>D</step><octave>3</octave></pitch><duration>6</duration>
<voice>1</voice><type>half</type><dot/></note>'''));
      final spaced = scoreFromMusicXml(xml('''
<forward><duration>0</duration></forward>
<note><pitch><step>D</step><octave>3</octave></pitch><duration>6</duration>
<voice>1</voice><type>half</type><dot/></note>'''));
      expect(spaced.measures.single.elements.last.id,
          plain.measures.single.elements.last.id);
    });

    test('a spacer round-trips as a print-object="no" rest', () {
      final score = scoreFromMusicXml(xml(debussyBass));
      final back = scoreFromMusicXml(scoreToMusicXml(score));
      expect(back.measures.single.voice2, score.measures.single.voice2);
      expect(startOf(back, const Pitch(Step.e, octave: 3)), Fraction(1, 2));
    });
  });

  test('every format with a spacer writes and reads it back', () {
    final score = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        Measure([
          const RestElement(NoteDuration.half, id: 's1', hidden: true),
          const NoteElement(
              pitches: [Pitch(Step.c, octave: 5)],
              duration: NoteDuration.half,
              id: 'n1'),
        ]),
      ],
    );
    bool hiddenThenNote(Score s) {
      final e = s.measures.first.elements;
      return e.length == 2 &&
          e[0] is RestElement &&
          (e[0] as RestElement).hidden &&
          e[1] is NoteElement;
    }

    expect(hiddenThenNote(scoreFromMusicXml(scoreToMusicXml(score))), isTrue,
        reason: 'MusicXML');
    expect(hiddenThenNote(scoreFromLilyPond(scoreToLilyPond(score))), isTrue,
        reason: 'LilyPond');
    expect(hiddenThenNote(scoreFromAbc(scoreToAbc(score))), isTrue,
        reason: 'ABC');
    expect(hiddenThenNote(scoreFromMei(scoreToMei(score))), isTrue,
        reason: 'MEI');
    expect(hiddenThenNote(scoreFromKern(scoreToKern(score))), isTrue,
        reason: 'kern');
    expect(hiddenThenNote(scoreFromMscx(scoreToMscx(score))), isTrue,
        reason: 'MuseScore');
  });

  group('layout', () {
    test('a spacer takes space but draws nothing', () {
      final hidden = const LayoutEngine().layout(
          Score(clef: Clef.treble, measures: [
            Measure([
              const RestElement(NoteDuration.half, id: 's', hidden: true),
              const NoteElement(
                  pitches: [Pitch(Step.c, octave: 5)],
                  duration: NoteDuration.half,
                  id: 'n'),
            ]),
          ]),
          settings);
      final glyphs = hidden.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.elementId == 's');
      expect(glyphs, isEmpty);
      expect(hidden.regions.where((r) => r.elementId == 's'), isEmpty);
      // The note stands after the spacer's time, not at the bar start.
      final note = hidden.regions.singleWhere((r) => r.elementId == 'n');
      expect(
          note.bounds.left, greaterThan(hidden.measureRegions[0].startX + 2));
    });

    test('text on a spacer lays out (LilyPond s1^"Fine")', () {
      final score = scoreFromLilyPond(r'''{ c'1 s1^"Fine" }''');
      expect(
          () => const LayoutEngine().layout(score, settings), returnsNormally);
    });

    test('a LilyPond spacer is not printed as a rest', () {
      final score = scoreFromLilyPond(r"{ \time 4/4 s2 c''2 }");
      final rest = score.measures.first.elements.first as RestElement;
      expect(rest.hidden, isTrue);
    });
  });

  test('staves align when an inner voice holds a triplet', () {
    // The Debussy shape: one staff's voice 2 is a triplet run; the other
    // staves' bars must still close on the same barline.
    final melody =
        Score.simple(timeSignature: const TimeSignature(3, 4), notes: 'e5:h.');
    final triplets = scoreFromMusicXml('''
<score-partwise version="3.1"><part-list><score-part id="P1">
<part-name>P</part-name></score-part></part-list><part id="P1">
<measure number="1"><attributes><divisions>6</divisions>
<time><beats>3</beats><beat-type>4</beat-type></time>
<clef><sign>G</sign><line>2</line></clef></attributes>
<note><pitch><step>E</step><octave>5</octave></pitch><duration>18</duration>
<voice>1</voice><type>half</type><dot/></note>
<backup><duration>18</duration></backup>
${[
      for (final step in ['C', 'D', 'E'])
        '<note><pitch><step>$step</step><octave>4</octave></pitch>'
            '<duration>2</duration><voice>2</voice><type>eighth</type>'
            '<time-modification><actual-notes>3</actual-notes>'
            '<normal-notes>2</normal-notes></time-modification>'
            '${step == 'C' ? '<notations><tuplet type="start"/></notations>' : step == 'E' ? '<notations><tuplet type="stop"/></notations>' : ''}'
            '</note>',
    ].join()}
<note><pitch><step>F</step><octave>4</octave></pitch><duration>6</duration>
<voice>2</voice><type>quarter</type></note>
<note><pitch><step>G</step><octave>4</octave></pitch><duration>6</duration>
<voice>2</voice><type>quarter</type></note>
</measure></part></score-partwise>''');
    final bass = Score.simple(
        clef: Clef.bass,
        timeSignature: const TimeSignature(3, 4),
        notes: 'c3:h. ; e3:h.');
    final layout =
        layoutStaffSystem(StaffSystem([melody, triplets, bass]), settings);
    final ends = {
      for (final st in layout.staves) st.measureRegions.single.endX,
    };
    expect(ends, hasLength(1), reason: 'every staff closes the bar together');
    expect(systemMisalignments(layout), isEmpty);
  });

  test('a syllable on a rest is reported, not an index overrun', () {
    final score = Score(
      clef: Clef.treble,
      measures: [
        Measure([
          const RestElement(NoteDuration.quarter, id: 'r'),
          const NoteElement(
              pitches: [Pitch(Step.c, octave: 5)],
              duration: NoteDuration.quarter,
              id: 'n'),
        ]),
      ],
      lyrics: const [Lyric('r', 'oh'), Lyric('n', 'la')],
    );
    expect(
        () => const LayoutEngine().layout(score, settings),
        throwsA(isA<ArgumentError>()
            .having((e) => e, 'type', isNot(isA<RangeError>()))
            .having((e) => e.message, 'message', contains('names no note'))));
  });
}
