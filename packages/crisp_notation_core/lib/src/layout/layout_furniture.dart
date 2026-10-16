part of 'layout_engine.dart';

// Staff furniture: clef, key-signature and time-signature drawing plus their
// mid-score clef change, and the pitch-class position tables. Moved out of
// layout_engine.dart. The tables and pure helpers are top-level (library-
// private, so _applyMeasureChanges still reaches them unqualified); the
// drawing passes are an extension on the builder. Behaviour unchanged.

// Key signature accidental staff positions per clef, in writing order.
// Bass/alto shift the treble pattern down 2/1 positions; the tenor sharp
// pattern is its own shape (F# starts low to stay inside the staff).
const Map<Clef, List<int>> _sharpPositions = {
  Clef.treble: [8, 5, 9, 6, 3, 7, 4],
  Clef.bass: [6, 3, 7, 4, 1, 5, 2],
  Clef.alto: [7, 4, 8, 5, 2, 6, 3],
  Clef.tenor: [2, 6, 3, 7, 4, 8, 5],
  // Octave clefs write key signatures like their base clef.
  Clef.treble8va: [8, 5, 9, 6, 3, 7, 4],
  Clef.treble8vb: [8, 5, 9, 6, 3, 7, 4],
  Clef.bass8vb: [6, 3, 7, 4, 1, 5, 2],
};

const Map<Clef, List<int>> _flatPositions = {
  Clef.treble: [4, 7, 3, 6, 2, 5, 1],
  Clef.bass: [2, 5, 1, 4, 0, 3, -1],
  Clef.alto: [3, 6, 2, 5, 1, 4, 0],
  Clef.tenor: [5, 8, 4, 7, 3, 6, 2],
  Clef.treble8va: [4, 7, 3, 6, 2, 5, 1],
  Clef.treble8vb: [4, 7, 3, 6, 2, 5, 1],
  Clef.bass8vb: [2, 5, 1, 4, 0, 3, -1],
};

/// Key-signature accidental staff positions for [clef]. Uses the hand-tuned
/// table where one exists (preserving tenor's special sharp shape); otherwise
/// derives them by the standard engraving rule — each accidental a fifth from
/// the last, taken up while it stays on the staff and dropping an octave
/// otherwise. Reproduces the treble table exactly; keeps every signature
/// within the five lines (positions −1..9) for the C-/F-clef positions.
List<int> _keyAccidentalPositions(Clef clef, {required bool sharp}) {
  final table = (sharp ? _sharpPositions : _flatPositions)[clef];
  if (table != null) return table;
  const high = 9;
  final firstStep = sharp ? 3 : 6; // F for sharps, B for flats
  final upDelta = sharp ? 4 : 3; // a fifth up (sharps) / a fourth up (flats)
  final downDelta = sharp ? 3 : 4; // the octave-complementary drop
  // The lowest occurrence of the first natural on/above the bottom line,
  // lifted as high as it fits — the traditional starting octave.
  var p = (firstStep - clef.bottomLineDiatonicIndex) % 7; // 0..6
  while (p + 7 <= high) {
    p += 7;
  }
  final out = [p];
  for (var i = 1; i < 7; i++) {
    final up = p + upDelta;
    p = up <= high ? up : p - downDelta;
    out.add(p);
  }
  return out;
}

/// The conventional key-signature staff position for [step] in [clef]: its
/// lowest occurrence on/above the bottom line, lifted as high as it fits
/// (matching the traditional starting octave). Used to place the accidentals
/// of a non-standard [KeySignature.custom].
int _keyStepPosition(Clef clef, Step step) {
  const high = 9;
  var p = (step.index - clef.bottomLineDiatonicIndex) % 7;
  while (p + 7 <= high) {
    p += 7;
  }
  return p;
}

/// Glyph + anchor staff position per clef (octave clefs carry the 8).
(String, int) _clefGlyph(Clef clef) => switch (clef) {
      Clef.treble => (SmuflGlyph.gClef, 2), // G4
      Clef.bass => (SmuflGlyph.fClef, 6), // F3
      Clef.alto => (SmuflGlyph.cClef, 4), // C4 on the middle line
      Clef.tenor => (SmuflGlyph.cClef, 6), // C4 on the fourth line
      Clef.treble8va => (SmuflGlyph.gClef8va, 2),
      Clef.treble8vb => (SmuflGlyph.gClef8vb, 2),
      Clef.bass8vb => (SmuflGlyph.fClef8vb, 6),
      Clef.frenchViolin => (SmuflGlyph.gClef, 0), // G4 on the bottom line
      Clef.soprano => (SmuflGlyph.cClef, 0), // C4 on the bottom line
      Clef.mezzoSoprano => (SmuflGlyph.cClef, 2), // C4 on the second line
      Clef.baritone => (SmuflGlyph.fClef, 4), // F3 on the middle line
      Clef.subbass => (SmuflGlyph.fClef, 8), // F3 on the top line
      Clef.percussion => (SmuflGlyph.percussionClef, 4), // centered
    };

extension _Furniture on _LayoutBuilder {
  /// Rule 1: clef anchored on its reference line (gClef on G4's line,
  /// fClef on F3's, cClef on C4's).
  void _layoutClef() {
    final (glyph, position) = _clefGlyph(_clef);
    _addGlyph(glyph, _x, _yOf(position));
    _x += _glyphWidth(glyph) + s.clefGap;
  }

  /// Rule 2: key signature in standard order at conventional octaves, or a
  /// non-standard [KeySignature.custom] with each accidental at its own step.
  void _layoutKeySignature() {
    // A neutral percussion staff carries no key signature.
    if (_clef == Clef.percussion) return;
    final custom = _key.custom;
    if (custom != null) {
      for (final acc in custom) {
        final glyph = SmuflGlyph.accidentalFor(acc.alter);
        _addGlyph(glyph, _x, _yOf(_keyStepPosition(_clef, acc.step)));
        _x += _glyphWidth(glyph) + s.keyAccidentalGap;
      }
      _x += s.signatureGap - s.keyAccidentalGap;
      return;
    }
    final fifths = _key.fifths;
    if (fifths == 0) return;
    final count = fifths.abs();
    final table = _keyAccidentalPositions(_clef, sharp: fifths > 0);
    final glyph =
        fifths > 0 ? SmuflGlyph.accidentalSharp : SmuflGlyph.accidentalFlat;
    final width = _glyphWidth(glyph);
    for (var i = 0; i < count; i++) {
      _addGlyph(glyph, _x, _yOf(table[i]));
      _x += width + s.keyAccidentalGap;
    }
    _x += s.signatureGap - s.keyAccidentalGap;
  }

  /// Rule 3: stacked timeSig digits centered on the staff.
  void _layoutTimeSignature() {
    final time = _time;
    if (time == null) return;
    _drawTimeSig(time);
    // An interchangeable meter draws its alternate beside the primary.
    final alt = time.alternate;
    if (alt != null) {
      _x += 0.4;
      _drawTimeSig(alt);
    }
  }

  /// Draws inline clef changes [clefs] ending just left of [right] — on the
  /// shared grid, left of the notes' ink at their column, so the notes stay
  /// on the column the other staves use.
  void _drawClefChangesBefore(List<Clef> clefs, double right) {
    var x = right;
    for (final clef in clefs.reversed) {
      x -= inlineClefAdvance(clef, s);
      final (glyph, position) = _clefGlyph(clef);
      _addGlyph(glyph, x, _yOf(position), scale: 0.8);
    }
  }

  void _layoutClefChange(Clef clef) {
    _clef = clef;
    final (glyph, position) = _clefGlyph(_clef);
    const changeScale = 0.8;
    _addGlyph(glyph, _x, _yOf(position), scale: changeScale);
    _x += _glyphWidth(glyph) * changeScale + s.clefGap * 0.75;
  }

  /// The notehead glyph for a [shape] at a [base] duration — the shape picks
  /// The diatonic step index (C=0…B=6) of the current key's major tonic —
  /// the reference "do" for the movable-do shape-note degree. Non-standard
  /// signatures fall back to C.
  int _keyTonicStepIndex() {
    if (!_key.isStandard) return 0;
    // Circle of fifths → tonic step letter: C G D A E B F#(=F).
    const stepOfFifth = [0, 4, 1, 5, 2, 6, 3];
    return stepOfFifth[((_key.fifths % 7) + 7) % 7];
  }
}

/// The room an inline clef change to [clef] takes in front of the notes it
/// precedes, in staff spaces: the small clef and its gap.
double inlineClefAdvance(Clef clef, LayoutSettings s) {
  final (glyph, _) = _clefGlyph(clef);
  return s.metadata.bBoxOf(glyph).width * 0.8 + s.clefGap * 0.75;
}
