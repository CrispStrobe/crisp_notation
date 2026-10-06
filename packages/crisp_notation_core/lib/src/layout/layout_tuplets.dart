part of 'layout_engine.dart';

// Tuplet ratio validation and bracket/number drawing.
// Extracted from layout_engine.dart; behaviour unchanged.

extension _Tuplets on _LayoutBuilder {
  void _validateTuplets(Measure measure) {
    // Validate per voice — each span's indices address its own voice's list.
    for (var v = 0; v < 4; v++) {
      final len = measure.voiceAt(v).length;
      final seen = <int>{};
      for (final span in measure.tupletsForVoice(v)) {
        if (span.endIndex >= len) {
          throw ArgumentError(
            '$span exceeds voice ${v + 1} ($len elements)',
          );
        }
        for (var i = span.startIndex; i <= span.endIndex; i++) {
          if (!seen.add(i)) {
            throw ArgumentError('Tuplet spans overlap at element $i');
          }
        }
      }
    }
  }

  /// v0.3.3: tuplet ratio digit with a bracket, on the stem side of the
  /// group.
  void _layoutTuplets(Measure measure, Map<int, int> tieIndexOf) {
    for (final span in measure.tuplets) {
      // Inner voices (2-4) don't have a tieIndexOf map; draw their brackets from
      // element bounds (by id) with the voice's fixed stem direction instead.
      if (span.voice != 0) {
        _layoutInnerVoiceTuplet(measure, span);
        continue;
      }
      final infos = [
        for (var i = span.startIndex; i <= span.endIndex; i++)
          _tieInfos[tieIndexOf[i]!],
      ];
      final notes = infos.where((i) => i.note != null).toList();
      final downCount = notes.where((i) => i.stemsDown).length;
      final below = notes.isNotEmpty && downCount * 2 >= notes.length;

      final x1 = infos.first.left - 0.2;
      final x2 = infos.last.right + 0.2;
      double topOf(_TieInfo info) =>
          (info.id == null ? null : _elementBounds[info.id]?.minY) ?? -1.0;
      double bottomOf(_TieInfo info) =>
          (info.id == null ? null : _elementBounds[info.id]?.maxY) ?? 5.0;

      final double bracketY;
      final double hookDir;
      if (below) {
        bracketY = _tupletLineBeyond(infos.map(bottomOf).reduce(max), x1, x2,
            below: true);
        hookDir = -1;
      } else {
        bracketY = _tupletLineBeyond(infos.map(topOf).reduce(min), x1, x2,
            below: false);
        hookDir = 1;
      }
      _drawTupletBracket(x1, x2, bracketY, hookDir, span.actual);
    }
  }

  /// Draws a tuplet bracket for an inner voice (2-4) from its notes' bounds.
  /// The bracket sits below odd voices (stems down) and above even ones.
  void _layoutInnerVoiceTuplet(Measure measure, TupletSpan span) {
    final voice = measure.voiceAt(span.voice);
    final bounds = <_Bounds>[];
    for (var i = span.startIndex; i <= span.endIndex; i++) {
      final id = voice[i].id;
      final b = id == null ? null : _elementBounds[id];
      if (b != null && !b.isEmpty) bounds.add(b);
    }
    if (bounds.isEmpty) return;
    final x1 = bounds.map((b) => b.minX).reduce(min) - 0.2;
    final x2 = bounds.map((b) => b.maxX).reduce(max) + 0.2;
    final below = span.voice.isOdd; // voices 2 & 4 stem down
    final bracketY = below
        ? _tupletLineBeyond(bounds.map((b) => b.maxY).reduce(max), x1, x2,
            below: true)
        : _tupletLineBeyond(bounds.map((b) => b.minY).reduce(min), x1, x2,
            below: false);
    _drawTupletBracket(x1, x2, bracketY, below ? -1.0 : 1.0, span.actual);
  }

  /// The bracket line's y beyond [edge] (the group's own outermost ink) and
  /// whatever else is drawn over [x1]..[x2] — the beam above all, which is
  /// not part of any note's bounds. The digit is centred ON the line and is
  /// about 1.5 spaces tall, so the line keeps half a digit plus a gap clear:
  /// at 0.7 the "3" reached back into the beam and the staff lines.
  double _tupletLineBeyond(double edge, double x1, double x2,
      {required bool below}) {
    final digitHalf = meta.bBoxOf(SmuflGlyph.tupletDigit(3)).height / 2;
    final clearance = digitHalf + 0.35;
    // And outside the staff: a digit across the staff lines reads as a
    // clash with them, so the line never sits nearer than that to the
    // outer staff line.
    if (below) {
      final ink = _skylineBottom(x1, x2, skipBarlines: true) ?? edge;
      return max(max(edge, ink), (staffLineCount - 1).toDouble()) + clearance;
    }
    final ink = _skylineTop(x1, x2, skipBarlines: true) ?? edge;
    return min(min(edge, ink), 0.0) - clearance;
  }

  /// Emits the bracket lines + ratio digit(s) for a tuplet spanning [x1]..[x2]
  /// with its horizontal at [bracketY] and hooks in direction [hookDir].
  void _drawTupletBracket(
      double x1, double x2, double bracketY, double hookDir, int actual) {
    final digits = [
      for (final ch in actual.toString().split(''))
        SmuflGlyph.tupletDigit(int.parse(ch)),
    ];
    final digitsWidth = digits.fold(0.0, (sum, g) => sum + _glyphWidth(g));
    final thickness =
        meta.engravingDefault('tupletBracketThickness', orElse: 0.16);
    final midX = (x1 + x2) / 2;
    final gap = digitsWidth / 2 + 0.3;

    _addLine(Point(x1, bracketY), Point(midX - gap, bracketY), thickness);
    _addLine(Point(midX + gap, bracketY), Point(x2, bracketY), thickness);
    _addLine(
        Point(x1, bracketY), Point(x1, bracketY + hookDir * 0.7), thickness);
    _addLine(
        Point(x2, bracketY), Point(x2, bracketY + hookDir * 0.7), thickness);

    var digitX = midX - digitsWidth / 2;
    for (final glyph in digits) {
      _addGlyph(glyph, digitX - meta.bBoxOf(glyph).swX, bracketY + 0.75);
      digitX += _glyphWidth(glyph);
    }
  }
}
