part of 'layout_engine.dart';

// Barlines, repeats, voltas, segmented (grand-staff) barlines, the final
// barline, and mid-measure navigation marks (segno/coda/D.C./D.S.). An
// extension on the builder; behaviour unchanged.

extension _Barlines on _LayoutBuilder {
  /// The pen for this staff's barlines (5-line staff, y 0..4).
  BarlinePen get _pen => BarlinePen(
        s,
        top: 0,
        bottom: 4,
        line: (x, y0, y1, thickness, {round = false}) =>
            _addLine(Point(x, y0), Point(x, y1), thickness, round: round),
        dots: (x) {
          _addGlyph(SmuflGlyph.repeatDots, x, 4);
          return _glyphWidth(SmuflGlyph.repeatDots);
        },
      );

  /// v0.3.8: `|:` — thick line, thin line, dots.
  void _addStartRepeat() => _x = _pen.startRepeat(_x);

  /// v0.3.8: `:|` — dots, thin line, thick line.
  void _addEndRepeat() => _x = _pen.endRepeat(_x);

  /// v0.3.8: volta (ending) bracket with its number over the measure.
  void _addVolta(int number, double startX, double endX) {
    const y = -1.8;
    const hook = 0.8;
    final thickness =
        meta.engravingDefault('repeatEndingLineThickness', orElse: 0.16);
    _addLine(Point(startX, y), Point(endX - 0.3, y), thickness);
    _addLine(Point(startX, y), Point(startX, y + hook), thickness);
    _addLine(Point(endX - 0.3, y), Point(endX - 0.3, y + hook), thickness);
    var digitX = startX + 0.5;
    for (final ch in number.toString().split('')) {
      final glyph = SmuflGlyph.tupletDigit(int.parse(ch));
      _addGlyph(glyph, digitX - meta.bBoxOf(glyph).swX, y + 1.0, scale: 0.8);
      digitX += _glyphWidth(glyph) * 0.8;
    }
  }

  /// v0.7.1: navigation marks above the staff, all on one shared clearance
  /// line (as engravers align them per system). Targets
  /// ([NavigationMark.segno]/[NavigationMark.coda]) draw their SMuFL glyph at
  /// the measure's left edge; every instruction draws its text word
  /// ([SmuflGlyph.navigationLabel]) right-aligned above the closing barline.
  void _layoutNavigation() {
    final marks = <(MeasureRegion, NavigationMark)>[
      for (final region in _measureRegions)
        if (score.measures[region.index].navigation case final mark?)
          (region, mark),
    ];
    if (marks.isEmpty) return;
    // One clearance line for the marks: a fixed gap above the ink under the
    // span they occupy (not the whole system's tallest note).
    var regionL = double.infinity, regionR = double.negativeInfinity;
    for (final (region, _) in marks) {
      regionL = min(regionL, region.startX);
      regionR = max(regionR, region.endX);
    }
    final localTop = _skylineTop(regionL, regionR) ?? 0;
    final clearance = min(-1.0, localTop - s.navigationGap);
    for (final (region, mark) in marks) {
      final glyph = SmuflGlyph.navigationGlyph(mark);
      if (glyph != null) {
        // Baseline so the (y-up) bbox bottom lands on `clearance`; the tall
        // segno/coda glyph then sits entirely above the staff.
        _addGlyph(glyph, region.startX, clearance + meta.bBoxOf(glyph).swY);
        continue;
      }
      final label = SmuflGlyph.navigationLabel(mark)!;
      final size = s.navigationSize;
      final halfWidth = 0.25 * size * label.length;
      final centerX = region.endX - 0.3 - halfWidth;
      // Baseline so the text's descender rests on `clearance`.
      final baselineY = clearance - 0.25 * size;
      _primitives
          .add(TextPrimitive(label, Point(centerX, baselineY), size: size));
      _expand(
        null,
        centerX - halfWidth,
        baselineY - 0.72 * size,
        centerX + halfWidth,
        clearance,
      );
    }
  }

  /// A mid-score barline in the requested [style] (the measure's right edge).
  void _addBarline(BarlineStyle style) => _x = _pen.barline(style, _x);

  /// A line padded to its target width: the last measure runs on to the
  /// moved closing barline (else the padding belonged to no measure, and a
  /// tap there hit nothing).
  void _extendLastMeasure() {
    if (_measureRegions.isEmpty) return;
    final last = _measureRegions.removeLast();
    _measureRegions
        .add(MeasureRegion(last.index, startX: last.startX, endX: _x));
  }

  /// Rule 13: `barlineFinal` (thin + thick) at the end; returns the width.
  /// With [finalBarline] false (systems that continue on the next line)
  /// a plain thin barline closes the layout instead.
  double _addFinalBarline() {
    // An explicit barline style on the last measure wins (a double bar, dashed
    // divider, or no barline ending a section) — honored even at a system
    // break. Only the default thin+thick "end of piece" is suppressed on a
    // continuation system (where the score's real end is elsewhere).
    final last = score.measures.isEmpty ? null : score.measures.last;
    // A repeat at the end IS the closing barline: the bar loop has drawn it
    // (dots, thin, thick), so the staff ends at its thick line. Adding the
    // end-of-piece thin+thick behind it doubled the closing barline (#19).
    if (last != null && last.endRepeat) return _x - s.barlineGap;
    if (last != null && last.barline != BarlineStyle.normal) {
      final style = last.barline;
      final (lead, width) = _pen.ink(style);
      // Justified like the default barline: its right edge on targetWidth.
      if (targetWidth != null && targetWidth! > _x + lead + width) {
        _x = targetWidth! - lead - width;
        _extendLastMeasure();
      }
      final barX = _x;
      _addBarline(style);
      // The staff ends at the barline's outer edge, not a barline gap past
      // it (a gap of bare staff after every explicit `light-heavy`).
      return style == BarlineStyle.none ? barX : barX + lead + width;
    }
    var thinX = _x;
    if (targetWidth != null && targetWidth! > thinX) {
      thinX = targetWidth! - s.thinBarlineThickness / 2;
      _x = thinX;
      _extendLastMeasure();
    }
    _addLine(Point(thinX, 0), Point(thinX, 4), s.thinBarlineThickness);
    if (!finalBarline) return thinX + s.thinBarlineThickness / 2;
    final thickX = thinX +
        s.thinBarlineThickness / 2 +
        s.barlineSeparation +
        s.thickBarlineThickness / 2;
    _addLine(Point(thickX, 0), Point(thickX, 4), s.thickBarlineThickness);
    return thickX + s.thickBarlineThickness / 2;
  }
}
