/// Tunable layout parameters, seeded from SMuFL engraving defaults.
library;

import '../smufl/smufl_metadata.dart';
import '../theory/pitch.dart';

/// A notehead shape-scheme that maps each pitch to a shape by its movable-do
/// scale degree in the current key.
enum NoteheadScheme {
  /// Ordinary round noteheads (the default).
  normal,

  /// American four-shape (Sacred Harp) noteheads: fa = triangle, sol = round,
  /// la = square, mi = diamond (degrees fa-sol-la-fa-sol-la-mi).
  sacredHarp,
}

/// Distances and thicknesses the layout engine works with.
///
/// All values are in **staff spaces** (1 space = the gap between two
/// adjacent staff lines). Engraving values default to the font's
/// `engravingDefaults` from [metadata]; spacing-policy values are
/// partitura's own defaults and can be overridden per instance.
class LayoutSettings {
  /// Font metadata used for glyph metrics (bounding boxes, stem anchors).
  final SmuflMetadata metadata;

  /// Thickness of the five staff lines.
  final double staffLineThickness;

  /// Thickness of note stems.
  final double stemThickness;

  /// Thickness of ledger lines.
  final double legerLineThickness;

  /// How far a ledger line extends beyond the notehead on each side.
  final double legerLineExtension;

  /// Vertical thickness of a beam.
  final double beamThickness;

  /// Vertical gap between adjacent beams (primary/secondary).
  final double beamSpacing;

  /// Thickness of ordinary (thin) barlines.
  final double thinBarlineThickness;

  /// Thickness of the thick stroke of a final barline.
  final double thickBarlineThickness;

  /// Gap between the thin and thick strokes of a final barline.
  final double barlineSeparation;

  /// Default stem length (one octave).
  final double stemLength;

  /// Horizontal padding before the clef.
  final double leadingPadding;

  /// Gap after the clef.
  final double clefGap;

  /// Gap between consecutive key-signature accidentals.
  final double keyAccidentalGap;

  /// Gap after the key signature and after the time signature.
  final double signatureGap;

  /// Gap between an accidental and its notehead.
  final double accidentalGap;

  /// Remaps microtonal (quarter-tone) accidentals to alternative SMuFL glyphs —
  /// e.g. Arabic or Turkish variants. Empty (the default) uses each
  /// accidental's [MicrotonalAccidental.defaultGlyph].
  final Map<MicrotonalAccidental, String> microtonalGlyphs;

  /// Notehead shape scheme. [NoteheadScheme.normal] (the default) draws round
  /// noteheads; [NoteheadScheme.sacredHarp] draws four-shape noteheads by each
  /// pitch's scale degree. Only applies to notes whose [NoteheadShape] is
  /// `normal` (an explicit shape such as x or diamond always wins).
  final NoteheadScheme noteheadScheme;

  /// Gap between a notehead and its first augmentation dot.
  final double dotGap;

  /// Gap between two augmentation dots.
  final double dotSpacing;

  /// Horizontal padding on each side of a barline.
  final double barlineGap;

  /// Minimum free space between an element's ink and the next element.
  final double minNoteGap;

  /// Duration-proportional spacing: advance for a sixteenth note (the
  /// shortest supported duration). See [DESIGN.md] for the formula.
  final double spacingBase;

  /// Duration-proportional spacing: extra advance per doubling of duration.
  final double spacingPerLog2;

  /// Vertical padding added above/below the outermost ink when computing
  /// the layout's bounding box.
  final double verticalPadding;

  /// Em size of lyric text, in staff spaces.
  final double lyricSize;

  /// Minimum clearance between the lowest ink and the lyric baseline.
  final double lyricGap;

  /// Em size of annotation text (chord symbols), in staff spaces.
  final double annotationSize;

  /// Minimum clearance between an annotation's text and the ink below.
  final double annotationGap;

  /// Em size of a navigation instruction's text (`D.C.`, `Fine`, …).
  final double navigationSize;

  /// Clearance above the highest ink at which a navigation mark's top sits.
  final double navigationGap;

  /// Creates settings seeded from [metadata]'s engraving defaults; any
  /// parameter can be overridden.
  LayoutSettings({
    required this.metadata,
    double? staffLineThickness,
    double? stemThickness,
    double? legerLineThickness,
    double? legerLineExtension,
    double? beamThickness,
    double? beamSpacing,
    double? thinBarlineThickness,
    double? thickBarlineThickness,
    double? barlineSeparation,
    this.stemLength = 3.5,
    this.leadingPadding = 1.0,
    this.clefGap = 1.0,
    this.keyAccidentalGap = 0.1,
    this.signatureGap = 1.0,
    this.accidentalGap = 0.25,
    this.microtonalGlyphs = const {},
    this.noteheadScheme = NoteheadScheme.normal,
    this.dotGap = 0.35,
    this.dotSpacing = 0.35,
    this.barlineGap = 1.0,
    this.minNoteGap = 0.6,
    this.spacingBase = 1.8,
    this.spacingPerLog2 = 0.75,
    this.verticalPadding = 0.5,
    this.lyricSize = 1.6,
    this.lyricGap = 0.8,
    this.annotationSize = 1.8,
    this.annotationGap = 0.5,
    this.navigationSize = 1.8,
    this.navigationGap = 0.6,
  })  : staffLineThickness = staffLineThickness ??
            metadata.engravingDefault('staffLineThickness', orElse: 0.13),
        stemThickness = stemThickness ??
            metadata.engravingDefault('stemThickness', orElse: 0.12),
        legerLineThickness = legerLineThickness ??
            metadata.engravingDefault('legerLineThickness', orElse: 0.16),
        legerLineExtension = legerLineExtension ??
            metadata.engravingDefault('legerLineExtension', orElse: 0.4),
        beamThickness = beamThickness ??
            metadata.engravingDefault('beamThickness', orElse: 0.5),
        beamSpacing = beamSpacing ??
            metadata.engravingDefault('beamSpacing', orElse: 0.25),
        thinBarlineThickness = thinBarlineThickness ??
            metadata.engravingDefault('thinBarlineThickness', orElse: 0.16),
        thickBarlineThickness = thickBarlineThickness ??
            metadata.engravingDefault('thickBarlineThickness', orElse: 0.5),
        barlineSeparation = barlineSeparation ??
            metadata.engravingDefault('barlineSeparation', orElse: 0.4);
}
