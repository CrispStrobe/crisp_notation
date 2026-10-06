import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Ossia and divisi: partial staves drawn only where they have music.
void main() {
  final settings = LayoutSettings(
      metadata: SmuflMetadata.fromJson(jsonDecode(
          File('../crisp_notation/assets/smufl/bravura_metadata.json')
              .readAsStringSync()) as Map<String, Object?>));

  NoteElement n(String id, Step step, {int octave = 4}) => NoteElement(
        id: id,
        pitches: [Pitch(step, octave: octave)],
        duration: NoteDuration.quarter,
      );

  Measure bar(String p, int b, {Step step = Step.c}) =>
      Measure([for (var i = 0; i < 4; i++) n('$p.$b.$i', step)]);

  Score part(String p, {int bars = 6}) => Score(
        clef: Clef.treble,
        timeSignature: const TimeSignature(4, 4),
        measures: [for (var b = 0; b < bars; b++) bar(p, b)],
      );

  final doc = MultiPartScore(
    [part('vn'), part('vc')],
    brackets: const [StaffBracket(0, 1)],
  );

  /// Staff lines: id-less horizontal lines at the five staff heights.
  List<LinePrimitive> staffLines(ScoreLayout l) => [
        for (final p in l.primitives.whereType<LinePrimitive>())
          if (p.elementId == null &&
              p.from.y == p.to.y &&
              const [0.0, 1.0, 2.0, 3.0, 4.0].contains(p.from.y) &&
              (p.to.x - p.from.x).abs() > 2)
            p,
      ];

  group('ossia', () {
    final ossia = doc.withOssia(0, 2, [
      bar('oss', 0, step: Step.e),
      bar('oss', 1, step: Step.g),
    ]);

    test('is a partial staff above its part', () {
      expect(ossia.parts, hasLength(3));
      expect(ossia.partialParts, {0});
      // The violin and cello keep their bracket; the ossia sits outside it.
      expect(ossia.brackets.single.first, 1);
      expect(ossia.brackets.single.last, 2);
      expect(ossia.parts[0].measures, hasLength(6));
    });

    test('draws staff lines and notes only over its own bars', () {
      final l = layoutStaffSystem(ossia.toStaffSystem(), settings);
      final staff = l.staves[0];
      final regions = staff.measureRegions;
      // The run spans bars 3-4, plus room for the clef in front.
      final lo = regions[2].startX - 6, hi = regions[3].endX + 1;
      final lines = staffLines(staff);
      expect(lines, hasLength(5), reason: 'one run, five lines');
      for (final line in lines) {
        expect(line.from.x, greaterThanOrEqualTo(lo));
        expect(line.to.x, lessThanOrEqualTo(hi));
      }
      // It opens with the staff's clef (set just before its first bar, where
      // its staff lines begin) and nothing else before that: no meter, none of
      // the rests of the bars it does not cover.
      final start = lines.first.from.x;
      final clefs = staff.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == 'gClef')
          .toList();
      expect(clefs, hasLength(1));
      expect(clefs.single.position.x, greaterThan(start));
      expect(clefs.single.position.x, lessThan(regions[2].startX));
      for (final g in staff.primitives.whereType<GlyphPrimitive>()) {
        expect(g.position.x, greaterThanOrEqualTo(start), reason: g.smuflName);
        expect(g.smuflName, isNot(startsWith('timeSig')));
        expect(g.smuflName, isNot(startsWith('rest')));
      }
      final ids = {for (final r in staff.regions) r.elementId};
      expect(ids, containsAll(['oss.0.0', 'oss.1.3']));
      expect(ids.where((id) => id.startsWith('ossia')), isEmpty);
    });

    test('its notes align with the staff it belongs to', () {
      final l = layoutStaffSystem(ossia.toStaffSystem(), settings);
      // Box centres: middle C's ledger line widens its box on both sides.
      double x(ScoreLayout s, String id) {
        final b = s.regions.firstWhere((r) => r.elementId == id).bounds;
        return b.left + b.width / 2;
      }

      expect(
          x(l.staves[0], 'oss.0.2'), closeTo(x(l.staves[1], 'vn.2.2'), 0.01));
    });

    test('systemic barlines leave it out', () {
      final l = layoutStaffSystem(ossia.toStaffSystem(), settings);
      final spans = l.barlineSpans;
      expect(spans, hasLength(1));
      expect(spans.single.top, l.staffTop(1));
      expect(spans.single.bottom, l.staffTop(2) + 4);
    });

    test('appears only on systems where it has music', () {
      final long = MultiPartScore([part('vn', bars: 24), part('vc', bars: 24)])
          .withOssia(0, 20, [bar('oss', 0, step: Step.a)]);
      final systems =
          layoutStaffSystemSystems(long.toStaffSystem(), settings, maxWidth: 60)
              .systems;
      expect(systems.length, greaterThan(2));
      for (final s in systems) {
        final has = s.firstMeasure <= 20 && 20 <= s.lastMeasure;
        expect(s.layout.staves.length, has ? 3 : 2,
            reason: 'bars ${s.firstMeasure}..${s.lastMeasure}');
      }
    });

    test('rejects bars outside the part', () {
      expect(() => doc.withOssia(0, 5, [bar('x', 0), bar('y', 0)]),
          throwsRangeError);
    });

    test('a page layout and an SVG render carry it', () {
      final pages = layoutMultiPartPages(ossia, settings,
          metrics: const PageMetrics(width: 120, height: 160));
      expect(pages.pages, isNotEmpty);
      final svg =
          staffSystemToSvg(layoutStaffSystem(ossia.toStaffSystem(), settings));
      expect(svg, contains('<svg'));
    });
  });

  group('divisi', () {
    // Bars 1 and 2 of the violin carry a second voice.
    final split = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        for (var b = 0; b < 4; b++)
          b == 1 || b == 2
              ? Measure(bar('up', b, step: Step.e).elements,
                  voice2: bar('lo', b, step: Step.c).elements)
              : bar('vn', b),
      ],
      slurs: const [Slur('lo.1.0', 'lo.1.3'), Slur('up.1.0', 'up.1.3')],
    );
    final divided =
        MultiPartScore([split, part('vc', bars: 4)]).withDivisi(0, {1, 2});

    test('moves the second voice onto a partial staff below', () {
      expect(divided.parts, hasLength(3));
      expect(divided.partialParts, {1});
      final upper = divided.parts[0], lower = divided.parts[1];
      expect(upper.measures[1].voice2, isEmpty);
      expect(upper.measures[1].elements.first.id, 'up.1.0');
      expect(lower.measures[1].elements.first.id, 'lo.1.0');
      expect(lower.measures[0].elements, everyElement(isA<RestElement>()));
      expect(upper.measures[0], split.measures[0]);
    });

    test('slurs travel with their notes', () {
      expect(divided.parts[0].slurs.single.startId, 'up.1.0');
      expect(divided.parts[1].slurs.single.startId, 'lo.1.0');
    });

    test('is drawn only over the divided bars', () {
      final l = layoutStaffSystem(divided.toStaffSystem(), settings);
      final staff = l.staves[1];
      final r = staff.measureRegions;
      for (final line in staffLines(staff)) {
        expect(line.from.x, greaterThanOrEqualTo(r[1].startX - 6));
        expect(line.to.x, lessThanOrEqualTo(r[2].endX + 1));
      }
    });
  });

  test('a partial staff survives MusicXML as an ossia staff type', () {
    final ossia = doc.withOssia(1, 1, [bar('oss', 0, step: Step.d)]);
    final xml = multiPartToMusicXml(ossia);
    expect(xml, contains('<staff-type>ossia</staff-type>'));
    final back = multiPartScoreFromMusicXml(xml);
    expect(back.partialParts, {1});
    expect(back.parts, hasLength(3));
  });

  test('a document without partial staves lays out as before', () {
    final a = layoutStaffSystem(doc.toStaffSystem(), settings);
    expect(a.staves.map(staffLines).map((l) => l.length), [5, 5]);
    expect(a.barlineSpans.single.top, 0);
  });
}
