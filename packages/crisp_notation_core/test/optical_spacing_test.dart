import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Optical spacing: an up-stem followed by a down-stem gets a little more
/// room, a down-stem then an up-stem a little less (Gould).
void main() {
  late LayoutSettings settings;
  setUpAll(() {
    settings = LayoutSettings(
        metadata: SmuflMetadata.fromJson(jsonDecode(
            File('../crisp_notation/assets/smufl/bravura_metadata.json')
                .readAsStringSync()) as Map<String, Object?>));
  });

  List<double> gaps(List<double> xs) =>
      [for (var i = 1; i < xs.length; i++) xs[i] - xs[i - 1]];

  test('one staff: up then down opens, down then up closes', () {
    final layout = const LayoutEngine()
        .layout(Score.simple(notes: 'g4:q d5 g4 d5'), settings);
    final xs = [
      for (final g in layout.primitives.whereType<GlyphPrimitive>())
        if (g.smuflName.startsWith('notehead')) g.position.x,
    ];
    final g = gaps(xs);
    expect(g[0], greaterThan(g[1]));
    expect(g[2], closeTo(g[0], 1e-9));
  });

  test('a system: the staves that show one stem direction vote', () {
    // The lower staff's whole note has no stem: only the upper staff votes.
    final cols = alignedColumns([
      Score.simple(notes: 'g4:q d5 g4 d5'),
      Score.simple(clef: Clef.bass, notes: 'c3:w'),
    ], settings);
    final xs = (cols.first.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => e.value)
        .toList();
    final g = gaps(xs);
    expect(g[0], greaterThan(g[1]), reason: 'up → down opens');
    // Staves that disagree leave the gap alone.
    final mixed = alignedColumns([
      Score.simple(notes: 'g4:q d5 g4 d5'),
      Score.simple(notes: 'd5:q g4 d5 g4'),
    ], settings);
    final ys = (mixed.first.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => e.value)
        .toList();
    final h = gaps(ys);
    expect(h[0], closeTo(h[1], 1e-9));
  });
}
