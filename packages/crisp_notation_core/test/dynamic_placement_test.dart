import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// A dynamic the source places above the staff stands there: a vocal line's
/// dynamics leave the space under the staff to the words. Read below, an
/// "mf" sat between the voice and its lyrics and pushed them down.
void main() {
  late final LayoutSettings settings;

  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    settings = LayoutSettings(
        metadata:
            SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>));
  });

  String xml(String placement) => '''<?xml version="1.0"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>Voice</part-name></score-part></part-list>
  <part id="P1"><measure number="1">
    <attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>
    <direction$placement><direction-type><dynamics><mf/></dynamics></direction-type></direction>
    <note><pitch><step>E</step><octave>4</octave></pitch><duration>4</duration><type>whole</type>
      <lyric number="1"><syllable>single</syllable><text>Oh</text></lyric></note>
  </measure></part>
</score-partwise>''';

  double dynamicY(Score s) => const LayoutEngine()
      .layout(s, settings)
      .primitives
      .whereType<GlyphPrimitive>()
      .firstWhere((g) => g.smuflName.startsWith('dynamic'))
      .position
      .y;

  test('placement="above" is read, drawn over the staff and written back', () {
    final above = scoreFromMusicXml(xml(' placement="above"'));
    expect(above.dynamics.single.above, isTrue);
    expect(dynamicY(above), lessThan(0));
    final back = scoreFromMusicXml(scoreToMusicXml(above));
    expect(back.dynamics.single.above, isTrue);
  });

  test('without a placement the dynamic stays under the staff', () {
    final below = scoreFromMusicXml(xml(''));
    expect(below.dynamics.single.above, isFalse);
    expect(dynamicY(below), greaterThan(4));
    expect(scoreToMusicXml(below), isNot(contains('placement="above"')));
  });
}
