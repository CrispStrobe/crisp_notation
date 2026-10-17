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

  /// Aikin seven-shape noteheads (a distinct shape per scale degree):
  /// do = triangle-up, re = moon, mi = diamond, fa = triangle, sol = round,
  /// la = square, ti = rounded-triangle.
  aikin,

  /// Pitch-name noteheads: the note's letter (C, D, E, …) is drawn in place of
  /// the notehead — a beginner/teaching aid.
  pitchName,

  /// Solfège noteheads: the movable-do syllable (do, re, mi, …) in place of the
  /// notehead, from each pitch's scale degree in the current key.
  solfege,
}

/// How the [LayoutEngine.layout] `showNoteNames` overlay spells each pitch.
enum NoteNameStyle {
  /// English letters: C D E F G A B.
  letter,

  /// German letters: like [letter], but B-natural is **H** and B-flat is **B**.
  german,

  /// Fixed-do solfège syllables: do re mi fa sol la ti (C = do).
  solfege,
}

/// Placement of fingering marks relative to the notation.
enum FingeringPlacement {
  /// Above each note's ink, allowing marks inside the staff.
  aboveNote,

  /// Above the staff, shifted outward to clear nearby notation.
  aboveStaff,

  /// Below the staff, shifted outward to clear nearby notation.
  belowStaff,

  /// Below bass-clef staves and above other staves.
  outsideStaff,
}

/// Distances and thicknesses the layout engine works with.
///
/// All values are in **staff spaces** (1 space = the gap between two
/// adjacent staff lines). Engraving values default to the font's
/// `engravingDefaults` from [metadata]; spacing-policy values are
/// crisp_notation's own defaults and can be overridden per instance.
class LayoutSettings {
  /// Font metadata used for glyph metrics (bounding boxes, stem anchors).
  final SmuflMetadata metadata;

  /// Where fingering marks are placed.
  final FingeringPlacement fingeringPlacement;

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
  /// noteheads; [NoteheadScheme.sacredHarp] and [NoteheadScheme.aikin] draw
  /// four- and seven-shape noteheads by each pitch's scale degree. Only applies
  /// to notes whose [NoteheadShape] is `normal` (an explicit shape such as x or
  /// diamond always wins).
  final NoteheadScheme noteheadScheme;

  /// Whether each beam level past the 16th breaks at half the pulse of the
  /// level above it: 32nd beams split at each eighth, 64th beams at each
  /// sixteenth, while the primary and 16th beams keep to the beat. Off by
  /// default, which keeps every beam level continuous within a beat.
  final bool subdivideBeamsPerLevel;

  /// Whether metronome marks are drawn: `Score.tempo` over the first bar and
  /// every `Measure.tempoChange` over its bar, as "♩ = 63", joined with the
  /// tempo words set at the same spot ("Adagio ♪ = 63"). On by default; turn
  /// it off when the app shows the tempo elsewhere.
  final bool drawTempoMarks;

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

  /// Measures [text] set at [size] (both in staff spaces) and returns its
  /// width — supplied by a renderer that has the real font (the Flutter views
  /// do). Without one, the layout estimates widths per character, sized for
  /// the widest common UI font, and leaves more room than most fonts need.
  final double Function(String text, double size)? textWidth;

  /// Print density — spacing and text sizes close to a published score, for
  /// reading a whole piece on a page or screen. The default constructor is a
  /// little roomier, which suits interactive use.
  factory LayoutSettings.engraved(
          {required SmuflMetadata metadata,
          double Function(String text, double size)? textWidth}) =>
      LayoutSettings(
        metadata: metadata,
        textWidth: textWidth,
        spacingBase: 1.5,
        spacingPerLog2: 0.65,
        minNoteGap: 0.5,
        barlineGap: 0.9,
        lyricSize: 1.5,
        annotationSize: 1.6,
      );

  /// Roomy — wider spacing and larger text, for young readers and for
  /// tapping notes on a small touch screen.
  factory LayoutSettings.spacious(
          {required SmuflMetadata metadata,
          double Function(String text, double size)? textWidth}) =>
      LayoutSettings(
        metadata: metadata,
        textWidth: textWidth,
        spacingBase: 2.2,
        spacingPerLog2: 0.9,
        minNoteGap: 0.8,
        lyricSize: 1.8,
        annotationSize: 2.0,
      );

  /// A house style from a style sheet — the JSON a publisher or teacher
  /// keeps beside their scores: `base` picks the preset it starts from
  /// (`default`, `engraved` or `spacious`), and any setting named as in this
  /// class overrides it, in staff spaces (`"spacingBase": 1.6`,
  /// `"lyricSize": 1.4`, `"noteheadScheme": "pitchName"`). An unknown key or a
  /// value of the wrong kind is a [FormatException] naming it, so a typo does
  /// not pass silently.
  factory LayoutSettings.fromStyle(
    Map<String, Object?> style, {
    required SmuflMetadata metadata,
    double Function(String text, double size)? textWidth,
  }) {
    final unknown = style.keys.where((k) => !_styleKeys.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException('unknown style keys: ${unknown.join(', ')}; '
          'known: ${_styleKeys.join(', ')}');
    }
    final base = switch (style['base']) {
      null ||
      'default' =>
        LayoutSettings(metadata: metadata, textWidth: textWidth),
      'engraved' =>
        LayoutSettings.engraved(metadata: metadata, textWidth: textWidth),
      'spacious' =>
        LayoutSettings.spacious(metadata: metadata, textWidth: textWidth),
      final other => throw FormatException(
          'style base "$other": default, engraved or spacious'),
    };
    double number(String key, double fallback) => switch (style[key]) {
          null => fallback,
          final num n => n.toDouble(),
          final other =>
            throw FormatException('style "$key": a number, not $other'),
        };
    bool flag(String key, bool fallback) => switch (style[key]) {
          null => fallback,
          final bool b => b,
          final other =>
            throw FormatException('style "$key": true or false, not $other'),
        };
    T choice<T extends Enum>(String key, List<T> values, T fallback) {
      final v = style[key];
      if (v == null) return fallback;
      for (final value in values) {
        if (value.name == v) return value;
      }
      throw FormatException('style "$key": one of '
          '${values.map((x) => x.name).join(', ')}, not $v');
    }

    var microtonal = base.microtonalGlyphs;
    final glyphs = style['microtonalGlyphs'];
    if (glyphs != null) {
      if (glyphs is! Map) {
        throw const FormatException(
            'style "microtonalGlyphs": an object of glyph names');
      }
      microtonal = {
        for (final MapEntry(:key, :value) in glyphs.entries)
          MicrotonalAccidental.values.where((m) => m.name == key).firstOrNull ??
                  (throw FormatException(
                      'style "microtonalGlyphs": no accidental "$key"')):
              value is String
                  ? value
                  : throw FormatException(
                      'style "microtonalGlyphs.$key": a glyph name'),
      };
    }
    return LayoutSettings(
      metadata: metadata,
      textWidth: textWidth,
      fingeringPlacement: choice('fingeringPlacement',
          FingeringPlacement.values, base.fingeringPlacement),
      noteheadScheme:
          choice('noteheadScheme', NoteheadScheme.values, base.noteheadScheme),
      microtonalGlyphs: microtonal,
      staffLineThickness: number('staffLineThickness', base.staffLineThickness),
      stemThickness: number('stemThickness', base.stemThickness),
      legerLineThickness: number('legerLineThickness', base.legerLineThickness),
      legerLineExtension: number('legerLineExtension', base.legerLineExtension),
      beamThickness: number('beamThickness', base.beamThickness),
      beamSpacing: number('beamSpacing', base.beamSpacing),
      thinBarlineThickness:
          number('thinBarlineThickness', base.thinBarlineThickness),
      thickBarlineThickness:
          number('thickBarlineThickness', base.thickBarlineThickness),
      barlineSeparation: number('barlineSeparation', base.barlineSeparation),
      stemLength: number('stemLength', base.stemLength),
      leadingPadding: number('leadingPadding', base.leadingPadding),
      clefGap: number('clefGap', base.clefGap),
      keyAccidentalGap: number('keyAccidentalGap', base.keyAccidentalGap),
      signatureGap: number('signatureGap', base.signatureGap),
      accidentalGap: number('accidentalGap', base.accidentalGap),
      dotGap: number('dotGap', base.dotGap),
      dotSpacing: number('dotSpacing', base.dotSpacing),
      barlineGap: number('barlineGap', base.barlineGap),
      minNoteGap: number('minNoteGap', base.minNoteGap),
      spacingBase: number('spacingBase', base.spacingBase),
      spacingPerLog2: number('spacingPerLog2', base.spacingPerLog2),
      verticalPadding: number('verticalPadding', base.verticalPadding),
      lyricSize: number('lyricSize', base.lyricSize),
      lyricGap: number('lyricGap', base.lyricGap),
      annotationSize: number('annotationSize', base.annotationSize),
      annotationGap: number('annotationGap', base.annotationGap),
      navigationSize: number('navigationSize', base.navigationSize),
      navigationGap: number('navigationGap', base.navigationGap),
      subdivideBeamsPerLevel:
          flag('subdivideBeamsPerLevel', base.subdivideBeamsPerLevel),
      drawTempoMarks: flag('drawTempoMarks', base.drawTempoMarks),
    );
  }

  /// This house style as a style sheet [LayoutSettings.fromStyle] reads back:
  /// every setting by name (the font metadata and text measurer stay with
  /// the renderer).
  Map<String, Object> toStyle() => {
        'fingeringPlacement': fingeringPlacement.name,
        'noteheadScheme': noteheadScheme.name,
        if (microtonalGlyphs.isNotEmpty)
          'microtonalGlyphs': {
            for (final MapEntry(:key, :value) in microtonalGlyphs.entries)
              key.name: value,
          },
        'staffLineThickness': staffLineThickness,
        'stemThickness': stemThickness,
        'legerLineThickness': legerLineThickness,
        'legerLineExtension': legerLineExtension,
        'beamThickness': beamThickness,
        'beamSpacing': beamSpacing,
        'thinBarlineThickness': thinBarlineThickness,
        'thickBarlineThickness': thickBarlineThickness,
        'barlineSeparation': barlineSeparation,
        'stemLength': stemLength,
        'leadingPadding': leadingPadding,
        'clefGap': clefGap,
        'keyAccidentalGap': keyAccidentalGap,
        'signatureGap': signatureGap,
        'accidentalGap': accidentalGap,
        'dotGap': dotGap,
        'dotSpacing': dotSpacing,
        'barlineGap': barlineGap,
        'minNoteGap': minNoteGap,
        'spacingBase': spacingBase,
        'spacingPerLog2': spacingPerLog2,
        'verticalPadding': verticalPadding,
        'lyricSize': lyricSize,
        'lyricGap': lyricGap,
        'annotationSize': annotationSize,
        'annotationGap': annotationGap,
        'navigationSize': navigationSize,
        'navigationGap': navigationGap,
        'subdivideBeamsPerLevel': subdivideBeamsPerLevel,
        'drawTempoMarks': drawTempoMarks,
      };

  static const _styleKeys = {
    'base',
    'fingeringPlacement',
    'noteheadScheme',
    'microtonalGlyphs',
    'staffLineThickness',
    'stemThickness',
    'legerLineThickness',
    'legerLineExtension',
    'beamThickness',
    'beamSpacing',
    'thinBarlineThickness',
    'thickBarlineThickness',
    'barlineSeparation',
    'stemLength',
    'leadingPadding',
    'clefGap',
    'keyAccidentalGap',
    'signatureGap',
    'accidentalGap',
    'dotGap',
    'dotSpacing',
    'barlineGap',
    'minNoteGap',
    'spacingBase',
    'spacingPerLog2',
    'verticalPadding',
    'lyricSize',
    'lyricGap',
    'annotationSize',
    'annotationGap',
    'navigationSize',
    'navigationGap',
    'subdivideBeamsPerLevel',
    'drawTempoMarks',
  };

  /// Creates settings seeded from [metadata]'s engraving defaults; any
  /// parameter can be overridden.
  LayoutSettings({
    required this.metadata,
    this.fingeringPlacement = FingeringPlacement.aboveNote,
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
    this.subdivideBeamsPerLevel = false,
    this.drawTempoMarks = true,
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
    this.textWidth,
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
