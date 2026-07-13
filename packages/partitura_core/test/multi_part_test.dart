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
      expect(g.contains(3), isTrue);
      expect(g.contains(4), isFalse);
    });

    test('value semantics', () {
      expect(const BarlineGroup(0, 2), const BarlineGroup(0, 2));
      expect(
          const BarlineGroup(0, 2).hashCode, const BarlineGroup(0, 2).hashCode);
      expect(const BarlineGroup(0, 2), isNot(const BarlineGroup(0, 3)));
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
      expect(concert.parts.first, written.parts.first.atConcertPitch());
      expect(concert.parts.first.transposition, isNull);
      expect(concert.parts[1], written.parts[1]);
      expect(concert.brackets, written.brackets);
      expect(concert.barlineGroups, written.barlineGroups);
    });

    test('value semantics: differing barline grouping breaks equality', () {
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

    test('toStaffSystem carries parts, brackets and barline groups', () {
      final s = quartet().toStaffSystem();
      expect(s.staves, hasLength(4));
      expect(s.brackets, const [StaffBracket(0, 3)]);
      expect(s.barlineGroups, const [BarlineGroup(0, 1), BarlineGroup(2, 3)]);
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

    test('fromStaffSystem: explicit groups carry over', () {
      final system = StaffSystem([
        Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5'),
        Score.simple(clef: Clef.treble, notes: 'e4:q f4 g4 a4'),
        Score.simple(clef: Clef.bass, notes: 'c3:q d3 e3 f3'),
        Score.simple(clef: Clef.bass, notes: 'c2:q d2 e2 f2'),
      ], barlineGroups: const [
        BarlineGroup(0, 1),
        BarlineGroup(2, 3),
      ]);
      final doc = MultiPartScore.fromStaffSystem(system);
      expect(doc.effectiveBarlineGroups,
          const [BarlineGroup(0, 1), BarlineGroup(2, 3)]);
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
      final multi = layoutStaffSystemSystems(doc.toStaffSystem(), settings,
          maxWidth: 45);
      expect(multi.systems.length, greaterThan(1));
      for (final s in multi.systems) {
        final ref = s.layout.staves.first.measureRegions;
        for (final p in s.layout.staves) {
          for (var i = 0; i < ref.length; i++) {
            expect(p.measureRegions[i].endX, closeTo(ref[i].endX, 1e-6));
          }
        }
      }
    });
  });

  // One un-wrapped multi-part system via the layout primitive.
  StaffSystemLayout oneSystem(MultiPartScore doc, {double staffGap = 4}) =>
      layoutStaffSystem(doc.toStaffSystem(), settings, staffGap: staffGap);

  group('single multi-part system (layoutStaffSystem via toStaffSystem)', () {
    test('all parts share the total width (aligned)', () {
      final layout = oneSystem(quartet());
      final w = layout.staves.first.width;
      for (final p in layout.staves) {
        expect(p.width, closeTo(w, 1e-9));
      }
    });

    test('barlines align: every measure column matches across parts', () {
      final layout = oneSystem(quartet());
      final ref = layout.staves.first.measureRegions;
      for (final p in layout.staves) {
        for (var i = 0; i < ref.length; i++) {
          expect(p.measureRegions[i].startX, closeTo(ref[i].startX, 1e-6));
          expect(p.measureRegions[i].endX, closeTo(ref[i].endX, 1e-6));
        }
      }
    });

    test('barline x positions are identical across parts', () {
      final layout = oneSystem(quartet());
      final xs = layout.barlineXs;
      expect(xs.length, greaterThanOrEqualTo(3));
      expect(xs.first, 0.0);
    });

    test('two barline groups: the barline breaks between the groups', () {
      final layout = oneSystem(quartet(), staffGap: 4);
      final spans = layout.barlineSpans;
      expect(spans, hasLength(2));
      expect(spans[0].group, const BarlineGroup(0, 1));
      expect(spans[1].group, const BarlineGroup(2, 3));
      expect(spans[0].top, layout.staffTop(0));
      expect(spans[0].bottom, layout.staffTop(1) + 4);
      expect(spans[1].top, layout.staffTop(2));
      expect(spans[1].bottom, layout.staffTop(3) + 4);
      // A real gap (of staffGap) — the barline is broken, not continuous.
      expect(spans[0].bottom, lessThan(spans[1].top));
      expect(spans[1].top - spans[0].bottom, closeTo(4, 1e-9));
    });

    test('no groups: one continuous barline over all parts', () {
      final doc = MultiPartScore([
        Score.simple(clef: Clef.treble, notes: 'c5:q d5 e5 f5'),
        Score.simple(clef: Clef.bass, notes: 'c3:q d3 e3 f3'),
        Score.simple(clef: Clef.bass, notes: 'c2:q d2 e2 f2'),
      ]);
      final layout = oneSystem(doc);
      final spans = layout.barlineSpans;
      expect(spans, hasLength(1));
      expect(spans.first.group, const BarlineGroup(0, 2));
      expect(spans.first.top, layout.staffTop(0));
      expect(spans.first.bottom, layout.staffTop(2) + 4);
    });

    test('parts stack by 4 + staffGap and the system has positive height', () {
      final layout = oneSystem(quartet(), staffGap: 5);
      expect(layout.staffTop(0), 0);
      expect(layout.staffTop(1), 9); // 4 + 5
      expect(layout.staffTop(3), 27);
      expect(layout.top, lessThan(0));
      expect(layout.height, greaterThan(27));
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

  group('layoutStaffSystemSystems (document line-breaking)', () {
    StaffSystemSystems wrap(MultiPartScore doc,
            {double maxWidth = 60,
            bool justify = true,
            bool hideEmptyStaves = false}) =>
        layoutStaffSystemSystems(doc.toStaffSystem(), settings,
            maxWidth: maxWidth,
            justify: justify,
            hideEmptyStaves: hideEmptyStaves);

    test('systems cover every measure once, contiguously, in order', () {
      final multi = wrap(longDuet());
      expect(multi.systems.length, greaterThan(1));
      expect(multi.systems.first.firstMeasure, 0);
      expect(multi.systems.last.lastMeasure, 7);
      for (var i = 1; i < multi.systems.length; i++) {
        expect(multi.systems[i].firstMeasure,
            multi.systems[i - 1].lastMeasure + 1);
      }
    });

    test('every system spans the same measure range across all parts', () {
      final multi = wrap(longDuet());
      for (final system in multi.systems) {
        final bars = system.lastMeasure - system.firstMeasure + 1;
        for (final part in system.layout.staves) {
          expect(part.measureRegions, hasLength(bars));
        }
        final ref = system.layout.staves.first.measureRegions;
        for (final part in system.layout.staves) {
          for (var i = 0; i < ref.length; i++) {
            expect(part.measureRegions[i].endX, closeTo(ref[i].endX, 1e-6));
          }
        }
      }
    });

    test('non-final systems are justified to maxWidth; the last is not', () {
      final multi = wrap(longDuet());
      for (var i = 0; i < multi.systems.length - 1; i++) {
        expect(multi.systems[i].layout.width, closeTo(60, 0.5));
      }
      expect(multi.systems.last.layout.width, lessThanOrEqualTo(60 + 1e-6));
    });
  });

  // A 6-bar, 3-part document whose middle part is silent after the first bar.
  MultiPartScore silentMiddle() {
    Score voice(String notes, Clef clef) => Score.simple(
        clef: clef, timeSignature: TimeSignature.fourFour, notes: notes);
    return MultiPartScore([
      voice(List.filled(6, 'c5:q d5 e5 f5').join(' | '), Clef.treble),
      voice(['g4:q g4 g4 g4', 'r:w', 'r:w', 'r:w', 'r:w', 'r:w'].join(' | '),
          Clef.treble),
      voice(List.filled(6, 'c3:q d3 e3 f3').join(' | '), Clef.bass),
    ], brackets: const [
      StaffBracket(0, 2)
    ]);
  }

  group('hide-empty staves', () {
    test('off by default: every system keeps all parts', () {
      final multi = layoutStaffSystemSystems(
          silentMiddle().toStaffSystem(), settings,
          maxWidth: 30);
      for (final system in multi.systems) {
        expect(system.layout.staves, hasLength(3));
      }
    });

    test('the first system always shows every part', () {
      final multi = layoutStaffSystemSystems(
          silentMiddle().toStaffSystem(), settings,
          maxWidth: 30, hideEmptyStaves: true);
      expect(multi.systems.first.firstMeasure, 0);
      expect(multi.systems.first.layout.staves, hasLength(3));
    });

    test('a silent part is dropped from a later system', () {
      final multi = layoutStaffSystemSystems(
          silentMiddle().toStaffSystem(), settings,
          maxWidth: 30, hideEmptyStaves: true);
      final hidden =
          multi.systems.where((s) => s.layout.staves.length < 3).toList();
      expect(hidden, isNotEmpty);
      for (final system in hidden) {
        expect(system.layout.staves, hasLength(2));
        // The dropped range really is silent for the middle part.
        expect(
            _silent(silentMiddle().parts[1], system.firstMeasure,
                system.lastMeasure),
            isTrue);
        // The default barline group clips to the two surviving staves.
        final spans = system.layout.barlineSpans;
        expect(spans, hasLength(1));
        expect(spans.first.top, system.layout.staffTop(0));
        expect(spans.first.bottom, system.layout.staffTop(1) + 4);
      }
    });

    test('a fully-silent system keeps all its parts (never blank)', () {
      final doc = MultiPartScore([
        Score.simple(
            timeSignature: TimeSignature.fourFour,
            notes: 'c5:q d5 e5 f5 | r:w | g5:q a5 b5 c6'),
        Score.simple(
            clef: Clef.bass,
            timeSignature: TimeSignature.fourFour,
            notes: 'c3:q d3 e3 f3 | r:w | g3:q a3 b3 c4'),
      ]);
      final multi = layoutStaffSystemSystems(doc.toStaffSystem(), settings,
          maxWidth: 26, hideEmptyStaves: true);
      for (final system in multi.systems) {
        expect(system.layout.staves, isNotEmpty);
        if (system.firstMeasure <= 1 && system.lastMeasure >= 1) {
          expect(system.layout.staves, hasLength(2));
        }
      }
    });
  });

  group('layoutMultiPartPages', () {
    test('paginates the systems into pages of the given box', () {
      final paged = layoutMultiPartPages(longDuet(), settings,
          metrics: const PageMetrics(width: 70, height: 40), systemGap: 6);
      expect(paged.pages, isNotEmpty);
      expect(paged.systemWidth, closeTo(70 - 16, 1e-9)); // width - 2*8 margins
      for (final page in paged.pages) {
        final content = page.systems.isEmpty
            ? 0.0
            : page.systems.last.top + page.systems.last.system.layout.height;
        expect(content, lessThanOrEqualTo(40 - 16 + 1e-6));
      }
    });

    test('every system lands on exactly one page, in order', () {
      const metrics = PageMetrics(width: 70, height: 40);
      final multi = layoutStaffSystemSystems(longDuet().toStaffSystem(),
          settings,
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

    test('pagination forwards hideEmptyStaves', () {
      final paged = layoutMultiPartPages(silentMiddle(), settings,
          metrics: const PageMetrics(width: 34, height: 80),
          hideEmptyStaves: true);
      final all = [
        for (final page in paged.pages)
          for (final s in page.systems) s.system,
      ];
      expect(all.any((s) => s.layout.staves.length < 3), isTrue);
    });
  });
}
