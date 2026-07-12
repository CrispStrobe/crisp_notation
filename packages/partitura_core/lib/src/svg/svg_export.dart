/// SVG export: renders a laid-out [ScoreLayout] to a standalone SVG document.
///
/// Pure Dart and dependency-free — it turns the layout's display list
/// (glyphs, lines, curves, beams, text) into SVG shapes, so the same emitter
/// serves both notation ([LayoutEngine]) and tablature ([TabLayoutEngine]).
/// SMuFL glyphs are emitted as `<text>` in the engraving font (default
/// `Bravura`); pass [fontFaceDataUri] to embed the font and make the file
/// fully self-contained.
library;

import '../layout/score_layout.dart';
import '../smufl/smufl_codepoints.dart';

/// Serializes [layout] to an SVG document string.
///
/// [staffSpace] is the pixel size of one staff space (the single scale
/// factor). [glyphFontFamily] names the SMuFL engraving font; [textFontFamily]
/// the face for plain text (lyrics, labels, fret numbers). [color] paints the
/// ink, [background] the page (pass `'none'` for transparency).
/// [elementColors] maps an element id to a CSS colour, painting that element's
/// ink in it (e.g. highlight a note, colour out-of-range notes) — matching the
/// Flutter painter's per-element colouring. When [fontFaceDataUri] is a `data:`
/// URI of the engraving font, it is embedded via `@font-face` so the SVG
/// renders without the font installed. Deterministic.
String scoreToSvg(
  ScoreLayout layout, {
  double staffSpace = 12,
  String glyphFontFamily = 'Bravura',
  String textFontFamily = 'sans-serif',
  String color = '#000000',
  String background = '#ffffff',
  String? fontFaceDataUri,
  Map<String, String> elementColors = const {},
}) {
  final widthPx = layout.width * staffSpace;
  final heightPx = layout.height * staffSpace;
  final b = StringBuffer();
  b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  b.write('<svg xmlns="http://www.w3.org/2000/svg" ');
  b.write('width="${_n(widthPx)}" height="${_n(heightPx)}" ');
  b.writeln('viewBox="0 0 ${_n(widthPx)} ${_n(heightPx)}">');

  if (fontFaceDataUri != null) {
    b.writeln('<defs><style>@font-face{font-family:"$glyphFontFamily";'
        'src:url($fontFaceDataUri);}</style></defs>');
  }
  if (background != 'none') {
    b.writeln('<rect x="0" y="0" width="${_n(widthPx)}" '
        'height="${_n(heightPx)}" fill="$background"/>');
  }

  // One transform: staff spaces → px, shifting the (possibly negative) top of
  // the ink to y = 0.
  b.writeln('<g transform="translate(0 ${_n(-layout.top * staffSpace)}) '
      'scale($staffSpace)" fill="$color" stroke="$color">');

  for (final p in layout.primitives) {
    // Per-element override (app-supplied note colors); else the group colour.
    final ec = p.elementId == null ? null : elementColors[p.elementId];
    final fill = ec == null ? '' : ' fill="$ec"';
    final stroke = ec == null ? '' : ' stroke="$ec"';
    switch (p) {
      case GlyphPrimitive(:final smuflName, :final position, :final scale):
        final char = smuflCodepoints[smuflName];
        if (char == null) continue;
        final size = 4.0 * scale; // glyph em = 4 staff spaces
        b.writeln('<text x="${_n(position.x)}" y="${_n(position.y)}" '
            'font-family="$glyphFontFamily" font-size="${_n(size)}" '
            'stroke="none"$fill>${_escape(char)}</text>');
      case LinePrimitive(
          :final from,
          :final to,
          :final thickness,
          :final round
        ):
        b.writeln('<line x1="${_n(from.x)}" y1="${_n(from.y)}" '
            'x2="${_n(to.x)}" y2="${_n(to.y)}" '
            'stroke-width="${_n(thickness)}" '
            'stroke-linecap="${round ? 'round' : 'butt'}"$stroke/>');
      case CurvePrimitive(
          :final start,
          :final control1,
          :final control2,
          :final end,
          :final thickness
        ):
        b.writeln('<path d="M ${_n(start.x)} ${_n(start.y)} '
            'C ${_n(control1.x)} ${_n(control1.y)} '
            '${_n(control2.x)} ${_n(control2.y)} '
            '${_n(end.x)} ${_n(end.y)}" fill="none" '
            'stroke-width="${_n(thickness)}"$stroke/>');
      case BeamPrimitive(:final start, :final end, :final thickness):
        final h = thickness / 2;
        final pts = '${_n(start.x)},${_n(start.y - h)} '
            '${_n(end.x)},${_n(end.y - h)} '
            '${_n(end.x)},${_n(end.y + h)} '
            '${_n(start.x)},${_n(start.y + h)}';
        b.writeln('<polygon points="$pts" stroke="none"$fill/>');
      case TextPrimitive(:final text, :final position, :final size):
        b.writeln('<text x="${_n(position.x)}" y="${_n(position.y)}" '
            'font-family="$textFontFamily" font-size="${_n(size)}" '
            'text-anchor="middle" stroke="none"$fill>${_escape(text)}</text>');
    }
  }

  b.writeln('</g>');
  b.writeln('</svg>');
  return b.toString();
}

/// Formats a coordinate, trimming a trailing `.0` and any zero padding.
String _n(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  var s = value.toStringAsFixed(3);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

/// Escapes XML text content (also used for PUA glyph characters, which are
/// left intact).
String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
