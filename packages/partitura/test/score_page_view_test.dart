import 'package:flutter/material.dart' hide Step, PageMetrics;
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

import 'test_setup.dart';

void main() {
  setUpAll(setUpPartituraForTests);

  Score longScore() => Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: List.filled(20, 'c5:q d5 e5 f5').join(' | '),
      );

  testWidgets('sizes to the page box and paginates', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ScorePageView(
            score: longScore(),
            metrics: const PageMetrics(width: 60, height: 40),
            staffSpace: 8,
            systemGap: 6,
          ),
        ),
      ),
    ));
    final render =
        tester.renderObject<RenderScorePageView>(find.byType(ScorePageView));
    // Fixed page size: width × height in pixels.
    expect(render.size.width, 60 * 8);
    expect(render.size.height, 40 * 8);
    // A 20-bar score at this small page breaks into more than one page.
    expect(render.pageCount, greaterThan(1));
  });

  testWidgets('changing the page index only repaints', (tester) async {
    Widget build(int page) => MaterialApp(
          home: Scaffold(
            body: ScorePageView(
              score: longScore(),
              metrics: const PageMetrics(width: 60, height: 40),
              staffSpace: 8,
              pageIndex: page,
            ),
          ),
        );
    await tester.pumpWidget(build(0));
    final render =
        tester.renderObject<RenderScorePageView>(find.byType(ScorePageView));
    final pages = render.pageCount;
    expect(pages, greaterThan(1));
    await tester.pumpWidget(build(1));
    expect(render.pageIndex, 1);
    // Same layout object — page switch did not force a relayout.
    expect(render.pageCount, pages);
  });
}
