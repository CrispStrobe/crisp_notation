import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Cross-staff beams beyond the flat eighth-note case: slanted with the
/// contour, every beam level a duration asks for, beamlets, and a group that
/// runs across a barline. Plus opt-in per-level beam subdivision.
void main() {
  final settings = LayoutSettings(
      metadata: SmuflMetadata.fromJson(jsonDecode(
          File('../crisp_notation/assets/smufl/bravura_metadata.json')
              .readAsStringSync()) as Map<String, Object?>));

  NoteElement n(String id, Step s, int o, DurationBase d) => NoteElement(
      id: id, pitches: [Pitch(s, octave: o)], duration: NoteDuration(d));
  RestElement r(String id, DurationBase d) =>
      RestElement(NoteDuration(d), id: id);
  const s16 = DurationBase.sixteenth,
      e8 = DurationBase.eighth,
      q = DurationBase.quarter,
      h = DurationBase.half;

  /// A rising run: two 16ths on the lower staff, then 16th, 16th | 16th,
  /// eighth, 16th on the upper one — crossing the staves AND the barline.
  GrandStaffLayout rising() {
    final upper = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(2, 4),
      measures: [
        Measure([
          r('ur1', q),
          r('ur2', s16),
          r('ur3', s16),
          n('u1', Step.c, 4, s16),
          n('u2', Step.e, 4, s16),
        ]),
        Measure([
          n('u3', Step.g, 4, s16),
          n('u4', Step.c, 5, e8),
          n('u5', Step.e, 5, s16),
          r('ur4', q),
        ]),
      ],
    );
    final lower = Score(
      clef: Clef.bass,
      timeSignature: const TimeSignature(2, 4),
      measures: [
        Measure([
          r('lr0', q),
          n('l1', Step.c, 3, s16),
          n('l2', Step.e, 3, s16),
          r('lr1', e8),
        ]),
        Measure([r('lr2', h)]),
      ],
    );
    return layoutGrandStaff(
      GrandStaff(upper: upper, lower: lower, crossStaffBeams: const [
        CrossStaffBeam(['l1', 'l2', 'u1', 'u2', 'u3', 'u4', 'u5'])
      ]),
      settings,
    );
  }

  /// The cross-staff beams: appended last to the upper layout.
  List<BeamPrimitive> beamsOf(GrandStaffLayout l) =>
      l.upper.primitives.whereType<BeamPrimitive>().toList();

  test('a rising figure gets a rising beam, gently', () {
    final beams = beamsOf(rising());
    final primary = beams.reduce(
        (a, b) => (a.end.x - a.start.x) >= (b.end.x - b.start.x) ? a : b);
    // y grows downward: rising means the right end is higher (smaller y).
    expect(primary.end.y, lessThan(primary.start.y));
    // At most one space between the outer stems (the beam overhangs them by
    // half a stem's width).
    expect(primary.start.y - primary.end.y, lessThanOrEqualTo(1.02));
  });

  test('sixteenths get a second beam, and a lone sixteenth a beamlet', () {
    final beams = beamsOf(rising());
    // Primary + one secondary over l1..u3 + a beamlet on u5 (after the
    // eighth u4 breaks the secondary).
    expect(beams, hasLength(3));
    final widths = [for (final b in beams) b.end.x - b.start.x]..sort();
    expect(widths.first, closeTo(1.0 + settings.stemThickness / 2, 1e-6));
  });

  test('stems reach the farthest beam their note needs', () {
    final l = rising();
    final step = settings.beamThickness + settings.beamSpacing;
    final primary = beamsOf(l).first;
    double beamY(double x) =>
        primary.start.y +
        (primary.end.y - primary.start.y) *
            (x - primary.start.x) /
            (primary.end.x - primary.start.x);
    final stems = [
      for (final p in l.upper.primitives.whereType<LinePrimitive>())
        if (p.from.x == p.to.x && p.thickness == settings.stemThickness) p,
    ];
    // A 16th from the lower staff runs past the primary to the second beam;
    // a stem from the upper staff ends at the primary.
    final lowStem = l.lower.crossStaffStubs['l1']!;
    final fromBelow =
        stems.firstWhere((s) => (s.from.x - lowStem.stemX).abs() < 1e-9);
    expect(fromBelow.to.y, closeTo(beamY(lowStem.stemX) - step, 1e-6));
    final highStem = l.upper.crossStaffStubs['u1']!;
    final fromAbove =
        stems.firstWhere((s) => (s.from.x - highStem.stemX).abs() < 1e-9);
    expect(fromAbove.to.y, closeTo(beamY(highStem.stemX), 1e-6));
  });

  test('one beam runs across the barline', () {
    final l = rising();
    final barX = l.upper.measureRegions[0].endX;
    final primary = beamsOf(l).first;
    expect(primary.start.x, lessThan(barX));
    expect(primary.end.x, greaterThan(barX));
  });

  test('the slant stays capped even across the whole gap', () {
    final upper = Score(clef: Clef.treble, measures: [
      Measure([n('u', Step.c, 4, e8), r('ur', q), r('ur2', h)]),
    ]);
    final lower = Score(clef: Clef.bass, measures: [
      Measure([r('lr', e8), n('l', Step.c, 4, e8), r('lr2', h), r('lr3', e8)]),
    ]);
    final beams = beamsOf(layoutGrandStaff(
        GrandStaff(upper: upper, lower: lower, crossStaffBeams: const [
          CrossStaffBeam(['u', 'l'])
        ]),
        settings));
    // Middle C on both staves sits a gap apart, so the contour is the gap
    // itself; the slant follows it only by half, capped at one space.
    expect((beams.single.start.y - beams.single.end.y).abs(),
        lessThanOrEqualTo(1.02));
  });

  group('per-level subdivision (opt-in)', () {
    // One beat of eight 32nds in 4/4.
    final score = Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(4, 4),
      measures: [
        Measure([
          for (var i = 0; i < 8; i++)
            n('t$i', Step.values[i % 7], 5, DurationBase.thirtySecond),
          r('rest', DurationBase.half),
          r('rest2', q),
        ]),
      ],
    );
    int beamCount(LayoutSettings s) => const LayoutEngine()
        .layout(score, s)
        .primitives
        .whereType<BeamPrimitive>()
        .length;

    test('off: every level is continuous within the beat', () {
      expect(beamCount(settings), 3);
    });

    test('on: the 32nd beam breaks at the eighth', () {
      final split = LayoutSettings(
        metadata: settings.metadata,
        subdivideBeamsPerLevel: true,
      );
      expect(beamCount(split), 4);
    });
  });
}
