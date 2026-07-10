/// Canonical SMuFL glyph names used by the layout engine.
///
/// Names follow the SMuFL specification (https://w3c.github.io/smufl/latest/)
/// and are stable across compliant fonts. The rendering layer maps them to
/// codepoints; the layout engine looks up their metrics in [SmuflMetadata]
/// by these names.
library;

import '../model/element.dart';

/// SMuFL glyph name constants (the subset partitura uses).
abstract final class SmuflGlyph {
  /// G clef (treble).
  static const String gClef = 'gClef';

  /// F clef (bass).
  static const String fClef = 'fClef';

  /// C clef (alto/tenor).
  static const String cClef = 'cClef';

  /// Breve (double whole) notehead.
  static const String noteheadDoubleWhole = 'noteheadDoubleWhole';

  /// Whole-note notehead.
  static const String noteheadWhole = 'noteheadWhole';

  /// Half-note notehead.
  static const String noteheadHalf = 'noteheadHalf';

  /// Filled notehead (quarter and shorter).
  static const String noteheadBlack = 'noteheadBlack';

  /// Eighth-note flag for an upward stem.
  static const String flag8thUp = 'flag8thUp';

  /// Eighth-note flag for a downward stem.
  static const String flag8thDown = 'flag8thDown';

  /// Sixteenth-note flag for an upward stem.
  static const String flag16thUp = 'flag16thUp';

  /// Sixteenth-note flag for a downward stem.
  static const String flag16thDown = 'flag16thDown';

  /// Thirty-second-note flag for an upward stem.
  static const String flag32ndUp = 'flag32ndUp';

  /// Thirty-second-note flag for a downward stem.
  static const String flag32ndDown = 'flag32ndDown';

  /// Sixty-fourth-note flag for an upward stem.
  static const String flag64thUp = 'flag64thUp';

  /// Sixty-fourth-note flag for a downward stem.
  static const String flag64thDown = 'flag64thDown';

  /// Breve (double whole) rest.
  static const String restDoubleWhole = 'restDoubleWhole';

  /// Whole rest (hangs from the fourth staff line).
  static const String restWhole = 'restWhole';

  /// Half rest (sits on the middle staff line).
  static const String restHalf = 'restHalf';

  /// Quarter rest.
  static const String restQuarter = 'restQuarter';

  /// Eighth rest.
  static const String rest8th = 'rest8th';

  /// Sixteenth rest.
  static const String rest16th = 'rest16th';

  /// Thirty-second rest.
  static const String rest32nd = 'rest32nd';

  /// Sixty-fourth rest.
  static const String rest64th = 'rest64th';

  /// Double flat.
  static const String accidentalDoubleFlat = 'accidentalDoubleFlat';

  /// Flat.
  static const String accidentalFlat = 'accidentalFlat';

  /// Natural.
  static const String accidentalNatural = 'accidentalNatural';

  /// Sharp.
  static const String accidentalSharp = 'accidentalSharp';

  /// Double sharp.
  static const String accidentalDoubleSharp = 'accidentalDoubleSharp';

  /// Augmentation dot.
  static const String augmentationDot = 'augmentationDot';

  /// The two dots of a repeat barline (drawn with origin on the bottom
  /// staff line; the dots land in the middle spaces).
  static const String repeatDots = 'repeatDots';

  /// The glyph for a [DynamicLevel].
  static String dynamicGlyph(DynamicLevel level) => switch (level) {
        DynamicLevel.pp => 'dynamicPP',
        DynamicLevel.p => 'dynamicPiano',
        DynamicLevel.mp => 'dynamicMP',
        DynamicLevel.mf => 'dynamicMF',
        DynamicLevel.f => 'dynamicForte',
        DynamicLevel.ff => 'dynamicFF',
      };

  /// The articulation glyph for [articulation], in its above/below variant.
  static String articulationGlyph(
    Articulation articulation, {
    required bool above,
  }) {
    final suffix = above ? 'Above' : 'Below';
    return switch (articulation) {
      Articulation.staccato => 'articStaccato$suffix',
      Articulation.tenuto => 'articTenuto$suffix',
      Articulation.accent => 'articAccent$suffix',
      Articulation.marcato => 'articMarcato$suffix',
      Articulation.fermata => 'fermata$suffix',
    };
  }

  /// Time signature digits 0–9; index with [timeSigDigit].
  static const List<String> timeSigDigits = [
    'timeSig0',
    'timeSig1',
    'timeSig2',
    'timeSig3',
    'timeSig4',
    'timeSig5',
    'timeSig6',
    'timeSig7',
    'timeSig8',
    'timeSig9',
  ];

  /// The time signature glyph for a single [digit] (0–9).
  static String timeSigDigit(int digit) => timeSigDigits[digit];

  /// The tuplet-number glyph for a single [digit] (0–9).
  static String tupletDigit(int digit) {
    if (digit < 0 || digit > 9) {
      throw ArgumentError.value(digit, 'digit', 'must be 0..9');
    }
    return 'tuplet$digit';
  }

  /// The accidental glyph for a chromatic [alter] of -2..2
  /// (double flat … double sharp).
  static String accidentalFor(int alter) => switch (alter) {
        -2 => accidentalDoubleFlat,
        -1 => accidentalFlat,
        0 => accidentalNatural,
        1 => accidentalSharp,
        2 => accidentalDoubleSharp,
        _ => throw ArgumentError.value(alter, 'alter', 'must be -2..2'),
      };
}
