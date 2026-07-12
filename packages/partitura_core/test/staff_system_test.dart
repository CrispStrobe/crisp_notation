import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

late final LayoutSettings settings;

void main() {
  setUpAll(() {
    final meta = SmuflMetadata.fromJson(jsonDecode(
        File('../partitura/assets/smufl/bravura_metadata.json')
            .readAsStringSync()) as Map<String, Object?>);
    settings = LayoutSettings(metadata: meta);
  });

  StaffSystem satb() => StaffSystem([
        Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5 | g5:h a5:h'),
        Score.simple(clef: Clef.treble, notes: 'g4:q g4 g4 g4 | b4:h c5:h'),
        Score.simple(clef: Clef.bass, notes: 'e3:q f3 g3 a3 | d3:h e3:h'),
        Score.simple(clef: Clef.bass, notes: 'c3:q b2 a2 g2 | g2:h c3:h'),
      ], brackets: const [
        StaffBracket(0, 3)
      ]);

  test('lays out one layout per staff', () {
    final layout = layoutStaffSystem(satb(), settings);
    expect(layout.staves, hasLength(4));
  });

  test('all staves share the total width (aligned)', () {
    final layout = layoutStaffSystem(satb(), settings);
    final w = layout.staves.first.width;
    for (final s in layout.staves) {
      expect(s.width, closeTo(w, 1e-9));
    }
  });

  test('barlines align: every measure column matches across staves', () {
    final layout = layoutStaffSystem(satb(), settings);
    final ref = layout.staves.first.measureRegions;
    for (final s in layout.staves) {
      for (var i = 0; i < ref.length; i++) {
        expect(s.measureRegions[i].startX, closeTo(ref[i].startX, 1e-6));
        expect(s.measureRegions[i].endX, closeTo(ref[i].endX, 1e-6));
      }
    }
  });

  test('staff tops stack by 4 + staffGap', () {
    final layout = layoutStaffSystem(satb(), settings, staffGap: 5);
    expect(layout.staffTop(0), 0);
    expect(layout.staffTop(1), 9); // 4 + 5
    expect(layout.staffTop(2), 18);
    expect(layout.staffTop(3), 27);
    // The system spans from above the first staff to below the last.
    expect(layout.top, lessThan(0));
    expect(layout.height, greaterThan(27));
  });

  test('a single-staff system is valid', () {
    final layout =
        layoutStaffSystem(StaffSystem([Score.simple(notes: 'c4:w')]), settings);
    expect(layout.staves, hasLength(1));
    expect(layout.staffTop(0), 0);
  });

  test('staves must agree on measure count', () {
    final bad = StaffSystem([
      Score.simple(notes: 'c4:q d4 e4 f4'),
      Score.simple(notes: 'c4:w | d4:w'), // 2 measures vs 1
    ]);
    expect(() => layoutStaffSystem(bad, settings), throwsArgumentError);
  });

  test('value semantics of the model', () {
    final a = StaffSystem([Score.simple(notes: 'c4:w')],
        brackets: const [StaffBracket(0, 0, kind: StaffBracketKind.brace)]);
    final b = StaffSystem([Score.simple(notes: 'c4:w')],
        brackets: const [StaffBracket(0, 0, kind: StaffBracketKind.brace)]);
    expect(a, b);
  });
}
