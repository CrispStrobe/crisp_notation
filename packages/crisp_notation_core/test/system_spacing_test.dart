import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Horizontal spacing of systems: aligned columns are as wide as the notes
/// in them need, and only the first system makes room for instrument names.
void main() {
  late final LayoutSettings settings;

  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    settings = LayoutSettings(
        metadata:
            SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>));
  });

  double barWidth(ScoreLayout l, int i) =>
      l.measureRegions[i].endX - l.measureRegions[i].startX;

  test('a triplet bracket does not widen the columns after its first note', () {
    // A piano right hand in triplets (each group bracketed, a dynamic under
    // the first) over a plain left hand. The bracket and the dynamic carry
    // the first note's id; counted as its ink, they pushed the next column
    // out by their width, and the system's bars came out a fifth wider than
    // the right hand needs alone.
    final triplets = List.filled(4, '3[c5:e e5 g5]').join(' ');
    final right = Score.simple(notes: '$triplets | $triplets');
    final withMarks =
        right.copyWith(dynamics: [const DynamicMarking('e0', DynamicLevel.mf)]);
    final left = Score.simple(clef: Clef.bass, notes: 'c3:q g2 e2 g2 | c3:w');
    final alone = const LayoutEngine().layout(withMarks, settings);
    final system = layoutStaffSystem(StaffSystem([withMarks, left]), settings);
    for (var i = 0; i < 2; i++) {
      expect(barWidth(system.staves.first, i),
          lessThan(barWidth(alone, i) * 1.08));
    }
  });

  test('only the first system is indented for the instrument names', () {
    final voice =
        Score.simple(notes: List.filled(16, 'c5:q d5 e5 f5').join(' | '));
    final piano = Score.simple(
        clef: Clef.bass, notes: List.filled(16, 'c3:h g2').join(' | '));
    final wrapped = layoutStaffSystemSystems(
        StaffSystem([voice, piano]), settings,
        maxWidth: 80, firstSystemIndent: 10);
    expect(wrapped.systems.length, greaterThan(2));
    final first = wrapped.systems.first, second = wrapped.systems[1];
    expect(first.indent, 10);
    expect(second.indent, 0);
    expect(first.layout.width, lessThanOrEqualTo(70 + 1e-6));
    expect(second.layout.width, greaterThan(70));
    expect(
        () => layoutStaffSystemSystems(StaffSystem([voice, piano]), settings,
            maxWidth: 80, firstSystemIndent: 80),
        throwsArgumentError);
  });

  test('a line a little over the width is squeezed, not broken', () {
    final voice = Score.simple(notes: 'c5:q d5 e5 f5 | g5 a5 b5 c6 | c5:h e5');
    final piano =
        Score.simple(clef: Clef.bass, notes: 'c3:h g2 | c3:h g2 | c3:w');
    final doc = StaffSystem([voice, piano]);
    final natural =
        layoutStaffSystem(doc, settings, finalBarline: true).staves.first.width;
    final squeezed =
        layoutStaffSystemSystems(doc, settings, maxWidth: natural / 1.05);
    expect(squeezed.systems, hasLength(1));
    expect(squeezed.systems.single.layout.width,
        lessThanOrEqualTo(natural / 1.05 + 1e-6));
    // Far over, the line breaks as before.
    expect(
        layoutStaffSystemSystems(doc, settings, maxWidth: natural / 1.3)
            .systems
            .length,
        greaterThan(1));
  });
}
