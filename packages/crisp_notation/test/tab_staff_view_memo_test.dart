// `TabStaffView` engraves once per CHANGE, not once per build.
//
// Engraving a score is the expensive thing this library does, and
// `highlightedIds` does not affect it — it only reaches the painter. So a view
// that re-engraved on every rebuild painted identical pixels to one that did
// not, and the difference was invisible: a moving playhead re-laid out every
// note of the piece for each column it lit up.
//
// A counter is therefore the only possible test. These pin both directions:
// what must NOT re-engrave, and what must.

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_setup.dart';

Score _score() => Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'e3:q g3 c4 e4',
    );

void main() {
  // The music font's metadata loads asynchronously and there is nothing to
  // engrave without it.
  setUpAll(setUpCrispNotationForTests);
  testWidgets('a highlight change does NOT re-engrave', (tester) async {
    final score = _score();
    var highlighted = <String>{};
    late StateSetter setOuter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return TabStaffView(
                score: score,
                tuning: Tuning.standardGuitar,
                highlightedIds: highlighted,
              );
            },
          ),
        ),
      ),
    );
    final state = tester.state(find.byType(TabStaffView));
    // ignore: avoid_dynamic_calls
    final before = (state as dynamic).engraveCount as int;
    expect(before, greaterThan(0), reason: 'it engraved once to begin with');

    setOuter(() => highlighted = {'e1'});
    await tester.pump();
    setOuter(() => highlighted = {'e2'});
    await tester.pump();

    // ignore: avoid_dynamic_calls
    expect((state as dynamic).engraveCount, before);
  });

  testWidgets('a new SCORE does re-engrave', (tester) async {
    // The other direction, and the one that matters for correctness: a cache
    // that never invalidates shows music that is no longer there.
    var score = _score();
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return TabStaffView(score: score, tuning: Tuning.standardGuitar);
            },
          ),
        ),
      ),
    );
    final state = tester.state(find.byType(TabStaffView));
    // ignore: avoid_dynamic_calls
    final before = (state as dynamic).engraveCount as int;

    setOuter(() {
      score = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c3:q d3 e3 f3 | g3:q a3 b3 c4',
      );
    });
    await tester.pump();

    // ignore: avoid_dynamic_calls
    expect((state as dynamic).engraveCount, greaterThan(before));
  });

  testWidgets('the capo and the tuning re-engrave too', (tester) async {
    // Both change where every digit lands, so neither may be cached past.
    final score = _score();
    var capo = 0;
    var tuning = Tuning.standardGuitar;
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return TabStaffView(score: score, tuning: tuning, capo: capo);
            },
          ),
        ),
      ),
    );
    final state = tester.state(find.byType(TabStaffView));
    // ignore: avoid_dynamic_calls
    var count = (state as dynamic).engraveCount as int;

    setOuter(() => capo = 2);
    await tester.pump();
    // ignore: avoid_dynamic_calls
    expect((state as dynamic).engraveCount, greaterThan(count));
    // ignore: avoid_dynamic_calls
    count = (state as dynamic).engraveCount as int;

    setOuter(() => tuning = Tuning.standardBass);
    await tester.pump();
    // ignore: avoid_dynamic_calls
    expect((state as dynamic).engraveCount, greaterThan(count));
  });
}
