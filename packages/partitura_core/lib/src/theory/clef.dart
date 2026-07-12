/// Clefs and clef-relative staff arithmetic.
library;

import 'pitch.dart';

/// The supported clefs.
enum Clef {
  /// G clef anchored on the second staff line from the bottom, G4
  /// (Violinschlüssel).
  treble,

  /// F clef anchored on the fourth staff line from the bottom, F3
  /// (Bassschlüssel).
  bass,

  /// C clef anchored on the middle staff line, C4 (Altschlüssel).
  alto,

  /// C clef anchored on the fourth staff line from the bottom, C4
  /// (Tenorschlüssel).
  tenor,

  /// G clef sounding an octave higher (8 above; piccolo).
  treble8va,

  /// G clef sounding an octave lower (8 below; choral tenor).
  treble8vb,

  /// F clef sounding an octave lower (8 below; double bass notation).
  bass8vb,

  /// G clef on the first (bottom) line — French violin clef, G4.
  frenchViolin,

  /// C clef on the first (bottom) line — soprano clef, C4.
  soprano,

  /// C clef on the second line — mezzo-soprano clef, C4.
  mezzoSoprano,

  /// F clef on the third (middle) line — baritone clef, F3.
  baritone,

  /// F clef on the fifth (top) line — sub-bass clef, F3.
  subbass,

  /// Neutral / unpitched percussion clef (two vertical strokes). Carries no
  /// pitch reference; pitched content is placed as in treble so a drum staff
  /// still lays out on the five lines.
  percussion;

  /// Absolute diatonic index ([Pitch.diatonicIndex]) of the natural pitch
  /// sitting on the bottom staff line: E4 (30) for treble, G2 (18) for
  /// bass, F3 (24) for alto, D3 (22) for tenor; octave clefs shift by
  /// ±7 (treble8vb: E3).
  int get bottomLineDiatonicIndex => switch (this) {
        Clef.treble => 30,
        Clef.bass => 18,
        Clef.alto => 24,
        Clef.tenor => 22,
        Clef.treble8va => 37,
        Clef.treble8vb => 23,
        Clef.bass8vb => 11,
        Clef.frenchViolin => 32, // G4 on the bottom line
        Clef.soprano => 28, // C4 on the bottom line
        Clef.mezzoSoprano => 26, // A3 on the bottom line (C4 on line 2)
        Clef.baritone => 20, // B2 on the bottom line (F3 on line 3)
        Clef.subbass => 16, // E2 on the bottom line (F3 on line 5)
        Clef.percussion => 30, // neutral; same reference as treble
      };

  /// The natural (unaltered) pitch at [staffPosition], where 0 is the bottom
  /// staff line and each line/space upward adds 1 (the [Pitch.staffPosition]
  /// convention). Positions outside 0–8 lie in the ledger-line range.
  Pitch pitchAt(int staffPosition) {
    final d = bottomLineDiatonicIndex + staffPosition;
    return Pitch(Step.values[d % 7], octave: (d - d % 7) ~/ 7);
  }
}
