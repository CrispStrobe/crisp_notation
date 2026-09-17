part of 'layout_engine.dart';

// Beam geometry: grouping notes into beams, the straight-beam pass with
// secondary-beam subdivision, and cross-measure beams. Extracted from
// layout_engine.dart; kept as an extension so it retains full access to the
// builder's private state. Behaviour unchanged.

extension _Beaming on _LayoutBuilder {
  void _addBeam(
    Point<double> start,
    Point<double> end,
    double thickness,
  ) {
    final halfStem = s.stemThickness / 2;
    final slope =
        end.x == start.x ? 0.0 : (end.y - start.y) / (end.x - start.x);
    start = Point(start.x - halfStem, start.y - slope * halfStem);
    end = Point(end.x + halfStem, end.y + slope * halfStem);
    _primitives.add(BeamPrimitive(start, end, thickness: thickness));
    final h = thickness / 2;
    _expand(
      null,
      min(start.x, end.x),
      min(start.y, end.y) - h,
      max(start.x, end.x),
      max(start.y, end.y) + h,
    );
  }

  /// Rule 7: group eighths/sixteenths within a beat (simple meter). In
  /// even x/4 meters, adjacent all-eighth beat groups within the same half
  /// measure merge (so 8 eighths in 4/4 yield 2 beams). No beaming across
  /// rests or beat boundaries.
  /// Resolves each [CrossMeasureBeam] to the note ids it spans (from its start
  /// through its end, across barlines) and the group's stem direction, so those
  /// notes are excluded from per-measure beaming and beamed together later.
  /// A run of fewer than two notes is ignored.
  void _prepareCrossMeasureBeams() {
    for (final cb in score.crossMeasureBeams) {
      final ids = <String>[];
      final pitches = <Pitch>[];
      var collecting = false;
      var done = false;
      for (final measure in score.measures) {
        for (final el in measure.elements) {
          if (el.id == cb.startId) collecting = true;
          if (collecting && el is NoteElement && el.id != null) {
            ids.add(el.id!);
            pitches.addAll(el.pitches);
          }
          if (el.id == cb.endId) {
            done = true;
            break;
          }
        }
        if (done) break;
      }
      if (ids.length < 2) continue;
      var maxAbove = -100, maxBelow = -100;
      for (final p in pitches) {
        final pos = p.staffPosition(_clef);
        if (pos - 4 > maxAbove) maxAbove = pos - 4;
        if (4 - pos > maxBelow) maxBelow = 4 - pos;
      }
      _crossBeamStemsDown[cb] = maxAbove >= maxBelow;
      for (final id in ids) {
        _crossMeasureIds.add(id);
        _crossBeamOf[id] = cb;
      }
    }
  }

  /// Draws each cross-measure beam over the stem data gathered across measures —
  /// a post-pass, so both measures' final x-positions are already fixed. The
  /// beam is continuous across the barline (no metric subdivision).
  void _layoutCrossMeasureBeams() {
    for (final entry in _crossBeamNotes.entries) {
      final notes = entry.value;
      if (notes.length < 2) continue;
      _layoutBeamGroup(
        notes,
        stemsDown: _crossBeamStemsDown[entry.key] ?? false,
        onsets: [for (final _ in notes) Fraction.zero],
      );
    }
  }

  List<_BeamGroup> _computeBeamGroups(
    List<MusicElement> elements, {
    required Fraction Function(int index) effectiveAt,
    required List<TupletSpan> tuplets,
    bool? forcedStemsDown,
  }) {
    final time = _time;
    // Unmetered scores group per quarter-note window.
    final span = time == null ? Fraction(1, 4) : Fraction(1, time.beatUnit);
    final halfSpan = Fraction(1, 2);

    // Beam-group boundaries (cumulative onsets) for the current meter — one per
    // group start. A note's beam window is the index of the group its onset
    // falls in. For a simple meter these boundaries are the beats, so this is
    // identical to `_LayoutBuilder._windowIndex(onset, 1/beatUnit)`; compound (6/8, 9/8, 12/8)
    // and additive (3+2/8) meters group in threes / by their components.
    final boundaries = <Fraction>[];
    if (time != null) {
      var acc = Fraction.zero;
      for (final g in time.beamGroups()) {
        boundaries.add(acc);
        acc += g;
      }
    }
    int windowOf(Fraction onset) {
      if (time == null) return _LayoutBuilder._windowIndex(onset, span);
      var idx = 0;
      for (var b = 0; b < boundaries.length; b++) {
        if (onset < boundaries[b]) break;
        idx = b;
      }
      return idx;
    }

    // Which tuplet span (by list index) an element belongs to, or -1.
    int spanOf(int index) {
      for (var t = 0; t < tuplets.length; t++) {
        if (tuplets[t].contains(index)) return t;
      }
      return -1;
    }

    // Feathered spans (by note id) covering this element list: force each
    // into its own group and exclude its notes from normal beaming.
    final idIndex = <String, int>{
      for (var i = 0; i < elements.length; i++)
        if (elements[i].id case final id?) id: i,
    };
    final feathers = <(int, int, int, int)>[]; // start, end, begin, endBeams
    final slants = <(int, int, double)>[]; // start, end, slant
    final claimed = <int>{};
    for (final fb in score.featheredBeams) {
      final a = idIndex[fb.startId];
      final b = idIndex[fb.endId];
      if (a == null || b == null || b <= a) continue;
      feathers.add((a, b, fb.beginBeams, fb.endBeams));
      for (var i = a; i <= b; i++) {
        claimed.add(i);
      }
    }
    for (final bs in score.beamSlants) {
      final a = idIndex[bs.startId];
      final b = idIndex[bs.endId];
      if (a == null || b == null || b <= a || claimed.contains(a)) continue;
      slants.add((a, b, bs.slant));
      for (var i = a; i <= b; i++) {
        claimed.add(i);
      }
    }

    var onset = Fraction.zero;
    final runs = <List<int>>[];
    final onsets = <Fraction>[];
    List<int>? current;
    int? currentWindow;
    int? currentSpan;

    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      onsets.add(onset);
      final beamable = element is NoteElement &&
          _LayoutBuilder._beamCountOf(element.duration.base) >= 1 &&
          !claimed.contains(i) &&
          !_crossMeasureIds.contains(element.id);
      if (beamable) {
        final window = windowOf(onset);
        // Beam runs never cross a tuplet boundary in either direction.
        final tuplet = spanOf(i);
        if (current != null &&
            window == currentWindow &&
            tuplet == currentSpan) {
          current.add(i);
        } else {
          current = [i];
          currentWindow = window;
          currentSpan = tuplet;
          runs.add(current);
        }
      } else if (element is RestElement) {
        // A rest does not break a beam on its own: if beamable notes continue
        // within the same beat window, the beam passes over the rest (the
        // rest's index is never added, so the beam simply spans the gap). The
        // window/tuplet check when the next note arrives re-attaches it or
        // starts a fresh run, so a rest at a beat boundary still separates.
      } else {
        current = null;
        currentWindow = null;
        currentSpan = null;
      }
      onset += effectiveAt(i);
    }

    // Merge adjacent all-eighth beat groups within the same half measure
    // (tuplet groups never merge).
    if (time != null && time.beatUnit == 4 && time.beats.isEven) {
      bool allEighths(List<int> run) => run.every((i) =>
          (elements[i] as NoteElement).duration.base == DurationBase.eighth);
      for (var i = 0; i < runs.length - 1;) {
        final a = runs[i];
        final b = runs[i + 1];
        if (b.first == a.last + 1 &&
            spanOf(a.first) == -1 &&
            spanOf(b.first) == -1 &&
            allEighths(a) &&
            allEighths(b) &&
            _LayoutBuilder._windowIndex(onsets[a.first], halfSpan) ==
                _LayoutBuilder._windowIndex(onsets[b.first], halfSpan)) {
          a.addAll(b);
          runs.removeAt(i + 1);
        } else {
          i++;
        }
      }
    }

    final groups = <_BeamGroup>[];
    for (final run in runs.where((r) => r.length >= 2)) {
      final bool stemsDown;
      if (forcedStemsDown != null) {
        stemsDown = forcedStemsDown;
      } else {
        var maxAbove = -100;
        var maxBelow = -100;
        for (final i in run) {
          final note = elements[i] as NoteElement;
          for (final pitch in note.pitches) {
            final p = pitch.staffPosition(_clef);
            if (p - 4 > maxAbove) maxAbove = p - 4;
            if (4 - p > maxBelow) maxBelow = 4 - p;
          }
        }
        stemsDown = maxAbove >= maxBelow;
      }
      groups.add(_BeamGroup(run,
          onsets: [for (final i in run) onsets[i]], stemsDown: stemsDown));
    }

    bool stemsDownFor(List<int> run) {
      if (forcedStemsDown != null) return forcedStemsDown;
      var maxAbove = -100;
      var maxBelow = -100;
      for (final i in run) {
        for (final pitch in (elements[i] as NoteElement).pitches) {
          final p = pitch.staffPosition(_clef);
          if (p - 4 > maxAbove) maxAbove = p - 4;
          if (4 - p > maxBelow) maxBelow = 4 - p;
        }
      }
      return maxAbove >= maxBelow;
    }

    for (final (a, b, begin, end) in feathers) {
      final run = [for (var i = a; i <= b; i++) i];
      groups.add(_BeamGroup(run,
          onsets: [for (final i in run) onsets[i]],
          stemsDown: stemsDownFor(run),
          feather: (begin, end)));
    }
    for (final (a, b, slant) in slants) {
      final run = [for (var i = a; i <= b; i++) i];
      groups.add(_BeamGroup(run,
          onsets: [for (final i in run) onsets[i]],
          stemsDown: stemsDownFor(run),
          forcedSlant: slant));
    }
    return groups;
  }

  /// Beam geometry: a straight beam through the stem tips, slant clamped to
  /// ±1 staff space over the group, intercept chosen so every stem keeps at
  /// least the default length. [BeamPrimitive] points are the midpoints of
  /// the beam's end edges; stems run to the beam's center line.
  void _layoutBeamGroup(
    List<_BeamedNote> notes, {
    required bool stemsDown,
    required List<Fraction> onsets,
    (int, int)? feather,
    double? forcedSlant,
  }) {
    final first = notes.first;
    final last = notes.last;
    final dx = last.stemX - first.stemX;
    final slant =
        forcedSlant ?? ((last.refY - first.refY) / 2).clamp(-1.0, 1.0);
    final slope = dx == 0 ? 0.0 : slant / dx;

    // Multi-level groups (32nds/64ths) need longer stems so the extra
    // beams stay clear of the noteheads. A feathered group reserves room for
    // its widest fan end instead.
    final maxLevel = feather == null
        ? notes.map((n) => n.beamCount).reduce(max)
        : max(feather.$1, feather.$2);
    final stemLength = s.stemLength + _LayoutBuilder._stemExtension(maxLevel);
    final edgeRise = slope.abs() * s.stemThickness / 2;
    double intercept;
    if (stemsDown) {
      intercept =
          notes.map((n) => n.refY + stemLength - slope * n.stemX).reduce(max);
      // Never let a downward beam sit above the middle line.
      for (final n in notes) {
        final y = slope * n.stemX + intercept;
        if (y < _middleY + edgeRise) intercept += _middleY + edgeRise - y;
      }
    } else {
      intercept =
          notes.map((n) => n.refY - stemLength - slope * n.stemX).reduce(min);
      for (final n in notes) {
        final y = slope * n.stemX + intercept;
        if (y > _middleY - edgeRise) intercept -= y - _middleY + edgeRise;
      }
    }

    double beamY(double x) => slope * x + intercept;

    for (final note in notes) {
      _addLine(
        Point(note.stemX, note.attachY),
        Point(note.stemX, beamY(note.stemX)),
        s.stemThickness,
        elementId: note.elementId,
      );
    }

    _addBeam(
      Point(first.stemX, beamY(first.stemX)),
      Point(last.stemX, beamY(last.stemX)),
      s.beamThickness,
    );

    // v0.7 Phase 1.4: feathered (fanned) beam — the extra beams converge on
    // the primary at the "few" end and spread by one step per level at the
    // "many" end (accelerando if growing left→right, ritardando if not).
    if (feather != null) {
      final step = (s.beamThickness + s.beamSpacing) * (stemsDown ? -1 : 1);
      final lo = min(feather.$1, feather.$2);
      final hi = max(feather.$1, feather.$2);
      final growing = feather.$2 > feather.$1;
      for (var level = 2; level <= hi; level++) {
        final off = step * (level - 1);
        final double y1;
        final double y2;
        if (level <= lo) {
          y1 = beamY(first.stemX) + off;
          y2 = beamY(last.stemX) + off;
        } else if (growing) {
          y1 = beamY(first.stemX);
          y2 = beamY(last.stemX) + off;
        } else {
          y1 = beamY(first.stemX) + off;
          y2 = beamY(last.stemX);
        }
        _addBeam(
            Point(first.stemX, y1), Point(last.stemX, y2), s.beamThickness);
      }
      return;
    }

    // Secondary/tertiary/quaternary beams, offset toward the noteheads. They
    // break at a metric sub-pulse (Phase 4.7 — driven by the meter's hierarchy)
    // so a group spanning more than one pulse shows the beat rather than one
    // over-long secondary beam: in **compound / additive** meters the pulse is
    // the base unit (6/8 sixteenths break at each eighth, not at a quarter),
    // and in **simple** meters it stays the quarter (so a half-note beat in cut
    // time still shows the quarter sub-pulse, and x/4 meters — whose beam groups
    // never exceed a quarter — are unchanged).
    final subdivision = _time == null ? null : _secondaryBeamPulse(_time!);
    for (var level = 2; level <= maxLevel; level++) {
      final offset = (s.beamThickness + s.beamSpacing) *
          (level - 1) *
          (stemsDown ? -1 : 1);
      var i = 0;
      while (i < notes.length) {
        if (notes[i].beamCount < level) {
          i++;
          continue;
        }
        var j = i;
        while (j + 1 < notes.length &&
            notes[j + 1].beamCount >= level &&
            !_LayoutBuilder._crossesSubdivision(
                onsets, subdivision, j, j + 1)) {
          j++;
        }
        if (j > i) {
          _addBeam(
            Point(notes[i].stemX, beamY(notes[i].stemX) + offset),
            Point(notes[j].stemX, beamY(notes[j].stemX) + offset),
            s.beamThickness,
          );
        } else {
          // Lone short note between longer ones: a beamlet stub pointing
          // into the group (leftward unless it is the group's first note).
          final x = notes[i].stemX;
          final stubX = i == 0 ? x + 1.0 : x - 1.0;
          _addBeam(
            Point(min(x, stubX), beamY(min(x, stubX)) + offset),
            Point(max(x, stubX), beamY(max(x, stubX)) + offset),
            s.beamThickness,
          );
        }
        i = j + 1;
      }
    }
  }
}

// The metric pulse at which secondary (16th+) beams break (Phase 4.7). In a
// compound (6/8, 9/8, 12/8) or additive (3+2/8) meter the pulse is the base
// unit, so a run of sixteenths inside a dotted-quarter beat breaks its
// secondary beams at each eighth. In simple meters it stays the quarter
// (matching prior behaviour: x/4 groups never exceed a quarter, and cut time
// still shows the quarter sub-pulse).
Fraction _secondaryBeamPulse(TimeSignature time) {
  final compound = (time.beatUnit == 8 || time.beatUnit == 16) &&
      time.beats > 3 &&
      time.beats % 3 == 0;
  return compound || time.components != null
      ? Fraction(1, time.beatUnit)
      : Fraction(1, 4);
}
