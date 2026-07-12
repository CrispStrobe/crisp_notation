import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Phase 5.7: common / cut time symbols.
void main() {
  group('model', () {
    test('common and cut carry their numeric meaning', () {
      expect(TimeSignature.commonTime.beats, 4);
      expect(TimeSignature.commonTime.beatUnit, 4);
      expect(TimeSignature.commonTime.symbol, TimeSymbol.common);
      expect(TimeSignature.cutTime.beats, 2);
      expect(TimeSignature.cutTime.beatUnit, 2);
      expect(TimeSignature.cutTime.symbol, TimeSymbol.cut);
    });

    test('a symbol makes a distinct value from the numeric form', () {
      expect(TimeSignature.commonTime, isNot(TimeSignature.fourFour));
      expect(TimeSignature.commonTime.toString(), 'C');
      expect(TimeSignature.cutTime.toString(), 'C|');
      expect(const TimeSignature(4, 4).toString(), '4/4');
    });
  });

  group('layout', () {
    late final LayoutSettings settings;
    setUpAll(() {
      final meta = SmuflMetadata.fromJson(jsonDecode(
          File('../partitura/assets/smufl/bravura_metadata.json')
              .readAsStringSync()) as Map<String, Object?>);
      settings = LayoutSettings(metadata: meta);
    });

    List<String> glyphs(Score s) => (const LayoutEngine())
        .layout(s, settings)
        .primitives
        .whereType<GlyphPrimitive>()
        .map((g) => g.smuflName)
        .toList();

    test('common time draws the C glyph, not digits', () {
      final g = glyphs(Score.simple(
          timeSignature: TimeSignature.commonTime, notes: 'c5:q d5 e5 f5'));
      expect(g, contains('timeSigCommon'));
      expect(g.where((n) => n.startsWith('timeSig') && n != 'timeSigCommon'),
          isEmpty);
    });

    test('cut time draws the ¢ glyph', () {
      final g = glyphs(Score.simple(
          timeSignature: TimeSignature.cutTime, notes: 'c5:h c5:h'));
      expect(g, contains('timeSigCutCommon'));
    });

    test('numeric time still stacks digits', () {
      final g = glyphs(Score.simple(
          timeSignature: const TimeSignature(3, 4), notes: 'c5:q d5 e5'));
      expect(g, contains('timeSig3'));
      expect(g, contains('timeSig4'));
    });
  });

  group('interchange', () {
    test('MusicXML writes and round-trips symbol="common"', () {
      final score = Score.simple(
          timeSignature: TimeSignature.commonTime, notes: 'c5:q d5 e5 f5');
      final xml = scoreToMusicXml(score);
      expect(xml, contains('<time symbol="common">'));
      expect(scoreFromMusicXml(xml).timeSignature, TimeSignature.commonTime);
    });

    test('MusicXML round-trips symbol="cut"', () {
      final score = Score.simple(
          timeSignature: TimeSignature.cutTime, notes: 'c5:h c5:h');
      final back = scoreFromMusicXml(scoreToMusicXml(score));
      expect(back.timeSignature, TimeSignature.cutTime);
    });

    test('ABC M:C and M:C| import as the symbols', () {
      expect(scoreFromAbc('X:1\nM:C\nL:1/4\nK:C\nCDEF|\n').timeSignature,
          TimeSignature.commonTime);
      expect(scoreFromAbc('X:1\nM:C|\nL:1/4\nK:C\nC2E2|\n').timeSignature,
          TimeSignature.cutTime);
    });

    test('ABC writes and round-trips M:C / M:C|', () {
      final common = scoreFromAbc('X:1\nM:C\nL:1/4\nK:C\nCDEF|\n');
      expect(scoreToAbc(common), contains('M:C\n'));
      expect(scoreFromAbc(scoreToAbc(common)).timeSignature,
          TimeSignature.commonTime);
      final cut = scoreFromAbc('X:1\nM:C|\nL:1/4\nK:C\nC2E2|\n');
      expect(scoreToAbc(cut), contains('M:C|'));
      expect(
          scoreFromAbc(scoreToAbc(cut)).timeSignature, TimeSignature.cutTime);
    });
  });
}
