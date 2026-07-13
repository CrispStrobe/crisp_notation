/// Canonical SMuFL glyph names used by the layout engine.
///
/// Names follow the SMuFL specification (https://w3c.github.io/smufl/latest/)
/// and are stable across compliant fonts. The rendering layer maps them to
/// codepoints; the layout engine looks up their metrics in [SmuflMetadata]
/// by these names.
library;

import '../model/element.dart';
import '../model/measure.dart';

/// SMuFL glyph name constants (the subset partitura uses).
abstract final class SmuflGlyph {
  /// G clef (treble).
  static const String gClef = 'gClef';

  /// F clef (bass).
  static const String fClef = 'fClef';

  /// C clef (alto/tenor).
  static const String cClef = 'cClef';

  /// Neutral / unpitched percussion clef (two vertical strokes).
  static const String percussionClef = 'unpitchedPercussionClef1';

  /// Breve (double whole) notehead.
  static const String noteheadDoubleWhole = 'noteheadDoubleWhole';

  /// Whole-note notehead.
  static const String noteheadWhole = 'noteheadWhole';

  /// Half-note notehead.
  static const String noteheadHalf = 'noteheadHalf';

  /// Filled notehead (quarter and shorter).
  static const String noteheadBlack = 'noteheadBlack';

  /// X notehead (breve / whole / half / filled — see [NoteheadShape.x]).
  static const String noteheadXDoubleWhole = 'noteheadXDoubleWhole';

  /// Whole-note X notehead.
  static const String noteheadXWhole = 'noteheadXWhole';

  /// Half-note X notehead.
  static const String noteheadXHalf = 'noteheadXHalf';

  /// Filled X notehead (quarter and shorter).
  static const String noteheadXBlack = 'noteheadXBlack';

  /// Breve diamond notehead ([NoteheadShape.diamond]).
  static const String noteheadDiamondDoubleWhole = 'noteheadDiamondDoubleWhole';

  /// Whole-note diamond notehead.
  static const String noteheadDiamondWhole = 'noteheadDiamondWhole';

  /// Half-note diamond notehead.
  static const String noteheadDiamondHalf = 'noteheadDiamondHalf';

  /// Filled diamond notehead (quarter and shorter).
  static const String noteheadDiamondBlack = 'noteheadDiamondBlack';

  /// Breve upward-triangle notehead ([NoteheadShape.triangleUp]).
  static const String noteheadTriangleUpDoubleWhole =
      'noteheadTriangleUpDoubleWhole';

  /// Whole-note upward-triangle notehead.
  static const String noteheadTriangleUpWhole = 'noteheadTriangleUpWhole';

  /// Half-note upward-triangle notehead.
  static const String noteheadTriangleUpHalf = 'noteheadTriangleUpHalf';

  /// Filled upward-triangle notehead (quarter and shorter).
  static const String noteheadTriangleUpBlack = 'noteheadTriangleUpBlack';

  /// Slash notehead with vertical ends ([NoteheadShape.slash]).
  static const String noteheadSlashVerticalEnds = 'noteheadSlashVerticalEnds';

  /// Circled-X notehead ([NoteheadShape.circleX]).
  static const String noteheadCircleX = 'noteheadCircleX';

  /// Jazz scoop — slides up into the note ([JazzArticulation.scoop]).
  static const String brassScoop = 'brassScoop';

  /// Jazz doit — a short upward flick off the note ([JazzArticulation.doit]).
  static const String brassDoitMedium = 'brassDoitMedium';

  /// Jazz fall / falloff — drops away below the note ([JazzArticulation.fall]).
  static const String brassFallLipShort = 'brassFallLipShort';

  /// Jazz plop — drops into the note from above ([JazzArticulation.plop]).
  static const String brassPlop = 'brassPlop';

  /// Jazz lift — a longer upward gesture off the note ([JazzArticulation.lift]).
  static const String brassLiftShort = 'brassLiftShort';

  /// Jazz flip — an upper-neighbour flip off the note ([JazzArticulation.flip]).
  static const String brassFlip = 'brassFlip';

  /// Jazz smear — a smeared slide into the note ([JazzArticulation.smear]).
  static const String brassSmear = 'brassSmear';

  /// Jazz bend — the note bends up and back ([JazzArticulation.bend]).
  static const String brassBend = 'brassBend';

  /// Figured-bass digit glyph (0–9) for the given [digit] (0–9).
  static String figbassDigit(int digit) => 'figbass$digit';

  /// Figured-bass sharp alteration.
  static const String figbassSharp = 'figbassSharp';

  /// Figured-bass flat alteration.
  static const String figbassFlat = 'figbassFlat';

  /// Figured-bass natural alteration.
  static const String figbassNatural = 'figbassNatural';

  /// Figured-bass plus (raised third).
  static const String figbassPlus = 'figbassPlus';

  /// Slashed (raised) figured-bass digit for the given [digit] — a slash
  /// through the number, the alternative to a prefixed sharp. Digits 2, 4, 5,
  /// 6, 7 and 9 have a dedicated glyph; others return `null` (draw the plain
  /// digit with [figbassCombiningRaising] overlaid instead).
  static String? figbassRaisedDigit(int digit) => switch (digit) {
        2 => 'figbass2Raised',
        4 => 'figbass4Raised',
        5 => 'figbass5Raised2',
        6 => 'figbass6Raised',
        7 => 'figbass7Raised1',
        9 => 'figbass9Raised',
        _ => null,
      };

  /// Combining slash that raises the preceding figured-bass digit, for digits
  /// without a dedicated slashed glyph.
  static const String figbassCombiningRaising = 'figbassCombiningRaising';

  /// Breath-mark comma ([BreathSymbol.comma]).
  static const String breathMarkComma = 'breathMarkComma';

  /// Caesura / grand pause ([BreathSymbol.caesura]).
  static const String caesura = 'caesura';

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

  /// Quarter-tone flat (Stein half-flat, −50 cents).
  static const String accidentalQuarterToneFlatStein =
      'accidentalQuarterToneFlatStein';

  /// Quarter-tone sharp (Stein half-sharp, +50 cents).
  static const String accidentalQuarterToneSharpStein =
      'accidentalQuarterToneSharpStein';

  /// Three-quarter-tone flat (Zimmermann, −150 cents).
  static const String accidentalThreeQuarterTonesFlatZimmermann =
      'accidentalThreeQuarterTonesFlatZimmermann';

  /// Three-quarter-tone sharp (Stein-Zimmermann, +150 cents).
  static const String accidentalThreeQuarterTonesSharpStein =
      'accidentalThreeQuarterTonesSharpStein';

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
        DynamicLevel.ppp => 'dynamicPPP',
        DynamicLevel.pppp => 'dynamicPPPP',
        DynamicLevel.fff => 'dynamicFFF',
        DynamicLevel.ffff => 'dynamicFFFF',
        DynamicLevel.sf => 'dynamicSforzando1',
        DynamicLevel.sfz => 'dynamicSforzato',
        DynamicLevel.sffz => 'dynamicSforzatoFF',
        DynamicLevel.fz => 'dynamicForzando',
        DynamicLevel.fp => 'dynamicFortePiano',
        DynamicLevel.rf => 'dynamicRinforzando1',
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
      // Bowing marks have a single (above) glyph; the suffix is ignored.
      Articulation.upBow => 'stringsUpBow',
      Articulation.downBow => 'stringsDownBow',
    };
  }

  /// G clef sounding an octave higher.
  static const String gClef8va = 'gClef8va';

  /// G clef sounding an octave lower.
  static const String gClef8vb = 'gClef8vb';

  /// F clef sounding an octave lower.
  static const String fClef8vb = 'fClef8vb';

  /// Trill ornament.
  static const String ornamentTrill = 'ornamentTrill';

  /// One trill-line wiggle segment, repeated to extend a trill.
  static const String wiggleTrill = 'wiggleTrill';

  /// Turn ornament.
  static const String ornamentTurn = 'ornamentTurn';

  /// Short trill (upper mordent).
  static const String ornamentShortTrill = 'ornamentShortTrill';

  /// Mordent (lower mordent, with the vertical stroke).
  static const String ornamentMordent = 'ornamentMordent';

  /// Inverted turn (turn from below).
  static const String ornamentTurnInverted = 'ornamentTurnInverted';

  /// The base glyph for [ornament]. The trill-with-accidental variants share
  /// the plain `tr`; their accidental is drawn separately above it.
  static String ornamentGlyph(Ornament ornament) => switch (ornament) {
        Ornament.trill => ornamentTrill,
        Ornament.shortTrill => ornamentShortTrill,
        Ornament.mordent => ornamentMordent,
        Ornament.turn => ornamentTurn,
        Ornament.invertedTurn => ornamentTurnInverted,
        Ornament.trillSharp ||
        Ornament.trillFlat ||
        Ornament.trillNatural =>
          ornamentTrill,
      };

  /// Segno sign (𝄋) — the target of a *dal segno* jump.
  static const String segno = 'segno';

  /// Coda sign (𝄌) — the target of a *to coda* jump.
  static const String coda = 'coda';

  /// The SMuFL glyph for a *target* navigation mark
  /// ([NavigationMark.segno]/[NavigationMark.coda]); null for the text
  /// instructions, which use [navigationLabel] instead.
  static String? navigationGlyph(NavigationMark mark) => switch (mark) {
        NavigationMark.segno => segno,
        NavigationMark.coda => coda,
        _ => null,
      };

  /// The above-staff text label for a navigation *instruction*
  /// (`D.C.`, `D.S. al Coda`, `Fine`, …); null for the two marks drawn as
  /// SMuFL glyphs ([NavigationMark.segno]/[NavigationMark.coda]).
  static String? navigationLabel(NavigationMark mark) => switch (mark) {
        NavigationMark.segno => null,
        NavigationMark.coda => null,
        NavigationMark.toCoda => 'To Coda',
        NavigationMark.daCapo => 'D.C.',
        NavigationMark.daCapoAlFine => 'D.C. al Fine',
        NavigationMark.daCapoAlCoda => 'D.C. al Coda',
        NavigationMark.dalSegno => 'D.S.',
        NavigationMark.dalSegnoAlFine => 'D.S. al Fine',
        NavigationMark.dalSegnoAlCoda => 'D.S. al Coda',
        NavigationMark.fine => 'Fine',
      };

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

  /// The common-time (C) time-signature glyph.
  static const String timeSigCommon = 'timeSigCommon';

  /// The cut-time (¢) time-signature glyph.
  static const String timeSigCutCommon = 'timeSigCutCommon';

  /// The `+` between groups of an additive time signature.
  static const String timeSigPlus = 'timeSigPlus';

  /// The tuplet-number glyph for a single [digit] (0–9).
  static String tupletDigit(int digit) {
    if (digit < 0 || digit > 9) {
      throw ArgumentError.value(digit, 'digit', 'must be 0..9');
    }
    return 'tuplet$digit';
  }

  /// The fingering glyph for a single [digit] (0–9).
  static String fingeringDigit(int digit) {
    if (digit < 0 || digit > 9) {
      throw ArgumentError.value(digit, 'digit', 'must be 0..9');
    }
    return 'fingering$digit';
  }

  /// The combined tremolo-strokes glyph for [strokes] beams (1–5), drawn
  /// through the stem.
  static String tremoloStrokes(int strokes) {
    if (strokes < 1 || strokes > 5) {
      throw ArgumentError.value(strokes, 'strokes', 'must be 1..5');
    }
    return 'tremolo$strokes';
  }

  /// Six-string guitar tablature clef ("TAB").
  static const String sixStringTabClef = '6stringTabClef';

  /// Four-string bass tablature clef ("TAB").
  static const String fourStringTabClef = '4stringTabClef';

  /// Piano sustain-pedal "Ped." mark (pedal down).
  static const String keyboardPedalPed = 'keyboardPedalPed';

  /// Piano sustain-pedal release star (pedal up).
  static const String keyboardPedalUp = 'keyboardPedalUp';

  /// Arpeggio wiggle segment; tiles vertically to form the rolled-chord line.
  static const String wiggleArpeggiatoUp = 'wiggleArpeggiatoUp';

  /// Arpeggio arrowhead pointing up (caps an upward roll at the top).
  static const String wiggleArpeggiatoUpArrow = 'wiggleArpeggiatoUpArrow';

  /// Arpeggio arrowhead pointing down (caps a downward roll at the bottom).
  static const String wiggleArpeggiatoDownArrow = 'wiggleArpeggiatoDownArrow';

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
