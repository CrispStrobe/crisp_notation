import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A piano part's voice 1 crossing to the bass staff for a beat meets that
/// staff's own voice 5 there. Voice 1 must keep slot 0 on that staff and
/// voice 5 take the next free one — they used to share slot 0, interleave,
/// and nest one triplet inside the other's span, so layout threw "Tuplet
/// spans overlap" (eight Lieder in the corpus, after Lang's "Namenlos").
void main() {
  // Bar 25 of Josephine Lang's "Namenlos" Op. 13/6, piano: voice 1 rests a
  // quarter on the treble staff, plays a triplet on the bass staff, then a
  // half on the treble; voice 5 plays its own triplet, a rest and a half.
  const xml = '''<?xml version="1.0"?>
<score-partwise version="3.1"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
<part id="P1"><measure number="1">
<attributes><divisions>12</divisions><time><beats>4</beats><beat-type>4</beat-type></time><staves>2</staves>
<clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>F</sign><line>4</line></clef></attributes>
<note><rest/><duration>12</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
<note><pitch><step>F</step><octave>3</octave></pitch><duration>4</duration><voice>1</voice><type>eighth</type><time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification><staff>2</staff><notations><tuplet type="start"/></notations></note>
<note><pitch><step>A</step><octave>3</octave></pitch><duration>4</duration><voice>1</voice><type>eighth</type><time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification><staff>2</staff></note>
<note><pitch><step>D</step><octave>4</octave></pitch><duration>4</duration><voice>1</voice><type>eighth</type><time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification><staff>2</staff><notations><tuplet type="stop"/></notations></note>
<note><pitch><step>D</step><octave>5</octave></pitch><duration>24</duration><voice>1</voice><type>half</type><staff>1</staff></note>
<backup><duration>48</duration></backup>
<note><pitch><step>D</step><octave>2</octave></pitch><duration>4</duration><voice>5</voice><type>eighth</type><time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification><staff>2</staff><notations><tuplet type="start"/></notations></note>
<note><pitch><step>A</step><octave>2</octave></pitch><duration>4</duration><voice>5</voice><type>eighth</type><time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification><staff>2</staff></note>
<note><pitch><step>D</step><octave>3</octave></pitch><duration>4</duration><voice>5</voice><type>eighth</type><time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification><staff>2</staff><notations><tuplet type="stop"/></notations></note>
<note><rest/><duration>12</duration><voice>5</voice><type>quarter</type><staff>2</staff></note>
<note><pitch><step>F</step><octave>3</octave></pitch><duration>24</duration><voice>5</voice><type>half</type><staff>2</staff></note>
</measure></part></score-partwise>''';

  Fraction length(List<MusicElement> voice, List<TupletSpan> spans) {
    var t = Fraction.zero;
    for (final (i, e) in voice.indexed) {
      var d = e.duration.toFraction();
      for (final s in spans) {
        if (s.contains(i)) d = d * Fraction(s.normal, s.actual);
      }
      t = t + d;
    }
    return t;
  }

  test('voice 1 visiting the bass staff keeps slot 0; voice 5 moves over', () {
    final bass = staffSystemFromMusicXml(xml).staves[1];
    final m = bass.measures.single;
    final v1 = m.voiceAt(0), v5 = m.voiceAt(1);
    expect(v1.whereType<NoteElement>().map((n) => n.pitches.single.toString()),
        ['F3', 'A3', 'D4'],
        reason: "voice 1's visit only");
    expect(
        v5
            .whereType<NoteElement>()
            .map((n) => n.pitches.map((p) => '$p').join('+')),
        ['D2', 'A2', 'D3', 'F3'],
        reason: "voice 5's own music, in its own slot");
    // Each triplet brackets its own voice's three notes.
    expect(
        m.tupletsForVoice(0).single.endIndex -
            m.tupletsForVoice(0).single.startIndex,
        2);
    expect(m.tupletsForVoice(1).single,
        const TupletSpan(0, 2, actual: 3, normal: 2, voice: 1));
    // Voice 5 fills the bar exactly: a triplet quarter, a quarter, a half.
    expect(length(v5, m.tupletsForVoice(1)), Fraction(1, 1));
  });

  test('the bass staff lays out', () {
    final settings = LayoutSettings(
        metadata: SmuflMetadata.fromJson(jsonDecode(
            File('../crisp_notation/assets/smufl/bravura_metadata.json')
                .readAsStringSync()) as Map<String, Object?>));
    for (final staff in staffSystemFromMusicXml(xml).staves) {
      expect(
          () => const LayoutEngine().layout(staff, settings), returnsNormally);
    }
  });
}
