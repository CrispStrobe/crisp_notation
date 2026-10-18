/// Grand staff (system) layout: two staves with aligned measures.
library;

import 'dart:math';

import '../model/element.dart';
import '../model/score.dart';
import '../smufl/smufl_metadata.dart';
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
  final natural = [for (final score in staves) engine.layout(score, settings)];
  final ink = [
    for (final layout in natural) _inkMetrics(layout, settings.metadata)
  ];
  final stems = [for (final layout in natural) _stemDirections(layout)];

  final measureCount = staves.first.measures.length;
  final result = <Map<Fraction, double>>[];
  for (var m = 0; m < measureCount; m++) {
    // The widest left/right ink at each onset, across all staves and voices.
    // Every voice counts its own tuplets, as the engine does: counting an
    // inner voice's triplet at face value ran its bar long, the shared
    // closing column moved right, and every other staff's barline stopped
    // short of it (a piano triplet misaligned all three staves of a song).
    final leftAt = <Fraction, double>{};
    final rightAt = <Fraction, double>{};
    var measureEnd = Fraction.zero;
    final waysPerStaff = <Map<Fraction, Set<bool>>>[];
    for (var si = 0; si < staves.length; si++) {
      final measure = staves[si].measures[m];
      // `Measure.voices` drops empty voices; tuplets are keyed by the
      // absolute voice number.
      final lists = [
        measure.elements,
        measure.voice2,
        measure.voice3,
        measure.voice4,
      ];
      // This staff's ink at each onset, measured from the onset's column —
      // the leftmost head there in the natural layout — so a voice displaced
      // sideways (a second, voices interlocking) counts with its offset.
      final heads = <Fraction, double>{};
      final lefts = <Fraction, double>{};
      final rights = <Fraction, double>{};
      // The stem directions this staff shows at each onset (optical spacing).
      final ways = <Fraction, Set<bool>>{};
      for (var v = 0; v < lists.length; v++) {
        final voice = lists[v];
        if (v > 0 && voice.isEmpty) continue;
        var onset = Fraction.zero;
        for (var i = 0; i < voice.length; i++) {
          final element = voice[i];
          final id = element.id;
          final metrics = id == null ? null : ink[si][id];
          if (element is RestElement && element.hidden) {
            // A spacer has no ink; it only marks its onset as a column.
            leftAt[onset] = leftAt[onset] ?? 0.0;
            rightAt[onset] = rightAt[onset] ?? 0.0;
          } else if (metrics == null) {
            leftAt[onset] = leftAt[onset] ?? 0.0;
            rightAt[onset] = max(rightAt[onset] ?? 0.0, 1.0);
          } else {
            final (head, l, r) = metrics;
            final down = stems[si][id];
            if (down != null) (ways[onset] ??= {}).add(down);
            heads[onset] = min(heads[onset] ?? head, head);
            lefts[onset] = min(lefts[onset] ?? l, l);
            rights[onset] = max(rights[onset] ?? r, r);
          }
          onset += measure.effectiveDurationAt(i, voice: v);
        }
        if (onset > measureEnd) measureEnd = onset;
      }
      waysPerStaff.add(ways);
      for (final onset in heads.keys) {
        final head = heads[onset]!;
        leftAt[onset] = max(leftAt[onset] ?? 0.0, head - lefts[onset]!);
        rightAt[onset] = max(rightAt[onset] ?? 0.0, rights[onset]! - head);
      }
      // A clef change inside the bar stands left of its notes' ink: room for
      // it at that column, on every staff, so the staves stay aligned.
      for (final change in measure.inlineClefs) {
        final ink = heads[change.onset] == null
            ? 0.0
            : heads[change.onset]! - lefts[change.onset]!;
        leftAt[change.onset] = max(leftAt[change.onset] ?? 0.0,
            ink + inlineClefAdvance(change.clef, settings));
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
      final ideal = _idealAdvanceFor(
              next - onsets[k], settings, spacingStretch) +
          (k + 1 < onsets.length
                  ? _opticalCorrection(waysPerStaff, onsets[k], onsets[k + 1])
                  : 0) *
              spacingStretch;
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

/// The optical correction between two columns of a system: an up-stem
/// followed by a down-stem opens the gap a little (+0.3), a down-stem then
/// an up-stem closes it (−0.2) — when every staff that shows one stem
/// direction at both columns agrees; a staff that has none there, or two,
/// does not vote, and disagreement leaves the gap as it is.
double _opticalCorrection(
    List<Map<Fraction, Set<bool>>> ways, Fraction here, Fraction next) {
  double? vote;
  for (final staff in ways) {
    final a = staff[here], b = staff[next];
    if (a == null || b == null || a.length != 1 || b.length != 1) continue;
    final v = a.single == b.single ? 0.0 : (a.single ? -0.2 : 0.3);
    if (vote != null && vote != v) return 0;
    vote = v;
  }
  return vote ?? 0;
}

/// Each stemmed note's stem direction in [layout] (true = down), read from
/// its stem line against its noteheads.
Map<String, bool> _stemDirections(ScoreLayout layout) {
  final heads = <String, List<double>>{};
  for (final g in layout.primitives.whereType<GlyphPrimitive>()) {
    if (g.elementId != null && g.smuflName.startsWith('notehead')) {
      (heads[g.elementId!] ??= []).add(g.position.y);
    }
  }
  final out = <String, bool>{};
  for (final l in layout.primitives.whereType<LinePrimitive>()) {
    final id = l.elementId;
    if (id == null || l.from.x != l.to.x) continue;
    final ys = heads[id];
    if (ys == null) continue;
    final head = ys.reduce((a, b) => a + b) / ys.length;
    out[id] = (l.from.y + l.to.y) / 2 > head;
  }
  return out;
}

/// Per measure, the widest room any of [natural] (a system's staves, laid
/// out alone) leaves between the previous bar's end and the bar's content —
/// its barline plus start-of-bar changes. Given to every staff as
/// `measurePrefixes`, it keeps one staff's mid-score clef or key change from
/// starting its bar, and so its barline, later than the others'.
List<double> alignedPrefixes(List<ScoreLayout> natural) {
  if (natural.isEmpty) return const [];
  final count = natural.map((l) => l.measureRegions.length).reduce(min);
  return [
    for (var i = 0; i < count; i++)
      i == 0
          ? 0.0
          : natural
              .map((l) =>
                  l.measureRegions[i].startX - l.measureRegions[i - 1].endX)
              .reduce(max),
  ];
}

/// Per-element ink split `(left, right)` about its notehead x, from a natural
/// [layout]: left = accidental (notehead x − ink left), right = notehead/stem/
/// dots (ink right − notehead x). Rests (no notehead) anchor at their ink left.
///
/// Only the ink that stands in the element's column counts — noteheads,
/// accidentals, dots, flags, rests, stems and ledger lines. A tuplet bracket,
/// a dynamic or a pedal mark drawn under the note's id spans the columns
/// after it; counted as the note's own ink, it pushed the next column out by
/// its whole width (a piano's triplets set two bars a line, not three).
Map<String, (double, double, double)> _inkMetrics(
    ScoreLayout layout, SmuflMetadata metadata) {
  const columnGlyphs = [
    'notehead',
    'accidental',
    'augmentationDot',
    'flag',
    'rest',
  ];
  final headX = <String, double>{};
  final lefts = <String, double>{};
  final rights = <String, double>{};
  void add(String id, double l, double r) {
    lefts[id] = min(lefts[id] ?? l, l);
    rights[id] = max(rights[id] ?? r, r);
  }

  for (final primitive in layout.primitives) {
    final id = primitive.elementId;
    if (primitive is! GlyphPrimitive || id == null) continue;
    final name = primitive.smuflName;
    if (!columnGlyphs.any(name.startsWith)) continue;
    final x = primitive.position.x;
    if (name.startsWith('notehead')) headX[id] = min(headX[id] ?? x, x);
    final box = metadata.bBoxOf(name);
    add(id, x + box.swX * primitive.scale, x + box.neX * primitive.scale);
  }
  // Stems and ledger lines: short or vertical lines at the notehead (a
  // tuplet bracket's hooks and pieces carry the id too, further out).
  for (final line in layout.primitives.whereType<LinePrimitive>()) {
    final id = line.elementId;
    final head = id == null ? null : headX[id];
    if (head == null) continue;
    final l = min(line.from.x, line.to.x), r = max(line.from.x, line.to.x);
    if (r - l <= 2.6 && l >= head - 1.0 && r <= head + 2.6) add(id!, l, r);
  }
  final out = <String, (double, double, double)>{};
  for (final region in layout.regions) {
    final id = region.elementId;
    final b = region.bounds;
    final l = lefts[id] ?? b.left, r = rights[id] ?? b.right;
    out[id] = (headX[id] ?? l, l, r);
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

  /// Chords across both staves on one stem. Empty for an ordinary grand
  /// staff.
  final List<CrossStaffChord> crossStaffChords;

  /// Creates a grand staff.
  const GrandStaff({
    required this.upper,
    required this.lower,
    this.crossStaffBeams = const [],
    this.crossStaffChords = const [],
  });

  @override
  bool operator ==(Object other) =>
      other is GrandStaff &&
      other.upper == upper &&
      other.lower == lower &&
      _sameBeams(other.crossStaffBeams, crossStaffBeams) &&
      other.crossStaffChords.length == crossStaffChords.length &&
      [
        for (var i = 0; i < crossStaffChords.length; i++)
          other.crossStaffChords[i] == crossStaffChords[i],
      ].every((same) => same);

  static bool _sameBeams(List<CrossStaffBeam> a, List<CrossStaffBeam> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(upper, lower, Object.hashAll(crossStaffBeams),
      Object.hashAll(crossStaffChords));

  @override
  String toString() => 'GrandStaff($upper / $lower)';
}

/// A chord written across both staves of a grand staff on ONE stem: its
/// notes on the upper staff ([upperId]) and those on the lower ([lowerId])
/// sound together, and a single stem joins them through the gap — the
/// pianist's chord taken by both hands' reach, as engravers print it. With
/// [stemsDown] the stem runs down from the upper notes through the lower
/// ones (the lower half carries the flag); otherwise it rises from the lower
/// notes through the upper ones.
class CrossStaffChord {
  /// The chord's upper-staff element.
  final String upperId;

  /// The chord's lower-staff element.
  final String lowerId;

  /// Whether the shared stem points down.
  final bool stemsDown;

  /// Creates a cross-staff chord.
  const CrossStaffChord(this.upperId, this.lowerId, {this.stemsDown = true});

  @override
  bool operator ==(Object other) =>
      other is CrossStaffChord &&
      other.upperId == upperId &&
      other.lowerId == lowerId &&
      other.stemsDown == stemsDown;

  @override
  int get hashCode => Object.hash(upperId, lowerId, stemsDown);

  @override
  String toString() => 'CrossStaffChord($upperId / $lowerId)';
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
  bool showNoteOctaves = false,
  NoteNameStyle noteNameStyle = NoteNameStyle.letter,
  double? targetWidth,
  bool? numberVerses,
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

  // Cross-staff chords: the half that carries the stem's tip keeps its stem,
  // turned the chord's way; the other half's stem is deferred, and one line
  // joins them across the gap below.
  final forceUpper = <String, bool>{};
  final forceLower = <String, bool>{};
  for (final chord in grandStaff.crossStaffChords) {
    if (!upperIds.contains(chord.upperId) ||
        !lowerIds.contains(chord.lowerId)) {
      continue;
    }
    if (chord.stemsDown) {
      deferUpper[chord.upperId] = true;
      forceLower[chord.lowerId] = true;
    } else {
      deferLower[chord.lowerId] = false;
      forceUpper[chord.upperId] = false;
    }
  }
  final upperScore = withStems(grandStaff.upper, forceUpper);
  final lowerScore = withStems(grandStaff.lower, forceLower);

  // §2.9: align simultaneous notes across the two staves (all voices).
  final columns = gridAlign
      ? alignedColumns([grandStaff.upper, grandStaff.lower], settings,
          spacingStretch: spacingStretch)
      : null;

  final prefixes = alignedPrefixes([upperNatural, lowerNatural]);
  final upper = engine.layout(
    upperScore,
    settings,
    leadingWidth: leading,
    measureWidths: columns == null ? measureWidths : null,
    forcedColumns: columns,
    measurePrefixes: prefixes,
    numberVerses: numberVerses,
    deferredStems: deferUpper,
    drawTimeSignature: drawTimeSignature,
    finalBarline: finalBarline,
    targetWidth: targetWidth,
    spacingStretch: spacingStretch,
    showNoteNames: showNoteNames,
    showNoteOctaves: showNoteOctaves,
    noteNameStyle: noteNameStyle,
  );
  final lower = engine.layout(
    lowerScore,
    settings,
    // Metronome marks belong over the upper staff only.
    drawTempoMarks: false,
    leadingWidth: leading,
    measureWidths: columns == null ? measureWidths : null,
    forcedColumns: columns,
    measurePrefixes: prefixes,
    numberVerses: numberVerses,
    deferredStems: deferLower,
    drawTimeSignature: drawTimeSignature,
    finalBarline: finalBarline,
    targetWidth: targetWidth,
    spacingStretch: spacingStretch,
    showNoteNames: showNoteNames,
    showNoteOctaves: showNoteOctaves,
    noteNameStyle: noteNameStyle,
  );

  final beamPrimitives = [
    ..._crossStaffBeamPrimitives(
      grandStaff.crossStaffBeams,
      upper,
      lower,
      settings,
      staffGap,
    ),
    ...crossStaffChordStems(
        grandStaff.crossStaffChords, upper, lower, settings, staffGap),
  ];

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
            inkProfile: upper.inkProfile,
          ),
    lower: lower,
    staffGap: staffGap,
  );
}

/// [score] with the notes named in [stems] turned up (false) or down (true).
/// Internal to the layout library.
Score withStems(Score score, Map<String, bool> stems) {
  if (stems.isEmpty) return score;
  List<MusicElement> turn(List<MusicElement> voice) => [
        for (final e in voice)
          e is NoteElement && stems.containsKey(e.id)
              ? e.copyWith(stemsDown: stems[e.id])
              : e,
      ];
  return score.copyWith(measures: [
    for (final m in score.measures)
      m.copyWith(
        elements: turn(m.elements),
        voice2: turn(m.voice2),
        voice3: turn(m.voice3),
        voice4: turn(m.voice4),
      ),
  ]);
}

/// Internal to the layout library. The line joining each cross-staff
/// chord's halves through the gap, in the upper staff's frame: from the deferred half's stem point to the drawn
/// half's stem, which continues it.
List<LayoutPrimitive> crossStaffChordStems(
  List<CrossStaffChord> chords,
  ScoreLayout upper,
  ScoreLayout lower,
  LayoutSettings settings,
  double staffGap,
) {
  final shift = 4 + staffGap;
  LinePrimitive? stemOf(ScoreLayout layout, String id) {
    for (final p in layout.primitives) {
      if (p is LinePrimitive && p.elementId == id && p.from.x == p.to.x) {
        return p;
      }
    }
    return null;
  }

  final out = <LayoutPrimitive>[];
  for (final chord in chords) {
    if (chord.stemsDown) {
      final stub = upper.crossStaffStubs[chord.upperId];
      final stem = stemOf(lower, chord.lowerId);
      if (stub == null || stem == null) continue;
      out.add(LinePrimitive(Point(stem.from.x, stub.attachY),
          Point(stem.from.x, min(stem.from.y, stem.to.y) + shift),
          thickness: settings.stemThickness, elementId: chord.upperId));
    } else {
      final stub = lower.crossStaffStubs[chord.lowerId];
      final stem = stemOf(upper, chord.upperId);
      if (stub == null || stem == null) continue;
      out.add(LinePrimitive(Point(stem.from.x, max(stem.from.y, stem.to.y)),
          Point(stem.from.x, stub.attachY + shift),
          thickness: settings.stemThickness, elementId: chord.lowerId));
    }
  }
  return out;
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
    // (stemX, attachY in the upper frame, stems down?, beams wanted).
    final pts = <({double x, double attachY, bool down, int count})>[];
    for (final id in beam.noteIds) {
      final u = upper.crossStaffStubs[id];
      if (u != null) {
        pts.add(
            (x: u.stemX, attachY: u.attachY, down: true, count: u.beamCount));
        continue;
      }
      final l = lower.crossStaffStubs[id];
      if (l != null) {
        pts.add((
          x: l.stemX,
          attachY: l.attachY + 4 + staffGap,
          down: false,
          count: l.beamCount,
        ));
      }
    }
    if (pts.length < 2) continue;
    pts.sort((a, b) => a.x.compareTo(b.x));
    final first = pts.first, last = pts.last;

    // Slant: half the contour of the two end notes, at most one space across
    // the whole group — the same restraint as a single-staff beam, so a
    // rising figure that crosses the staves reads as rising.
    final dx = last.x - first.x;
    var slope = dx > 0 ? (last.attachY - first.attachY) / dx * 0.5 : 0.0;
    if (dx > 0) slope = slope.clamp(-1.0 / dx, 1.0 / dx);

    // Height: between the two staves' noteheads. Every stem from above must
    // reach down to the beam and every stem from below up to it, with room
    // to spare where the gap allows; with notes on one staff only, the beam
    // sits midway in the gap.
    const minStem = 2.0;
    final step = settings.beamThickness + settings.beamSpacing;
    double c(double y, double x) => y - slope * x;
    final downs = [
      for (final p in pts)
        if (p.down) p
    ];
    final ups = [
      for (final p in pts)
        if (!p.down) p
    ];
    final midX = (first.x + last.x) / 2;
    double intercept;
    if (downs.isNotEmpty && ups.isNotEmpty) {
      final low = downs.map((p) => c(p.attachY + minStem, p.x)).reduce(max);
      final high = ups
          .map((p) => c(p.attachY - minStem - (p.count - 1) * step, p.x))
          .reduce(min);
      intercept = low <= high
          ? (low + high) / 2
          : (downs.map((p) => c(p.attachY, p.x)).reduce(max) +
                  ups.map((p) => c(p.attachY, p.x)).reduce(min)) /
              2;
    } else {
      intercept = c(4 + staffGap / 2, midX);
    }
    double beamY(double x) => intercept + slope * x;

    // Further beams stack toward the UPPER staff: a stem from above ends at
    // the primary beam, a stem from below runs on to the farthest beam its
    // note needs.
    for (final p in pts) {
      final end = p.down ? beamY(p.x) : beamY(p.x) - (p.count - 1) * step;
      out.add(LinePrimitive(
        Point(p.x, p.attachY),
        Point(p.x, end),
        thickness: settings.stemThickness,
      ));
    }
    final half = settings.stemThickness / 2;
    out.add(BeamPrimitive(
      Point(first.x - half, beamY(first.x - half)),
      Point(last.x + half, beamY(last.x + half)),
      thickness: settings.beamThickness,
    ));
    final deepest = pts.map((p) => p.count).reduce(max);
    for (var level = 2; level <= deepest; level++) {
      final off = -step * (level - 1);
      var i = 0;
      while (i < pts.length) {
        if (pts[i].count < level) {
          i++;
          continue;
        }
        var j = i;
        while (j + 1 < pts.length && pts[j + 1].count >= level) {
          j++;
        }
        final (x0, x1) = j > i
            ? (pts[i].x - half, pts[j].x + half)
            // A lone short note: a beamlet pointing into the group.
            : i == 0
                ? (pts[i].x - half, pts[i].x + 1.0)
                : (pts[i].x - 1.0, pts[i].x + half);
        out.add(BeamPrimitive(
          Point(x0, beamY(x0) + off),
          Point(x1, beamY(x1) + off),
          thickness: settings.beamThickness,
        ));
        i = j + 1;
      }
    }
  }
  return out;
}

double _max(double a, double b) => a > b ? a : b;
