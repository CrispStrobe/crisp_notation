/// Grand staff (system) layout: two staves with aligned measures.
library;

import 'dart:math';

import '../model/score.dart';
import '../theory/fraction.dart';
import 'layout_engine.dart';
import 'layout_settings.dart';
import 'score_layout.dart';

/// Cross-staff onset gridding (§2.9): shared per-measure column positions
/// (onset → the **notehead** x from the measure's content start) that align
/// simultaneous notes across [staves], which must share measures (all voices
/// participate). Feed the result to `LayoutEngine.layout`'s `forcedColumns` for
/// every staff so their noteheads land on the same columns and accidentals
/// extend left. Column gaps are the optical time-spacing, floored so one
/// column's right ink (notehead/stem/dots) never collides with the next
/// column's left ink (accidental).
List<Map<Fraction, double>> alignedColumns(
  List<Score> staves,
  LayoutSettings settings, {
  double spacingStretch = 1.0,
}) {
  if (staves.isEmpty) return const [];
  const engine = LayoutEngine();
  // Natural per-staff layouts give each element's ink split into the part left
  // of its notehead (accidental) and right of it (notehead/stem/dots), so the
  // column x can be the notehead position (accidental-aware).
  final ink = [
    for (final score in staves) _inkMetrics(engine.layout(score, settings))
  ];

  final measureCount = staves.first.measures.length;
  final result = <Map<Fraction, double>>[];
  for (var m = 0; m < measureCount; m++) {
    // The widest left/right ink at each onset, across all staves and voices
    // (voice 0 carries any tuplet adjustment; other voices use raw durations,
    // matching the engine's multi-voice onset arithmetic).
    final leftAt = <Fraction, double>{};
    final rightAt = <Fraction, double>{};
    var measureEnd = Fraction.zero;
    for (var si = 0; si < staves.length; si++) {
      final measure = staves[si].measures[m];
      final voices = measure.voices;
      for (var v = 0; v < voices.length; v++) {
        var onset = Fraction.zero;
        for (var i = 0; i < voices[v].length; i++) {
          final id = voices[v][i].id;
          final (l, r) = (id == null ? null : ink[si][id]) ?? (0.0, 1.0);
          leftAt[onset] = max(leftAt[onset] ?? 0.0, l);
          rightAt[onset] = max(rightAt[onset] ?? 0.0, r);
          onset += v == 0
              ? measure.effectiveDurationAt(i)
              : voices[v][i].duration.toFraction();
        }
        if (onset > measureEnd) measureEnd = onset;
      }
    }

    final onsets = leftAt.keys.toList()..sort((a, b) => a.compareTo(b));
    final columns = <Fraction, double>{};
    // The first column leaves room for its own left ink (accidental) after the
    // measure's content start.
    var x = onsets.isEmpty ? 0.0 : (leftAt[onsets.first] ?? 0.0);
    for (var k = 0; k < onsets.length; k++) {
      columns[onsets[k]] = x;
      final next = k + 1 < onsets.length ? onsets[k + 1] : measureEnd;
      final ideal =
          _idealAdvanceFor(next - onsets[k], settings, spacingStretch);
      // Never let this column's right ink collide with the next column's left
      // ink (its accidental).
      final nextLeft =
          k + 1 < onsets.length ? (leftAt[onsets[k + 1]] ?? 0.0) : 0.0;
      final collision =
          (rightAt[onsets[k]] ?? 0.0) + nextLeft + settings.minNoteGap;
      x += max(ideal, collision);
    }
    columns[measureEnd] = x; // the closing-barline column
    result.add(columns);
  }
  return result;
}

/// Per-element ink split `(left, right)` about its notehead x, from a natural
/// [layout]: left = accidental (notehead x − ink left), right = notehead/stem/
/// dots (ink right − notehead x). Rests (no notehead) anchor at their ink left.
Map<String, (double, double)> _inkMetrics(ScoreLayout layout) {
  final headX = <String, double>{};
  for (final primitive in layout.primitives) {
    if (primitive is GlyphPrimitive &&
        primitive.elementId != null &&
        primitive.smuflName.startsWith('notehead')) {
      headX.putIfAbsent(primitive.elementId!, () => primitive.position.x);
    }
  }
  final out = <String, (double, double)>{};
  for (final region in layout.regions) {
    final b = region.bounds;
    final anchor = headX[region.elementId] ?? b.left;
    out[region.elementId] = (anchor - b.left, b.right - anchor);
  }
  return out;
}

/// The optical time-based spacing for an onset gap of [delta] (mirrors the
/// engine's `_idealAdvance`).
double _idealAdvanceFor(Fraction delta, LayoutSettings s, double stretch) {
  if (delta.numerator <= 0) return 0;
  final log2Delta = log(delta.numerator / delta.denominator) / ln2;
  return (s.spacingBase + s.spacingPerLog2 * (4 + log2Delta)) * stretch;
}

/// A beam that spans both staves of a grand staff, joining notes written on
/// the [upper] and [lower] staves under one beam — the keyboard "cross-staff"
/// beam (e.g. a broken-chord figure that reaches from the bass staff up into
/// the treble). Lists the ids of the notes it beams; each note stays on the
/// staff it is written on. Upper-staff notes stem down toward the beam, lower-
/// staff notes stem up, and the beam is drawn between the staves.
///
/// The notes should be eighths or shorter (they carry a beam) and span both
/// staves; a group confined to one staff should use ordinary beaming instead.
class CrossStaffBeam {
  /// Ids of the notes joined by this beam, left to right.
  final List<String> noteIds;

  /// Creates a cross-staff beam over [noteIds].
  const CrossStaffBeam(this.noteIds);

  @override
  bool operator ==(Object other) =>
      other is CrossStaffBeam && _sameIds(other.noteIds, noteIds);

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(noteIds);

  @override
  String toString() => 'CrossStaffBeam($noteIds)';
}

/// Two scores stacked as one system — typically a treble [upper] and a
/// bass [lower] staff (piano/grand staff).
///
/// Element ids should be unique across both scores so interaction stays
/// unambiguous.
class GrandStaff {
  /// The upper staff.
  final Score upper;

  /// The lower staff.
  final Score lower;

  /// Beams that span both staves (keyboard cross-staff beams). Empty for an
  /// ordinary grand staff.
  final List<CrossStaffBeam> crossStaffBeams;

  /// Creates a grand staff.
  const GrandStaff({
    required this.upper,
    required this.lower,
    this.crossStaffBeams = const [],
  });

  @override
  bool operator ==(Object other) =>
      other is GrandStaff &&
      other.upper == upper &&
      other.lower == lower &&
      _sameBeams(other.crossStaffBeams, crossStaffBeams);

  static bool _sameBeams(List<CrossStaffBeam> a, List<CrossStaffBeam> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(upper, lower, Object.hashAll(crossStaffBeams));

  @override
  String toString() => 'GrandStaff($upper / $lower)';
}

/// The laid-out grand staff: both staff layouts share leading width,
/// per-measure widths and total width, so barlines align vertically.
///
/// Staff-space coordinates are **per staff** (each layout has its own
/// origin at its top line); the renderer stacks them [staffGap] spaces
/// apart (bottom line of the upper staff to top line of the lower).
class GrandStaffLayout {
  /// Layout of the upper staff.
  final ScoreLayout upper;

  /// Layout of the lower staff.
  final ScoreLayout lower;

  /// Vertical distance in staff spaces from the upper staff's bottom
  /// line (y = 4) to the lower staff's top line (y = 0).
  final double staffGap;

  /// Creates a grand-staff layout.
  const GrandStaffLayout({
    required this.upper,
    required this.lower,
    required this.staffGap,
  });

  /// Shared total width in staff spaces.
  double get width => upper.width;

  /// Total height in staff spaces: the upper staff's box, the gap, and
  /// the lower staff's box below its top line.
  double get height =>
      (4 - upper.top) + staffGap + (lower.top + lower.height - 0);

  @override
  String toString() => 'GrandStaffLayout(${width}x$height)';
}

/// Lays out a [GrandStaff]: each staff is laid out once to discover its
/// natural leading and per-measure widths, then both are laid out again
/// with the column-wise maxima so barlines align.
///
/// Throws an [ArgumentError] if the staves disagree on measure count.
GrandStaffLayout layoutGrandStaff(
  GrandStaff grandStaff,
  LayoutSettings settings, {
  double staffGap = 4.0,
  bool drawTimeSignature = true,
  bool finalBarline = true,
  double spacingStretch = 1.0,
  bool gridAlign = true,
  bool showNoteNames = false,
  NoteNameStyle noteNameStyle = NoteNameStyle.letter,
}) {
  if (grandStaff.upper.measures.length != grandStaff.lower.measures.length) {
    throw ArgumentError(
      'Grand staff staves must have the same measure count '
      '(${grandStaff.upper.measures.length} vs '
      '${grandStaff.lower.measures.length})',
    );
  }
  const engine = LayoutEngine();
  // The natural passes carry the same [spacingStretch] as the final passes, so
  // the shared [measureWidths] grow with the stretch and both staves stay
  // aligned (a wider stretch fills the line, distributed as note spacing).
  final upperNatural = engine.layout(grandStaff.upper, settings,
      drawTimeSignature: drawTimeSignature, spacingStretch: spacingStretch);
  final lowerNatural = engine.layout(grandStaff.lower, settings,
      drawTimeSignature: drawTimeSignature, spacingStretch: spacingStretch);

  double leadingOf(ScoreLayout layout) => layout.measureRegions.isEmpty
      ? layout.width
      : layout.measureRegions.first.startX;
  final leading =
      [leadingOf(upperNatural), leadingOf(lowerNatural)].reduce(_max);
  final measureWidths = <double>[
    for (var i = 0; i < upperNatural.measureRegions.length; i++)
      _max(
        upperNatural.measureRegions[i].endX -
            upperNatural.measureRegions[i].startX,
        lowerNatural.measureRegions[i].endX -
            lowerNatural.measureRegions[i].startX,
      ),
  ];

  // Cross-staff beams: an upper-staff note stems down toward the beam, a
  // lower-staff note stems up. Defer those stems so the engine draws the
  // notehead but no stem/flag, then draw the connecting beam here where the
  // inter-staff [staffGap] is known.
  final upperIds = _elementIds(grandStaff.upper);
  final lowerIds = _elementIds(grandStaff.lower);
  final deferUpper = <String, bool>{};
  final deferLower = <String, bool>{};
  for (final beam in grandStaff.crossStaffBeams) {
    for (final id in beam.noteIds) {
      if (upperIds.contains(id)) {
        deferUpper[id] = true; // stem down
      } else if (lowerIds.contains(id)) {
        deferLower[id] = false; // stem up
      }
    }
  }

  // §2.9: align simultaneous notes across the two staves (all voices).
  final columns = gridAlign
      ? alignedColumns([grandStaff.upper, grandStaff.lower], settings,
          spacingStretch: spacingStretch)
      : null;

  final upper = engine.layout(
    grandStaff.upper,
    settings,
    leadingWidth: leading,
    measureWidths: columns == null ? measureWidths : null,
    forcedColumns: columns,
    deferredStems: deferUpper,
    drawTimeSignature: drawTimeSignature,
    finalBarline: finalBarline,
    spacingStretch: spacingStretch,
    showNoteNames: showNoteNames,
    noteNameStyle: noteNameStyle,
  );
  final lower = engine.layout(
    grandStaff.lower,
    settings,
    leadingWidth: leading,
    measureWidths: columns == null ? measureWidths : null,
    forcedColumns: columns,
    deferredStems: deferLower,
    drawTimeSignature: drawTimeSignature,
    finalBarline: finalBarline,
    spacingStretch: spacingStretch,
    showNoteNames: showNoteNames,
    noteNameStyle: noteNameStyle,
  );

  final beamPrimitives = _crossStaffBeamPrimitives(
    grandStaff.crossStaffBeams,
    upper,
    lower,
    settings,
    staffGap,
  );

  return GrandStaffLayout(
    // The cross-staff beams are drawn in the upper staff's frame (the lower
    // staff sits `4 + staffGap` spaces below), so appending them to the upper
    // layout paints them with the existing renderer, spanning both staves.
    upper: beamPrimitives.isEmpty
        ? upper
        : ScoreLayout(
            width: upper.width,
            height: upper.height,
            top: upper.top,
            primitives: [...upper.primitives, ...beamPrimitives],
            regions: upper.regions,
            measureRegions: upper.measureRegions,
            crossStaffStubs: upper.crossStaffStubs,
          ),
    lower: lower,
    staffGap: staffGap,
  );
}

/// The ids of every element in [score] (across all voices).
Set<String> _elementIds(Score score) => {
      for (final measure in score.measures)
        for (final voice in measure.voices)
          for (final element in voice)
            if (element.id != null) element.id!,
    };

/// Builds the stem + beam primitives for each [beams] group, in the upper
/// staff's frame (a lower-staff stub's y is shifted down by `4 + staffGap`).
List<LayoutPrimitive> _crossStaffBeamPrimitives(
  List<CrossStaffBeam> beams,
  ScoreLayout upper,
  ScoreLayout lower,
  LayoutSettings settings,
  double staffGap,
) {
  final out = <LayoutPrimitive>[];
  for (final beam in beams) {
    // (stemX, attachY in the upper frame, whether the note stems down).
    final pts = <({double x, double attachY, bool down})>[];
    for (final id in beam.noteIds) {
      final u = upper.crossStaffStubs[id];
      if (u != null) {
        pts.add((x: u.stemX, attachY: u.attachY, down: true));
        continue;
      }
      final l = lower.crossStaffStubs[id];
      if (l != null) {
        pts.add((x: l.stemX, attachY: l.attachY + 4 + staffGap, down: false));
      }
    }
    if (pts.length < 2) continue;
    pts.sort((a, b) => a.x.compareTo(b.x));

    // The beam sits between the innermost notes of the two staves (or midway
    // in the gap if the notes are all on one staff).
    final downYs = [
      for (final p in pts)
        if (p.down) p.attachY
    ];
    final upYs = [
      for (final p in pts)
        if (!p.down) p.attachY
    ];
    final beamY = downYs.isNotEmpty && upYs.isNotEmpty
        ? (downYs.reduce(max) + upYs.reduce(min)) / 2
        : 4 + staffGap / 2;

    for (final p in pts) {
      out.add(LinePrimitive(
        Point(p.x, p.attachY),
        Point(p.x, beamY),
        thickness: settings.stemThickness,
      ));
    }
    out.add(BeamPrimitive(
      Point(pts.first.x, beamY),
      Point(pts.last.x, beamY),
      thickness: settings.beamThickness,
    ));
  }
  return out;
}

double _max(double a, double b) => a > b ? a : b;
