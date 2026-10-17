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
}
