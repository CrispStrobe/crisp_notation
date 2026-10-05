import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Marks that a MusicXML round trip used to lose — found by the live corpus
/// sweep's round-trip check across six formats (~300 files lost slurs).

/// Slurs as (start, end) element positions, independent of regenerated ids.
List<(int, int)> slurPositions(Score s) {
  final pos = <String, int>{};
  var k = 0;
  for (final m in s.measures) {
    for (final e in m.elements) {
      if (e.id != null) pos[e.id!] = k++;
    }
  }
  return [for (final sl in s.slurs) (pos[sl.startId]!, pos[sl.endId]!)]
    ..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
}

Score withSlurs(String notes, List<(int, int)> spans) {
  final score = Score.simple(notes: notes);
  return score.copyWith(slurs: [
    for (final (a, b) in spans) Slur('e$a', 'e$b'),
  ]);
}

Score roundTrip(Score s) => scoreFromMusicXml(scoreToMusicXml(s));

void main() {
  group('slur numbering', () {
    test('two slurs ending on the same note both survive', () {
      final score = withSlurs('c4:q d4 e4 f4 g4', [(0, 4), (2, 4)]);
      expect(slurPositions(roundTrip(score)), [(0, 4), (2, 4)]);
    });

    test('two slurs starting on the same note both survive', () {
      final score = withSlurs('c4:q d4 e4 f4 g4', [(0, 2), (0, 4)]);
      expect(slurPositions(roundTrip(score)), [(0, 2), (0, 4)]);
    });

    test('a chain (one slur ends where the next starts) pairs correctly', () {
      final score = withSlurs('c4:q d4 e4 f4 g4', [(0, 2), (2, 4)]);
      expect(slurPositions(roundTrip(score)), [(0, 2), (2, 4)]);
      // The note ending one slur and starting the next writes the stop
      // first, so the number can be reused.
      final xml = scoreToMusicXml(score);
      expect(
          xml.indexOf('<slur type="stop"'),
          lessThan(xml.indexOf(
              '<slur type="start"', xml.indexOf('<slur type="stop"') - 200)));
    });

    test('more than six overlapping slurs keep distinct numbers', () {
      // Numbered by list position (i % 6 + 1), the 1st and 7th collided.
      final spans = [for (var i = 0; i < 8; i++) (i, 15 - i)];
      final score =
          withSlurs('c4:s d4 e4 f4 g4 a4 b4 c5 d5 e5 f5 g5 a5 b5 c6 d6', spans);
      expect(slurPositions(roundTrip(score)), slurPositions(score));
    });
  });

  group('marks on rests', () {
    test('text over a rest stays on the rest', () {
      final score = Score.simple(notes: 'c4:q r:q d4:h')
          .copyWith(annotations: const [Annotation('e1', 'Solo')]);
      final back = roundTrip(score);
      final anchor = back.annotations.single.elementId;
      final rest = back.measures.single.elements[1];
      expect(rest, isA<RestElement>());
      expect(anchor, rest.id);
    });

    test('dynamics over rests stay on their rests (a LilyPond Dynamics line)',
        () {
      final score =
          Score.simple(notes: 'r:q r:q c4:h').copyWith(dynamics: const [
        DynamicMarking('e0', DynamicLevel.pp),
        DynamicMarking('e1', DynamicLevel.f),
      ]);
      final back = roundTrip(score);
      final els = back.measures.single.elements;
      expect(back.dynamics.map((d) => (d.elementId, d.level)), [
        (els[0].id, DynamicLevel.pp),
        (els[1].id, DynamicLevel.f),
      ]);
    });

    test('a dynamic after the last note of a bar carries to the next bar', () {
      const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Music</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>1</divisions><time><beats>1</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef></attributes>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type></note>
      <direction><direction-type><dynamics><p/></dynamics></direction-type></direction>
    </measure>
    <measure number="2">
      <note><pitch><step>D</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type></note>
    </measure>
  </part>
</score-partwise>''';
      final score = scoreFromMusicXml(xml);
      expect(score.dynamics.single.elementId,
          score.measures[1].elements.single.id);
      expect(score.dynamics.single.level, DynamicLevel.p);
    });

    test('a dynamic on a rest is drawn (it used to be skipped)', () {
      final metadata = SmuflMetadata.fromJson(jsonDecode(
          File('../crisp_notation/assets/smufl/bravura_metadata.json')
              .readAsStringSync()) as Map<String, Object?>);
      final score = Score.simple(notes: 'r:q c4:q')
          .copyWith(dynamics: const [DynamicMarking('e0', DynamicLevel.pp)]);
      final layout = const LayoutEngine()
          .layout(score, LayoutSettings(metadata: metadata));
      expect(
          layout.primitives.whereType<GlyphPrimitive>().where((g) =>
              g.elementId == 'e0' &&
              g.smuflName == SmuflGlyph.dynamicGlyph(DynamicLevel.pp)),
          hasLength(1));
    });
  });
}
