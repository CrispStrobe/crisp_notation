import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// How far apart staves and systems sit. Every pair of staves used to get the
/// widest gap any pair needed, measured from each staff's extremes anywhere,
/// and pages were packed at the full system gap: a voice-and-piano song set
/// two or three systems a page.
void main() {
  late final LayoutSettings settings;

  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    settings = LayoutSettings(
        metadata:
            SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>));
  });

  test('a voice with lyrics does not spread the piano staves below it', () {
    final voice = Score.simple(
        notes: 'c4:q d4 e4 f4 | g4 a4 b4 c5',
        lyrics: 'one two three four five six se- ven');
    final right = Score.simple(notes: 'e4:q g4 c5 g4 | f4 a4 c5 a4');
    final left = Score.simple(clef: Clef.bass, notes: 'c3:h g2 | f2 c3');
    final system =
        layoutStaffSystem(StaffSystem([voice, right, left]), settings);
    expect(system.gapBelow(0), greaterThan(system.gapBelow(1)));
    expect(system.staffTop(2) - system.staffTop(1), 4 + system.gapBelow(1));
    expect(system.staffGap, system.gapBelow(0));
  });

  test('ink in different bars does not hold two staves apart', () {
    // The upper staff dips low only in bar 1, the lower one rises high only
    // in bar 2: at no x do they meet, so the staves need no extra room.
    final upper = Score.simple(notes: 'g3:w | c5:w');
    final lower = Score.simple(clef: Clef.bass, notes: 'c3:w | c5:w');
    final system = layoutStaffSystem(StaffSystem([upper, lower]), settings);
    final extremes = system.staves[0].top +
        system.staves[0].height -
        system.staves[1].top -
        4;
    expect(system.gapBelow(0), lessThan(extremes));
  });

  test('a page holds the systems that fit the minimum system gap', () {
    final score =
        Score.simple(notes: List.filled(48, 'c4:q d4 e4 f4').join(' | '));
    const metrics = PageMetrics(width: 120, height: 90);
    final loose =
        layoutPages(score, settings, metrics: metrics, minSystemGap: 8);
    final tight = layoutPages(score, settings, metrics: metrics);
    expect(tight.pages.length, lessThanOrEqualTo(loose.pages.length));
    expect(tight.pages.first.systems.length,
        greaterThan(loose.pages.first.systems.length));
    // Spread to fill the page, the systems stay at least minSystemGap apart.
    final s = tight.pages.first.systems;
    for (var i = 0; i + 1 < s.length; i++) {
      final gap = s[i + 1].top - (s[i].top + s[i].system.layout.height);
      expect(gap, greaterThanOrEqualTo(5 - 1e-9));
    }
  });
}
