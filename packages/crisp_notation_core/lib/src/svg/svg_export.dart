/// SVG export: renders a laid-out [ScoreLayout] to a standalone SVG document.
///
/// Pure Dart and dependency-free — it turns the layout's display list
/// (glyphs, lines, curves, beams, text) into SVG shapes, so the same emitter
/// serves both notation ([LayoutEngine]) and tablature ([TabLayoutEngine]).
/// SMuFL glyphs are emitted as `<text>` in the engraving font (default
/// `Bravura`); pass [fontFaceDataUri] to embed the font and make the file
/// fully self-contained.
library;

import 'dart:math';

import '../layout/grand_staff.dart';
import '../layout/multi_system.dart';
import '../layout/physical_size.dart';
import '../layout/score_layout.dart';
import '../layout/staff_system.dart';
import '../layout/title_block.dart';
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

/// Several laid-out lines of one staff — a line-broken score's systems, or
/// chant from `layoutChantLines` — stacked [systemGap] staff spaces apart in
/// one SVG, each line's ink top on its own row.
String scoreLinesToSvg(
  List<ScoreLayout> lines, {
  double staffSpace = 12,
  double systemGap = 4,
  String glyphFontFamily = 'Bravura',
  String textFontFamily = _defaultTextFontFamily,
  String color = '#000000',
  String background = '#ffffff',
  String? fontFaceDataUri,
  Map<String, String> elementColors = const {},
  Spatium? physicalSize,
}) {
  final width = lines.fold(0.0, (w, l) => max(w, l.width));
  final height = lines.fold(0.0, (h, l) => h + l.height) +
      systemGap * max(0, lines.length - 1);
  final b = StringBuffer();
  _svgOpen(b, width * staffSpace, height * staffSpace, glyphFontFamily,
      background, fontFaceDataUri,
      physicalSize: physicalSize, staffSpace: staffSpace);
  var y = 0.0;
  for (final line in lines) {
    _emitStaff(b, line, staffSpace, (y - line.top) * staffSpace, color,
        glyphFontFamily, textFontFamily, elementColors);
    y += line.height + systemGap;
  }
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
      case TextPrimitive(
          :final text,
          :final position,
          :final size,
          :final italic,
          :final bold
        ):
        final style = '${italic ? ' font-style="italic"' : ''}'
            '${bold ? ' font-weight="bold"' : ''}';
        b.writeln('<text x="${_n(position.x)}" y="${_n(position.y)}" '
            'font-family="$textFontFamily" font-size="${_n(size)}"$style '
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
  // Room for the brace left of the staves.
  const margin = 1.8;
  final widthPx = (layout.width + margin) * staffSpace;
  final heightPx = layout.height * staffSpace;
  final b = StringBuffer();
  _svgOpen(b, widthPx, heightPx, glyphFontFamily, background, fontFaceDataUri,
      physicalSize: physicalSize, staffSpace: staffSpace);
  b.writeln('<g transform="translate(${_n(margin * staffSpace)} 0)">');

  // Upper ink top shifts to y = 0; the lower staff's top line sits its own top
  // line at (upper bottom line = 4) + staffGap below that.
  final upperOffset = -layout.upper.top * staffSpace;
  final lowerOffset = (4 - layout.upper.top + layout.staffGap) * staffSpace;
  _emitStaff(b, layout.upper, staffSpace, upperOffset, color, glyphFontFamily,
      textFontFamily, elementColors);
  _emitStaff(b, layout.lower, staffSpace, lowerOffset, color, glyphFontFamily,
      textFontFamily, elementColors);

  // A grand staff is one instrument: its barlines run through both staves,
  // it opens with a line joining them, and a brace holds them together.
  final lowerTop = 4 + layout.staffGap;
  final bars = <double>{
    0,
    for (final l in layout.upper.primitives.whereType<LinePrimitive>())
      if (l.elementId == null &&
          l.from.x == l.to.x &&
          {l.from.y, l.to.y}.containsAll({0.0, 4.0}))
        l.from.x,
  };
  b.writeln('<g transform="translate(0 ${_n(upperOffset)}) '
      'scale($staffSpace)" stroke="$color">');
  for (final x in bars) {
    b.writeln('<line x1="${_n(x)}" y1="4" x2="${_n(x)}" '
        'y2="${_n(lowerTop)}" stroke-width="0.16"/>');
  }
  b.writeln('<line x1="0" y1="0" x2="0" y2="${_n(lowerTop + 4)}" '
      'stroke-width="0.16"/>');
  final brace = smuflCodepoints['brace'];
  if (brace != null) {
    b.writeln('<text x="${_n(-1.8 + 0.35)}" y="${_n(lowerTop + 4)}" '
        'font-family="$glyphFontFamily" font-size="${_n(lowerTop + 4)}" '
        'stroke="none" fill="$color">${_escape(brace)}</text>');
  }
  b.writeln('</g>');
  b.writeln('</g>');

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
  final staves = layout.staves.length;
  if ((spans.isNotEmpty && xs.isNotEmpty) || staves > 1) {
    b.writeln(
        '<g transform="translate(0 ${_n(baseY - layout.top * staffSpace)})'
        ' scale($staffSpace)" stroke="$color">');
    for (final x in xs) {
      for (final span in spans) {
        b.writeln('<line x1="${_n(x)}" y1="${_n(span.top)}" '
            'x2="${_n(x)}" y2="${_n(span.bottom)}" stroke-width="0.16"/>');
      }
    }
    if (staves > 1) {
      // The system's opening line joins every staff, whatever the barline
      // groups (a voice's barlines stand apart from the piano's; its opening
      // line does not).
      b.writeln('<line x1="0" y1="${_n(layout.staffTop(0))}" '
          'x2="0" y2="${_n(layout.staffTop(staves - 1) + 4)}" '
          'stroke-width="0.16"/>');
    }
    _emitBrackets(b, layout, color, glyphFontFamily);
    b.writeln('</g>');
  }
}

/// Space a system's brackets need left of its staves, in staff spaces.
double bracketMargin(StaffSystemLayout layout) =>
    layout.source.brackets.isEmpty ? 0 : 1.8;

/// The system's brackets and braces at its left edge, as the views draw
/// them: a brace glyph stretched over its staves, a square bracket as a thick
/// line with serifs; a group nested in another sits nearer the staves. Drawn
/// in staff-space units inside the system's group.
void _emitBrackets(StringBuffer b, StaffSystemLayout layout, String color,
    String glyphFontFamily) {
  final brackets = layout.source.brackets;
  if (brackets.isEmpty) return;
  int depthOf(StaffBracket x) => brackets
      .where((a) =>
          !identical(a, x) &&
          a.first <= x.first &&
          x.last <= a.last &&
          (a.last - a.first) > (x.last - x.first))
      .length;
  final maxDepth = brackets.map(depthOf).fold(0, (m, d) => d > m ? d : m);
  const step = 0.6; // staff spaces per nesting level
  for (final group in brackets) {
    if (group.last >= layout.staves.length) continue;
    final shift = (maxDepth - depthOf(group)) * step;
    final top = layout.staffTop(group.first);
    final bottom = layout.staffTop(group.last) + 4;
    if (group.kind == StaffBracketKind.brace) {
      // The SMuFL brace is one em (four staff spaces) tall; scale it to the
      // group, baseline on the bottom line.
      final size = 4.0 * (bottom - top) / 4.0;
      final char = smuflCodepoints['brace'];
      if (char == null) continue;
      b.writeln('<text x="${_n(-1.8 + 0.35 - shift)}" y="${_n(bottom)}" '
          'font-family="$glyphFontFamily" font-size="${_n(size)}" '
          'stroke="none" fill="$color">${_escape(char)}</text>');
    } else {
      final x = -0.5 - shift;
      b.writeln('<line x1="${_n(x)}" y1="${_n(top)}" x2="${_n(x)}" '
          'y2="${_n(bottom)}" stroke-width="0.4"/>');
      for (final y in [top, bottom]) {
        b.writeln('<line x1="${_n(x)}" y1="${_n(y)}" x2="${_n(x + 0.6)}" '
            'y2="${_n(y)}" stroke-width="0.16"/>');
      }
    }
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
  final margin = bracketMargin(layout);
  final widthPx = (layout.width + margin) * staffSpace;
  final heightPx = layout.height * staffSpace;
  final b = StringBuffer();
  _svgOpen(b, widthPx, heightPx, glyphFontFamily, background, fontFaceDataUri,
      physicalSize: physicalSize, staffSpace: staffSpace);
  if (margin > 0) {
    b.writeln('<g transform="translate(${_n(margin * staffSpace)} 0)">');
  }
  _emitStaffSystem(b, layout, staffSpace, -layout.top * staffSpace, color,
      glyphFontFamily, textFontFamily, elementColors);
  if (margin > 0) b.writeln('</g>');
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
  // Room for the brackets and braces left of the staves.
  if (wrapped.systems.isNotEmpty) {
    final need = bracketMargin(wrapped.systems.first.layout);
    if (leftMargin < need) leftMargin = need;
  }
  final metadata = _firstMetadata(wrapped);
  final titleTop = showTitle ? _titleBlockHeight(metadata) : 0.0;
  final widthPx = (wrapped.maxWidth + leftMargin) * staffSpace;
  final musicBottom = titleTop + wrapped.heightWith(systemGap);
  final footer = showTitle
      ? _footer(null, metadata, staffSpace, widthPx, musicBottom, color,
          textFontFamily)
      : 0.0;
  final heightPx = (musicBottom + footer) * staffSpace;
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
  if (footer > 0) {
    _footer(
        b, metadata, staffSpace, widthPx, musicBottom, color, textFontFamily);
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

double _titleBlockHeight(ScoreMetadata metadata) =>
    titleBlockOf(metadata, left: 0, right: 0).height;

void _emitTitleLines(StringBuffer b, Iterable<TitleLine> lines,
    double staffSpace, double top, String color, String textFontFamily,
    {bool weights = true}) {
  for (final line in lines) {
    final anchor = switch (line.anchor) {
      TitleAnchor.start => 'start',
      TitleAnchor.middle => 'middle',
      TitleAnchor.end => 'end',
    };
    b.writeln('<text x="${_n(line.x * staffSpace)}" '
        'y="${_n((top + line.y) * staffSpace)}" '
        'font-family="$textFontFamily" '
        'font-size="${_n(line.size * staffSpace)}" '
        '${weights ? 'font-weight="${line.weight}" ' : ''}'
        'text-anchor="$anchor" fill="$color" '
        'stroke="none">${_escape(line.text)}</text>');
  }
}

/// Draws the title block (see [titleBlockOf]) at the top of the page.
void _emitTitleBlock(
  StringBuffer b,
  ScoreMetadata metadata,
  double staffSpace,
  double leftMargin,
  double maxWidth,
  String color,
  String textFontFamily,
) {
  final block =
      titleBlockOf(metadata, left: leftMargin, right: leftMargin + maxWidth);
  _emitTitleLines(b, block.lines, staffSpace, 0, color, textFontFamily);
}

/// The copyright line at the foot of the page, if [metadata] has one; returns
/// the height it takes (staff spaces).
double _footer(StringBuffer? b, ScoreMetadata metadata, double staffSpace,
    double pageWidth, double top, String color, String textFontFamily) {
  final footer = footerOf(metadata, centerX: pageWidth / 2 / staffSpace);
  if (b != null) {
    _emitTitleLines(b, footer.lines, staffSpace, top, color, textFontFamily,
        weights: false);
  }
  return footer.height;
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
    // Right of the label: the system's brackets and braces, then the staff.
    final x = (leftMargin - 1.0 - bracketMargin(layout)) * staffSpace;
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
