import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

/// A long score so the multi-system view is tall enough to scroll.
Score longScore() => Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5 | c5:q b4 a4 g4 | f4:q e4 d4 c4 | '
          'e4:q f4 g4 a4 | b4:q a4 g4 f4 | e4:q d4 c4 d4 | c4:q d4 e4 f4 | '
          'g4:q a4 b4 c5 | c5:q b4 a4 g4 | f4:q e4 d4 c4 | c4:w',
    );

void main() {
  setUpAll(setUpPartituraForTests);

  group('overlay state', () {
    test('setLoop / clearLoop notify only on change', () {
      final c = ScoreEditorController();
      var n = 0;
      c.addListener(() => n++);
      c.setLoop('a', 'b');
      expect(c.loopRange, ('a', 'b'));
      c.setLoop('a', 'b'); // same — no notify
      c.clearLoop();
      c.clearLoop(); // already clear — no notify
      expect(c.loopRange, isNull);
      expect(n, 2);
      c.dispose();
    });

    test('mark / unmark / clearMarks build the overlay map', () {
      final c = ScoreEditorController();
      var n = 0;
      c.addListener(() => n++);
      const red = EditorMark(Color(0xFFD32F2F), message: 'flat');
      c.mark('e5', red);
      expect(c.errorOverlay, {'e5': red});
      c.mark('e5', red); // identical — no notify
      c.mark('e9', const EditorMark(Color(0xFF388E3C)));
      expect(c.errorOverlay.length, 2);
      c.unmark('e5');
      expect(c.errorOverlay.containsKey('e5'), isFalse);
      c.unmark('nope'); // absent — no notify
      c.clearMarks();
      expect(c.errorOverlay, isEmpty);
      expect(n, 4); // mark, mark(e9), unmark, clearMarks
      c.dispose();
    });

    test('highlight replaces the set and de-dupes notifications', () {
      final c = ScoreEditorController();
      var n = 0;
      c.addListener(() => n++);
      c.highlight(['e1', 'e2']);
      expect(c.highlightedIds, {'e1', 'e2'});
      c.highlight(['e2', 'e1']); // same set — no notify
      c.clearHighlight();
      expect(n, 2);
      c.dispose();
    });
  });

  testWidgets('AnimatedBuilder binds controller state into the view',
      (tester) async {
    final c = ScoreEditorController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            child: AnimatedBuilder(
              animation: c,
              builder: (_, __) => MultiSystemView(
                score: longScore(),
                staffSpace: 9,
                errorOverlay: c.errorOverlay,
                loopRange: c.loopRange,
                highlightedIds: c.highlightedIds,
              ),
            ),
          ),
        ),
      ),
    );
    final render = tester
        .renderObject<RenderMultiSystemView>(find.bySubtype<MultiSystemView>());
    expect(render.loopRange, isNull);

    c.setLoop('e4', 'e7');
    c.mark('e2', const EditorMark(Color(0xFFD32F2F)));
    await tester.pump();
    expect(render.loopRange, ('e4', 'e7'));
    expect(render.errorOverlay.containsKey('e2'), isTrue);
    c.dispose();
  });

  testWidgets('scrollToNote drives an app-owned ScrollController',
      (tester) async {
    final c = ScoreEditorController();
    final scroll = ScrollController();
    late RenderMultiSystemView render;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 320,
            height: 180, // short viewport → the tall score overflows
            child: SingleChildScrollView(
              controller: scroll,
              child: SizedBox(
                width: 320,
                child: MultiSystemView(score: longScore(), staffSpace: 9),
              ),
            ),
          ),
        ),
      ),
    );
    render = tester
        .renderObject<RenderMultiSystemView>(find.bySubtype<MultiSystemView>());
    c.attachViewport(
      scrollController: scroll,
      rectOfElement: render.rectOfElement,
    );
    expect(c.isViewportAttached, isTrue);
    expect(scroll.offset, 0);

    // A note in the last system is below the fold.
    final layout = render.multiSystemLayout!;
    final lastId =
        'e${layout.systems[layout.systems.length - 1].firstMeasure * 4}';
    final target = c.offsetToReveal(lastId);
    expect(target, isNotNull);
    expect(target, greaterThan(0));

    // Drive the animation: kick it off (unawaited — awaiting its future before
    // pumping would deadlock the test clock), then let pumpAndSettle run it out.
    final done = c.scrollToNote(lastId);
    await tester.pumpAndSettle();
    await done;
    expect(scroll.offset, closeTo(target!, 0.5));

    // Unknown id and detach are no-ops.
    expect(c.offsetToReveal('no-such-id'), isNull);
    c.detachViewport();
    expect(c.isViewportAttached, isFalse);
    await c.scrollToNote(lastId); // no throw
    c.dispose();
    scroll.dispose();
  });

  group('drill / visualizer / part visibility (3.7 + 3.8)', () {
    Score drillScore() => Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: 'c4:q e4 g4 c5', // e0=60 e1=64 e2=67 e3=72
        );

    test('showDrill applies marks and reports the result', () {
      final c = ScoreEditorController();
      var n = 0;
      c.addListener(() => n++);
      final result = c.showDrill(
        score: drillScore(),
        expectedIds: ['e0', 'e1'],
        played: {60}, // e1 (64) missing
      );
      expect(result.isPerfect, isFalse);
      expect(result.missingPitches, {64});
      // The overlay was pushed into the controller's marks.
      expect(c.errorOverlay.containsKey('e0'), isTrue);
      expect(c.errorOverlay.containsKey('e1'), isTrue);
      expect(n, 1); // one setMarks notification
      c.dispose();
    });

    test('soundingPitches resolves the highlighted ids to MIDI', () {
      final c = ScoreEditorController();
      final score = drillScore();
      expect(c.soundingPitches(score), isEmpty);
      c.highlight(['e0', 'e3']);
      expect(c.soundingPitches(score), {60, 72});
      c.dispose();
    });

    test('part visibility toggles and notifies', () {
      final c = ScoreEditorController();
      var n = 0;
      c.addListener(() => n++);
      expect(c.isPartVisible(1), isTrue);
      c.togglePart(1);
      expect(c.isPartVisible(1), isFalse);
      expect(c.hiddenParts, {1});
      c.hidePart(1); // already hidden — no notify
      c.showPart(1);
      expect(c.isPartVisible(1), isTrue);
      c.hidePart(0);
      c.showAllParts();
      expect(c.hiddenParts, isEmpty);
      expect(n, 4); // toggle, showPart, hidePart(0), showAllParts
      c.dispose();
    });
  });
}
