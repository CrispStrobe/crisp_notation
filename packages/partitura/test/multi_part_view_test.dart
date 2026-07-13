import 'package:flutter/material.dart' hide Step, PageMetrics;
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

void main() {
  setUpAll(setUpPartituraForTests);

  // A small string-quartet-ish document: two connected barline groups (upper
  // pair and lower pair) under one section bracket, over several bars so the
  // document line-breaks.
  MultiPartScore quartet() {
    Score part(Clef clef, String bars) => Score.simple(
          clef: clef,
          keySignature: const KeySignature(1),
          timeSignature: TimeSignature.fourFour,
          notes: bars,
        );
    return MultiPartScore([
      part(
          Clef.treble,
          'd5:q b4 g4 b4 | c5:q e5 g5 e5 | '
          'd5:h g5:h | a5:q g5 f#5 e5'),
      part(
          Clef.treble,
          'g4:q g4 d4 g4 | e4:q g4 c5 g4 | '
          'b4:h b4:h | c5:q b4 a4 g4'),
      part(
          Clef.alto,
          'b3:q d4 b3 d4 | g3:q c4 e4 c4 | '
          'g3:h d4:h | e4:q d4 c4 b3'),
      part(
          Clef.bass,
          'g2:q g2 g2 g2 | c3:q c3 c3 c3 | '
          'g2:h g2:h | a2:q b2 c3 c2'),
    ], brackets: const [
      StaffBracket(0, 3)
    ], barlineGroups: const [
      BarlineGroup(0, 1),
      BarlineGroup(2, 3),
    ]);
  }

  testWidgets('sizes to the page box and paginates the parts', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: MultiPartView(
            document: quartet(),
            metrics: const PageMetrics(width: 70, height: 80),
            staffSpace: 6,
          ),
        ),
      ),
    ));
    final render =
        tester.renderObject<RenderMultiPartView>(find.byType(MultiPartView));
    expect(render.size.width, 70 * 6);
    expect(render.size.height, 80 * 6);
    expect(render.pageCount, greaterThanOrEqualTo(1));
    // Every system carries all four parts and both barline groups.
    final page = render.pagedLayout!.pages.first;
    expect(page.systems, isNotEmpty);
    for (final placed in page.systems) {
      expect(placed.system.parts, hasLength(4));
      expect(placed.system.barlineSpans, hasLength(2));
    }
  });

  testWidgets('changing the page index only repaints', (tester) async {
    // A short page forces multiple pages.
    Widget build(int page) => MaterialApp(
          home: Scaffold(
            body: MultiPartView(
              document: quartet(),
              metrics: const PageMetrics(width: 60, height: 40),
              staffSpace: 6,
              pageIndex: page,
            ),
          ),
        );
    await tester.pumpWidget(build(0));
    final render =
        tester.renderObject<RenderMultiPartView>(find.byType(MultiPartView));
    final pages = render.pageCount;
    expect(pages, greaterThan(1));
    await tester.pumpWidget(build(1));
    expect(render.pageIndex, 1);
    expect(render.pageCount, pages); // no relayout
  });

  testWidgets('120 orchestral system: bracket + two barline groups',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: MultiPartView(
                  document: quartet(),
                  metrics: const PageMetrics(width: 64, height: 60),
                  staffSpace: 8,
                  staffGap: 5,
                  systemGap: 10,
                  drawPageBorder: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(RepaintBoundary).last,
      matchesGoldenFile('goldens/120_multi_part_document.png'),
    );
  });
}
