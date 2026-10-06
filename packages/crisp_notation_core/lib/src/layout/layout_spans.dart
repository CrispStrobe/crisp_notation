part of 'layout_engine.dart';

// Spans and per-note markings drawn over the notehead geometry collected in
// the main measure pass (_tieInfos): ties, slurs, glissandos, portamentos,
// laissez-vibrer, arpeggios, dynamics/hairpins, pedals, ottavas, trill
// extensions and breath marks. An extension so it keeps full access to the
// builder's private state. Behaviour unchanged.

extension _Spans on _LayoutBuilder {
  /// v0.7.2: glissando/slide — a straight line from the first note's right
  /// edge to the second note's left edge, at their notehead centers.
  void _layoutGlissandos() {
    for (final gliss in score.glissandos) {
      final startIdx = _tieIndexOf(gliss.startId);
      final endIdx = _tieIndexOf(gliss.endId);
      if (startIdx < 0 || endIdx < 0) {
        continue;
      }
      if (endIdx <= startIdx) {
        continue;
      }
      final start = _tieInfos[startIdx];
      final end = _tieInfos[endIdx];
      double centerY(_TieInfo i) =>
          i.heads.map((h) => h.$4).reduce((a, b) => a + b) / i.heads.length;
      _addLine(
        Point(start.right + 0.15, centerY(start)),
        Point(end.left - 0.15, centerY(end)),
        meta.engravingDefault('glissandoLineThickness', orElse: 0.15),
      );
    }
  }

  /// Portamento: a smooth **curved** slide line between two notes (unlike the
  /// straight [Glissando] line), bowing gently between the noteheads.
  void _layoutPortamentos() {
    for (final port in score.portamentos) {
      final startIdx = _tieIndexOf(port.startId);
      final endIdx = _tieIndexOf(port.endId);
      if (startIdx < 0 || endIdx < 0) {
        continue;
      }
      if (endIdx <= startIdx) {
        continue;
      }
      final start = _tieInfos[startIdx];
      final end = _tieInfos[endIdx];
      double centerY(_TieInfo i) =>
          i.heads.map((h) => h.$4).reduce((a, b) => a + b) / i.heads.length;
      final x1 = start.right + 0.15, y1 = centerY(start);
      final x2 = end.left - 0.15, y2 = centerY(end);
      final midY = (y1 + y2) / 2;
      const bow = 0.7; // downward bow depth at the middle
      _addCurve(
        Point(x1, y1),
        Point(x1 + (x2 - x1) * 0.25, midY + bow),
        Point(x1 + (x2 - x1) * 0.75, midY + bow),
        Point(x2, y2),
        meta.engravingDefault('glissandoLineThickness', orElse: 0.15),
      );
    }
  }

  /// v0.7.2: arpeggio — a vertical wavy line just left of the chord,
  /// spanning its noteheads, tiled from `wiggleArpeggiatoUp` and capped with
  /// a direction arrowhead.
  void _layoutArpeggios(
    List<MusicElement> elements,
    Map<int, int> tieIndexOf,
  ) {
    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      if (element is! NoteElement || element.arpeggio == null) continue;
      final info = _tieInfos[tieIndexOf[i]!];
      final ys = info.heads.map((h) => h.$4);
      final topY = ys.reduce(min) - 0.5;
      final bottomY = ys.reduce(max) + 0.5;
      final x = info.left - 0.5;
      final tileH = meta.bBoxOf(SmuflGlyph.wiggleArpeggiatoUp).height;
      for (var y = bottomY; y > topY; y -= tileH) {
        _addGlyph(SmuflGlyph.wiggleArpeggiatoUp, x, y, elementId: element.id);
      }
      if (element.arpeggio == Arpeggio.up) {
        _addGlyph(SmuflGlyph.wiggleArpeggiatoUpArrow, x, topY,
            elementId: element.id);
      } else {
        _addGlyph(SmuflGlyph.wiggleArpeggiatoDownArrow, x, bottomY,
            elementId: element.id);
      }
    }
  }

  /// Whether another voice has a note or a rest within the horizontal span
  /// [left]..[right], i.e. whether a curve there shares the staff with
  /// another voice and must keep to its own voice's side. Rests count: a
  /// voice resting under a slurred upper voice still owns the space below.
  bool _otherVoiceWithin(int voice, double left, double right) {
    for (final MapEntry(key: other, value: (lefts, maxRights, _))
        in _noteSpansByVoice.entries) {
      if (other == voice) continue;
      // Notes starting before [right] are the candidates; one overlaps the
      // span iff the furthest right edge among them passes [left].
      var lo = 0, hi = lefts.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (lefts[mid] < right) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      if (lo > 0 && maxRights[lo - 1] > left) return true;
    }
    return false;
  }

  /// Whether a notehead of a voice other than [voice] has its centre inside
  /// the box [x1]..[x2] × [yTop]..[yBottom]: a tie drawn there would run
  /// through it. Binary search on the per-voice index, as above.
  bool _otherVoiceHeadIn(
      int voice, double x1, double x2, double yTop, double yBottom) {
    for (final MapEntry(key: other, value: (lefts, _, infos))
        in _noteSpansByVoice.entries) {
      if (other == voice) continue;
      // Heads are a few spaces wide at most; start a little left of x1.
      var lo = 0, hi = lefts.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (lefts[mid] < x1 - 4) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      for (var k = lo; k < infos.length && lefts[k] < x2; k++) {
        for (final (_, hl, hr, hy) in infos[k].heads) {
          final cx = (hl + hr) / 2;
          if (cx > x1 && cx < x2 && hy > yTop && hy < yBottom) return true;
        }
      }
    }
    return false;
  }

  /// v0.3.1: for every note with `tieToNext`, draw a tie curve to each
  /// identically-pitched notehead of the immediately following note
  /// element (also across barlines). Ties into rests or the end of the score
  /// draw nothing. Which side each curve takes:
  ///
  /// - **Another voice shares the span:** the stem side, for every head —
  ///   above in the upper (stems-up) voice, below in the lower one, so the two
  ///   voices' ties never cross into each other.
  /// - **A chord:** the ties split — the upper notes curve up, the lower ones
  ///   down, and an odd middle note away from the stem. All on one side, the
  ///   inner ties ran into the neighbouring noteheads (issue #2).
  /// - **A single note:** the notehead side, away from the stem.
  void _layoutTies() {
    for (var i = 0; i < _tieInfos.length - 1; i++) {
      final start = _tieInfos[i];
      final note = start.note;
      if (note == null || !note.tieToNext) continue;
      // The next element of the SAME voice (columns interleave voices).
      _TieInfo? next;
      for (var j = i + 1; j < _tieInfos.length; j++) {
        if (_tieInfos[j].voice == start.voice) {
          next = _tieInfos[j];
          break;
        }
      }
      if (next == null || next.note == null) continue;
      final awayFromStem = start.stemsDown ? -1.0 : 1.0;
      final multiVoice = _otherVoiceWithin(start.voice, start.left, next.right);
      // Head rows top to bottom (smaller y is higher on the staff).
      final rows = start.heads.map((h) => h.$4).toSet().toList()..sort();
      double dirFor(double y) {
        if (multiVoice) return -awayFromStem;
        if (rows.length < 2) return awayFromStem;
        final rank = rows.indexOf(y);
        final mid = (rows.length - 1) / 2;
        if (rank < mid) return -1.0; // upper half: above
        if (rank > mid) return 1.0; // lower half: below
        return awayFromStem;
      }

      for (final (pitch, _, xRight, y) in start.heads) {
        final matches = next.heads.where((h) => h.$1 == pitch);
        if (matches.isEmpty) continue;
        var dir = dirFor(y);
        final x1 = xRight + 0.15;
        final x2 = matches.first.$2 - 0.15;
        if (x2 <= x1) continue;
        // The tied head may sit at another height: a clef change between the
        // two notes moves the same pitch. Run the tie head to head; drawing it
        // flat at the first head's height left it ending in empty space.
        final yEnd = matches.first.$4;
        final depth = 0.35 + min(0.6, (x2 - x1) * 0.06);
        // Voices crossing: if the stem-side arc would run through another
        // voice's notehead, take the other side instead.
        if (multiVoice) {
          final lo = min(y, yEnd) + min(0.0, dir * (0.6 + depth));
          final hi = max(y, yEnd) + max(0.0, dir * (0.6 + depth));
          if (_otherVoiceHeadIn(start.voice, x1, x2, lo, hi)) dir = -dir;
        }
        final y1 = y + dir * 0.6, y2 = yEnd + dir * 0.6;
        _addCurve(
          Point(x1, y1),
          Point(x1 + (x2 - x1) * 0.3, y1 + (y2 - y1) * 0.3 + dir * depth),
          Point(x1 + (x2 - x1) * 0.7, y1 + (y2 - y1) * 0.7 + dir * depth),
          Point(x2, y2),
          0.18,
        );
      }
    }
  }

  /// Laissez-vibrer ("let ring") ties: a short curved tie trailing off the
  /// right of each notehead of the marked element, with no destination note.
  /// Curves opposite the stem like an ordinary tie unless [LaissezVibrer.down]
  /// forces a side.
  void _layoutLaissezVibrer() {
    for (final lv in score.laissezVibrer) {
      final idx = _tieIndexOf(lv.noteId);
      if (idx < 0) {
        continue;
      }
      final info = _tieInfos[idx];
      final dir = lv.down == null
          ? (info.stemsDown ? -1.0 : 1.0)
          : (lv.down! ? 1.0 : -1.0);
      for (final (_, _, xRight, y) in info.heads) {
        final x1 = xRight + 0.15;
        final x2 = x1 + 1.3; // trails off — there is no destination note
        final baseY = y + dir * 0.6;
        final controlY = baseY + dir * 0.5;
        _addCurve(
          Point(x1, baseY),
          Point(x1 + 0.4, controlY),
          Point(x2 - 0.35, controlY),
          Point(x2, baseY + dir * 0.15),
          0.18,
        );
      }
    }
  }

  /// v0.3.2: slurs between note elements referenced by id. The curve goes
  /// above unless every spanned note stems up; endpoints anchor just
  /// outside each end element's ink, and the arc clears everything in
  /// between.
  void _layoutSlurs() {
    // Shortest first: an inner slur settles next to its notes and the outer
    // slur, laid out after it, goes around it. In list order an outer slur
    // drawn first pushed every slur nested inside it out beyond it.
    int extent(Slur s) => (_tieIndexOf(s.endId) - _tieIndexOf(s.startId)).abs();
    // A slur given twice over the same notes is drawn once: as nested slurs
    // the copies fanned out into a stack of arcs (#14).
    final seen = <(String, String)>{};
    final unique = [
      for (final s in score.slurs)
        if (seen.add((s.startId, s.endId))) s
    ];
    final ordered = unique..sort((a, b) => extent(a).compareTo(extent(b)));
    for (final slur in ordered) {
      final startIndex = _tieIndexOf(slur.startId);
      final endIndex = _tieIndexOf(slur.endId);
      if (startIndex < 0 || endIndex < 0) {
        continue;
      }
      if (endIndex <= startIndex) {
        continue;
      }
      var spanned = _tieInfos.sublist(startIndex, endIndex + 1);
      final first = spanned.first, last = spanned.last;
      // A slur within one voice, sharing the staff with another voice, keeps
      // to its own voice: it clears only that voice's notes and sits on the
      // stem side. Counting the other voice's notes made an upper-voice slur
      // dive under the lower voice's stems (issue #2).
      final ownVoice = first.voice == last.voice &&
          _otherVoiceWithin(first.voice, first.left, last.right);
      if (ownVoice) {
        spanned = [
          for (final info in spanned)
            if (info.voice == first.voice) info,
        ];
      }
      final notes = spanned.where((i) => i.note != null).toList();

      double headCenterX(_TieInfo info) =>
          (info.heads.first.$2 + info.heads.first.$3) / 2;
      double? topOf(_TieInfo info) {
        final bounds = info.id == null ? null : _elementBounds[info.id];
        if (bounds != null) return bounds.minY;
        if (info.heads.isEmpty) return null;
        return info.heads.map((h) => h.$4).reduce(min) - 0.5;
      }

      double? bottomOf(_TieInfo info) {
        final bounds = info.id == null ? null : _elementBounds[info.id];
        if (bounds != null) return bounds.maxY;
        if (info.heads.isEmpty) return null;
        return info.heads.map((h) => h.$4).reduce(max) + 0.5;
      }

      // Only stemmed notes vote: a whole note has no stem side.
      final stemmed = notes.where((i) {
        final base = i.note!.duration.base;
        return base != DurationBase.whole &&
            base != DurationBase.breve &&
            base != DurationBase.long;
      }).toList();
      final stemsDown = stemmed.where((i) => i.stemsDown).length;
      final stemsUp = stemmed.length - stemsDown;
      final x1 = headCenterX(spanned.first);
      final x2 = headCenterX(spanned.last);
      final span = x2 - x1;
      final bool above;
      switch (slur.placement) {
        case SlurPlacement.above:
          above = true;
        case SlurPlacement.below:
          above = false;
        case SlurPlacement.auto:
          if (ownVoice) {
            // Beside another voice: on this voice's stem side.
            above = stemsUp >= stemsDown;
          } else if (stemsUp > 0 && stemsDown > 0) {
            // Mixed stems: above (#8). The old rule asked which note's ink
            // was highest, and an up-stem's TOP counted — so a run with stems
            // up then down put its slur under the staff, far from the notes.
            above = true;
          } else if (stemsUp > 0) {
            // All stems up: on the notehead side, below.
            above = false;
          } else {
            // Stems down (or none): above — except a long slur in a bass
            // clef, which keeps the low register's habit of going below.
            above = !(_isBassFamily(score.clef) && span > 20);
          }
      }
      final double y1;
      final double y2;
      final double controlY;
      // Clear everything under the arc — not just the spanned noteheads, but
      // any articulations, accidentals, ornaments or other slurs in the span
      // (via the ink skyline).
      final loX = min(x1, x2), hiX = max(x1, x2);
      if (above) {
        y1 = _slurEndpointY(topOf(spanned.first)! - 0.35, span, above: true);
        y2 = _slurEndpointY(topOf(spanned.last)! - 0.35, span, above: true);
        final noteTop = spanned.map(topOf).whereType<double>().reduce(min);
        final clearance =
            min(noteTop, _skylineTop(loX, hiX, skipBarlines: true) ?? noteTop) -
                0.4;
        controlY = min(min(y1, y2), clearance) - _slurArchDepth(span);
      } else {
        y1 =
            _slurEndpointY(bottomOf(spanned.first)! + 0.35, span, above: false);
        y2 = _slurEndpointY(bottomOf(spanned.last)! + 0.35, span, above: false);
        final noteBottom =
            spanned.map(bottomOf).whereType<double>().reduce(max);
        final clearance = max(noteBottom,
                _skylineBottom(loX, hiX, skipBarlines: true) ?? noteBottom) +
            0.4;
        controlY = max(max(y1, y2), clearance) + _slurArchDepth(span);
      }
      var start = Point(x1, y1);
      var control1 = Point(x1 + (x2 - x1) * 0.3, controlY);
      var control2 = Point(x1 + (x2 - x1) * 0.7, controlY);
      var end = Point(x2, y2);
      if ((x2 - x1) > 8) {
        final offset = _slurClearanceOffset(
          start,
          control1,
          control2,
          end,
          above: above,
        );
        if (offset != 0) {
          final endpointCap = above ? 1.4 : 0.8;
          final endpointOffset =
              offset.sign * min(offset.abs() * 0.35, endpointCap);
          start = Point(start.x, start.y + endpointOffset);
          control1 = Point(control1.x, control1.y + offset);
          control2 = Point(control2.x, control2.y + offset);
          end = Point(end.x, end.y + endpointOffset);
        }
      }
      _addCurve(
        start,
        control1,
        control2,
        end,
        0.2,
      );
      // A cubic never passes its control points, so their extremes bound it.
      _slurInk.add((
        min(start.x, end.x),
        max(start.x, end.x),
        [start.y, control1.y, control2.y, end.y].reduce(max),
      ));
    }
  }

  /// v0.3.5: dynamic markings centered below their element and hairpin
  /// wedges between two elements, both on the dynamics line under the
  /// staff (pushed lower by any element ink reaching below it).
  void _layoutDynamics() {
    double lineFor(Iterable<_TieInfo> infos) {
      var y = 6.2;
      var left = double.infinity, right = double.negativeInfinity;
      for (final info in infos) {
        final bounds = info.id == null ? null : _elementBounds[info.id];
        if (bounds != null) y = max(y, bounds.maxY + 1.0);
        left = min(left, info.left);
        right = max(right, info.right);
      }
      // Below any slur over the same span (slurs are laid out first).
      for (final (l, r, bottom) in _slurInk) {
        if (r > left && l < right) y = max(y, bottom + 0.8);
      }
      return y;
    }

    // Hairpins that touch (one ends where, or just before, the next starts)
    // and the dynamics at their ends form one run, and a run shares ONE
    // line: the lowest any of its parts needs. Per mark, a cresc. over
    // stems-up notes and the dim. after it over stems-down notes sat at
    // different heights (#9).
    final pins = <(int, int, Hairpin)>[
      for (final h in score.hairpins)
        if ((_elementIndexOf(h.startId), _elementIndexOf(h.endId))
            case (final a, final b) when a >= 0 && b > a)
          (a, b, h),
    ]..sort((x, y) => x.$1.compareTo(y.$1));
    final marks = <(int, DynamicMarking)>[
      for (final d in score.dynamics)
        if (_elementIndexOf(d.elementId) case final i when i >= 0) (i, d),
    ];
    // Runs as index ranges [lo, hi] over _tieInfos.
    final runs = <(int, int)>[];
    for (final (a, b, _) in pins) {
      if (runs.isNotEmpty && a <= runs.last.$2 + 1) {
        runs[runs.length - 1] = (runs.last.$1, max(runs.last.$2, b));
      } else {
        runs.add((a, b));
      }
    }
    int? runOf(int index) {
      for (var r = 0; r < runs.length; r++) {
        if (index >= runs[r].$1 - 1 && index <= runs[r].$2 + 1) return r;
      }
      return null;
    }

    final runLine = [
      for (final (lo, hi) in runs) lineFor(_tieInfos.sublist(lo, hi + 1)),
    ];
    for (final (index, _) in marks) {
      final r = runOf(index);
      if (r != null) runLine[r] = max(runLine[r], lineFor([_tieInfos[index]]));
    }

    // Each drawn dynamic's horizontal extent, so a hairpin starting or
    // ending at it stops short of the letters instead of running through.
    final dynamicSpan = <int, (double, double)>{};
    for (final (index, marking) in marks) {
      // A dynamic may sit on a rest: LilyPond writes a Dynamics line as
      // spacer rests (`s4\p`), and such marks were never drawn at all.
      final info = _tieInfos[index];
      final glyph = SmuflGlyph.dynamicGlyph(marking.level);
      final box = meta.bBoxOf(glyph);
      final centerX = (info.left + info.right) / 2;
      final r = runOf(index);
      // Dynamics glyphs sit on their text baseline; center their ink.
      final left = centerX - box.width / 2;
      _addGlyph(
        glyph,
        left - box.swX,
        (r == null ? lineFor([info]) : runLine[r]) + 0.6,
        elementId: marking.elementId,
      );
      dynamicSpan[index] = (left, left + box.width);
    }

    // A degenerate (start == end) or dangling hairpin was skipped above
    // instead of crashing: real imports carry them — most often a span whose
    // other end is in a part that was not imported.
    for (final (startIndex, endIndex, hairpin) in pins) {
      final start = _tieInfos[startIndex];
      final end = _tieInfos[endIndex];
      var x1 = (start.left + start.right) / 2;
      var x2 = (end.left + end.right) / 2;
      const clearance = 0.4;
      if (dynamicSpan[startIndex] case (_, final right)) {
        x1 = max(x1, right + clearance);
      }
      if (dynamicSpan[endIndex] case (final left, _)) {
        x2 = min(x2, left - clearance);
      }
      // Level with the middle of the dynamic letters on the same line (they
      // sit on its baseline + 0.6 and stand about 1.1 tall).
      var midY = runLine[runOf(startIndex)!] + 0.05;
      if (x2 - x1 < 1.5) {
        // No room between its dynamics for a readable wedge: it runs its
        // full span just under the letters instead.
        x1 = (start.left + start.right) / 2;
        x2 = (end.left + end.right) / 2;
        midY += 2.1; // below the descenders (p, f), with a little air
      }
      final thickness = meta.engravingDefault('hairpinThickness', orElse: 0.16);
      const halfOpening = 0.55;
      final openX = hairpin.type == HairpinType.crescendo ? x2 : x1;
      final tipX = hairpin.type == HairpinType.crescendo ? x1 : x2;
      _addLine(Point(tipX, midY), Point(openX, midY - halfOpening), thickness);
      _addLine(Point(tipX, midY), Point(openX, midY + halfOpening), thickness);
    }
  }

  /// v0.7.2: sustain-pedal marks — "Ped." under the start note and a release
  /// star under the end note, on a line below the staff and any dynamics.
  void _layoutPedals() {
    for (final pedal in score.pedals) {
      final startIdx = _tieIndexOf(pedal.startId);
      final endIdx = _tieIndexOf(pedal.endId);
      // Skip a dangling or backwards pedal rather than crash (see hairpins).
      if (startIdx < 0 || endIdx < 0 || endIdx < startIdx) continue;
      final start = _tieInfos[startIdx];
      final end = _tieInfos[endIdx];
      // Below all spanned ink and clear of the dynamics line.
      var y = 8.0;
      for (final info in _tieInfos.sublist(startIdx, endIdx + 1)) {
        final bounds = info.id == null ? null : _elementBounds[info.id];
        if (bounds != null) y = max(y, bounds.maxY + 1.2);
      }
      void mark(String glyph, _TieInfo info, String id) {
        final box = meta.bBoxOf(glyph);
        _addGlyph(
            glyph, (info.left + info.right) / 2 - box.swX - box.width / 2, y,
            elementId: id);
      }

      mark(SmuflGlyph.keyboardPedalPed, start, pedal.startId);
      mark(SmuflGlyph.keyboardPedalUp, end, pedal.endId);
    }
  }

  /// v0.6.4: ottava brackets — the "8va"/"8vb" label at the span start
  /// with a dashed line to the span end and a small closing hook,
  /// above (8va) or below (8vb) the spanned ink.
  void _layoutOttavas() {
    if (score.ottavas.isEmpty) return;
    // Every element (rests too — a bracket may start or end on one).
    final indexOf = <String, int>{
      for (var i = 0; i < _tieInfos.length; i++)
        if (_tieInfos[i].id != null) _tieInfos[i].id!: i,
    };
    for (final ottava in score.ottavas) {
      final from = indexOf[ottava.startId], to = indexOf[ottava.endId];
      if (from == null || to == null) {
        continue;
      }
      final start = _tieInfos[from], end = _tieInfos[to];
      final left = start.left;
      final right = end.right;
      double edge = ottava.down ? 5.0 : -1.0;
      // Clear only the shifted notes under THIS bracket. Scanning every
      // element put each bracket at the height of the most extreme shifted
      // note anywhere in the score — and cost O(ottavas × notes).
      for (final info in _tieInfos.sublist(min(from, to), max(from, to) + 1)) {
        if (info.id == null || !_ottavaShift.containsKey(info.id)) continue;
        final bounds = _elementBounds[info.id];
        if (bounds == null) continue;
        edge = ottava.down
            ? max(edge, bounds.maxY + 0.6)
            : min(edge, bounds.minY - 0.6);
      }
      final y = edge;
      _primitives.add(TextPrimitive(
        ottava.down ? '8vb' : '8va',
        Point(left + 0.9, y + 0.35),
        size: 1.6,
      ));
      // Dashed line from after the label to the span end.
      var x = left + 2.2;
      while (x < right - 0.7) {
        _addLine(Point(x, y), Point(min(x + 0.5, right), y), 0.12);
        x += 1.0;
      }
      // Closing hook toward the staff.
      _addLine(
        Point(right, y),
        Point(right, y + (ottava.down ? -0.75 : 0.75)),
        0.12,
      );
      _ink.expand(left, y - 0.8, right, y + 0.8);
    }
  }

  /// Extended trills: a `tr` glyph over the start note, then a run of
  /// `wiggleTrill` segments to the end of the span, above the staff ink.
  void _layoutTrillExtensions() {
    if (score.trillExtensions.isEmpty) return;
    final infoOf = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    final trWidth = _glyphWidth(SmuflGlyph.ornamentTrill);
    final wiggleWidth = _glyphWidth(SmuflGlyph.wiggleTrill);
    for (final trill in score.trillExtensions) {
      final start = infoOf[trill.startId];
      final end = infoOf[trill.endId];
      if (start == null || end == null) {
        continue;
      }
      final left = start.left;
      // Run the wavy line to the end of the trilled note's duration — the
      // onset (left edge) of the next note after the span, or its own right
      // edge if it is the last note.
      var right = end.right;
      final endIdx = _tieInfos.indexOf(end);
      for (var j = endIdx + 1; j < _tieInfos.length; j++) {
        if (_tieInfos[j].left > end.right) {
          right = _tieInfos[j].left - 0.4;
          break;
        }
      }
      final top = _skylineTop(left, right) ?? 0.0;
      final y = min(-1.2, top - 0.6);
      // The `tr` sits over the start note; its baseline is ~0.7 below the top.
      _addGlyph(SmuflGlyph.ornamentTrill, left, y + 0.9,
          elementId: trill.startId);
      // Wavy line from after the `tr` to the span end, tiling wiggle segments.
      var x = left + trWidth + 0.1;
      while (x + wiggleWidth <= right + 0.05) {
        _addGlyph(SmuflGlyph.wiggleTrill, x, y + 0.6, elementId: trill.startId);
        x += wiggleWidth;
      }
      _ink.expand(left, y - 0.2, right, y + 1.0);
    }
  }

  /// Breath marks / caesuras: a comma or "railroad tracks" just after the
  /// note, at the top of the staff.
  void _layoutBreathMarks() {
    if (score.breathMarks.isEmpty) return;
    final infoOf = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    for (final bm in score.breathMarks) {
      final info = infoOf[bm.noteId];
      if (info == null || info.note == null) {
        continue;
      }
      final glyph = bm.symbol == BreathSymbol.comma
          ? SmuflGlyph.breathMarkComma
          : SmuflGlyph.caesura;
      // Just after the note, sitting at (comma) or above (caesura) the top line.
      final x = info.right + 0.35;
      final y = bm.symbol == BreathSymbol.comma ? 0.0 : -0.5;
      _addGlyph(glyph, x, y, elementId: bm.noteId);
    }
  }
}
