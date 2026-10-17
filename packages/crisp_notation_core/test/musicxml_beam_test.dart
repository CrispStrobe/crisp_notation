import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// MusicXML `<beam>`: a part that states its beams is beamed only where it
/// says. The reader ignored `<beam>` and grouped by the meter, so a vocal
/// line's flagged eighths came out beamed and a 3+3+2 grouping of eighths in
/// 4/4 came out 4+4.
void main() {
  late final LayoutSettings settings;

  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    settings = LayoutSettings(
        metadata:
            SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>));
  });

  String eighth(String step, [String? beam]) =>
      '<note><pitch><step>$step</step><octave>4</octave></pitch>'
      '<duration>1</duration><voice>1</voice><type>eighth</type>'
      '${beam == null ? '' : '<beam number="1">$beam</beam>'}</note>';

  String xml(List<List<String>> bars) => '''<?xml version="1.0"?>
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>P</part-name></score-part></part-list>
  <part id="P1">
${[
        for (var b = 0; b < bars.length; b++)
          '<measure number="${b + 1}">'
              '${b == 0 ? '<attributes><divisions>2</divisions><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>' : ''}'
              '${bars[b].join()}</measure>'
      ].join('\n')}
  </part>
</score-partwise>''';

  List<BeamPrimitive> primaryBeams(Score s) {
    final beams = const LayoutEngine()
        .layout(s, settings)
        .primitives
        .whereType<BeamPrimitive>()
        .toList();
    // One primary beam per group: eighths only here.
    return beams;
  }

  int flags(Score s) => const LayoutEngine()
      .layout(s, settings)
      .primitives
      .whereType<GlyphPrimitive>()
      .where((g) => g.smuflName.startsWith('flag'))
      .length;

  test('a 3+3+2 grouping is read as stated, not as the meter groups it', () {
    final score = scoreFromMusicXml(xml([
      [
        eighth('C', 'begin'),
        eighth('D', 'continue'),
        eighth('E', 'end'),
        eighth('F', 'begin'),
        eighth('G', 'continue'),
        eighth('A', 'end'),
        eighth('B', 'begin'),
        eighth('C', 'end'),
      ],
    ]));
    expect(score.beamsExplicit, isTrue);
    expect(score.beamSpans, hasLength(3));
    expect(primaryBeams(score), hasLength(3));
    expect(flags(score), 0);
  });

  test('a part that states beams keeps unbeamed notes flagged', () {
    // A vocal line: the first four eighths each carry a syllable and a flag,
    // the last four are one melisma under one beam.
    final score = scoreFromMusicXml(xml([
      [
        eighth('C'),
        eighth('D'),
        eighth('E'),
        eighth('F'),
        eighth('G', 'begin'),
        eighth('A', 'continue'),
        eighth('B', 'continue'),
        eighth('C', 'end'),
      ],
    ]));
    expect(primaryBeams(score), hasLength(1));
    expect(flags(score), 4);
  });

  test('a part without any <beam> is still grouped by the meter', () {
    final score = scoreFromMusicXml(xml([
      [for (final s in 'CDEFGABC'.split('')) eighth(s)],
    ]));
    expect(score.beamsExplicit, isFalse);
    expect(primaryBeams(score), hasLength(2));
    expect(flags(score), 0);
  });

  test('a beam over the barline is one cross-measure beam', () {
    String quarter(String step) =>
        '<note><pitch><step>$step</step><octave>4</octave></pitch>'
        '<duration>2</duration><voice>1</voice><type>quarter</type></note>';
    final score = scoreFromMusicXml(xml([
      [
        quarter('C'),
        quarter('D'),
        quarter('E'),
        eighth('F'),
        eighth('G', 'begin')
      ],
      [
        eighth('A', 'end'),
        eighth('B'),
        quarter('C'),
        quarter('D'),
        quarter('E')
      ],
    ]));
    expect(score.crossMeasureBeams, hasLength(1));
    expect(score.beamSpans, isEmpty);
    expect(primaryBeams(score), hasLength(1));
    expect(flags(score), 2); // F and B
  });

  test('beams that are never closed, or opened by a secondary, still group',
      () {
    // Dolet 3 for Sibelius (test suite 99a) writes no `end`, and can open a
    // group with only `<beam number="2">`.
    String sec(String step, String value) =>
        '<note><pitch><step>$step</step><octave>4</octave></pitch>'
        '<duration>1</duration><voice>1</voice><type>eighth</type>'
        '<beam number="2">$value</beam></note>';
    final score = scoreFromMusicXml(xml([
      [
        eighth('C', 'begin'),
        eighth('D', 'continue'),
        eighth('E', 'continue'),
        eighth('F'),
        sec('G', 'begin'),
        eighth('A', 'continue'),
        eighth('B'),
        eighth('C'),
      ],
    ]));
    expect(score.beamSpans, hasLength(2));
    expect(primaryBeams(score), hasLength(2));
    expect(flags(score), 3);
  });

  test('the writer states the beams, so a round trip keeps them', () {
    final score = scoreFromMusicXml(xml([
      [
        eighth('C', 'begin'),
        eighth('D', 'continue'),
        eighth('E', 'end'),
        eighth('F', 'begin'),
        eighth('G', 'continue'),
        eighth('A', 'end'),
        eighth('B'),
        eighth('C'),
      ],
    ]));
    final again = scoreFromMusicXml(scoreToMusicXml(score));
    expect(again.beamsExplicit, isTrue);
    expect(again.beamSpans, hasLength(2));
    expect(primaryBeams(again), hasLength(2));
    expect(flags(again), 2);
  });

  test('a system slice keeps its stated beams and flags the rest', () {
    final score = scoreFromMusicXml(xml([
      for (var b = 0; b < 6; b++)
        [
          eighth('C', 'begin'),
          eighth('D', 'end'),
          eighth('E'),
          eighth('F'),
          eighth('G'),
          eighth('A'),
          eighth('B'),
          eighth('C'),
        ],
    ]));
    final systems = layoutSystems(score, settings, maxWidth: 60).systems;
    expect(systems.length, greaterThan(1));
    for (final system in systems) {
      final beams = system.layout.primitives.whereType<BeamPrimitive>().length;
      final flagged = system.layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName.startsWith('flag'))
          .length;
      expect(flagged, 6 * beams);
    }
  });
}
