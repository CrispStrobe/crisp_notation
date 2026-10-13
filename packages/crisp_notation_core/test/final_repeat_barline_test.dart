import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// #19: a piece that ends on a repeat ends with the repeat barline alone.
/// The end-of-piece thin+thick barline was drawn behind it, doubling it.
void main() {
  final settings = LayoutSettings(
      metadata: SmuflMetadata.fromJson(jsonDecode(
          File('../crisp_notation/assets/smufl/bravura_metadata.json')
              .readAsStringSync()) as Map<String, Object?>));

  /// Vertical full-staff lines, as (x, thickness), left to right.
  List<(double, double)> barlines(ScoreLayout l) => [
        for (final p in l.primitives.whereType<LinePrimitive>())
          if (p.from.x == p.to.x &&
              p.elementId == null &&
              {p.from.y, p.to.y}.containsAll({0.0, 4.0}))
            (p.from.x, p.thickness),
      ]..sort((a, b) => a.$1.compareTo(b.$1));

  int thick(ScoreLayout l) =>
      barlines(l).where((b) => b.$2 == settings.thickBarlineThickness).length;

  // The reporter's last bar: <bar-style>light-heavy</bar-style> plus a
  // backward repeat, as MuseScore exports it.
  const xml = '''
<score-partwise version="3.1"><part-list><score-part id="P1">
<part-name>V</part-name></score-part></part-list><part id="P1">
<measure number="1"><attributes><divisions>1</divisions><key><fifths>0</fifths>
</key><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign>
<line>2</line></clef></attributes>
<note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration>
<voice>1</voice><type>whole</type></note></measure>
<measure number="2">
<note><pitch><step>D</step><octave>5</octave></pitch><duration>4</duration>
<voice>1</voice><type>whole</type></note>
<barline location="right"><bar-style>light-heavy</bar-style>
<repeat direction="backward"/></barline></measure>
</part></score-partwise>''';

  test('the reporter\'s file ends with one repeat barline', () {
    final score = scoreFromMusicXml(xml);
    expect(score.measures.last.endRepeat, isTrue);
    final l = const LayoutEngine().layout(score, settings);
    expect(thick(l), 1, reason: 'one thick line: the repeat\'s');
    // Nothing after it: the layout ends at the thick line's outer edge.
    final last = barlines(l).last;
    expect(last.$2, settings.thickBarlineThickness);
    expect(l.width, closeTo(last.$1 + last.$2 / 2, 1e-9));
    // And its dots are drawn.
    expect(l.primitives.whereType<GlyphPrimitive>().map((g) => g.smuflName),
        contains(SmuflGlyph.repeatDots));
  });

  test('a repeat that ends a wrapped piece: the last system too', () {
    final score = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: List.filled(12, 'c5:w').join(' | '),
    );
    final repeated = score.copyWith(measures: [
      ...score.measures.take(11),
      score.measures.last.copyWith(endRepeat: true),
    ]);
    final systems = layoutSystems(repeated, settings, maxWidth: 40).systems;
    expect(systems.length, greaterThan(1));
    expect(thick(systems.last.layout), 1);
  });

  test('without a repeat the piece still closes thin+thick', () {
    final l = const LayoutEngine()
        .layout(Score.simple(notes: 'c5:w | d5:w'), settings);
    expect(thick(l), 1);
    final lines = barlines(l);
    expect(lines.last.$2, settings.thickBarlineThickness);
    expect(lines[lines.length - 2].$2, settings.thinBarlineThickness);
  });

  test('a repeat in the middle is unaffected', () {
    final s = Score.simple(notes: 'c5:w | d5:w | e5:w');
    final l = const LayoutEngine().layout(
        s.copyWith(measures: [
          s.measures[0],
          s.measures[1].copyWith(endRepeat: true),
          s.measures[2],
        ]),
        settings);
    // The repeat's thick line and the final barline's.
    expect(thick(l), 2);
  });
}
