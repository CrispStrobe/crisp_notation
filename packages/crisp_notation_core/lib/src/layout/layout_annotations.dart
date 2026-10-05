part of 'layout_engine.dart';

// Text over/under the staff: lyrics, annotations/chord symbols and figured
// bass, plus the text-width estimate and the bracket helper. Drawing passes
// are an extension; the pure text/glyph helpers are top-level library-private.
// Behaviour unchanged.

/// v0.4.4: lyric syllables on a shared baseline below all other ink,
/// centered under their note; hyphens between connected syllables,
/// extender lines under melismas.
///
/// Core cannot measure text, so syllable widths are estimated at
/// 0.5 em per character (renderers center the real text on the same
/// anchor; see [TextPrimitive]).
/// Half the estimated rendered width of [text] at em [size], in staff
/// spaces. The layout has no text-font metrics, so this is a deliberately
/// generous per-character average (≈0.62 em) chosen so the reserved box
/// covers wide glyphs (uppercase, `m`, `w`) — the space budget that keeps
/// words from overlapping. Text is center-anchored, so callers use ±this.
double _estTextHalfWidth(String text, double size) =>
    0.31 * size * max(1, text.length);

/// Nudges box [centers] rightward (never left) as little as possible so
/// consecutive boxes `center ± halfWidth` keep at least [gap] between them.
/// The lists are parallel and must be in left-to-right order; guarantees no
/// horizontal overlap. The layout has no text-font metrics, so callers pass
/// a per-character width estimate — enough to keep words from colliding.
void _spreadRight(List<double> centers, List<double> halfWidths, double gap) {
  for (var i = 1; i < centers.length; i++) {
    final minCenter = centers[i - 1] + halfWidths[i - 1] + gap + halfWidths[i];
    if (centers[i] < minCenter) centers[i] = minCenter;
  }
}

/// Parses a figured-bass figure string (e.g. `6`, `#6`, `b7`, `4+`) into the
/// SMuFL figured-bass glyphs to draw left-to-right. Digits map to
/// `figbass0`–`figbass9`; `#`/`♯`, `b`/`♭`, `n`/`♮` and `+` to the
/// alteration glyphs. Unknown characters are skipped.
List<String> _figuredBassGlyphs(String figure) {
  final out = <String>[];
  final chars = figure.split('');
  for (var i = 0; i < chars.length; i++) {
    final ch = chars[i];
    final code = ch.codeUnitAt(0);
    if (code >= 0x30 && code <= 0x39) {
      final digit = code - 0x30;
      // A trailing backslash slashes (raises) the digit — the engraver's
      // alternative to a prefixed sharp (e.g. `6\` = raised sixth).
      if (i + 1 < chars.length && chars[i + 1] == r'\') {
        final raised = SmuflGlyph.figbassRaisedDigit(digit);
        if (raised != null) {
          out.add(raised);
        } else {
          out
            ..add(SmuflGlyph.figbassDigit(digit))
            ..add(SmuflGlyph.figbassCombiningRaising);
        }
        i++; // consume the backslash
      } else {
        out.add(SmuflGlyph.figbassDigit(digit));
      }
    } else {
      switch (ch) {
        case '#':
        case '♯':
          out.add(SmuflGlyph.figbassSharp);
        case 'b':
        case '♭':
          out.add(SmuflGlyph.figbassFlat);
        case 'n':
        case '♮':
          out.add(SmuflGlyph.figbassNatural);
        case '+':
          out.add(SmuflGlyph.figbassPlus);
      }
    }
  }
  return out;
}

extension _Annotations on _LayoutBuilder {
  /// Draws a [label] + dashed bracket above the staff spanning the notes
  /// [startId]…[endId], sitting above any ink under the span.
  void _textBracketAbove(
      String label, String startId, String endId, Map<String, _TieInfo> of) {
    final start = of[startId];
    final end = of[endId];
    if (start == null || end == null) {
      throw ArgumentError(
          'palm-mute/let-ring references an unknown note element id');
    }
    final left = start.left;
    final right = end.right;
    const size = 1.1;
    final top = _skylineTop(left, right) ?? 0.0;
    final y = min(-1.4, top - 0.8);
    final labelHalf = _estTextHalfWidth(label, size);
    _primitives.add(TextPrimitive(
      label,
      Point(left + labelHalf, y + 0.35),
      size: size,
    ));
    // Dashed line from just after the label to the span end.
    final lineStart = left + 2 * labelHalf + 0.3;
    var x = lineStart;
    while (x < right - 0.2) {
      _addLine(Point(x, y), Point(min(x + 0.5, right), y), 0.12);
      x += 0.78;
    }
    // Downward end hook (only when the span reaches past the label).
    if (right > lineStart + 0.2) {
      _addLine(Point(right, y), Point(right, y + 0.6), 0.12);
    }
    _ink.expand(left, y - 0.4, right, y + 0.6);
  }

  void _layoutLyrics() {
    if (score.lyrics.isEmpty) return;
    final size = s.lyricSize;
    final lineHeight = size * 1.5;

    final infoIndexOf = <String, int>{
      for (var i = 0; i < _tieInfos.length; i++)
        if (_tieInfos[i].id != null) _tieInfos[i].id!: i,
    };
    double halfWidthOf(String text) => _estTextHalfWidth(text, size);

    // First verse's baseline: below the ink under the lyric span (a per-column
    // skyline), so a low note elsewhere on the line does not push the words
    // down. Extra verses stack below it.
    var regionL = double.infinity, regionR = double.negativeInfinity;
    for (final lyric in score.lyrics) {
      final index = infoIndexOf[lyric.elementId];
      if (index == null) continue;
      regionL = min(regionL, _tieInfos[index].left);
      regionR = max(regionR, _tieInfos[index].right);
    }
    final localBottom = _skylineBottom(regionL, regionR) ?? 4;
    final firstBaseline = max(6.5, localBottom + s.lyricGap + 0.72 * size);

    // Group syllables into verses; each verse is its own stacked row.
    final byVerse = <int, List<Lyric>>{};
    for (final lyric in score.lyrics) {
      byVerse.putIfAbsent(lyric.verse, () => []).add(lyric);
    }
    final verses = byVerse.keys.toList()..sort();

    for (var row = 0; row < verses.length; row++) {
      final lyrics = byVerse[verses[row]]!;
      final baselineY = firstBaseline + row * lineHeight;
      // Notes that carry a syllable *in this verse* — an extender stops here.
      final lyricIds = {for (final l in lyrics) l.elementId};

      // Anchor x per syllable, then keep them from colliding on close notes:
      // push each right of the previous by its width + a word gap. Hyphens and
      // extenders below use the adjusted centers, so they stay aligned.
      final centers = <double>[];
      for (final lyric in lyrics) {
        final index = infoIndexOf[lyric.elementId];
        if (index == null || _tieInfos[index].note == null) {
          continue;
        }
        final info = _tieInfos[index];
        centers.add((info.left + info.right) / 2);
      }
      _spreadRight(
        centers,
        [for (final l in lyrics) halfWidthOf(l.text)],
        0.4 * size,
      );

      for (var i = 0; i < lyrics.length; i++) {
        final lyric = lyrics[i];
        final centerX = centers[i];
        final halfWidth = halfWidthOf(lyric.text);
        _primitives.add(TextPrimitive(
          lyric.text,
          Point(centerX, baselineY),
          size: size,
          elementId: lyric.elementId,
        ));
        _expand(
          lyric.elementId,
          centerX - halfWidth,
          baselineY - 0.72 * size,
          centerX + halfWidth,
          baselineY + 0.25 * size,
        );

        if (lyric.hyphenToNext && i + 1 < lyrics.length) {
          // Dash centered between this syllable's end and the next one's
          // start, on the x-height line.
          final gapStart = centerX + halfWidth;
          final gapEnd = centers[i + 1] - halfWidthOf(lyrics[i + 1].text);
          if (gapEnd > gapStart + 0.2) {
            final mid = (gapStart + gapEnd) / 2;
            final dashHalf = min(0.3, (gapEnd - gapStart) / 4);
            _addLine(
              Point(mid - dashHalf, baselineY - 0.25 * size),
              Point(mid + dashHalf, baselineY - 0.25 * size),
              0.1,
              elementId: lyric.elementId,
            );
          }
        }

        if (lyric.elidesToNext &&
            i + 1 < lyrics.length &&
            lyrics[i + 1].elementId == lyric.elementId) {
          // Elision (synalepha): an undertie (‿) below the two syllables sung
          // on the one note, bridging this syllable's end to the next's start.
          final x1 = centerX + halfWidth * 0.6;
          final x2 = centers[i + 1] - halfWidthOf(lyrics[i + 1].text) * 0.6;
          if (x2 > x1 + 0.1) {
            final y = baselineY + 0.12 * size;
            final dip = y + 0.18 * size;
            _addCurve(
              Point(x1, y),
              Point(x1 + (x2 - x1) * 0.3, dip),
              Point(x1 + (x2 - x1) * 0.7, dip),
              Point(x2, y),
              0.1,
            );
          }
        }

        if (lyric.extender) {
          // Extender runs along the baseline under the following voice-1
          // notes that carry no syllable of their own in this verse.
          final startIndex = infoIndexOf[lyric.elementId]!;
          double? endX;
          for (var j = startIndex + 1; j < _tieInfos.length; j++) {
            final info = _tieInfos[j];
            if (info.voice != 0 || info.note == null) continue;
            if (info.id != null && lyricIds.contains(info.id)) break;
            endX = info.right;
          }
          if (endX != null && endX > centerX + halfWidth + 0.2) {
            _addLine(
              Point(centerX + halfWidth + 0.15, baselineY),
              Point(endX, baselineY),
              0.1,
              elementId: lyric.elementId,
            );
          }
        }
      }
    }
  }

  /// v0.4.5: text annotations (chord symbols, tempo/rehearsal text) on a
  /// shared baseline above their note. The baseline clears only the ink within
  /// the horizontal span the annotations occupy (a per-column skyline), so a
  /// high note elsewhere on the line no longer lifts the whole chord-symbol row.
  void _layoutAnnotations() {
    if (score.annotations.isEmpty && score.chordSymbols.isEmpty) return;
    final size = s.annotationSize;
    final infoOf = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };

    final aboveItems = <(String, String)>[
      for (final a in score.annotations)
        if (a.placement == AnnotationPlacement.above) (a.elementId, a.text),
      for (final c in score.chordSymbols) (c.elementId, c.text),
    ];
    final belowItems = <(String, String)>[
      for (final a in score.annotations)
        if (a.placement == AnnotationPlacement.below) (a.elementId, a.text),
    ];

    void layoutRow(List<(String, String)> items, {required bool above}) {
      if (items.isEmpty) return;
      // Gather each item's note-centered anchor and estimated half-width, then
      // order left-to-right and spread so wide symbols on close notes never
      // overlap.
      final placed =
          <(String, String, double, double)>[]; // id, text, ctr, half
      for (final (id, text) in items) {
        // A rest is a valid anchor — "Fine", tempo text or "N.C." over a rest
        // is ordinary engraving, and the LilyPond and kern readers produce it
        // from real files (rejecting it made 14% of a LilyPond corpus fail to
        // lay out at all). Only an id that names no element is an error.
        final info = infoOf[id];
        if (info == null) {
          throw ArgumentError(
              'annotation/chord symbol references an unknown element id: $id');
        }
        placed.add((
          id,
          text,
          (info.left + info.right) / 2,
          _estTextHalfWidth(text, size),
        ));
      }
      placed.sort((a, b) => a.$3.compareTo(b.$3));
      final centers = [for (final p in placed) p.$3];
      final halves = [for (final p in placed) p.$4];
      _spreadRight(centers, halves, 0.4 * size);

      // The row clears the local skyline under the text span, not unrelated
      // high/low ink elsewhere on the staff.
      var regionL = double.infinity, regionR = double.negativeInfinity;
      for (var i = 0; i < centers.length; i++) {
        regionL = min(regionL, centers[i] - halves[i]);
        regionR = max(regionR, centers[i] + halves[i]);
      }
      final baselineY = above
          ? min(
              -1.0,
              (_skylineTop(regionL, regionR) ?? 0) -
                  s.annotationGap -
                  0.25 * size)
          : max(
              6.0,
              (_skylineBottom(regionL, regionR) ?? 4) +
                  s.annotationGap +
                  0.72 * size);

      for (var i = 0; i < placed.length; i++) {
        final (id, text, _, halfWidth) = placed[i];
        final centerX = centers[i];
        _primitives.add(TextPrimitive(
          text,
          Point(centerX, baselineY),
          size: size,
          elementId: id,
        ));
        _expand(
          id,
          centerX - halfWidth,
          baselineY - 0.72 * size,
          centerX + halfWidth,
          baselineY + 0.25 * size,
        );
      }
    }

    layoutRow(aboveItems, above: true);
    layoutRow(belowItems, above: false);
  }

  /// Figured-bass figures stacked under each bass note, below all other ink
  /// (so it clears lyrics when both are present). Figures in one column align
  /// to their note; rows stack downward.
  void _layoutFiguredBass() {
    if (score.figuredBass.isEmpty) return;
    const rowHeight = 1.7;
    final infoOf = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    // Clear only the ink under the figured bass's own note span (a per-column
    // skyline), not the whole system's lowest note.
    var regionL = double.infinity, regionR = double.negativeInfinity;
    for (final fb in score.figuredBass) {
      final info = infoOf[fb.noteId];
      if (info == null) continue;
      regionL = min(regionL, info.left);
      regionR = max(regionR, info.right);
    }
    final localBottom = _skylineBottom(regionL, regionR) ?? 4;
    final topBaseline = max(6.2, localBottom + s.lyricGap + 1.0);
    // Left edges of every resolved figured-bass column, so a continuation
    // ('_') row can draw its extension line rightward to the next column.
    final columnLefts = <double>[
      for (final fb in score.figuredBass)
        if (infoOf[fb.noteId] case final i?) i.left,
    ]..sort();
    for (final fb in score.figuredBass) {
      final info = infoOf[fb.noteId];
      if (info == null || info.note == null) {
        continue;
      }
      final centerX = (info.left + info.right) / 2;
      for (var row = 0; row < fb.figures.length; row++) {
        final y = topBaseline + row * rowHeight;
        // A '_' row is a held figure: draw a horizontal extension line reaching
        // the next figured-bass column (or this note's right edge if last).
        if (fb.figures[row] == '_') {
          final next = columnLefts.firstWhere(
            (l) => l > info.left + 1e-6,
            orElse: () => info.right,
          );
          final lineY = y - 0.5;
          _addLine(
              Point(info.left, lineY), Point(next, lineY), s.staffLineThickness,
              elementId: fb.noteId);
          continue;
        }
        final glyphs = _figuredBassGlyphs(fb.figures[row]);
        if (glyphs.isEmpty) continue;
        final widths = [for (final g in glyphs) _glyphWidth(g)];
        final total =
            widths.fold(0.0, (a, b) => a + b) + 0.1 * (glyphs.length - 1);
        var x = centerX - total / 2;
        for (var k = 0; k < glyphs.length; k++) {
          _addGlyph(glyphs[k], x, y, elementId: fb.noteId);
          x += widths[k] + 0.1;
        }
      }
    }
  }
}
