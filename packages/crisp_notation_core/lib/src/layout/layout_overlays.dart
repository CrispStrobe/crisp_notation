part of 'layout_engine.dart';

// Pedagogical overlays: note-name letters, beat numbers and measure numbers.
// Extracted from layout_engine.dart; behaviour unchanged.

/// The counting label for a note [onset] whole notes into its measure: the
/// beat number on a beat, `+` on the half-beat, else null (finer offbeats).
String? _beatLabel(Fraction onset, int beatUnit) {
  final beats = onset * Fraction(beatUnit, 1);
  if (beats.denominator == 1) return '${beats.numerator + 1}';
  if (beats.denominator == 2) return '+';
  return null;
}

String _noteName(Pitch pitch, NoteNameStyle style, {bool octave = false}) {
  final oct = octave ? '${pitch.octave}' : '';
  final alter = pitch.alter;
  final accidental = switch (alter) {
    0 => '',
    2 => 'x',
    -2 => 'bb',
    _ => alter > 0 ? '#' * alter : 'b' * -alter,
  };
  if (style == NoteNameStyle.solfege) {
    return '${_solfege[pitch.step]}$accidental$oct';
  }
  // German: B-natural is H, B-flat is B (no suffix); everything else is the
  // English letter with the same accidental.
  if (style == NoteNameStyle.german && pitch.step == Step.b) {
    if (alter == 0) return 'H$oct';
    if (alter == -1) return 'B$oct';
    return 'H$accidental$oct';
  }
  return '${pitch.step.name.toUpperCase()}$accidental$oct';
}

extension _Overlays on _LayoutBuilder {
  /// Educational note-name overlay ([LayoutEngine.layout] `showNoteNames`): the
  /// pitch letter under each note, in a row below the staff (a chord stacks its
  /// letters top-to-bottom). Derived from the score, so it renders in both the
  /// Flutter and SVG back-ends.
  void _layoutNoteNames() {
    if (!showNoteNames) return;
    final size = s.lyricSize * 0.85;
    final baseline = max(6.5, _ink.maxY + s.lyricGap + 0.72 * size);
    final rowHeight = size * 1.1;
    for (final info in _tieInfos) {
      final note = info.note;
      if (note == null || note.pitches.isEmpty) continue;
      final centerX = (info.left + info.right) / 2;
      // Pitches are stored low→high; stack the names with the top pitch first.
      final names = [
        for (final p in note.pitches)
          _noteName(p, noteNameStyle, octave: showNoteOctaves),
      ];
      for (var r = 0; r < names.length; r++) {
        final text = names[names.length - 1 - r];
        final y = baseline + r * rowHeight;
        final half = _estTextHalfWidth(text, size);
        _primitives.add(TextPrimitive(
          text,
          Point(centerX, y),
          size: size,
          elementId: info.id,
        ));
        _expand(info.id, centerX - half, y - 0.72 * size, centerX + half,
            y + 0.25 * size);
      }
    }
  }

  /// Educational rhythm-count overlay ([LayoutEngine.layout] `showBeatNumbers`):
  /// the beat number (`1`, `2`, …) above each note that lands on a beat, and
  /// `+` on the half-beat "and", in a row above all other ink.
  void _layoutBeatNumbers() {
    if (!showBeatNumbers) return;
    final size = s.lyricSize * 0.8;
    final baseline = min(-1.5, _ink.minY - 0.4 - 0.25 * size);
    final infoById = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    var meter = score.timeSignature;
    for (final measure in score.measures) {
      meter = measure.timeChange ?? meter;
      if (meter == null) continue;
      var onset = Fraction.zero;
      for (var i = 0; i < measure.elements.length; i++) {
        final element = measure.elements[i];
        final dur = measure.effectiveDurationAt(i);
        if (element is NoteElement && element.id != null) {
          final info = infoById[element.id];
          final label = _beatLabel(onset, meter.beatUnit);
          if (info != null && info.note != null && label != null) {
            final centerX = (info.left + info.right) / 2;
            final half = _estTextHalfWidth(label, size);
            _primitives.add(TextPrimitive(
              label,
              Point(centerX, baseline),
              size: size,
              elementId: element.id,
            ));
            _expand(element.id, centerX - half, baseline - 0.72 * size,
                centerX + half, baseline + 0.25 * size);
          }
        }
        onset += dur;
      }
    }
  }

  /// Measure-number overlay ([LayoutEngine.layout] `showMeasureNumbers`): a
  /// small bar number above the start of each measure. Pickups (anacruses) are
  /// unnumbered and don't advance the count, so the first full bar reads `1`.
  ///
  /// With `measureNumberInterval` > 1, only bar 1 and every Nth bar are labelled
  /// (the common "every 5 bars" convention); ≤ 1 numbers every bar.
  void _layoutMeasureNumbers() {
    if (!showMeasureNumbers) return;
    final interval = measureNumberInterval;
    final size = s.lyricSize * 0.8;
    final baseline = min(-2.0, _ink.minY - 0.6 - 0.25 * size);
    final infoById = <String, _TieInfo>{
      for (final info in _tieInfos)
        if (info.id != null) info.id!: info,
    };
    for (var mi = 0; mi < score.measures.length; mi++) {
      final measure = score.measures[mi];
      final barNo = score.barNumberAt(mi);
      if (barNo == null) continue; // anacrusis: uncounted, unnumbered
      if (interval > 1 && barNo != 1 && barNo % interval != 0) continue;
      // Anchor at the leftmost laid-out element of the measure.
      _TieInfo? anchor;
      for (final element in measure.elements) {
        final info = element.id == null ? null : infoById[element.id];
        if (info != null) {
          anchor = info;
          break;
        }
      }
      if (anchor == null) continue;
      final label = '$barNo';
      final half = _estTextHalfWidth(label, size);
      final x = anchor.left + half;
      _primitives.add(TextPrimitive(
        label,
        Point(x, baseline),
        size: size,
        elementId: anchor.id,
      ));
      _expand(anchor.id, x - half, baseline - 0.72 * size, x + half,
          baseline + 0.25 * size);
    }
  }
}

/// The letter name of [pitch] with any accidental (`C`, `F#`, `Bb`, `Gx`).
const _solfege = {
  Step.c: 'do',
  Step.d: 're',
  Step.e: 'mi',
  Step.f: 'fa',
  Step.g: 'sol',
  Step.a: 'la',
  Step.b: 'ti',
};
