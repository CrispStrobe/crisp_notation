import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

late final LayoutSettings settings;

void main() {
  setUpAll(() {
    final meta = SmuflMetadata.fromJson(jsonDecode(
        File('../crisp_notation/assets/smufl/bravura_metadata.json')
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

  test('a short final measure still aligns its barline with full voices', () {
    // Voice 1's last bar holds only 1/4 (an under-full measure); voice 2 is
    // full 4/4. Same measure COUNT, different last-measure duration — as when
    // an imported ABC voice ends short. The closing barline must still align.
    final sys = StaffSystem([
      Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5 | e5:e c5'),
      Score.simple(clef: Clef.treble, notes: 'g4:q a4 b4 c5 | b4:h c5:h'),
    ]);
    final layout = layoutStaffSystem(sys, settings);
    final a = layout.staves[0].measureRegions;
    final b = layout.staves[1].measureRegions;
    expect(a, hasLength(2));
    expect(b, hasLength(2));
    // The short measure's closing barline lines up with the full voice's.
    expect(a[1].endX, closeTo(b[1].endX, 1e-6),
        reason: 'short-measure barline must align with the full voice');
  });

  test('cross-staff onset gridding aligns notes across N staves (§2.9)', () {
    // Three staves, different rhythms: four quarters / a half + two quarters /
    // a whole note. Compare the notehead x (the column), not ink bounds, which
    // vary with ledger lines and notehead bearing.
    final sys = StaffSystem([
      Score.simple(notes: 'c5:q d5 e5 f5'),
      Score.simple(clef: Clef.bass, notes: 'c3:h e3:q g3:q'),
      Score.simple(clef: Clef.bass, notes: 'c2:w'),
    ]);
    final layout = layoutStaffSystem(sys, settings);
    double noteX(int staff, String id) => layout.staves[staff].primitives
        .whereType<GlyphPrimitive>()
        .firstWhere(
            (g) => g.elementId == id && g.smuflName.startsWith('notehead'))
        .position
        .x;

    // Beat 1 (onset 0): all three first notes share a column.
    expect(noteX(0, 'e0'), closeTo(noteX(1, 'e0'), 0.01));
    expect(noteX(0, 'e0'), closeTo(noteX(2, 'e0'), 0.01));
    // Beat 3 (onset 1/2): staff 0's third quarter over staff 1's second note.
    expect(noteX(0, 'e2'), closeTo(noteX(1, 'e1'), 0.01));
  });

  test('gridAlign: false keeps barline-only alignment', () {
    final sys = StaffSystem([
      Score.simple(notes: 'c5:q d5 e5 f5'),
      Score.simple(clef: Clef.bass, notes: 'c3:h e3:q g3:q'),
    ]);
    final layout = layoutStaffSystem(sys, settings, gridAlign: false);
    expect(layout.staves[0].width, closeTo(layout.staves[1].width, 1e-6));
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

  group('hideEmptyStaves', () {
    // A three-staff system whose middle staff rests through the whole system.
    StaffSystem withEmptyMiddle() => StaffSystem([
          Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5 | g5:h a5:h'),
          Score.simple(clef: Clef.treble, notes: 'r:w | r:w'),
          Score.simple(clef: Clef.bass, notes: 'c3:q b2 a2 g2 | g2:h c3:h'),
        ], brackets: const [
          StaffBracket(0, 2)
        ]);

    test('off by default — every staff is laid out', () {
      expect(
          layoutStaffSystem(withEmptyMiddle(), settings).staves, hasLength(3));
    });

    test('drops the all-rest staff and remaps the bracket', () {
      final layout =
          layoutStaffSystem(withEmptyMiddle(), settings, hideEmptyStaves: true);
      expect(layout.staves, hasLength(2));
      // The bracket spanning 0..2 now spans the two surviving staves, 0..1.
      expect(layout.source.staves, hasLength(2));
      expect(layout.source.brackets.single.first, 0);
      expect(layout.source.brackets.single.last, 1);
    });

    test('barlines still align across the surviving staves', () {
      final layout =
          layoutStaffSystem(withEmptyMiddle(), settings, hideEmptyStaves: true);
      final a = layout.staves[0].measureRegions;
      final b = layout.staves[1].measureRegions;
      for (var i = 0; i < a.length; i++) {
        expect(b[i].endX, closeTo(a[i].endX, 1e-6));
      }
    });

    test('keeps at least one staff when every staff is empty', () {
      final allRests = StaffSystem([
        Score.simple(notes: 'r:w'),
        Score.simple(notes: 'r:w'),
      ]);
      expect(
          layoutStaffSystem(allRests, settings, hideEmptyStaves: true).staves,
          hasLength(1));
    });

    test('a bracket over only-hidden staves is dropped', () {
      final system = StaffSystem([
        Score.simple(notes: 'c5:w'),
        Score.simple(notes: 'r:w'),
        Score.simple(notes: 'r:w'),
      ], brackets: const [
        StaffBracket(1, 2) // both hidden
      ]);
      final layout = layoutStaffSystem(system, settings, hideEmptyStaves: true);
      expect(layout.staves, hasLength(1));
      expect(layout.source.brackets, isEmpty);
    });
  });
}
