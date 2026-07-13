import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/services.dart' show rootBundle;
import 'package:partitura_core/partitura_core.dart';

import 'music_font.dart';
import 'png_export.dart';
import 'theme.dart';

/// One-call `Score` / `GrandStaff` → PNG or SVG export (Workshop contract C8).
///
/// These wrap the lower-level `renderLayoutToPng` / `scoreToSvg` (which need a
/// pre-built `ScoreLayout`, and — for SVG — a font data-URI) so the app's
/// print / page-export action is a single call: they own the layout pass, the
/// SMuFL metadata lookup, and embedding the engraving font. `theme` and
/// `staffSpace` mirror the on-screen views.

const LayoutEngine _engine = LayoutEngine();

LayoutSettings _settingsFor(SmuflMetadata metadata, PartituraTheme theme) {
  final boost = theme.lineBoost;
  final base = LayoutSettings(metadata: metadata);
  if (boost == 1.0) return base;
  return LayoutSettings(
    metadata: metadata,
    staffLineThickness: base.staffLineThickness * boost,
    stemThickness: base.stemThickness * boost,
    legerLineThickness: base.legerLineThickness * boost,
    thinBarlineThickness: base.thinBarlineThickness * boost,
  );
}

Future<SmuflMetadata> _metadata(PartituraTheme theme) async =>
    MusicFonts.metadataOrNull(theme.musicFont) ??
    await MusicFonts.load(theme.musicFont);

Future<String?> _fontDataUri(MusicFont font) async {
  final asset = font.fontAsset;
  if (asset == null) return null;
  final bytes = await rootBundle.load(asset);
  return 'data:font/otf;base64,${base64Encode(bytes.buffer.asUint8List())}';
}

String _hex(Color c) {
  int ch(double v) => (v * 255).round().clamp(0, 255);
  final rgb = (ch(c.r) << 16) | (ch(c.g) << 8) | ch(c.b);
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

/// Renders [score] straight to PNG bytes — owns the layout pass, the SMuFL
/// metadata, and rasterization. Runs inside a Flutter binding (an app, or
/// `flutter test`); the engraving font must be registered (it is after
/// [MusicFonts.load] / the test setup). [background] fills the page — pass a
/// transparent color for none.
Future<Uint8List> exportScoreToPng(
  Score score, {
  PartituraTheme theme = PartituraTheme.standard,
  double staffSpace = 12,
  Set<String> highlightedIds = const {},
  Color background = const Color(0xFFFFFFFF),
}) async {
  final metadata = await _metadata(theme);
  final layout = _engine.layout(score, _settingsFor(metadata, theme));
  return renderLayoutToPng(
    layout,
    staffSpace: staffSpace,
    theme: theme,
    highlightedIds: highlightedIds,
    background: background,
  );
}

/// Renders [score] straight to an SVG string with the engraving font embedded
/// (so the file renders anywhere). Pure geometry — no rasterizer — but async
/// because it loads the font bytes; pass `embedFont: false` to reference the
/// font by family instead. [elementColors] overrides per-element ink (hex).
Future<String> exportScoreToSvg(
  Score score, {
  PartituraTheme theme = PartituraTheme.standard,
  double staffSpace = 12,
  bool embedFont = true,
  Map<String, String> elementColors = const {},
}) async {
  final metadata = await _metadata(theme);
  final layout = _engine.layout(score, _settingsFor(metadata, theme));
  return scoreToSvg(
    layout,
    staffSpace: staffSpace,
    glyphFontFamily: theme.musicFont.family,
    textFontFamily: theme.textFontFamily ?? 'sans-serif',
    color: _hex(theme.staffColor),
    fontFaceDataUri: embedFont ? await _fontDataUri(theme.musicFont) : null,
    elementColors: elementColors,
  );
}

/// The grand-staff (two-clef) overload of [exportScoreToPng].
Future<Uint8List> exportGrandStaffToPng(
  GrandStaff grandStaff, {
  PartituraTheme theme = PartituraTheme.standard,
  double staffSpace = 12,
  double staffGap = 4.0,
  Set<String> highlightedIds = const {},
  Color background = const Color(0xFFFFFFFF),
}) async {
  final metadata = await _metadata(theme);
  final layout = layoutGrandStaff(grandStaff, _settingsFor(metadata, theme),
      staffGap: staffGap);
  return renderGrandStaffLayoutToPng(
    layout,
    staffSpace: staffSpace,
    theme: theme,
    highlightedIds: highlightedIds,
    background: background,
  );
}

/// The grand-staff (two-clef) overload of [exportScoreToSvg].
Future<String> exportGrandStaffToSvg(
  GrandStaff grandStaff, {
  PartituraTheme theme = PartituraTheme.standard,
  double staffSpace = 12,
  double staffGap = 4.0,
  bool embedFont = true,
  Map<String, String> elementColors = const {},
}) async {
  final metadata = await _metadata(theme);
  final layout = layoutGrandStaff(grandStaff, _settingsFor(metadata, theme),
      staffGap: staffGap);
  return grandStaffToSvg(
    layout,
    staffSpace: staffSpace,
    glyphFontFamily: theme.musicFont.family,
    textFontFamily: theme.textFontFamily ?? 'sans-serif',
    color: _hex(theme.staffColor),
    fontFaceDataUri: embedFont ? await _fontDataUri(theme.musicFont) : null,
    elementColors: elementColors,
  );
}
