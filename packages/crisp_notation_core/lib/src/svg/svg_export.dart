/// SVG export: renders a laid-out [ScoreLayout] to a standalone SVG document.
///
/// Pure Dart and dependency-free — it turns the layout's display list
/// (glyphs, lines, curves, beams, text) into SVG shapes, so the same emitter
/// serves both notation ([LayoutEngine]) and tablature ([TabLayoutEngine]).
/// SMuFL glyphs are emitted as `<text>` in the engraving font (default
/// `Bravura`); pass [fontFaceDataUri] to embed the font and make the file
/// fully self-contained.
library;

import '../layout/grand_staff.dart';
import '../layout/multi_system.dart';
import '../layout/physical_size.dart';
import '../layout/score_layout.dart';
import '../layout/staff_system.dart';
import '../model/score.dart';
import '../smufl/smufl_codepoints.dart';

const _defaultTextFontFamily =
    "Academico, 'New York', 'Times New Roman', Times, serif";

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
/// renders without the font installed. With [physicalSize] the document is
/// sized in millimetres for true-size printing (see [Spatium]).
/// Deterministic.
String scoreToSvg(
  ScoreLayout layout, {
  double staffSpace = 12,
  String glyphFontFamily = 'Bravura',
  String textFontFamily = _defaultTextFontFamily,
  String color = '#000000',
  String background = '#ffffff',
  String? fontFaceDataUri,
  Map<String, String> elementColors = const {},
  Spatium? physicalSize,
}) {
  final widthPx = layout.width * staffSpace;
  final heightPx = layout.height * staffSpace;
  final b = StringBuffer();
  _svgOpen(b, widthPx, heightPx, glyphFontFamily, background, fontFaceDataUri,
      physicalSize: physicalSize, staffSpace: staffSpace);

  // One transform: staff spaces → px, shifting the (possibly negative) top of
  // the ink to y = 0.
  _emitStaff(b, layout, staffSpace, -layout.top * staffSpace, color,
      glyphFontFamily, textFontFamily, elementColors);

  b.writeln('</svg>');
  return b.toString();
}

/// Emits one staff's [ScoreLayout] as an SVG group, transforming staff spaces →
/// px and translating by [offsetY] px. Shared by [scoreToSvg] and
/// [grandStaffToSvg].
void _emitStaff(
  StringBuffer b,
  ScoreLayout layout,
  double staffSpace,
  double offsetY,
  String color,
  String glyphFontFamily,
  String textFontFamily,
  Map<String, String> elementColors,
) {
  b.writeln('<g transform="translate(0 ${_n(offsetY)}) '
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
}

/// Serializes a laid-out [GrandStaffLayout] (two staves) to a standalone SVG
/// document — the same emitter as [scoreToSvg], with the upper and lower staves
/// stacked [GrandStaffLayout.staffGap] spaces apart. Parameters match
/// [scoreToSvg]; [elementColors] applies across both staves.
String grandStaffToSvg(
  GrandStaffLayout layout, {
  double staffSpace = 12,
  String glyphFontFamily = 'Bravura',
  String textFontFamily = _defaultTextFontFamily,
  String color = '#000000',
  String background = '#ffffff',
  String? fontFaceDataUri,
  Map<String, String> elementColors = const {},
  Spatium? physicalSize,
}) {
  final widthPx = layout.width * staffSpace;
  final heightPx = layout.height * staffSpace;
  final b = StringBuffer();
  _svgOpen(b, widthPx, heightPx, glyphFontFamily, background, fontFaceDataUri,
      physicalSize: physicalSize, staffSpace: staffSpace);

  // Upper ink top shifts to y = 0; the lower staff's top line sits its own top
  // line at (upper bottom line = 4) + staffGap below that.
  final upperOffset = -layout.upper.top * staffSpace;
  final lowerOffset = (4 - layout.upper.top + layout.staffGap) * staffSpace;
  _emitStaff(b, layout.upper, staffSpace, upperOffset, color, glyphFontFamily,
      textFontFamily, elementColors);
  _emitStaff(b, layout.lower, staffSpace, lowerOffset, color, glyphFontFamily,
      textFontFamily, elementColors);

  b.writeln('</svg>');
  return b.toString();
}

/// Emits one multi-staff system's staves (each at its stacked y) plus the
/// systemic barline connectors that run through the barline groups — at pixel
/// offset [baseY] within an already-open `<svg>`.
void _emitStaffSystem(
  StringBuffer b,
  StaffSystemLayout layout,
  double staffSpace,
  double baseY,
  String color,
  String glyphFontFamily,
  String textFontFamily,
  Map<String, String> elementColors,
) {
  for (var i = 0; i < layout.staves.length; i++) {
    _emitStaff(
        b,
        layout.staves[i],
        staffSpace,
        baseY + (layout.staffTop(i) - layout.top) * staffSpace,
        color,
        glyphFontFamily,
        textFontFamily,
        elementColors);
  }
  // Systemic barlines: a vertical line at every barline x, spanning each
  // connected group (so grouped staves join and the line breaks between groups).
  final spans = layout.barlineSpans;
  final xs = layout.barlineXs;
  if (spans.isNotEmpty && xs.isNotEmpty) {
    b.writeln(
        '<g transform="translate(0 ${_n(baseY - layout.top * staffSpace)})'
        ' scale($staffSpace)" stroke="$color">');
    for (final x in xs) {
      for (final span in spans) {
        b.writeln('<line x1="${_n(x)}" y1="${_n(span.top)}" '
            'x2="${_n(x)}" y2="${_n(span.bottom)}" stroke-width="0.16"/>');
      }
    }
    b.writeln('</g>');
  }
}

/// Renders a single multi-staff [StaffSystemLayout] (all parts, one line) to
/// SVG — the N-staff counterpart of [grandStaffToSvg].
String staffSystemToSvg(
  StaffSystemLayout layout, {
  double staffSpace = 12,
  String glyphFontFamily = 'Bravura',
  String textFontFamily = _defaultTextFontFamily,
  String color = '#000000',
  String background = '#ffffff',
  String? fontFaceDataUri,
  Map<String, String> elementColors = const {},
  Spatium? physicalSize,
}) {
  final widthPx = layout.width * staffSpace;
  final heightPx = layout.height * staffSpace;
  final b = StringBuffer();
  _svgOpen(b, widthPx, heightPx, glyphFontFamily, background, fontFaceDataUri,
      physicalSize: physicalSize, staffSpace: staffSpace);
  _emitStaffSystem(b, layout, staffSpace, -layout.top * staffSpace, color,
      glyphFontFamily, textFontFamily, elementColors);
  b.writeln('</svg>');
  return b.toString();
}

/// Renders a **wrapped**, line-broken multi-staff document
/// ([StaffSystemSystems] from `layoutStaffSystemSystems`) — every part's system
/// stacked vertically [systemGap] spaces apart — to one SVG. This is how a long
/// multi-part score (quartet, orchestral) renders on the command line.
String staffSystemSystemsToSvg(
  StaffSystemSystems wrapped, {
  double staffSpace = 12,
  double systemGap = 8,
  double leftMargin = 0,
  bool showInstrumentLabels = false,
  bool showSystemMeasureNumbers = false,
  bool showTitle = false,
  String glyphFontFamily = 'Bravura',
  String textFontFamily = _defaultTextFontFamily,
  String color = '#000000',
  String background = '#ffffff',
  String? fontFaceDataUri,
  Map<String, String> elementColors = const {},
  Spatium? physicalSize,
}) {
  final metadata = _firstMetadata(wrapped);
  final titleTop = showTitle ? _titleBlockHeight(metadata) : 0.0;
  final widthPx = (wrapped.maxWidth + leftMargin) * staffSpace;
  final heightPx = (titleTop + wrapped.heightWith(systemGap)) * staffSpace;
  final b = StringBuffer();
  _svgOpen(b, widthPx, heightPx, glyphFontFamily, background, fontFaceDataUri,
      physicalSize: physicalSize, staffSpace: staffSpace);
  if (titleTop > 0) {
    _emitTitleBlock(b, metadata, staffSpace, leftMargin, wrapped.maxWidth,
        color, textFontFamily);
  }
  var y = titleTop * staffSpace;
  for (var i = 0; i < wrapped.systems.length; i++) {
    final system = wrapped.systems[i];
    if (showInstrumentLabels && i == 0 && leftMargin > 0) {
      _emitInstrumentLabels(
          b, system.layout, staffSpace, y, leftMargin, color, textFontFamily);
    }
    if (showSystemMeasureNumbers && i > 0) {
      _emitSystemMeasureNumber(
          b, system, staffSpace, y, leftMargin, color, textFontFamily);
    }
    if (leftMargin > 0) {
      b.writeln('<g transform="translate(${_n(leftMargin * staffSpace)} 0)">');
    }
    _emitStaffSystem(b, system.layout, staffSpace, y, color, glyphFontFamily,
        textFontFamily, elementColors);
    if (leftMargin > 0) b.writeln('</g>');
    y += (system.layout.height + systemGap) * staffSpace;
  }
  b.writeln('</svg>');
  return b.toString();
}

ScoreMetadata _firstMetadata(StaffSystemSystems wrapped) {
  if (wrapped.systems.isEmpty ||
      wrapped.systems.first.layout.source.staves.isEmpty) {
    return const ScoreMetadata();
  }
  return wrapped.systems.first.layout.source.staves.first.metadata;
}

double _titleBlockHeight(ScoreMetadata metadata) {
  final hasTitle = metadata.title?.trim().isNotEmpty ?? false;
  final hasComposer = metadata.composer?.trim().isNotEmpty ?? false;
  if (!hasTitle && !hasComposer) return 0;
  final titleLines = _metadataLines(metadata.title);
  return 3.2 + titleLines.length * 1.25 + (hasComposer ? 1.3 : 0);
}

List<String> _metadataLines(String? text) => (text ?? '')
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList();

void _emitTitleBlock(
  StringBuffer b,
  ScoreMetadata metadata,
  double staffSpace,
  double leftMargin,
  double maxWidth,
  String color,
  String textFontFamily,
) {
  final titleLines = _metadataLines(metadata.title);
  final composerLines = _metadataLines(metadata.composer);
  final pageWidth = (leftMargin + maxWidth) * staffSpace;
  final centerX = pageWidth / 2;
  var y = 1.8 * staffSpace;
  for (var i = 0; i < titleLines.length; i++) {
    final size = (i == 0 ? 1.55 : 1.05) * staffSpace;
    b.writeln('<text x="${_n(centerX)}" y="${_n(y)}" '
        'font-family="$textFontFamily" font-size="${_n(size)}" '
        'font-weight="${i == 0 ? '600' : '400'}" '
        'text-anchor="middle" fill="$color" stroke="none">'
        '${_escape(titleLines[i])}</text>');
    y += (i == 0 ? 1.45 : 1.25) * staffSpace;
  }
  if (composerLines.isNotEmpty) {
    y += 0.35 * staffSpace;
    for (final line in composerLines) {
      b.writeln('<text x="${_n(pageWidth)}" y="${_n(y)}" '
          'font-family="$textFontFamily" font-size="${_n(0.9 * staffSpace)}" '
          'text-anchor="end" fill="$color" stroke="none">'
          '${_escape(line)}</text>');
      y += 1.05 * staffSpace;
    }
  }
}

void _emitInstrumentLabels(
  StringBuffer b,
  StaffSystemLayout layout,
  double staffSpace,
  double baseY,
  double leftMargin,
  String color,
  String textFontFamily,
) {
  var start = 0;
  while (start < layout.source.staves.length) {
    final label = layout.source.staves[start].metadata.instrument;
    if (label == null || label.trim().isEmpty) {
      start++;
      continue;
    }
    var end = start;
    while (end + 1 < layout.source.staves.length &&
        layout.source.staves[end + 1].metadata.instrument == label) {
      end++;
    }
    final top = layout.staffTop(start);
    final bottom = layout.staffTop(end) + 4;
    final y = baseY + ((top + bottom) / 2 - layout.top) * staffSpace;
    final x = (leftMargin - 1.0) * staffSpace;
    b.writeln('<text x="${_n(x)}" y="${_n(y)}" '
        'font-family="$textFontFamily" font-size="${_n(1.1 * staffSpace)}" '
        'text-anchor="end" dominant-baseline="middle" '
        'fill="$color" stroke="none">${_escape(label)}</text>');
    start = end + 1;
  }
}

void _emitSystemMeasureNumber(
  StringBuffer b,
  StaffSystemSystem system,
  double staffSpace,
  double baseY,
  double leftMargin,
  String color,
  String textFontFamily,
) {
  final layout = system.layout;
  final number = system.firstMeasure + 1;
  final x = (leftMargin + 0.5) * staffSpace;
  final y = baseY + (layout.staffTop(0) - layout.top - 1.0) * staffSpace;
  b.writeln('<text x="${_n(x)}" y="${_n(y)}" '
      'font-family="$textFontFamily" font-size="${_n(0.9 * staffSpace)}" '
      'text-anchor="start" fill="$color" stroke="none">$number</text>');
}

/// Writes the `<svg>` open tag, optional embedded font and background fill.
///
/// With [physicalSize], the document's width and height are given in
/// millimetres (each staff space [Spatium.millimetres] long), so a viewer or
/// printer shows it at true staff size; the drawing itself, in its pixel
/// `viewBox`, is unchanged.
void _svgOpen(StringBuffer b, double widthPx, double heightPx,
    String glyphFontFamily, String background, String? fontFaceDataUri,
    {Spatium? physicalSize, double staffSpace = 12}) {
  b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  b.write('<svg xmlns="http://www.w3.org/2000/svg" ');
  if (physicalSize == null) {
    b.write('width="${_n(widthPx)}" height="${_n(heightPx)}" ');
  } else {
    final mm = physicalSize.millimetres / staffSpace;
    b.write('width="${_n(widthPx * mm)}mm" height="${_n(heightPx * mm)}mm" ');
  }
  b.writeln('viewBox="0 0 ${_n(widthPx)} ${_n(heightPx)}">');
  if (fontFaceDataUri != null) {
    b.writeln('<defs><style>@font-face{font-family:"$glyphFontFamily";'
        'src:url($fontFaceDataUri);}</style></defs>');
  }
  if (background != 'none') {
    b.writeln('<rect x="0" y="0" width="${_n(widthPx)}" '
        'height="${_n(heightPx)}" fill="$background"/>');
  }
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
