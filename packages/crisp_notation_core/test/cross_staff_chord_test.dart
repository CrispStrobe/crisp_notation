import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A chord across both staves of a grand staff, on one stem.
void main() {
  late LayoutSettings settings;
  setUpAll(() {
    settings = LayoutSettings(
        metadata: SmuflMetadata.fromJson(jsonDecode(
            File('../crisp_notation/assets/smufl/bravura_metadata.json')
                .readAsStringSync()) as Map<String, Object?>));
  });

  GrandStaff piano({required bool down}) => GrandStaff(
        upper: Score.simple(notes: 'e4+g4:q r:q r:h'),
        lower: Score.simple(clef: Clef.bass, notes: 'c3+g3:q r:q r:h')
            .copyWith(measures: [
          // Ids distinct from the upper staff's.
          Measure([
            NoteElement(pitches: const [
              Pitch(Step.c, octave: 3),
              Pitch(Step.g, octave: 3),
            ], duration: NoteDuration.quarter, id: 'L0'),
            RestElement(NoteDuration.quarter, id: 'L1'),
            RestElement(NoteDuration.half, id: 'L2'),
          ]),
        ]),
        crossStaffChords: [CrossStaffChord('e0', 'L0', stemsDown: down)],
      );

  List<LinePrimitive> stems(ScoreLayout l, String id) => [
        for (final p in l.primitives.whereType<LinePrimitive>())
          if (p.elementId == id && p.from.x == p.to.x) p,
      ];

  test('stem down: one stem from the upper notes through the lower ones', () {
    final l = layoutGrandStaff(piano(down: true), settings);
    final lowerStem = stems(l.lower, 'L0').single;
    final join = stems(l.upper, 'e0').single; // the upper half's own is gone
    expect(join.from.x, lowerStem.from.x, reason: 'one vertical line');
    final shift = 4 + l.staffGap;
    expect(max(join.from.y, join.to.y),
        closeTo(min(lowerStem.from.y, lowerStem.to.y) + shift, 1e-9));
    expect(min(join.from.y, join.to.y), lessThan(4),
        reason: 'starts at the upper notes');
    expect(max(lowerStem.from.y, lowerStem.to.y),
        greaterThan(min(lowerStem.from.y, lowerStem.to.y) + 3),
        reason: 'the tip runs on below the lower notes');
  });

  test('stem up: one stem from the lower notes up through the upper ones', () {
    final l = layoutGrandStaff(piano(down: false), settings);
    expect(stems(l.lower, 'L0'), isEmpty, reason: 'deferred');
    final upperStem = stems(l.upper, 'e0').single;
    final join = stems(l.upper, 'L0').single;
    expect(join.from.x, upperStem.from.x);
    expect(max(join.from.y, join.to.y), greaterThan(4 + l.staffGap));
  });

  test('MusicXML: a chord written on both staves reads as one', () {
    const xml = '''<?xml version="1.0"?>
<score-partwise version="3.1"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
<part id="P1"><measure number="1">
<attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time><staves>2</staves>
<clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>F</sign><line>4</line></clef></attributes>
<note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type><stem>down</stem><staff>1</staff></note>
<note><chord/><pitch><step>C</step><octave>3</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type><stem>down</stem><staff>2</staff></note>
<note><rest/><duration>3</duration><voice>1</voice><staff>1</staff></note>
<backup><duration>4</duration></backup>
<note><rest/><duration>1</duration><voice>5</voice><staff>2</staff></note>
<note><rest/><duration>3</duration><voice>5</voice><staff>2</staff></note>
</measure></part></score-partwise>''';
    final g = grandStaffFromMusicXml(xml);
    expect(g.crossStaffChords, hasLength(1));
    final chord = g.crossStaffChords.single;
    expect(chord.stemsDown, isTrue);
    final upper = g.upper.measures.first.elements.first as NoteElement;
    expect(chord.upperId, upper.id);
    final lowerChordHalf = g.lower.measures.first.voices
        .expand((v) => v)
        .whereType<NoteElement>()
        .single;
    expect(chord.lowerId, lowerChordHalf.id);
    // And it lays out with one stem.
    final l = layoutGrandStaff(g, settings);
    expect(stems(l.upper, chord.upperId), hasLength(1));
  });

  test('multi-part: a piano chord across its staves takes one stem', () {
    const xml = '''<?xml version="1.0"?>
<score-partwise version="3.1"><part-list>
<score-part id="P0"><part-name>Violin</part-name></score-part>
<score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
<part id="P0"><measure number="1"><attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>
<note><pitch><step>A</step><octave>4</octave></pitch><duration>4</duration><voice>1</voice><type>whole</type></note></measure></part>
<part id="P1"><measure number="1">
<attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time><staves>2</staves>
<clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>F</sign><line>4</line></clef></attributes>
<note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type><stem>down</stem><staff>1</staff></note>
<note><chord/><pitch><step>C</step><octave>3</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type><stem>down</stem><staff>2</staff></note>
<note><rest/><duration>3</duration><voice>1</voice><staff>1</staff></note>
<backup><duration>4</duration></backup>
<note><rest/><duration>1</duration><voice>5</voice><staff>2</staff></note>
<note><rest/><duration>3</duration><voice>5</voice><staff>2</staff></note>
</measure></part></score-partwise>''';
    final system = staffSystemFromMusicXml(xml);
    expect(system.staves, hasLength(3));
    final chord = system.crossStaffChords.single;
    final l = layoutStaffSystem(system, settings);
    // The join is drawn on the piano's upper staff (staff 1), one line.
    expect(stems(l.staves[1], chord.upperId), hasLength(1));
    expect(stems(l.staves[2], chord.lowerId), hasLength(1));
    // And it survives into the paginating document model.
    final doc = MultiPartScore.fromStaffSystem(system);
    expect(doc.crossStaffChords, [chord]);
    final pages = layoutMultiPartPages(doc, settings,
        metrics: const PageMetrics(width: 100, height: 140));
    final placed = pages.pages.first.systems.first.system.layout;
    expect(stems(placed.staves[1], chord.upperId), hasLength(1));
  });

  test('MusicXML round trip: one piano part of two staves, chord kept', () {
    const source = '''<?xml version="1.0"?>
<score-partwise version="3.1"><part-list>
<score-part id="P0"><part-name>Violin</part-name></score-part>
<score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
<part id="P0"><measure number="1"><attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>
<note><pitch><step>A</step><octave>4</octave></pitch><duration>4</duration><voice>1</voice><type>whole</type></note></measure></part>
<part id="P1"><measure number="1">
<attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time><staves>2</staves>
<clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>F</sign><line>4</line></clef></attributes>
<note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type><stem>down</stem><staff>1</staff></note>
<note><chord/><pitch><step>C</step><octave>3</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type><stem>down</stem><staff>2</staff></note>
<note><rest/><duration>3</duration><voice>1</voice><staff>1</staff></note>
<backup><duration>4</duration></backup>
<note><rest/><duration>1</duration><voice>5</voice><staff>2</staff></note>
<note><rest/><duration>3</duration><voice>5</voice><staff>2</staff></note>
</measure></part></score-partwise>''';
    final doc = multiPartScoreFromMusicXml(source);
    final written = multiPartToMusicXml(doc);
    expect('<part id='.allMatches(written), hasLength(2),
        reason: 'violin + one two-staff piano part');
    expect(written, contains('<staves>2</staves>'));
    final back = multiPartScoreFromMusicXml(written);
    expect(back.parts, hasLength(3));
    expect(back.crossStaffChords, hasLength(1));
    List<int> pitches(Score s) => [
          for (final m in s.measures)
            for (final e in m.voices.expand((v) => v))
              if (e is NoteElement) ...e.pitches.map((p) => p.midiNumber),
        ];
    for (var i = 0; i < 3; i++) {
      expect(pitches(back.parts[i]), pitches(doc.parts[i]), reason: 'staff $i');
    }
    // Written again, it is stable.
    expect(multiPartToMusicXml(back), written);
  });

  test('MusicXML: three braced staves of one instrument are one part', () {
    Score staff(String notes, Clef clef, String prefix) {
      final s = Score.simple(clef: clef, notes: notes);
      var n = 0;
      return s.copyWith(
          metadata: const ScoreMetadata(instrument: 'Organ'),
          measures: [
            for (final m in s.measures)
              m.copyWith(elements: [
                for (final e in m.elements)
                  e is NoteElement
                      ? e.copyWith(id: '$prefix${n++}')
                      : RestElement(e.duration, id: '$prefix${n++}'),
              ]),
          ]);
    }

    final organ = MultiPartScore([
      staff('c5:q d5 e5 f5', Clef.treble, 'a'),
      staff('e4:h g4', Clef.treble, 'b'),
      staff('c3:w', Clef.bass, 'c'),
    ], brackets: const [
      StaffBracket(0, 2, kind: StaffBracketKind.brace)
    ]);
    final written = multiPartToMusicXml(organ);
    expect('<part id='.allMatches(written), hasLength(1));
    expect(written, contains('<staves>3</staves>'));
    final back = multiPartScoreFromMusicXml(written);
    expect(back.parts, hasLength(3));
    List<int> pitches(Score s) => [
          for (final m in s.measures)
            for (final e in m.elements)
              if (e is NoteElement) ...e.pitches.map((p) => p.midiNumber),
        ];
    for (var i = 0; i < 3; i++) {
      expect(pitches(back.parts[i]), pitches(organ.parts[i]));
    }
  });

  /// Each note of [s] as `midi@onset`, in time order, chord tones included.
  List<String> timed(Score s) {
    final pitches = <String, List<int>>{
      for (final m in s.measures)
        for (final e in m.voices.expand((v) => v))
          if (e is NoteElement && e.id != null)
            e.id!: [for (final p in e.pitches) p.midiNumber],
    };
    return [
      for (final n in playbackTimeline(s, expandRepeats: false))
        if (!n.isRest)
          for (final midi in pitches[n.elementId] ?? const <int>[])
            '$midi@${n.start}',
    ];
  }

  test('MusicXML: a voice read out of time order takes its onsets', () {
    // Staff 2's G2 on beat 4 is written with staff 1's music, ahead of the
    // staff's own beats 1-3: it must still come last in its voice.
    const xml = '''<?xml version="1.0"?>
<score-partwise version="3.1"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
<part id="P1"><measure number="1">
<attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time><staves>2</staves>
<clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>F</sign><line>4</line></clef></attributes>
<note><rest/><duration>3</duration><voice>1</voice><staff>1</staff></note>
<note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
<backup><duration>1</duration></backup>
<note><pitch><step>G</step><octave>2</octave></pitch><duration>1</duration><voice>5</voice><type>quarter</type><staff>2</staff></note>
<backup><duration>4</duration></backup>
<note><pitch><step>C</step><octave>3</octave></pitch><duration>1</duration><voice>5</voice><type>quarter</type><staff>2</staff></note>
<note><pitch><step>D</step><octave>3</octave></pitch><duration>1</duration><voice>5</voice><type>quarter</type><staff>2</staff></note>
<note><pitch><step>E</step><octave>3</octave></pitch><duration>1</duration><voice>5</voice><type>quarter</type><staff>2</staff></note>
</measure></part></score-partwise>''';
    final g = grandStaffFromMusicXml(xml);
    final voice = g.lower.measures.single.elements;
    expect(voice.map((e) => e is NoteElement ? e.pitches.single.midiNumber : 0),
        [48, 50, 52, 43],
        reason: 'the gap rests before the G2 gave way to the earlier notes');
    expect(timed(g.lower), ['48@0/1', '50@1/4', '52@1/2', '43@3/4']);
  });

  test('MusicXML round trip: a chord across the staves after earlier notes',
      () {
    Score staff(String notes, Clef clef, String prefix) {
      final s = Score.simple(clef: clef, notes: notes);
      var n = 0;
      return s.copyWith(
          metadata: const ScoreMetadata(instrument: 'Piano'),
          measures: [
            for (final m in s.measures)
              m.copyWith(elements: [
                for (final e in m.elements)
                  e is NoteElement
                      ? e.copyWith(id: '$prefix${n++}')
                      : RestElement(e.duration, id: '$prefix${n++}'),
              ]),
          ]);
    }

    // The lower staff's chord half (L2, beat 3) follows two notes of its
    // own voice, so its tones are written ahead of them.
    final piano = MultiPartScore([
      staff('c5:q d5 e5+g5 f5', Clef.treble, 'U'),
      staff('c3:q d3 g2 r:q', Clef.bass, 'L'),
    ], brackets: const [
      StaffBracket(0, 1, kind: StaffBracketKind.brace)
    ], crossStaffChords: const [
      CrossStaffChord('U2', 'L2', stemsDown: true)
    ]);
    final written = multiPartToMusicXml(piano);
    expect(written, contains('<forward>'), reason: 'the lower half moved');
    final back = multiPartScoreFromMusicXml(written);
    expect(back.crossStaffChords, hasLength(1));
    final chord = back.crossStaffChords.single;
    for (var i = 0; i < 2; i++) {
      expect(timed(back.parts[i]), timed(piano.parts[i]), reason: 'staff $i');
    }
    final lowerIds = {
      for (final e in back.parts[1].measures.single.voices.expand((v) => v))
        if (e is NoteElement) e.id: e.pitches.single.midiNumber,
    };
    expect(lowerIds[chord.lowerId], 43, reason: 'linked to the G2');
    // Written again, it is stable.
    expect(multiPartToMusicXml(back), written);
  });

  Score instrumentStaff(String notes, Clef clef, String prefix,
      {String instrument = 'Piano'}) {
    final s = Score.simple(clef: clef, notes: notes);
    var n = 0;
    return s
        .copyWith(metadata: ScoreMetadata(instrument: instrument), measures: [
      for (final m in s.measures)
        m.copyWith(elements: [
          for (final e in m.elements)
            e is NoteElement
                ? e.copyWith(id: '$prefix${n++}')
                : RestElement(e.duration, id: '$prefix${n++}'),
        ]),
    ]);
  }

  test('MEI round trip: one piano part of two staves, chord kept', () {
    final piano = MultiPartScore([
      instrumentStaff('c5:q d5 e5 f5', Clef.treble, 'U'),
      instrumentStaff('c3+g3:q d3 e3 r:q', Clef.bass, 'L'),
    ], brackets: const [
      StaffBracket(0, 1, kind: StaffBracketKind.brace)
    ], crossStaffChords: const [
      CrossStaffChord('U0', 'L0', stemsDown: true)
    ]);
    final written = multiPartToMei(piano);
    final back = multiPartScoreFromMei(written);
    expect(back.parts, hasLength(2));
    expect(back.crossStaffChords, hasLength(1));
    for (var i = 0; i < 2; i++) {
      expect(timed(back.parts[i]), timed(piano.parts[i]), reason: 'staff $i');
    }
    // MEI regenerates element ids on every read (unlike MusicXML, which
    // writes none at all), so the written XML itself is not byte-stable —
    // but a SECOND round trip through it keeps the same music and link.
    final again = multiPartScoreFromMei(multiPartToMei(back));
    expect(again.crossStaffChords, hasLength(1));
    for (var i = 0; i < 2; i++) {
      expect(timed(again.parts[i]), timed(piano.parts[i]), reason: 'staff $i');
    }
  });

  test('MEI: a chord split by @staff on some of its notes reads as one', () {
    // The real shape MEI's own sample corpus uses (e.g.
    // `attribute_copyof.mei`): a <chord> sits in the UPPER staff's layer with
    // one local note and the rest pointing at the lower staff via @staff.
    const mei = '''<?xml version="1.0" encoding="UTF-8"?>
<mei xmlns="http://www.music-encoding.org/ns/mei" meiversion="5.1">
  <music><body><mdiv><score>
    <scoreDef meter.count="4" meter.unit="4" keysig="0">
      <staffGrp symbol="brace">
        <staffDef n="1" lines="5" clef.shape="G" clef.line="2"/>
        <staffDef n="2" lines="5" clef.shape="F" clef.line="4"/>
      </staffGrp>
    </scoreDef>
    <section><measure n="1">
      <staff n="1"><layer n="1">
        <chord xml:id="c1" dur="4" stem.dir="up">
          <note pname="c" oct="5" staff="1"/>
          <note pname="g" oct="3" staff="2"/>
          <note pname="e" oct="3" staff="2"/>
        </chord>
        <note pname="d" oct="5" dur="4"/>
        <note pname="e" oct="5" dur="2"/>
      </layer></staff>
      <staff n="2"><layer n="1">
        <note pname="c" oct="3" dur="2"/>
        <rest dur="4"/>
      </layer></staff>
    </measure></section>
  </score></mdiv></body></music>
</mei>''';
    final system = staffSystemFromMei(mei);
    expect(system.staves, hasLength(2));
    final chord = system.crossStaffChords.single;
    expect(chord.stemsDown, isFalse, reason: 'stem.dir="up"');
    final upper = system.staves[0].measures.first.elements.first as NoteElement;
    expect(chord.upperId, upper.id);
    expect(upper.pitches.single.midiNumber, 72); // c5, the local note
    final lowerHalf =
        system.staves[1].measures.first.voice2.single as NoteElement;
    expect(chord.lowerId, lowerHalf.id);
    expect(lowerHalf.pitches.map((p) => p.midiNumber), [55, 52]); // g3, e3
  });

  test('MSCX round trip: one piano part of two staves, chord kept', () {
    final piano = MultiPartScore([
      instrumentStaff('c5:q d5 e5 f5', Clef.treble, 'U'),
      instrumentStaff('c3+g3:q d3 e3 r:q', Clef.bass, 'L'),
    ], brackets: const [
      StaffBracket(0, 1, kind: StaffBracketKind.brace)
    ], crossStaffChords: const [
      CrossStaffChord('U0', 'L0', stemsDown: true)
    ]);
    final written = multiPartToMscx(piano);
    expect('<Part>'.allMatches(written), hasLength(1),
        reason: 'one braced piano part, not two');
    final back = multiPartScoreFromMscx(written);
    expect(back.parts, hasLength(2));
    expect(back.crossStaffChords, hasLength(1));
    for (var i = 0; i < 2; i++) {
      expect(timed(back.parts[i]), timed(piano.parts[i]), reason: 'staff $i');
    }
  });

  test('MSCX: a staffMove co-located with another voice reads as one chord',
      () {
    // MuseScore's own idiom (no per-note @staff like MEI): the crossing
    // chord is its OWN <Chord> in a different voice of the SAME (home)
    // staff, carrying <staffMove>, at the SAME onset as the staying chord.
    const mscx = '''<museScore version="4.20">
  <Score>
    <Staff id="1">
      <Measure>
        <voice>
          <TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>
          <Chord><durationType>quarter</durationType>
            <Note><pitch>72</pitch><tpc>14</tpc></Note></Chord>
          <Chord><durationType>quarter</durationType>
            <Note><pitch>74</pitch><tpc>16</tpc></Note></Chord>
          <Rest><durationType>half</durationType></Rest>
        </voice>
      </Measure>
    </Staff>
    <Staff id="2">
      <Measure>
        <voice>
          <Clef><concertClefType>F</concertClefType></Clef>
          <Chord><durationType>quarter</durationType>
            <Note><pitch>48</pitch><tpc>14</tpc></Note></Chord>
          <Chord><durationType>half</durationType>
            <Note><pitch>43</pitch><tpc>15</tpc></Note></Chord>
          <Rest><durationType>quarter</durationType></Rest>
        </voice>
        <voice>
          <Chord><staffMove>-1</staffMove><StemDirection>up</StemDirection>
            <durationType>quarter</durationType>
            <Note><pitch>55</pitch><tpc>15</tpc></Note>
            <Note><pitch>59</pitch><tpc>19</tpc></Note></Chord>
        </voice>
      </Measure>
    </Staff>
  </Score>
</museScore>''';
    final system = staffSystemFromMscx(mscx);
    expect(system.staves, hasLength(2));
    final chord = system.crossStaffChords.single;
    expect(chord.stemsDown, isFalse, reason: 'StemDirection up');
    final upper = system.staves[0].measures.first.voice2.single as NoteElement;
    expect(chord.upperId, upper.id);
    expect(upper.pitches.map((p) => p.midiNumber), [55, 59]);
    final lower = system.staves[1].measures.first.elements.first as NoteElement;
    expect(chord.lowerId, lower.id);
    expect(lower.pitches.single.midiNumber, 48);
  });
}
