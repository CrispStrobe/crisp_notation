import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

import 'support/layout_lint.dart';

/// The bugs the layout lint (`support/layout_lint.dart`) found on its first
/// run over the real corpus and the LilyPond MusicXML test suite, one test
/// each. Barline cases live in `barline_grid_test.dart`.
void main() {
  final settings = LayoutSettings(
      metadata: SmuflMetadata.fromJson(jsonDecode(
          File('../crisp_notation/assets/smufl/bravura_metadata.json')
              .readAsStringSync()) as Map<String, Object?>));
  ScoreLayout layoutOf(Score s) => const LayoutEngine().layout(s, settings);

  String measureXml(String body, {String attributes = ''}) => '''
<score-partwise version="3.1"><part-list><score-part id="P1">
<part-name>V</part-name></score-part></part-list><part id="P1">
<measure number="1"><attributes><divisions>2</divisions>$attributes
<time><beats>4</beats><beat-type>4</beat-type></time>
<clef><sign>G</sign><line>2</line></clef></attributes>$body</measure>
</part></score-partwise>''';

  group('theoretical keys (LilyPond test suite 13a)', () {
    test('8 sharps: F double-sharp, then six sharps', () {
      final key = KeySignature.fromFifths(8);
      expect(key.custom, [
        const KeyAccidental(Step.f, 2),
        const KeyAccidental(Step.c, 1),
        const KeyAccidental(Step.g, 1),
        const KeyAccidental(Step.d, 1),
        const KeyAccidental(Step.a, 1),
        const KeyAccidental(Step.e, 1),
        const KeyAccidental(Step.b, 1),
      ]);
      expect(KeySignature.fromFifths(-9).custom!.take(2), [
        const KeyAccidental(Step.b, -2),
        const KeyAccidental(Step.e, -2),
      ]);
      expect(KeySignature.fromFifths(3), const KeySignature(3));
    });

    test('a MusicXML key beyond 7 fifths reads and lays out', () {
      final score = scoreFromMusicXml(measureXml(
          '<note><pitch><step>F</step><alter>2</alter><octave>4</octave>'
          '</pitch><duration>8</duration><type>whole</type></note>',
          attributes: '<key><fifths>8</fifths></key>'));
      final l = layoutOf(score);
      final keyGlyphs = l.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.elementId == null && g.smuflName.startsWith('acc'))
          .map((g) => g.smuflName);
      expect(keyGlyphs.where((n) => n == SmuflGlyph.accidentalDoubleSharp),
          hasLength(1));
      expect(keyGlyphs.where((n) => n == SmuflGlyph.accidentalSharp),
          hasLength(6));
      // The key already says F double-sharp: the note needs no accidental.
      expect(
          l.primitives.whereType<GlyphPrimitive>().where(
              (g) => g.elementId != null && g.smuflName.startsWith('acc')),
          isEmpty);
    });
  });

  test('two voices: a stated accidental is drawn once', () {
    // Voice 2's G#3 carries <accidental>sharp</accidental>: the joint column
    // drew it, and the note drew it again.
    final score = scoreFromMusicXml(measureXml('''
<note><pitch><step>D</step><octave>5</octave></pitch><duration>8</duration>
<voice>1</voice><type>whole</type><stem>up</stem></note>
<backup><duration>8</duration></backup>
<note><pitch><step>G</step><alter>1</alter><octave>4</octave></pitch>
<duration>8</duration><voice>2</voice><type>whole</type>
<accidental>sharp</accidental><stem>down</stem></note>'''));
    final l = layoutOf(score);
    expect(
        lintLayout(l, settings).where((i) => i.rule == 'duplicate'), isEmpty);
    expect(
        l.primitives
            .whereType<GlyphPrimitive>()
            .where((g) => g.smuflName == SmuflGlyph.accidentalSharp),
        hasLength(1));
  });

  test('a dotted second gives each head its own dot', () {
    // D5 sits on a line, E5 in the space above it: D5's dot goes below.
    final l = layoutOf(Score.simple(notes: 'd5+e5:h.'));
    final dots = l.primitives
        .whereType<GlyphPrimitive>()
        .where((g) => g.smuflName == SmuflGlyph.augmentationDot)
        .map((g) => g.position.y)
        .toList();
    expect(dots.toSet(), hasLength(2));
    expect(dots.every((y) => (y * 2).round().isOdd), isTrue,
        reason: 'dots sit in spaces');
  });

  test('a stem-down second clears the time signature', () {
    for (final notes in ['d5+e5:h.', 'e5+f5:q g5 a5']) {
      final l = layoutOf(
          Score.simple(timeSignature: const TimeSignature(3, 4), notes: notes));
      expect(
          lintLayout(l, settings).where((i) => i.rule == 'collision'), isEmpty,
          reason: notes);
    }
  });

  test('an empty bar keeps a bar\'s width', () {
    final l = layoutOf(Score.simple(notes: 'c5:w | | d5:w'));
    expect(lintLayout(l, settings), isEmpty);
  });
}
