import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'music_font.dart';

/// Visual styling and ergonomics for `StaffView` and `InteractiveStaff`.
class PartituraTheme {
  /// Color of staff furniture: staff lines, barlines, clef, signatures.
  final Color staffColor;

  /// Color of score elements: noteheads, stems, flags, beams, rests,
  /// accidentals, dots.
  final Color noteColor;

  /// Color applied to elements whose id is in `StaffView.highlightedIds`.
  final Color highlightColor;

  /// Per-element color overrides by element id; wins over [noteColor] but
  /// is itself overridden by [highlightColor] for highlighted elements.
  final Map<String, Color> elementColors;

  /// Kid mode: bolder lines and generous hit slop, sized for children's
  /// motor precision (ages 6+).
  final bool kidMode;

  /// Extra margin in **staff spaces** added around element hit boxes when
  /// hit-testing taps.
  final double hitSlop;

  /// Multiplier applied to line thicknesses when painting (kid mode uses a
  /// bolder stroke).
  final double lineBoost;

  /// Font family for plain text (lyrics, annotations); null uses the
  /// platform default. Golden tests set this to a loaded font so text
  /// renders as glyphs instead of the test framework's box font.
  final String? textFontFamily;

  /// The SMuFL music font used to draw notation glyphs (default: Bravura).
  /// Switching it swaps the whole engraving face — see [MusicFont].
  final MusicFont musicFont;

  /// Creates a theme; defaults are ink-on-paper black.
  const PartituraTheme({
    this.staffColor = const Color(0xFF1A1A1A),
    this.noteColor = const Color(0xFF1A1A1A),
    this.highlightColor = const Color(0xFF1E88E5),
    this.elementColors = const {},
    this.kidMode = false,
    this.hitSlop = 0.5,
    this.lineBoost = 1.0,
    this.textFontFamily,
    this.musicFont = MusicFont.bravura,
  });

  /// The default theme.
  static const PartituraTheme standard = PartituraTheme();

  /// Bolder lines, orange highlight and generous hit targets for children.
  static const PartituraTheme kids = PartituraTheme(
    kidMode: true,
    hitSlop: 1.5,
    lineBoost: 1.4,
    highlightColor: Color(0xFFF4511E),
  );

  /// A copy of this theme with the given fields replaced.
  PartituraTheme copyWith({
    Color? staffColor,
    Color? noteColor,
    Color? highlightColor,
    Map<String, Color>? elementColors,
    bool? kidMode,
    double? hitSlop,
    double? lineBoost,
    String? textFontFamily,
    MusicFont? musicFont,
  }) =>
      PartituraTheme(
        staffColor: staffColor ?? this.staffColor,
        noteColor: noteColor ?? this.noteColor,
        highlightColor: highlightColor ?? this.highlightColor,
        elementColors: elementColors ?? this.elementColors,
        kidMode: kidMode ?? this.kidMode,
        hitSlop: hitSlop ?? this.hitSlop,
        lineBoost: lineBoost ?? this.lineBoost,
        textFontFamily: textFontFamily ?? this.textFontFamily,
        musicFont: musicFont ?? this.musicFont,
      );

  @override
  bool operator ==(Object other) =>
      other is PartituraTheme &&
      other.staffColor == staffColor &&
      other.noteColor == noteColor &&
      other.highlightColor == highlightColor &&
      other.kidMode == kidMode &&
      other.hitSlop == hitSlop &&
      other.lineBoost == lineBoost &&
      other.textFontFamily == textFontFamily &&
      other.musicFont == musicFont &&
      mapEquals(other.elementColors, elementColors);

  @override
  int get hashCode => Object.hash(
        staffColor,
        noteColor,
        highlightColor,
        kidMode,
        hitSlop,
        lineBoost,
        textFontFamily,
        musicFont,
        Object.hashAllUnordered(
          elementColors.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );
}
