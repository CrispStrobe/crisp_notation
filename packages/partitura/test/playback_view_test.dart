import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

/// Live playback-cursor simulation: step a highlight through a score the
/// way an app would while playing audio, and verify the widget updates
/// are repaint-only (never a relayout).
void main() {
  setUpAll(setUpPartituraForTests);

  Widget scene(Score score, Set<String> highlights) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: StaffView(
              score: score,
              staffSpace: 10,
              highlightedIds: highlights,
            ),
          ),
        ),
      );

  testWidgets('cursor steps through every onset without relayout',
      (tester) async {
    final score = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4:e e4:e f4:h | 3[g4:e a4 b4] c5:q c5:h ; c3:w',
    );
    final timeline = playbackTimeline(score);
    expect(timeline, isNotEmpty);

    await tester.pumpWidget(scene(score, const {}));
    final staff =
        tester.renderObject<RenderStaffView>(find.bySubtype<StaffView>());
    final layoutBefore = staff.scoreLayout;
    final knownIds = staff.scoreLayout!.regions.map((r) => r.elementId).toSet();

    // Every distinct onset is a cursor step; highlight what sounds there.
    final onsets = timeline.map((n) => n.start).toSet().toList()..sort();
    for (final onset in onsets) {
      final highlights = soundingAt(timeline, onset);
      expect(highlights, isNotEmpty, reason: 'onset $onset');
      // The cursor only ever references real, hittable elements.
      expect(knownIds.containsAll(highlights), isTrue);
      await tester.pumpWidget(scene(score, highlights));
      expect(tester.takeException(), isNull);
    }
    // Same score all along: the layout object never changed.
    expect(identical(staff.scoreLayout, layoutBefore), isTrue);
  });

  testWidgets('repeated passes highlight the same elements again',
      (tester) async {
    final score = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: '!repeat c4:w !endrepeat | d4:w',
    );
    final timeline = playbackTimeline(score);
    // Three whole-note steps: e0, e0 again (second pass), e1.
    final steps = [
      for (final note in timeline) soundingAt(timeline, note.start),
    ];
    expect(steps, [
      {'e0'},
      {'e0'},
      {'e1'},
    ]);
    await tester.pumpWidget(scene(score, steps.first));
    expect(tester.takeException(), isNull);
  });

  testWidgets('secondsFor drives a wall-clock schedule', (tester) async {
    final score = Score.simple(notes: 'c4:q d4:q e4:h');
    final timeline = playbackTimeline(score);
    final schedule = [
      for (final note in timeline) secondsFor(note.start, quarterBpm: 120),
    ];
    expect(schedule, [0.0, 0.5, 1.0]);
    // End of playback in seconds.
    expect(secondsFor(timeline.last.end, quarterBpm: 120), 2.0);
    await tester.pumpWidget(scene(score, const {}));
    expect(tester.takeException(), isNull);
  });
}
