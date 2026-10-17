/// Vector PDF of laid-out notation, in pure Dart: lines, beams and curves as
/// PDF paths, music glyphs from the embedded SMuFL font (OpenType/CFF), text
/// in the standard Times faces. Prints sharp at any size, unlike a PDF of
/// page images, and runs wherever the core does (server, CLI, web).
///
/// Text outside Latin-1 prints as `?`: the standard faces carry no more.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../interchange/deflate.dart';
import '../layout/multi_part.dart';
import '../layout/page_layout.dart';
import '../layout/score_layout.dart';
import '../layout/staff_system.dart';
import '../layout/title_block.dart';
import '../model/score.dart';
import '../smufl/smufl_codepoints.dart';

/// [layout] on one page sized to it, [margin] staff spaces around the ink.
///
/// [musicFont] is the SMuFL font file the glyphs come from (Bravura's
/// `.otf`, as the Flutter package bundles it); [pointsPerSpace] sets the
/// print size — 5 pt is a common staff (rastral size 3–4).
Uint8List scoreLayoutToPdf(
  ScoreLayout layout, {
  required List<int> musicFont,
  double pointsPerSpace = 5.0,
  double margin = 3.0,
}) {
  final page = _Page(
      layout.width + 2 * margin, layout.height + 2 * margin, pointsPerSpace);
  page.drawLayout(layout, margin, margin - layout.top);
  return _PdfWriter(musicFont).write([page]);
}

/// Every page of [paged], at [pointsPerSpace] points per staff space (its
/// [PageMetrics] are in staff spaces, so this also sets the paper size).
///
/// With [metadata], the first page carries its title block in the space the
/// layout kept free (`layoutPages(firstPageTop: titleBlockHeight(…))`) and
/// its copyright in the bottom margin.
Uint8List pagedLayoutToPdf(
  PagedLayout paged, {
  required List<int> musicFont,
  double pointsPerSpace = 5.0,
  ScoreMetadata? metadata,
}) {
  final m = paged.metrics;
  final pages = <_Page>[];
  for (final page in paged.pages) {
    final out = _Page(m.width, m.height, pointsPerSpace);
    if (pages.isEmpty && metadata != null) out.drawHeading(metadata, m);
    for (final positioned in page.systems) {
      final layout = positioned.system.layout;
      out.drawLayout(
          layout, m.marginLeft, m.marginTop + positioned.top - layout.top);
    }
    pages.add(out);
  }
  return _PdfWriter(musicFont).write(pages);
}

/// Lines of one staff — a line-broken score's systems, or chant from
/// `layoutChantLines` — packed top to bottom onto pages of [metrics] (in
/// staff spaces), [systemGap] staff spaces apart; with [metadata], the
/// first page opens with its title block and carries its copyright.
Uint8List scoreLinesToPdf(
  List<ScoreLayout> lines, {
  required List<int> musicFont,
  required PageMetrics metrics,
  double pointsPerSpace = 5.0,
  double systemGap = 4,
  ScoreMetadata? metadata,
}) {
  final m = metrics;
  final title = metadata == null ? 0.0 : titleBlockHeight(metadata);
  final pages = <_Page>[];
  _Page? page;
  var y = 0.0;
  for (final line in lines) {
    if (page == null || (y > 0 && y + line.height > m.contentHeight)) {
      page = _Page(m.width, m.height, pointsPerSpace);
      if (pages.isEmpty && metadata != null) page.drawHeading(metadata, m);
      y = pages.isEmpty ? title : 0;
      pages.add(page);
    }
    page.drawLayout(line, m.marginLeft, m.marginTop + y - line.top);
    y += line.height + systemGap;
  }
  if (pages.isEmpty) pages.add(_Page(m.width, m.height, pointsPerSpace));
  return _PdfWriter(musicFont).write(pages);
}

/// Every page of a multi-part [paged] score (from [layoutMultiPartPages]):
/// each system's staves with their systemic barlines, brackets and braces;
/// the instrument names before the first system and the bar number at the
/// start of every later one (unless [systemContext] is false); and, with
/// [metadata], the title block and copyright on the first page (see
/// [pagedLayoutToPdf]). Brackets and names hang in the left margin.
Uint8List multiPartPagesToPdf(
  MultiPartPagedLayout paged, {
  required List<int> musicFont,
  double pointsPerSpace = 5.0,
  ScoreMetadata? metadata,
  bool systemContext = true,
}) {
  final m = paged.metrics;
  final pages = <_Page>[];
  var first = true;
  for (final page in paged.pages) {
    final out = _Page(m.width, m.height, pointsPerSpace);
    if (pages.isEmpty && metadata != null) out.drawHeading(metadata, m);
    for (final positioned in page.systems) {
      final system = positioned.system;
      final y = m.marginTop + positioned.top - system.layout.top;
      out.drawStaffSystem(system.layout, m.marginLeft, y);
      if (systemContext) {
        if (first) {
          out.drawInstrumentNames(system.layout, m.marginLeft, y);
        } else {
          out.text('${system.firstMeasure + 1}', m.marginLeft + 0.5,
              y + system.layout.staffTop(0) - 1.0, 0.9,
              anchor: TitleAnchor.start);
        }
      }
      first = false;
    }
    pages.add(out);
  }
  return _PdfWriter(musicFont).write(pages);
}

/// One page's drawing, collected as PDF content operators. Callers work in
/// staff spaces from the page's top-left, y down; [k] points per staff space.
class _Page {
  final double width, height, k;
  final _ops = StringBuffer();
  _Page(double width, double height, this.k)
      : width = width * k,
        height = height * k;

  String _n(double v) => v.toStringAsFixed(3);
  String _x(double x) => _n(x * k);
  String _y(double y) => _n(height - y * k);

  void line(double x1, double y1, double x2, double y2, double thickness,
      {bool round = false}) {
    _ops.writeln('${_n(thickness * k)} w ${round ? 1 : 0} J '
        '${_x(x1)} ${_y(y1)} m ${_x(x2)} ${_y(y2)} l S');
  }

  /// SMuFL glyph [name] with its origin at ([x], [y]), [em] staff spaces.
  void glyph(String name, double x, double y, double em) {
    final char = smuflCodepoints[name];
    if (char == null) return;
    _ops.writeln('BT /M ${_n(em * k)} Tf 1 0 0 1 ${_x(x)} ${_y(y)} Tm '
        '<${_gidPlaceholder(char.runes.first)}> Tj ET');
  }

  /// [s] with its baseline at [y], anchored at [x] as [anchor] says.
  void text(String s, double x, double y, double size,
      {TitleAnchor anchor = TitleAnchor.middle,
      bool bold = false,
      bool italic = false}) {
    final font = bold ? (italic ? 'TBI' : 'TB') : (italic ? 'TI' : 'TR');
    final w = _timesWidth(s) * size;
    final left = switch (anchor) {
      TitleAnchor.start => x,
      TitleAnchor.middle => x - w / 2,
      TitleAnchor.end => x - w,
    };
    _ops.writeln('BT /$font ${_n(size * k)} Tf 1 0 0 1 '
        '${_x(left)} ${_y(y)} Tm (${_pdfText(s)}) Tj ET');
  }

  /// [layout] with its origin (top staff line, left edge) at ([dx], [dy]).
  void drawLayout(ScoreLayout layout, double dx, double dy) {
    for (final p in layout.primitives) {
      switch (p) {
        case LinePrimitive(
            :final from,
            :final to,
            :final thickness,
            :final round
          ):
          line(dx + from.x, dy + from.y, dx + to.x, dy + to.y, thickness,
              round: round);
        case BeamPrimitive(:final start, :final end, :final thickness):
          final h = thickness / 2;
          _ops.writeln('${_x(dx + start.x)} ${_y(dy + start.y - h)} m '
              '${_x(dx + end.x)} ${_y(dy + end.y - h)} l '
              '${_x(dx + end.x)} ${_y(dy + end.y + h)} l '
              '${_x(dx + start.x)} ${_y(dy + start.y + h)} l h f');
        case CurvePrimitive(
            :final start,
            :final control1,
            :final control2,
            :final end,
            :final thickness
          ):
          _ops.writeln('${_n(thickness * k)} w 1 J '
              '${_x(dx + start.x)} ${_y(dy + start.y)} m '
              '${_x(dx + control1.x)} ${_y(dy + control1.y)} '
              '${_x(dx + control2.x)} ${_y(dy + control2.y)} '
              '${_x(dx + end.x)} ${_y(dy + end.y)} c S');
        case GlyphPrimitive(:final smuflName, :final position, :final scale):
          // A glyph's em is four staff spaces.
          glyph(smuflName, dx + position.x, dy + position.y, 4 * scale);
        case TextPrimitive(
            :final text,
            :final position,
            :final size,
            :final italic,
            :final bold
          ):
          this.text(text, dx + position.x, dy + position.y, size,
              bold: bold, italic: italic);
      }
    }
  }

  /// A multi-staff system with its first staff's top line at y = [dy] +
  /// staffTop(0): the staves, the barlines joining each barline group, the
  /// opening line through every staff, and the brackets and braces (as the
  /// SVG export draws them).
  void drawStaffSystem(StaffSystemLayout layout, double dx, double dy) {
    for (var i = 0; i < layout.staves.length; i++) {
      drawLayout(layout.staves[i], dx, dy + layout.staffTop(i));
    }
    for (final x in layout.barlineXs) {
      for (final span in layout.barlineSpans) {
        line(dx + x, dy + span.top, dx + x, dy + span.bottom, 0.16);
      }
    }
    final staves = layout.staves.length;
    if (staves > 1) {
      line(dx, dy + layout.staffTop(0), dx,
          dy + layout.staffTop(staves - 1) + 4, 0.16);
    }
    final brackets = layout.source.brackets;
    int depthOf(StaffBracket x) => brackets
        .where((a) =>
            !identical(a, x) &&
            a.first <= x.first &&
            x.last <= a.last &&
            (a.last - a.first) > (x.last - x.first))
        .length;
    final maxDepth = brackets.map(depthOf).fold(0, (m, d) => d > m ? d : m);
    for (final group in brackets) {
      if (group.last >= staves) continue;
      final shift = (maxDepth - depthOf(group)) * 0.6;
      final top = dy + layout.staffTop(group.first);
      final bottom = dy + layout.staffTop(group.last) + 4;
      if (group.kind == StaffBracketKind.brace) {
        // The brace glyph is one em tall: an em of the group's height.
        glyph('brace', dx - 1.8 + 0.35 - shift, bottom, bottom - top);
      } else {
        final x = dx - 0.5 - shift;
        line(x, top, x, bottom, 0.4);
        for (final y in [top, bottom]) {
          line(x, y, x + 0.6, y, 0.16);
        }
      }
    }
  }

  /// Each run of staves sharing an instrument name, named left of the
  /// system's brackets, centred on the run.
  void drawInstrumentNames(StaffSystemLayout layout, double dx, double dy) {
    final staves = layout.source.staves;
    final margin = layout.source.brackets.isEmpty ? 0 : 1.8;
    var start = 0;
    while (start < staves.length) {
      final label = staves[start].metadata.instrument;
      if (label == null || label.trim().isEmpty) {
        start++;
        continue;
      }
      var end = start;
      while (end + 1 < staves.length &&
          staves[end + 1].metadata.instrument == label) {
        end++;
      }
      final middle =
          dy + (layout.staffTop(start) + layout.staffTop(end) + 4) / 2;
      text(label.trim(), dx - 1.0 - margin, middle + 0.35 * 1.1, 1.1,
          anchor: TitleAnchor.end);
      start = end + 1;
    }
  }

  /// [metadata]'s title block at the top of the content box (where the
  /// layout kept room for it) and its copyright in the bottom margin.
  void drawHeading(ScoreMetadata metadata, PageMetrics m) {
    final block = titleBlockOf(metadata,
        left: m.marginLeft, right: m.width - m.marginRight);
    for (final l in block.lines) {
      text(l.text, l.x, m.marginTop + l.y, l.size,
          anchor: l.anchor, bold: l.weight >= 600);
    }
    final footer = footerOf(metadata, centerX: m.width / 2);
    for (final l in footer.lines) {
      text(l.text, l.x, m.height - m.marginBottom + l.y, l.size);
    }
  }
}

/// A placeholder resolved to the glyph id once the font's cmap is read.
String _gidPlaceholder(int code) => '@${code.toRadixString(16)}@';

/// Text for a WinAnsi-encoded standard font: Latin-1 as is, anything else
/// as `?`, with the string delimiters escaped.
String _pdfText(String text) {
  final b = StringBuffer();
  for (final r in text.runes) {
    final c = r < 256 ? String.fromCharCode(r) : '?';
    if (c == '(' || c == ')' || c == r'\') b.write(r'\');
    b.write(c);
  }
  return b.toString();
}

/// The width of [text] set in Times-Roman at [size] (Adobe's metrics), in
/// the same units as [size] — the face this writer prints text in. Pass it
/// as [LayoutSettings.textWidth] when laying out for PDF (or for an SVG set
/// in a Times-like serif), so lyrics and markings are spaced for the font
/// actually drawn rather than for the widest common one.
double timesTextWidth(String text, double size) => _timesWidth(text) * size;

/// Width of [text] in em for Times-Roman (Adobe's metrics), to centre text
/// as the layout anchors it; other faces are close enough for that.
double _timesWidth(String text) {
  var w = 0;
  for (final r in text.runes) {
    w += (r >= 32 && r < 127) ? _times[r - 32] : 500;
  }
  return w / 1000;
}

const _times = [
  250, 333, 408, 500, 500, 833, 778, 333, 333, 333, 500, 564, 250, 333, 250, //
  278, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 278, 278, 564, 564,
  564, 444, 921, 722, 667, 667, 722, 611, 556, 722, 722, 333, 389, 722, 611,
  889, 722, 722, 556, 722, 667, 556, 611, 722, 722, 944, 722, 722, 611, 333,
  278, 333, 469, 500, 333, 444, 500, 444, 500, 444, 333, 500, 500, 278, 278,
  500, 278, 778, 500, 500, 500, 500, 333, 389, 278, 500, 500, 722, 500, 500,
  444, 480, 200, 480, 541,
];

/// Writes the document: pages, the embedded music font (Type0 over a
/// CIDFontType0 with the OpenType file, Identity-H, glyph ids from the
/// font's cmap) and the four standard Times faces.
class _PdfWriter {
  final List<int> font;
  _PdfWriter(this.font);

  final _objects = <List<int>>[];

  int _add(List<int> bytes) {
    _objects.add(bytes);
    return _objects.length; // 1-based object number
  }

  List<int> _ascii(String s) => latin1.encode(s);

  int _stream(String dict, List<int> data, {bool compress = true}) {
    final body = compress ? _zlib(data) : data;
    final head = '<< $dict /Length ${body.length}'
        '${compress ? ' /Filter /FlateDecode' : ''} >>\nstream\n';
    return _add([..._ascii(head), ...body, ..._ascii('\nendstream')]);
  }

  Uint8List write(List<_Page> pages) {
    final cmap = _readCmap(font);
    // Fonts.
    final fontFile = _stream('/Subtype /OpenType', font);
    final descriptor = _add(_ascii('<< /Type /FontDescriptor /FontName '
        '/Bravura /Flags 4 /FontBBox [-1000 -2000 3000 2000] '
        '/ItalicAngle 0 /Ascent 1000 /Descent -1000 /CapHeight 1000 '
        '/StemV 80 /FontFile3 $fontFile 0 R >>'));
    final cid = _add(_ascii('<< /Type /Font /Subtype /CIDFontType0 '
        '/BaseFont /Bravura /CIDSystemInfo << /Registry (Adobe) '
        '/Ordering (Identity) /Supplement 0 >> /FontDescriptor '
        '$descriptor 0 R /DW 1000 >>'));
    final music = _add(_ascii('<< /Type /Font /Subtype /Type0 /BaseFont '
        '/Bravura /Encoding /Identity-H /DescendantFonts [$cid 0 R] >>'));
    int std(String name) => _add(_ascii('<< /Type /Font /Subtype /Type1 '
        '/BaseFont /$name /Encoding /WinAnsiEncoding >>'));
    final fonts = '/M $music 0 R /TR ${std('Times-Roman')} 0 R '
        '/TI ${std('Times-Italic')} 0 R /TB ${std('Times-Bold')} 0 R '
        '/TBI ${std('Times-BoldItalic')} 0 R';

    // Pages: the page tree's number is known before its kids are written.
    final pagesNumber = _objects.length + 1 + 2 * pages.length;
    final kids = <int>[];
    for (final page in pages) {
      var ops = page._ops.toString();
      ops = ops.replaceAllMapped(RegExp(r'@([0-9a-f]+)@'), (m) {
        final gid = cmap[int.parse(m[1]!, radix: 16)] ?? 0;
        return gid.toRadixString(16).padLeft(4, '0');
      });
      final content = _stream('', _ascii(ops));
      kids.add(_add(_ascii('<< /Type /Page /Parent $pagesNumber 0 R '
          '/MediaBox [0 0 ${page.width.toStringAsFixed(2)} '
          '${page.height.toStringAsFixed(2)}] /Resources << /Font << $fonts '
          '>> >> /Contents $content 0 R >>')));
    }
    final tree = _add(_ascii('<< /Type /Pages /Kids '
        '[${kids.map((k) => '$k 0 R').join(' ')}] /Count ${kids.length} >>'));
    assert(tree == pagesNumber);
    final catalog = _add(_ascii('<< /Type /Catalog /Pages $tree 0 R >>'));

    final out = BytesBuilder();
    out.add(_ascii('%PDF-1.7\n%\xe2\xe3\xcf\xd3\n'));
    final offsets = <int>[];
    for (var i = 0; i < _objects.length; i++) {
      offsets.add(out.length);
      out
        ..add(_ascii('${i + 1} 0 obj\n'))
        ..add(_objects[i])
        ..add(_ascii('\nendobj\n'));
    }
    final xref = out.length;
    out.add(_ascii('xref\n0 ${_objects.length + 1}\n0000000000 65535 f \n'));
    for (final o in offsets) {
      out.add(_ascii('${o.toString().padLeft(10, '0')} 00000 n \n'));
    }
    out.add(_ascii('trailer\n<< /Size ${_objects.length + 1} /Root '
        '$catalog 0 R >>\nstartxref\n$xref\n%%EOF\n'));
    return out.toBytes();
  }
}

/// zlib-wrapped DEFLATE (PDF's FlateDecode): header, raw stream, Adler-32.
List<int> _zlib(List<int> data) {
  var a = 1, b = 0;
  for (final byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  final adler = (b << 16) | a;
  return [
    0x78, 0x01, //
    ...deflate(Uint8List.fromList(data)),
    (adler >> 24) & 0xff, (adler >> 16) & 0xff, (adler >> 8) & 0xff,
    adler & 0xff,
  ];
}

/// The font's Unicode → glyph id map, from its `cmap` table (format 4, BMP —
/// SMuFL's code points are all in the private-use area there).
Map<int, int> _readCmap(List<int> font) {
  final d = ByteData.sublistView(Uint8List.fromList(font));
  int u16(int o) => d.getUint16(o);
  int i16(int o) => d.getInt16(o);
  int u32(int o) => d.getUint32(o);
  final tables = u16(4);
  int? cmapAt;
  for (var i = 0; i < tables; i++) {
    final rec = 12 + 16 * i;
    if (String.fromCharCodes(font.sublist(rec, rec + 4)) == 'cmap') {
      cmapAt = u32(rec + 8);
    }
  }
  final out = <int, int>{};
  if (cmapAt == null) return out;
  final subtables = u16(cmapAt + 2);
  int? sub;
  for (var i = 0; i < subtables; i++) {
    final rec = cmapAt + 4 + 8 * i;
    final platform = u16(rec), encoding = u16(rec + 2);
    final at = cmapAt + u32(rec + 4);
    if (u16(at) == 4 && ((platform == 3 && encoding == 1) || platform == 0)) {
      sub = at;
      if (platform == 3) break;
    }
  }
  if (sub == null) return out;
  final segX2 = u16(sub + 6);
  final ends = sub + 14;
  final starts = ends + segX2 + 2;
  final deltas = starts + segX2;
  final ranges = deltas + segX2;
  for (var s = 0; s < segX2 ~/ 2; s++) {
    final end = u16(ends + 2 * s), start = u16(starts + 2 * s);
    final delta = i16(deltas + 2 * s);
    final rangeOffsetAt = ranges + 2 * s;
    final rangeOffset = u16(rangeOffsetAt);
    for (var c = start; c <= end && c != 0xffff; c++) {
      int gid;
      if (rangeOffset == 0) {
        gid = (c + delta) & 0xffff;
      } else {
        final at = rangeOffsetAt + rangeOffset + 2 * (c - start);
        gid = u16(at);
        if (gid != 0) gid = (gid + delta) & 0xffff;
      }
      if (gid != 0) out[c] = gid;
    }
  }
  return out;
}
