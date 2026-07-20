import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Phase 6.3: a notation staff paired with a tab staff of the same music,
/// barlines aligned.
void main() {
  late final LayoutSettings settings;
  setUpAll(() {
    final meta = SmuflMetadata.fromJson(jsonDecode(
        File('../crisp_notation/assets/smufl/bravura_metadata.json')
            .readAsStringSync()) as Map<String, Object?>);
    settings = LayoutSettings(metadata: meta);
  });

  NotationTabLayout pairOf(String notes, [Tuning? tuning]) => layoutNotationTab(
      Score.simple(notes: notes, timeSignature: TimeSignature.fourFour),
      tuning ?? Tuning.standardGuitar,
      settings);

  test('both staves render primitives for the same score', () {
    final pair = pairOf('e2:q a2 d3 g3');
    expect(pair.notation.primitives, isNotEmpty);
    expect(pair.tab.primitives, isNotEmpty);
    // The tab staff sits below the notation staff.
    expect(pair.tabTop, greaterThan(4));
    expect(pair.height, greaterThan(pair.tabTop));
  });

  test('barlines align: every measure shares its barline x (endX)', () {
    final pair = pairOf('e2:q a2 d3 g3 | c3:q e3 g3 c4 | e2:h a2:h');
    final n = pair.notation.measureRegions;
    final t = pair.tab.measureRegions;
    expect(n, hasLength(3));
    expect(t, hasLength(3));
    // The barlines (measure ends) are the connected vertical lines, so they
    // must coincide exactly; the first measure also shares its start (leading).
    expect(t.first.startX, closeTo(n.first.startX, 1e-6));
    for (var i = 0; i < n.length; i++) {
      expect(t[i].endX, closeTo(n[i].endX, 1e-6), reason: 'barline $i');
    }
  });

  test('the first measure starts at a shared leading on both staves', () {
    final pair = pairOf('e2:q a2 d3 g3');
    expect(pair.tab.measureRegions.first.startX,
        closeTo(pair.notation.measureRegions.first.startX, 1e-6));
  });

  test('alignment holds when the tab clef is wider than the notation lead', () {
    // A 6-string tab clef is tall/wide; a short pickup measure stresses the
    // shared-leading logic. Barlines must still line up.
    final pair = pairOf('e2:q | a2:q d3 g3 b3');
    for (var i = 0; i < pair.notation.measureRegions.length; i++) {
      expect(pair.tab.measureRegions[i].endX,
          closeTo(pair.notation.measureRegions[i].endX, 1e-6));
    }
  });

  test('low notes push the tab clear of the notation ink (no collision)', () {
    final low = pairOf('e2:q'); // low E: far below the treble staff (ledger)
    final high = pairOf('e5:q'); // high E: within/above the staff
    // The tab's top string line must sit at or below the notation's lowest ink
    // (painted at notation.height); a low E on ledger lines used to overlap it.
    expect(low.tabTop, greaterThanOrEqualTo(low.notation.height));
    // A low note therefore pushes the tab further down than a high one.
    expect(low.tabTop, greaterThan(high.tabTop));
  });

  test('a four-string tuning (bass) also aligns', () {
    final pair = pairOf('e1:q a1 d2 g2 | c2:h e2:h', Tuning.standardBass);
    final n = pair.notation.measureRegions;
    final t = pair.tab.measureRegions;
    for (var i = 0; i < n.length; i++) {
      expect(t[i].endX, closeTo(n[i].endX, 1e-6));
    }
  });
}
