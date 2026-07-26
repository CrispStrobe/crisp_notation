part of 'layout_engine.dart';

// Per-note marks drawn around the notehead: articulations, fingerings and jazz articulations.
// Extracted from layout_engine.dart; behaviour unchanged.

extension _PerNoteMarks on _LayoutBuilder {
  /// v0.3.4: articulation marks on the notehead side (opposite the stem),
  /// stacked outward in enum order; fermatas always go above the element
  /// and outside the staff.
  void _layoutArticulations(
    List<MusicElement> elements,
    Map<int, int> tieIndexOf,
  ) {
    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      if (element is! NoteElement ||
          (element.articulations.isEmpty && element.ornament == null)) {
        continue;
      }
      final info = _tieInfos[tieIndexOf[i]!];
      final centerX = (info.left + info.right) / 2;
      final above = info.stemsDown; // notehead side = opposite the stem
      final headYs = info.heads.map((h) => h.$4);
      var y = above ? headYs.reduce(min) - 0.75 : headYs.reduce(max) + 0.75;
      for (final articulation in Articulation.values) {
        if (articulation == Articulation.fermata ||
            articulation == Articulation.upBow ||
            articulation == Articulation.downBow ||
            !element.articulations.contains(articulation)) {
          continue;
        }
        final glyph = SmuflGlyph.articulationGlyph(articulation, above: above);
        final box = meta.bBoxOf(glyph);
        _addGlyph(glyph, centerX - box.swX - box.width / 2, y,
            elementId: element.id);
        y += (above ? -1 : 1) * (box.height + 0.45);
      }
      final bounds = element.id == null ? null : _elementBounds[element.id];
      var top = min(bounds?.minY ?? headYs.reduce(min), -0.5);
      // Bowing marks (up/down bow) always sit above the staff, like fermata.
      for (final bow in const [Articulation.downBow, Articulation.upBow]) {
        if (!element.articulations.contains(bow)) continue;
        final glyph = SmuflGlyph.articulationGlyph(bow, above: true);
        final box = meta.bBoxOf(glyph);
        _addGlyph(glyph, centerX - box.swX - box.width / 2, top - 0.4,
            elementId: element.id);
        top -= box.height + 0.4;
      }
      if (element.articulations.contains(Articulation.fermata)) {
        final glyph =
            SmuflGlyph.articulationGlyph(Articulation.fermata, above: true);
        final box = meta.bBoxOf(glyph);
        _addGlyph(glyph, centerX - box.swX - box.width / 2, top - 0.4,
            elementId: element.id);
        top -= box.height + 0.4;
      }
      // v0.6.2: the ornament sits above everything else on the element.
      final ornament = element.ornament;
      if (ornament != null) {
        final glyph = SmuflGlyph.ornamentGlyph(ornament);
        final box = meta.bBoxOf(glyph);
        final oy = top - 0.4;
        _addGlyph(glyph, centerX - box.swX - box.width / 2, oy,
            elementId: element.id);
        // Baroque trill variants: a small accidental centered above the `tr`.
        final alter = ornament.trillAccidentalAlter;
        if (alter != null) {
          final accGlyph = switch (alter) {
            1 => SmuflGlyph.accidentalSharp,
            -1 => SmuflGlyph.accidentalFlat,
            _ => SmuflGlyph.accidentalNatural,
          };
          const accScale = 0.6;
          final accBox = meta.bBoxOf(accGlyph);
          _addGlyph(
            accGlyph,
            centerX - (accBox.swX + accBox.width / 2) * accScale,
            oy - box.height - 0.15,
            elementId: element.id,
            scale: accScale,
          );
        }
      }
    }
  }

  /// v0.7.2: fingering digits stacked above the note, from the topmost
  /// notehead upward (first entry nearest the note).
  void _layoutFingerings(
    List<MusicElement> elements,
    Map<int, int> tieIndexOf,
  ) {
    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      if (element is! NoteElement) continue;
      // Marks computed at display time (an arranger fingering a score it did
      // not build) are appended after the note's own — see `extraFingerings`.
      final extra = element.id == null ? null : extraFingerings[element.id];
      final marks = extra == null
          ? element.fingerings
          : [...element.fingerings, ...extra];
      if (marks.isEmpty) continue;
      final info = _tieInfos[tieIndexOf[i]!];
      final centerX = (info.left + info.right) / 2;
      // Start above the current ink over the note (heads, stem, ornaments,
      // articulations already placed) so digits never collide with them.
      final bounds = element.id == null ? null : _elementBounds[element.id];
      final headTop = info.heads.map((h) => h.$4).reduce(min);
      var y = min(bounds?.minY ?? headTop, headTop) - 0.6;
      for (final finger in marks) {
        final glyph = SmuflGlyph.fingeringMark(finger);
        if (glyph == null) continue;
        final box = meta.bBoxOf(glyph);
        _addGlyph(glyph, centerX - box.swX - box.width / 2, y,
            elementId: element.id);
        y -= box.height + 0.2;
      }
    }
  }

  /// Jazz / brass articulations (scoop, doit, fall, plop): a small brass
  /// glyph just before or after the notehead, at the notehead's height.
  void _layoutJazzArticulations() {
    if (score.jazzMarks.isEmpty) return;
    final infoOf = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    for (final mark in score.jazzMarks) {
      final info = infoOf[mark.noteId];
      if (info == null || info.note == null || info.heads.isEmpty) {
        continue;
      }
      // Vertical anchor: the notehead nearest the gesture — the top head for
      // marks that rise (doit/plop), the bottom head for those that fall.
      final ys = [for (final h in info.heads) h.$4];
      final topY = ys.reduce(min);
      final bottomY = ys.reduce(max);
      final glyph = switch (mark.type) {
        JazzArticulation.scoop => SmuflGlyph.brassScoop,
        JazzArticulation.doit => SmuflGlyph.brassDoitMedium,
        JazzArticulation.fall => SmuflGlyph.brassFallLipShort,
        JazzArticulation.plop => SmuflGlyph.brassPlop,
        JazzArticulation.lift => SmuflGlyph.brassLiftShort,
        JazzArticulation.flip => SmuflGlyph.brassFlip,
        JazzArticulation.smear => SmuflGlyph.brassSmear,
        JazzArticulation.bend => SmuflGlyph.brassBend,
      };
      final y = mark.type.rises ? topY - 0.4 : bottomY + 0.4;
      final w = _glyphWidth(glyph);
      final x = mark.type.isBefore ? info.left - 0.3 - w : info.right + 0.3;
      _addGlyph(glyph, x, y, elementId: mark.noteId);
    }
  }
}
