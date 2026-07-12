import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Phase 2.5: pagination — grouping broken systems into pages with margins
/// and vertical justification.
void main() {
  late final LayoutSettings settings;
  setUpAll(() {
    final meta = SmuflMetadata.fromJson(jsonDecode(
        File('../partitura/assets/smufl/bravura_metadata.json')
            .readAsStringSync()) as Map<String, Object?>);
    settings = LayoutSettings(metadata: meta);
  });

  // A score with `count` identical bars — long enough to break into systems.
  Score longScore(int count) => Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: List.filled(count, 'c5:q d5 e5 f5').join(' | '),
      );

  test('PageMetrics content box excludes the margins', () {
    const m = PageMetrics(
        width: 100, height: 140, marginLeft: 8, marginRight: 8, marginTop: 10);
    expect(m.contentWidth, 100 - 16);
    expect(m.contentHeight, 140 - 10 - 8);
  });

  test('a short score is a single page', () {
    final paged = layoutPages(longScore(4), settings,
        metrics: const PageMetrics(width: 120, height: 160));
    expect(paged.pages, hasLength(1));
    expect(paged.pages.single.systems, isNotEmpty);
    expect(paged.pages.single.systems.first.top, 0);
  });

  test('systems break across pages when the content height is small', () {
    const metrics = PageMetrics(
        width: 80,
        height: 40,
        marginTop: 4,
        marginBottom: 4,
        marginLeft: 4,
        marginRight: 4);
    final paged =
        layoutPages(longScore(24), settings, metrics: metrics, systemGap: 6);
    // More than one page, and every system fits within the content height.
    expect(paged.pages.length, greaterThan(1));
    for (final page in paged.pages) {
      for (final placed in page.systems) {
        expect(placed.top + placed.system.layout.height,
            lessThanOrEqualTo(metrics.contentHeight + 0.001));
      }
    }
    // Every original system is placed exactly once.
    final placedCount =
        paged.pages.fold<int>(0, (n, p) => n + p.systems.length);
    final broken =
        layoutSystems(longScore(24), settings, maxWidth: metrics.contentWidth);
    expect(placedCount, broken.systems.length);
  });

  test('a justified page fills the content height', () {
    const metrics = PageMetrics(
        width: 80,
        height: 44,
        marginTop: 4,
        marginBottom: 4,
        marginLeft: 4,
        marginRight: 4);
    final paged =
        layoutPages(longScore(40), settings, metrics: metrics, systemGap: 4);
    // The first (non-last) page should be justified and reach the bottom.
    final firstPage = paged.pages.first;
    expect(paged.pages.length, greaterThan(1));
    expect(firstPage.justified, isTrue);
    expect(firstPage.systems.first.top, 0);
    final last = firstPage.systems.last;
    expect(last.top + last.system.layout.height,
        closeTo(metrics.contentHeight, 0.01));
  });

  test('the last page keeps natural spacing (not justified)', () {
    const metrics = PageMetrics(
        width: 80,
        height: 44,
        marginTop: 4,
        marginBottom: 4,
        marginLeft: 4,
        marginRight: 4);
    final paged =
        layoutPages(longScore(40), settings, metrics: metrics, systemGap: 5);
    final lastPage = paged.pages.last;
    expect(lastPage.justified, isFalse);
    if (lastPage.systems.length >= 2) {
      final gap = lastPage.systems[1].top -
          (lastPage.systems[0].top + lastPage.systems[0].system.layout.height);
      expect(gap, closeTo(5, 0.01)); // the natural systemGap
    }
  });

  test('justifyVertically: false leaves pages top-aligned at natural gap', () {
    const metrics = PageMetrics(
        width: 80,
        height: 44,
        marginTop: 4,
        marginBottom: 4,
        marginLeft: 4,
        marginRight: 4);
    final paged = layoutPages(longScore(40), settings,
        metrics: metrics, systemGap: 5, justifyVertically: false);
    expect(paged.pages.every((p) => !p.justified), isTrue);
  });

  test('a page never leaves fewer systems than it can hold empty', () {
    // Sanity: at least one system per page, always.
    const metrics = PageMetrics(
        width: 60,
        height: 20,
        marginTop: 2,
        marginBottom: 2,
        marginLeft: 2,
        marginRight: 2);
    final paged = layoutPages(longScore(6), settings, metrics: metrics);
    expect(paged.pages.every((p) => p.systems.isNotEmpty), isTrue);
  });
}
