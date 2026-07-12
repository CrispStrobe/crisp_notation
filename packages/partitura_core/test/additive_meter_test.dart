import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Phase 5.7: additive / composite time signatures (e.g. 3+2/8).
void main() {
  group('model', () {
    test('additive sums its groups and remembers them', () {
      final ts = TimeSignature.additive([3, 2], 8);
      expect(ts.beats, 5);
      expect(ts.beatUnit, 8);
      expect(ts.components, [3, 2]);
      expect(ts.toString(), '3+2/8');
    });

    test('value equality is component-sensitive', () {
      expect(
          TimeSignature.additive([3, 2], 8), TimeSignature.additive([3, 2], 8));
      expect(TimeSignature.additive([3, 2], 8),
          isNot(TimeSignature.additive([2, 3], 8)));
      // Same total, but additive is a distinct value from the simple meter.
      expect(
          TimeSignature.additive([3, 2], 8), isNot(const TimeSignature(5, 8)));
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

    test('draws the digit groups with a plus between them', () {
      final g = (const LayoutEngine())
          .layout(
            Score.simple(
                timeSignature: TimeSignature.additive([3, 2], 8),
                notes: 'c5:e d5 e5 f5 g5'),
            settings,
          )
          .primitives
          .whereType<GlyphPrimitive>()
          .map((p) => p.smuflName)
          .toList();
      expect(g, contains('timeSig3'));
      expect(g, contains('timeSig2'));
      expect(g, contains('timeSig8'));
      expect(g, contains('timeSigPlus'));
    });
  });

  group('interchange', () {
    test('MusicXML writes "3+2" beats and round-trips', () {
      final score = Score.simple(
          timeSignature: TimeSignature.additive([3, 2], 8),
          notes: 'c5:e d5 e5 f5 g5');
      final xml = scoreToMusicXml(score);
      expect(xml, contains('<beats>3+2</beats>'));
      expect(scoreFromMusicXml(xml).timeSignature,
          TimeSignature.additive([3, 2], 8));
    });

    test('ABC imports M:3+2/8 and M:(3+2)/8', () {
      final a = scoreFromAbc('X:1\nM:3+2/8\nL:1/8\nK:C\nCDEFG|\n');
      expect(a.timeSignature, TimeSignature.additive([3, 2], 8));
      final b = scoreFromAbc('X:1\nM:(2+2+3)/8\nL:1/8\nK:C\nCDEFGAB|\n');
      expect(b.timeSignature, TimeSignature.additive([2, 2, 3], 8));
    });

    test('ABC round-trips an additive meter', () {
      final src = scoreFromAbc('X:1\nM:3+2/8\nL:1/8\nK:C\nCDEFG|\n');
      expect(scoreToAbc(src), contains('M:3+2/8'));
      expect(scoreFromAbc(scoreToAbc(src)).timeSignature,
          TimeSignature.additive([3, 2], 8));
    });
  });
}
