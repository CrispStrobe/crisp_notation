import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

late final LayoutSettings settings;

/// Whether [part] is all rests across measures [start]..[end] — the same
/// silence test the layout uses to hide a staff.
bool _silent(Score part, int start, int end) {
  for (var i = start; i <= end; i++) {
    final measure = part.measures[i];
    if (measure.multiRest != null) continue;
    for (final e in [...measure.elements, ...measure.voice2]) {
      if (e is! RestElement) return false;
    }
  }
  return true;
}

void main() {
  setUpAll(() {
    final meta = SmuflMetadata.fromJson(jsonDecode(
        File('../partitura/assets/smufl/bravura_metadata.json')
            .readAsStringSync()) as Map<String, Object?>);
    settings = LayoutSettings(metadata: meta);
  });

  MultiPartScore quartet() => MultiPartScore([
        Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5 | g5:h a5:h'),
        Score.simple(clef: Clef.treble, notes: 'g4:q g4 g4 g4 | b4:h c5:h'),
        Score.simple(clef: Clef.alto, notes: 'e4:q f4 g4 a4 | d4:h e4:h'),
        Score.simple(clef: Clef.bass, notes: 'c3:q b2 a2 g2 | g2:h c3:h'),
      ], brackets: const [
        StaffBracket(0, 3)
      ], barlineGroups: const [
        BarlineGroup(0, 1),
        BarlineGroup(2, 3),
      ]);

  group('BarlineGroup', () {
    test('contains is inclusive of both ends', () {
      const g = BarlineGroup(1, 3);
      expect(g.contains(0), isFalse);
      expect(g.contains(1), isTrue);
      expect(g.contains(2), isTrue);
      expect(g.contains(3), isTrue);
      expect(g.contains(4), isFalse);
    });

    test('value semantics', () {
      expect(const BarlineGroup(0, 2), const BarlineGroup(0, 2));
      expect(
          const BarlineGroup(0, 2).hashCode, const BarlineGroup(0, 2).hashCode);
      expect(const BarlineGroup(0, 2), isNot(const BarlineGroup(0, 3)));
    });

    test('a single-part group is valid', () {
      expect(const BarlineGroup(2, 2).contains(2), isTrue);
    });
  });

  group('MultiPartScore', () {
    test('exposes its parts and shared measure count', () {
      final doc = quartet();
      expect(doc.parts, hasLength(4));
      expect(doc.measureCount, 2);
    });

    test('effectiveBarlineGroups returns the explicit groups when given', () {
      expect(quartet().effectiveBarlineGroups,
          const [BarlineGroup(0, 1), BarlineGroup(2, 3)]);
    });

    test('effectiveBarlineGroups defaults to one group over all parts', () {
      final doc = MultiPartScore([
        Score.simple(notes: 'c4:w'),
        Score.simple(clef: Clef.bass, notes: 'c3:w'),
        Score.simple(clef: Clef.bass, notes: 'c2:w'),
      ]);
      expect(doc.barlineGroups, isEmpty);
      expect(doc.effectiveBarlineGroups, const [BarlineGroup(0, 2)]);
    });

    test('atConcertPitch transposes each part and preserves grouping', () {
      final clarinet = Score.simple(notes: 'd5:w');
      final written = MultiPartScore([
        // A B-flat clarinet: written a major second above sounding.
        Score(
          clef: clarinet.clef,
          measures: clarinet.measures,
          transposition: Transposition.bFlat,
        ),
        Score.simple(clef: Clef.bass, notes: 'c3:w'),
      ], brackets: const [
        StaffBracket(0, 1)
      ], barlineGroups: const [
        BarlineGroup(0, 1)
      ]);
      final concert = written.atConcertPitch();
      // The transposing part sounds a major second lower (d5 -> c5).
      expect(concert.parts.first, written.parts.first.atConcertPitch());
      expect(concert.parts.first.transposition, isNull);
      // The non-transposing part is unchanged.
      expect(concert.parts[1], written.parts[1]);
      // Grouping metadata is carried through.
      expect(concert.brackets, written.brackets);
      expect(concert.barlineGroups, written.barlineGroups);
    });

    test('value semantics', () {
      MultiPartScore make() => MultiPartScore([
            Score.simple(notes: 'c4:w'),
            Score.simple(clef: Clef.bass, notes: 'c3:w'),
          ], brackets: const [
            StaffBracket(0, 1, kind: StaffBracketKind.brace)
          ], barlineGroups: const [
            BarlineGroup(0, 1)
          ]);
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
      // Differing barline grouping breaks equality.
      final other = MultiPartScore([
        Score.simple(notes: 'c4:w'),
        Score.simple(clef: Clef.bass, notes: 'c3:w'),
      ], brackets: const [
        StaffBracket(0, 1, kind: StaffBracketKind.brace)
      ]);
      expect(make(), isNot(other));
    });

    test('toString names the part count', () {
      expect(quartet().toString(), contains('4 parts'));
    });

    test('fromStaffSystem: connected barlines -> one group over all parts', () {
      final system = StaffSystem([
        Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5'),
        Score.simple(clef: Clef.bass, notes: 'c3:q d3 e3 f3'),
      ], brackets: const [
        StaffBracket(0, 1, kind: StaffBracketKind.brace)
      ]);
      final doc = MultiPartScore.fromStaffSystem(system);
      expect(doc.parts, system.staves);
      expect(doc.brackets, system.brackets);
      // connectBarlines defaults to true -> empty groups -> one over all.
      expect(doc.barlineGroups, isEmpty);
      expect(doc.effectiveBarlineGroups, const [BarlineGroup(0, 1)]);
    });

    test('fromStaffSystem: disconnected -> each part its own barline', () {
      final system = StaffSystem([
        Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5'),
        Score.simple(clef: Clef.treble, notes: 'e4:q f4 g4 a4'),
        Score.simple(clef: Clef.bass, notes: 'c3:q d3 e3 f3'),
      ], connectBarlines: false);
      final doc = MultiPartScore.fromStaffSystem(system);
      expect(doc.effectiveBarlineGroups,
          const [BarlineGroup(0, 0), BarlineGroup(1, 1), BarlineGroup(2, 2)]);
    });

    test('fromStaffSystem bridges an ABC import into a paginating document',
        () {
      final system = staffSystemFromAbc('X:1\nM:4/4\nL:1/4\n'
          'V:1 clef=treble\n'
          'V:2 clef=bass\n'
          'K:G\n'
          'V:1\n'
          'G A B c | d2 e2 | e d c B | A4 |\n'
          'V:2\n'
          'G,2 B,2 | C2 D2 | E2 C2 | D,4 |\n');
      final doc = MultiPartScore.fromStaffSystem(system);
      expect(doc.parts, hasLength(2));
      // It line-breaks and lays out with aligned barlines like any document.
      final multi = layoutMultiPartSystems(doc, settings, maxWidth: 45);
      expect(multi.systems.length, greaterThan(1));
      for (final s in multi.systems) {
        final ref = s.parts.first.measureRegions;
        for (final p in s.parts) {
          for (var i = 0; i < ref.length; i++) {
            expect(p.measureRegions[i].endX, closeTo(ref[i].endX, 1e-6));
          }
        }
      }
    });
  });

  group('layoutMultiPartSystem', () {
    test('lays out one layout per part', () {
      final layout = layoutMultiPartSystem(quartet(), settings);
      expect(layout.parts, hasLength(4));
      expect(layout.firstMeasure, 0);
      expect(layout.lastMeasure, 1); // two measures
    });

    test('all parts share the total width (aligned)', () {
      final layout = layoutMultiPartSystem(quartet(), settings);
      final w = layout.parts.first.width;
      for (final p in layout.parts) {
        expect(p.width, closeTo(w, 1e-9));
      }
    });

    test('barlines align: every measure column matches across parts', () {
      final layout = layoutMultiPartSystem(quartet(), settings);
      final ref = layout.parts.first.measureRegions;
      for (final p in layout.parts) {
        for (var i = 0; i < ref.length; i++) {
          expect(p.measureRegions[i].startX, closeTo(ref[i].startX, 1e-6));
          expect(p.measureRegions[i].endX, closeTo(ref[i].endX, 1e-6));
        }
      }
    });

    test('barline x positions are identical across parts', () {
      final layout = layoutMultiPartSystem(quartet(), settings);
      final xs = layout.barlineXs;
      // At least the left system line, an interior barline and the closing one.
      expect(xs.length, greaterThanOrEqualTo(3));
      expect(xs.first, 0.0);
      // Reading the full-staff vertical lines off any other part gives the
      // same set (the parts share their measure widths).
      List<double> partXs(int i) {
        final s = <double>{0.0};
        for (final line
            in layout.parts[i].primitives.whereType<LinePrimitive>()) {
          final vertical = line.from.x == line.to.x;
          final full = (line.from.y == 0 && line.to.y == 4) ||
              (line.from.y == 4 && line.to.y == 0);
          if (vertical && full) s.add(line.from.x);
        }
        return s.toList()..sort();
      }

      for (var i = 1; i < layout.parts.length; i++) {
        expect(partXs(i), orderedEquals(xs));
      }
    });

    test('two barline groups: the barline breaks between the groups', () {
      final layout = layoutMultiPartSystem(quartet(), settings, staffGap: 4);
      final spans = layout.barlineSpans;
      expect(spans, hasLength(2));
      // Group 0 spans parts 0..1; group 1 spans parts 2..3.
      expect(spans[0].group, const BarlineGroup(0, 1));
      expect(spans[1].group, const BarlineGroup(2, 3));
      // Group 0 bottom is the y=4 line of part 1; group 1 top is part 2's top.
      expect(spans[0].top, layout.staffTop(0));
      expect(spans[0].bottom, layout.staffTop(1) + 4);
      expect(spans[1].top, layout.staffTop(2));
      expect(spans[1].bottom, layout.staffTop(3) + 4);
      // There is a real gap (of staffGap) — the barline is broken, not
      // continuous through the whole system.
      expect(spans[0].bottom, lessThan(spans[1].top));
      expect(spans[1].top - spans[0].bottom, closeTo(4, 1e-9)); // staffGap
    });

    test('no groups: one continuous barline over all parts', () {
      final doc = MultiPartScore([
        Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5'),
        Score.simple(clef: Clef.bass, notes: 'c3:q d3 e3 f3'),
        Score.simple(clef: Clef.bass, notes: 'c2:q d2 e2 f2'),
      ]);
      final layout = layoutMultiPartSystem(doc, settings);
      final spans = layout.barlineSpans;
      expect(spans, hasLength(1));
      expect(spans.first.group, const BarlineGroup(0, 2));
      expect(spans.first.top, layout.staffTop(0));
      expect(spans.first.bottom, layout.staffTop(2) + 4);
    });

    test('parts must agree on measure count', () {
      final bad = MultiPartScore([
        Score.simple(notes: 'c4:q d4 e4 f4'),
        Score.simple(notes: 'c4:w | d4:w'), // 2 measures vs 1
      ]);
      expect(() => layoutMultiPartSystem(bad, settings), throwsArgumentError);
    });

    test('parts stack by 4 + staffGap and the system has positive height', () {
      final layout = layoutMultiPartSystem(quartet(), settings, staffGap: 5);
      expect(layout.staffTop(0), 0);
      expect(layout.staffTop(1), 9); // 4 + 5
      expect(layout.staffTop(3), 27);
      expect(layout.top, lessThan(0));
      expect(layout.height, greaterThan(27));
    });

    test('justifyToWidth stretches every part to fill and keeps alignment', () {
      final natural = layoutMultiPartSystem(quartet(), settings);
      final target = natural.width + 20;
      final justified =
          layoutMultiPartSystem(quartet(), settings, justifyToWidth: target);
      expect(justified.width, closeTo(target, 0.1));
      // All parts still share the (now wider) total width.
      for (final p in justified.parts) {
        expect(p.width, closeTo(justified.width, 1e-6));
      }
      // Barlines still align across parts after stretching.
      final ref = justified.parts.first.measureRegions;
      for (final p in justified.parts) {
        for (var i = 0; i < ref.length; i++) {
          expect(p.measureRegions[i].endX, closeTo(ref[i].endX, 1e-6));
        }
      }
    });
  });

  // A long single-line-per-part document that must break into several systems.
  MultiPartScore longDuet() {
    final bars = List.generate(8, (i) => 'c5:q d5 e5 f5').join(' | ');
    final low = List.generate(8, (i) => 'c3:q d3 e3 f3').join(' | ');
    return MultiPartScore([
      Score.simple(
          clef: Clef.treble,
          timeSignature: TimeSignature.fourFour,
          notes: bars),
      Score.simple(
          clef: Clef.bass, timeSignature: TimeSignature.fourFour, notes: low),
    ], brackets: const [
      StaffBracket(0, 1)
    ]);
  }

  group('layoutMultiPartSystems', () {
    test('breaks the document into several systems', () {
      final multi = layoutMultiPartSystems(longDuet(), settings, maxWidth: 60);
      expect(multi.systems.length, greaterThan(1));
      expect(multi.maxWidth, 60);
    });

    test('systems cover every measure once, contiguously, in order', () {
      final multi = layoutMultiPartSystems(longDuet(), settings, maxWidth: 60);
      expect(multi.systems.first.firstMeasure, 0);
      expect(multi.systems.last.lastMeasure, 7);
      for (var i = 1; i < multi.systems.length; i++) {
        expect(multi.systems[i].firstMeasure,
            multi.systems[i - 1].lastMeasure + 1);
      }
    });

    test('every system spans the same measure range across all parts', () {
      final multi = layoutMultiPartSystems(longDuet(), settings, maxWidth: 60);
      for (final system in multi.systems) {
        final bars = system.lastMeasure - system.firstMeasure + 1;
        for (final part in system.parts) {
          expect(part.measureRegions, hasLength(bars));
        }
        // And barlines align within the system.
        final ref = system.parts.first.measureRegions;
        for (final part in system.parts) {
          for (var i = 0; i < ref.length; i++) {
            expect(part.measureRegions[i].endX, closeTo(ref[i].endX, 1e-6));
          }
        }
      }
    });

    test('non-final systems are justified to maxWidth; the last is not', () {
      final multi = layoutMultiPartSystems(longDuet(), settings, maxWidth: 60);
      for (var i = 0; i < multi.systems.length - 1; i++) {
        expect(multi.systems[i].width, closeTo(60, 0.5),
            reason: 'system $i should fill the width');
      }
      expect(multi.systems.last.width, lessThanOrEqualTo(60 + 1e-6));
    });

    test('justify: false leaves systems at their natural width', () {
      final multi = layoutMultiPartSystems(longDuet(), settings,
          maxWidth: 60, justify: false);
      for (final system in multi.systems) {
        expect(system.width, lessThanOrEqualTo(60 + 1e-6));
      }
      // At least one interior system is narrower than the full width.
      expect(
          multi.systems.take(multi.systems.length - 1).any((s) => s.width < 59),
          isTrue);
    });

    test('a non-positive maxWidth is rejected', () {
      expect(() => layoutMultiPartSystems(longDuet(), settings, maxWidth: 0),
          throwsArgumentError);
    });

    test('parts must agree on measure count', () {
      final bad = MultiPartScore([
        Score.simple(notes: 'c4:q d4 e4 f4'),
        Score.simple(notes: 'c4:w | d4:w'),
      ]);
      expect(() => layoutMultiPartSystems(bad, settings, maxWidth: 60),
          throwsArgumentError);
    });

    test('visibleParts defaults to every part', () {
      final multi = layoutMultiPartSystems(longDuet(), settings, maxWidth: 60);
      for (final system in multi.systems) {
        expect(system.visibleParts, [0, 1]);
      }
    });
  });

  // A 6-bar, 3-part document whose middle part is silent after the first bar.
  MultiPartScore silentMiddle() {
    Score voice(String notes, Clef clef) => Score.simple(
        clef: clef, timeSignature: TimeSignature.fourFour, notes: notes);
    return MultiPartScore([
      voice(List.filled(6, 'c5:q d5 e5 f5').join(' | '), Clef.treble),
      // Middle: plays bar 0, then five bars of rest.
      voice(['g4:q g4 g4 g4', 'r:w', 'r:w', 'r:w', 'r:w', 'r:w'].join(' | '),
          Clef.treble),
      voice(List.filled(6, 'c3:q d3 e3 f3').join(' | '), Clef.bass),
    ], brackets: const [
      StaffBracket(0, 2)
    ]);
  }

  group('hide-empty staves', () {
    test('off by default: every system keeps all parts', () {
      final multi = layoutMultiPartSystems(silentMiddle(), settings,
          maxWidth: 30); // small -> many systems
      for (final system in multi.systems) {
        expect(system.visibleParts, [0, 1, 2]);
      }
    });

    test('the first system always shows every part', () {
      final multi = layoutMultiPartSystems(silentMiddle(), settings,
          maxWidth: 30, hideEmptyStaves: true);
      expect(multi.systems.first.firstMeasure, 0);
      expect(multi.systems.first.visibleParts, [0, 1, 2]);
    });

    test('a silent part is dropped from a later system', () {
      final multi = layoutMultiPartSystems(silentMiddle(), settings,
          maxWidth: 30, hideEmptyStaves: true);
      // Some later system drops the (silent) middle part.
      final hidden =
          multi.systems.where((s) => s.visibleParts.length < 3).toList();
      expect(hidden, isNotEmpty);
      for (final system in hidden) {
        expect(system.visibleParts, [0, 2]); // middle gone
        expect(system.parts, hasLength(2));
        // Every measure of the dropped range really is silent for part 1.
        expect(
            _silent(silentMiddle().parts[1], system.firstMeasure,
                system.lastMeasure),
            isTrue);
      }
    });

    test('a dropped part is removed from the stack geometry', () {
      final multi = layoutMultiPartSystems(silentMiddle(), settings,
          maxWidth: 30, hideEmptyStaves: true);
      final two = multi.systems.firstWhere((s) => s.visibleParts.length == 2);
      // Two staves stacked -> the second sits one staff+gap below the first.
      expect(two.staffTop(0), 0);
      expect(two.staffTop(1), 4 + two.staffGap);
      // The default barline group (0..2) clips to the two visible parts.
      final spans = two.barlineSpans;
      expect(spans, hasLength(1));
      expect(spans.first.top, two.staffTop(0));
      expect(spans.first.bottom, two.staffTop(1) + 4);
      // visibleRange remaps original indices to visible positions.
      expect(two.visibleRange(0, 2), (first: 0, last: 1));
      expect(two.visibleRange(1, 1), isNull); // the hidden middle
      expect(two.visibleRange(2, 2), (first: 1, last: 1));
    });

    test('a fully-silent system keeps all its parts (never blank)', () {
      // Both parts rest in bar 1; that system must not drop everything.
      final doc = MultiPartScore([
        Score.simple(
            timeSignature: TimeSignature.fourFour,
            notes: 'c5:q d5 e5 f5 | r:w | g5:q a5 b5 c6'),
        Score.simple(
            clef: Clef.bass,
            timeSignature: TimeSignature.fourFour,
            notes: 'c3:q d3 e3 f3 | r:w | g3:q a3 b3 c4'),
      ]);
      final multi = layoutMultiPartSystems(doc, settings,
          maxWidth: 26, hideEmptyStaves: true);
      for (final system in multi.systems) {
        expect(system.visibleParts, isNotEmpty);
        // The all-rest bar keeps both staves rather than vanishing.
        if (system.firstMeasure <= 1 && system.lastMeasure >= 1) {
          expect(system.visibleParts, [0, 1]);
        }
      }
    });

    test('pagination forwards hideEmptyStaves', () {
      final paged = layoutMultiPartPages(silentMiddle(), settings,
          metrics: const PageMetrics(width: 34, height: 80),
          hideEmptyStaves: true);
      final all = [
        for (final page in paged.pages)
          for (final s in page.systems) s.system,
      ];
      expect(all.any((s) => s.visibleParts.length < 3), isTrue);
    });
  });

  group('layoutMultiPartPages', () {
    test('paginates the systems into pages of the given box', () {
      final paged = layoutMultiPartPages(longDuet(), settings,
          metrics: const PageMetrics(width: 70, height: 40), systemGap: 6);
      expect(paged.pages, isNotEmpty);
      expect(paged.systemWidth, closeTo(70 - 16, 1e-9)); // width - 2*8 margins
      // No page overflows the content height.
      for (final page in paged.pages) {
        final content = page.systems.isEmpty
            ? 0.0
            : page.systems.last.top + page.systems.last.system.height;
        expect(content, lessThanOrEqualTo(40 - 16 + 1e-6));
      }
    });

    test('every system lands on exactly one page, in order', () {
      final metrics = const PageMetrics(width: 70, height: 40);
      final multi = layoutMultiPartSystems(longDuet(), settings,
          maxWidth: metrics.contentWidth);
      final paged =
          layoutMultiPartPages(longDuet(), settings, metrics: metrics);
      final placed = [
        for (final page in paged.pages)
          for (final s in page.systems) s.system.firstMeasure,
      ];
      expect(placed, [for (final s in multi.systems) s.firstMeasure]);
    });

    test('a taller-than-page system still gets its own page', () {
      // A tall four-part system into a short page: one system per page, never
      // dropped.
      final paged = layoutMultiPartPages(
        MultiPartScore([
          Score.simple(clef: Clef.treble, notes: 'c5:w | d5:w'),
          Score.simple(clef: Clef.treble, notes: 'g4:w | a4:w'),
          Score.simple(clef: Clef.bass, notes: 'c3:w | d3:w'),
          Score.simple(clef: Clef.bass, notes: 'c2:w | d2:w'),
        ]),
        settings,
        metrics: const PageMetrics(width: 80, height: 20),
      );
      expect(paged.pages, isNotEmpty);
      for (final page in paged.pages) {
        expect(page.systems, isNotEmpty);
      }
    });
  });
}
