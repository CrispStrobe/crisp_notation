import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

/// End-to-end: a MusicXML document imports and renders — the full
/// pipeline from markup to pixels.
const fixture = '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list>
    <score-part id="P1"><part-name>Song</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>2</divisions>
        <key><fifths>1</fifths></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      <harmony><root><root-step>G</root-step></root><kind>major</kind></harmony>
      <note><pitch><step>G</step><octave>4</octave></pitch>
        <duration>2</duration><type>quarter</type>
        <lyric><syllabic>begin</syllabic><text>Al</text></lyric></note>
      <note><pitch><step>A</step><octave>4</octave></pitch>
        <duration>1</duration><type>eighth</type>
        <lyric><syllabic>end</syllabic><text>le</text></lyric></note>
      <note><pitch><step>B</step><octave>4</octave></pitch>
        <duration>1</duration><type>eighth</type>
        <lyric><text>mei</text></lyric></note>
      <note><pitch><step>C</step><octave>5</octave></pitch>
        <duration>2</duration><type>quarter</type>
        <tie type="start"/></note>
      <note><pitch><step>C</step><octave>5</octave></pitch>
        <duration>2</duration><type>quarter</type></note>
    </measure>
    <measure number="2">
      <harmony><root><root-step>D</root-step></root>
        <kind>dominant</kind></harmony>
      <note><pitch><step>D</step><octave>5</octave></pitch>
        <duration>4</duration><type>half</type></note>
      <note><rest/><duration>4</duration><type>half</type></note>
    </measure>
  </part>
</score-partwise>
''';

void main() {
  setUpAll(setUpPartituraForTests);

  Widget scene(Widget staff) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: staff,
              ),
            ),
          ),
        ),
      );

  testWidgets('imported MusicXML renders without errors', (tester) async {
    final score = scoreFromMusicXml(fixture);
    await tester.pumpWidget(scene(StaffView(score: score, staffSpace: 10)));
    expect(tester.takeException(), isNull);
    final staff =
        tester.renderObject<RenderStaffView>(find.bySubtype<StaffView>());
    final layout = staff.scoreLayout!;
    // Everything arrived: 7 elements, a tie curve, lyrics and chords.
    expect(layout.regions, hasLength(7));
    expect(layout.primitives.whereType<CurvePrimitive>(), hasLength(1));
    expect(layout.primitives.whereType<TextPrimitive>(), hasLength(5));
    expect(layout.measureRegions, hasLength(2));
  });

  testWidgets('39 golden: imported MusicXML end to end', (tester) async {
    final score = scoreFromMusicXml(fixture);
    await tester.pumpWidget(scene(StaffView(
      score: score,
      staffSpace: 10,
      theme: const PartituraTheme(textFontFamily: 'Roboto'),
    )));
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/39_musicxml_import.png'),
    );
  });

  testWidgets('imported grand staff renders on both staves', (tester) async {
    const grandFixture = '''
<score-partwise version="4.0">
  <part-list><score-part id="P1"/></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
        <time><beats>4</beats><beat-type>4</beat-type></time>
        <staves>2</staves>
        <clef number="1"><sign>G</sign><line>2</line></clef>
        <clef number="2"><sign>F</sign><line>4</line></clef>
      </attributes>
      <note><pitch><step>C</step><octave>5</octave></pitch>
        <duration>4</duration><type>whole</type><staff>1</staff></note>
      <backup><duration>4</duration></backup>
      <note><pitch><step>C</step><octave>3</octave></pitch>
        <duration>4</duration><type>whole</type><staff>2</staff></note>
    </measure>
  </part>
</score-partwise>
''';
    final grand = grandStaffFromMusicXml(grandFixture);
    await tester
        .pumpWidget(scene(GrandStaffView(grandStaff: grand, staffSpace: 8)));
    expect(tester.takeException(), isNull);
    final render =
        tester.renderObject<RenderGrandStaffView>(find.byType(GrandStaffView));
    expect(render.grandLayout, isNotNull);
    expect(render.grandLayout!.upper.regions.single.elementId, 'e0');
    expect(render.grandLayout!.lower.regions.single.elementId, 'e1000');
  });

  testWidgets('export -> import -> render is pixel-stable', (tester) async {
    final original = Score.simple(
      keySignature: const KeySignature(1),
      timeSignature: TimeSignature.fourFour,
      notes: 'g4:q( a4) b4:e c5 d5:q~ | d5:q 3[e5:e d5 c5] b4:q',
      lyrics: 'la la mi- ne * so * * * fa',
      annotations: 'G * * * * D7 * * * *',
    );
    final reimported = scoreFromMusicXml(scoreToMusicXml(original));
    expect(reimported, original);
    await tester.pumpWidget(scene(StaffView(score: original, staffSpace: 10)));
    final layoutA = tester
        .renderObject<RenderStaffView>(find.bySubtype<StaffView>())
        .scoreLayout!
        .primitives
        .toString();
    await tester
        .pumpWidget(scene(StaffView(score: reimported, staffSpace: 10)));
    final layoutB = tester
        .renderObject<RenderStaffView>(find.bySubtype<StaffView>())
        .scoreLayout!
        .primitives
        .toString();
    expect(layoutB, layoutA);
  });
}
