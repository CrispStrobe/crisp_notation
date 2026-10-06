// #10: painting a note with <staccatissimo/> threw "No codepoint for SMuFL
// glyph articStaccatissimoAbove" in every debug build, and so did any
// quarter-tone accidental. The codepoint table now covers all of SMuFL, and
// an unknown name is skipped instead of thrown.

import 'package:crisp_notation/crisp_notation.dart';
import 'package:crisp_notation/src/rendering/layout_painter.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';

import 'test_setup.dart';

void main() {
  setUpAll(setUpCrispNotationForTests);

  // The reporter's reproduction, verbatim.
  const xml = '''
<score-partwise version="3.1">
 <part-list><score-part id="P1"><part-name>M</part-name></score-part></part-list>
 <part id="P1"><measure number="1">
 <attributes><divisions>24</divisions><key><fifths>0</fifths></key>
 <time><beats>4</beats><beat-type>4</beat-type></time>
 <clef><sign>G</sign><line>2</line></clef></attributes>
 <note>
 <pitch><step>D</step><octave>5</octave></pitch>
 <duration>24</duration><voice>1</voice><type>quarter</type>
 <notations><articulations><staccatissimo/></articulations></notations>
 </note>
 <note><rest/><duration>72</duration><voice>1</voice><type>half</type><dot/></note>
 </measure></part>
 </score-partwise>''';

  Future<void> pump(WidgetTester tester, Score score) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: MultiSystemView(score: score, staffSpace: 8),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('staccatissimo above paints', (tester) async {
    await pump(tester, scoreFromMusicXml(xml));
    expect(tester.takeException(), isNull);
  });

  testWidgets('staccatissimo below paints', (tester) async {
    await pump(
        tester,
        scoreFromMusicXml(xml.replaceFirst('<step>D</step><octave>5</octave>',
            '<step>C</step><octave>4</octave>')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every articulation and every microtone paints', (tester) async {
    final score = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        for (final a in Articulation.values)
          Measure([
            NoteElement(
              id: 'a${a.name}',
              pitches: const [Pitch(Step.b, octave: 4)],
              duration: NoteDuration.whole,
              articulations: {a},
            ),
          ]),
        for (final m in MicrotonalAccidental.values)
          Measure([
            NoteElement(
              id: 'm${m.name}',
              pitches: [Pitch(Step.g, octave: 4, microtone: m)],
              duration: NoteDuration.whole,
            ),
          ]),
      ],
    );
    await pump(tester, score);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown glyph name is skipped, not thrown', (tester) async {
    final painter = LayoutPainter(theme: CrispNotationTheme.standard, scale: 8);
    expect(() => painter.glyphPainter('noSuchGlyph', Colors.black, 1.0),
        returnsNormally);
  });
}
