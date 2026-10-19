import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

late final LayoutSettings settings;
late final List<int> bravura;

/// The decoded content streams of [pdf], one per page, in order — those
/// with no dictionary entries but their length and filter, so never an
/// embedded font file, however its bytes happen to read.
List<String> contents(Uint8List pdf) {
  final text = latin1.decode(pdf);
  final out = <String>[];
  final stream = RegExp(r'<<  /Length (\d+) /Filter /FlateDecode >>\nstream\n');
  for (final m in stream.allMatches(text)) {
    final length = int.parse(m[1]!);
    final body = pdf.sublist(m.end, m.end + length);
    final decoded = latin1.decode(zlib.decode(body), allowInvalid: true);
    if (decoded.contains(' Tf ') || decoded.contains(' m ')) out.add(decoded);
  }
  return out;
}

/// Every stream of [pdf], decompressed — fonts and CMaps as well as page
/// contents — keyed by the number of the object holding it.
Map<int, List<int>> streams(Uint8List pdf) {
  final text = latin1.decode(pdf);
  final out = <int, List<int>>{};
  final stream = RegExp(r'(\d+) 0 obj\n<<[^\n]*?/Length (\d+) '
      r'/Filter /FlateDecode >>\nstream\n');
  for (final m in stream.allMatches(text)) {
    final length = int.parse(m[2]!);
    out[int.parse(m[1]!)] = zlib.decode(pdf.sublist(m.end, m.end + length));
  }
  return out;
}

/// A Unicode TrueType font on this system — DejaVu Sans where Debian-like
/// systems put it, else whatever `fc-list` knows by that name — or null.
String? unicodeTrueType() {
  const known = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
  if (File(known).existsSync()) return known;
  try {
    final listed = Process.runSync('fc-list', [':', 'file']).stdout as String;
    for (final line in const LineSplitter().convert(listed)) {
      final path = line.split(':').first.trim();
      if (path.endsWith('/DejaVuSans.ttf') && File(path).existsSync()) {
        return path;
      }
    }
  } on ProcessException {
    // No fontconfig: no font to test with.
  }
  return null;
}

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    settings = LayoutSettings(
        metadata:
            SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>));
    bravura =
        File('../crisp_notation/assets/fonts/Bravura.otf').readAsBytesSync();
  });

  test('a single layout is a well-formed one-page PDF', () {
    final layout = const LayoutEngine()
        .layout(Score.simple(notes: 'c4:q d4 e4 f4'), settings);
    final pdf = scoreLayoutToPdf(layout, musicFont: bravura);
    final text = latin1.decode(pdf);
    expect(text, startsWith('%PDF-1.7'));
    expect(text.trimRight(), endsWith('%%EOF'));
    expect(text, contains('/Count 1'));
    expect(text, contains('/Subtype /OpenType'));
    expect(text, contains('/Encoding /Identity-H'));

    // The xref offsets point at the objects they name.
    final xrefAt = int.parse(RegExp(r'startxref\n(\d+)').firstMatch(text)![1]!);
    final table = text.substring(xrefAt).split('\n');
    final count = int.parse(table[1].split(' ')[1]);
    for (var i = 1; i < count; i++) {
      final offset = int.parse(table[2 + i].substring(0, 10));
      expect(text.substring(offset), startsWith('$i 0 obj'));
    }
  });

  test('music glyphs are drawn by glyph id, never the zero glyph', () {
    final layout = const LayoutEngine()
        .layout(Score.simple(notes: 'c4:q d4 e4 f4'), settings);
    final ops = contents(scoreLayoutToPdf(layout, musicFont: bravura)).single;
    final glyphs = RegExp(r'/M [\d.]+ Tf .*?<([0-9a-f]{4})> Tj')
        .allMatches(ops)
        .map((m) => m[1]!)
        .toList();
    final drawn = layout.primitives.whereType<GlyphPrimitive>().length;
    expect(glyphs, hasLength(drawn));
    expect(glyphs, isNot(contains('0000')));
    expect(ops, isNot(contains('@'))); // every placeholder resolved
    // Staff lines and stems are stroked paths.
    expect(RegExp(r' l S').allMatches(ops).length, greaterThan(5));
  });

  test('the music font is embedded as a tagged subset', () {
    final layout = const LayoutEngine()
        .layout(Score.simple(notes: 'c4:q d4 e4 f4'), settings);
    final pdf = scoreLayoutToPdf(layout, musicFont: bravura);
    final text = latin1.decode(pdf);
    expect(text, matches(RegExp(r'/FontName /[A-Z]{6}\+Bravura ')));
    // Bravura is half a megabyte; a page of notes needs a few glyphs of it.
    expect(pdf.length, lessThan(bravura.length ~/ 4));
  });

  test('text is centred, escaped and styled', () {
    final layout = ScoreLayout(
      width: 20,
      height: 8,
      top: -2,
      primitives: const [
        TextPrimitive('Allegro (a)', Point(10, 0), size: 1.5, bold: true),
        TextPrimitive('dolce', Point(10, 4), size: 1.5, italic: true),
      ],
      regions: const [],
      measureRegions: const [],
    );
    final ops = contents(scoreLayoutToPdf(layout, musicFont: bravura)).single;
    expect(ops, contains(r'/TB 7.500 Tf'));
    expect(ops, contains(r'(Allegro \(a\)) Tj'));
    expect(ops, contains('/TI 7.500 Tf'));
  });

  test('a paged layout gives one PDF page per page', () {
    final score =
        Score.simple(notes: List.filled(24, 'c4:q d4 e4 f4').join(' | '));
    const metrics = PageMetrics(width: 40, height: 30);
    final paged = layoutPages(score, settings, metrics: metrics);
    expect(paged.pages.length, greaterThan(1));
    final pdf = pagedLayoutToPdf(paged, musicFont: bravura);
    expect(latin1.decode(pdf), contains('/Count ${paged.pages.length}'));
    expect(contents(pdf), hasLength(paged.pages.length));
    expect(latin1.decode(pdf), contains('/MediaBox [0 0 200.00 150.00]'));
  });

  test('the first page carries the title block, in room the layout kept', () {
    const metadata = ScoreMetadata(
        title: 'Lied', composer: 'F. Schubert', copyright: '(c) 2026');
    final score = Score.simple(
        notes: List.filled(8, 'c4:q d4 e4 f4').join(' | '), metadata: metadata);
    const metrics = PageMetrics(width: 119, height: 168);
    final top = titleBlockHeight(metadata);
    expect(top, greaterThan(3));
    final paged =
        layoutPages(score, settings, metrics: metrics, firstPageTop: top);
    expect(paged.pages.first.systems.first.top, top);
    final ops = contents(
            pagedLayoutToPdf(paged, musicFont: bravura, metadata: metadata))
        .first;
    expect(ops, contains('(Lied) Tj'));
    expect(ops, contains('(F. Schubert) Tj'));
    expect(ops, contains(r'(\(c\) 2026) Tj'));
  });

  test('a multi-part score prints braces, joined barlines and names', () {
    final piano = MultiPartScore([
      Score.simple(
          notes: 'c5:w | d5:w | e5:w',
          metadata: const ScoreMetadata(instrument: 'Piano')),
      Score.simple(
          clef: Clef.bass,
          notes: 'c3:w | d3:w | e3:w',
          metadata: const ScoreMetadata(instrument: 'Piano')),
    ], brackets: const [
      StaffBracket(0, 1, kind: StaffBracketKind.brace)
    ]);
    const metrics = PageMetrics(width: 119, height: 168, marginLeft: 14);
    final paged = layoutMultiPartPages(piano, settings, metrics: metrics);
    final pdf = multiPartPagesToPdf(paged, musicFont: bravura);
    final ops = contents(pdf).single;
    expect(ops, contains('(Piano) Tj'));
    // Two staves' worth of glyphs plus the brace.
    final layout = paged.pages.single.systems.single.system.layout;
    final glyphs = layout.staves
        .expand((s) => s.primitives)
        .whereType<GlyphPrimitive>()
        .length;
    expect(RegExp(r'/M [\d.]+ Tf').allMatches(ops).length, glyphs + 1);
  });

  // MuseScore writes `<part-name>Singstimme\nVoice</part-name>`: set on one
  // line the break printed as a missing-glyph box between the words.
  test('a line-broken instrument name prints as stacked lines', () {
    final voice = MultiPartScore([
      Score.simple(
          notes: 'c5:w | d5:w',
          metadata: const ScoreMetadata(instrument: 'Singstimme\nVoice')),
      Score.simple(
          clef: Clef.bass,
          notes: 'c3:w | d3:w',
          metadata: const ScoreMetadata(instrument: 'Piano')),
    ]);
    const metrics = PageMetrics(width: 119, height: 168, marginLeft: 20);
    final paged = layoutMultiPartPages(voice, settings, metrics: metrics);
    final ops = contents(multiPartPagesToPdf(paged, musicFont: bravura)).single;
    expect(ops, contains('(Singstimme) Tj'));
    expect(ops, contains('(Voice) Tj'));
    expect(ops, isNot(contains('Singstimme\n')));
    double baselineOf(String word) => double.parse(
        RegExp(r'([\d.]+) Tm\s*\(' + word + r'\) Tj').firstMatch(ops)![1]!);
    // PDF y grows upwards: the first line sits above the second.
    expect(baselineOf('Singstimme'), greaterThan(baselineOf('Voice')));
  });

  test('timesTextWidth measures with Times-Roman\'s metrics', () {
    // Adobe's AFM: W is 944/1000 em, i 278/1000.
    expect(timesTextWidth('W', 2), closeTo(1.888, 1e-9));
    expect(timesTextWidth('Wi', 1), closeTo(1.222, 1e-9));
    // Narrower than the safe estimate the layout uses when the font is
    // unknown — what lets a PDF set lyrics tighter.
    expect(timesTextWidth('amour', 1.6),
        lessThan(2 * estimateTextHalfWidth('amour', 1.6)));
  });

  group('an embedded text font', () {
    final ttfPath = unicodeTrueType();
    final skip = ttfPath == null ? 'no DejaVuSans.ttf on this system' : null;
    late List<int> ttf;
    late FontMetrics metrics;
    setUpAll(() {
      if (ttfPath == null) return;
      ttf = File(ttfPath).readAsBytesSync();
      metrics = FontMetrics.parse(ttf);
    });

    const title = 'Dvořák – Życzenie';
    String gids(String s) => [
          for (final r in s.runes)
            metrics.glyphIdOf(r).toRadixString(16).padLeft(4, '0')
        ].join();

    ScoreLayout textLayout() => ScoreLayout(
          width: 30,
          height: 8,
          top: -2,
          primitives: const [
            TextPrimitive(title, Point(15, 0), size: 1.5, bold: true),
            TextPrimitive('Ślą (się)', Point(15, 4), size: 1.5),
          ],
          regions: const [],
          measureRegions: const [],
        );

    test('is embedded as a Type0 CIDFontType2 with widths and ToUnicode', () {
      final pdf = scoreLayoutToPdf(textLayout(),
          musicFont: bravura, textFont: PdfTextFont(ttf));
      final text = latin1.decode(pdf);
      final tag = RegExp(r'/Subtype /Type0 /BaseFont /([A-Z]{6})\+DejaVuSans ')
          .firstMatch(text)![1];
      expect(
          text, contains('/Subtype /CIDFontType2 /BaseFont /$tag+DejaVuSans'));
      expect(text, contains('/CIDToGIDMap /Identity'));
      expect(text, contains('/FontFile2 '));
      expect(text, contains('/ToUnicode '));
      expect(text, isNot(contains('/Times-Roman')));
      // No bold file given: TB is the regular face, one font for both.
      final tr = RegExp(r'/TR (\d+) 0 R').firstMatch(text)![1];
      final tb = RegExp(r'/TB (\d+) 0 R').firstMatch(text)![1];
      expect(tb, tr);
      expect(RegExp(r'/Subtype /CIDFontType2').allMatches(text), hasLength(1));
      // The used glyphs' widths, in thousandths of an em.
      final r = metrics.glyphIdOf('ř'.runes.single);
      final w = (metrics.advanceOfGlyph(r) * 1000 / metrics.unitsPerEm).round();
      expect(text, contains('$r [$w]'));
      // A subset is embedded: its /Length1 is the file's, far below the
      // whole font's, and it still draws the used glyph with its width.
      final length1 =
          int.parse(RegExp(r'/Length1 (\d+) ').firstMatch(text)![1]!);
      expect(length1, lessThan(ttf.length ~/ 4));
      final file = streams(pdf).values.singleWhere((s) => s.length == length1);
      final subset = FontMetrics.parse(file);
      expect(subset.glyphIdOf('ř'.runes.single), r);
      expect(subset.advanceOfGlyph(r), metrics.advanceOfGlyph(r));
    }, skip: skip);

    test('writes text as glyph ids, never substituting ?', () {
      final pdf = scoreLayoutToPdf(textLayout(),
          musicFont: bravura, textFont: PdfTextFont(ttf));
      final ops = contents(pdf).single;
      expect(ops, contains('<${gids(title)}> Tj'));
      expect(ops, contains('<${gids('Ślą (się)')}> Tj'));
      // Every glyph is in the font: no .notdef, no literal strings, no `?`.
      final shown = RegExp(r'/T(?:R|B) [\d.]+ Tf .*?<([0-9a-f]+)> Tj')
          .allMatches(ops)
          .map((m) => m[1]!)
          .toList();
      expect(shown, hasLength(2));
      for (final hex in shown) {
        for (var i = 0; i < hex.length; i += 4) {
          expect(hex.substring(i, i + 4), isNot('0000'));
        }
      }
      expect(ops, isNot(contains(') Tj')));
      expect(ops, isNot(contains('?')));
    }, skip: skip);

    test('centres text with the font\'s own widths', () {
      final pdf = scoreLayoutToPdf(textLayout(),
          musicFont: bravura, textFont: PdfTextFont(ttf), margin: 0);
      final ops = contents(pdf).single;
      // pointsPerSpace 5: the anchor at x = 15 staff spaces.
      final left = (15 - metrics.widthOf(title, 1.5) / 2) * 5;
      expect(ops, contains('Tf 1 0 0 1 ${left.toStringAsFixed(3)} '));
      expect(
          PdfTextFont(ttf).textWidth(title, 1.5), metrics.widthOf(title, 1.5));
    }, skip: skip);

    test('maps every glyph used back to its character (ToUnicode)', () {
      final pdf = scoreLayoutToPdf(textLayout(),
          musicFont: bravura, textFont: PdfTextFont(ttf));
      final cmap = streams(pdf)
          .values
          .map((s) => latin1.decode(s, allowInvalid: true))
          .singleWhere((s) => s.contains('beginbfchar'));
      String hex(int v) => v.toRadixString(16).padLeft(4, '0').toUpperCase();
      for (final c in '$titleŚlą (się)'.runes) {
        expect(cmap, contains('<${hex(metrics.glyphIdOf(c))}> <${hex(c)}>'));
      }
    }, skip: skip);

    test('carries a paged score\'s title block and lyrics', () {
      final font = PdfTextFont(ttf);
      final wide = LayoutSettings(
          metadata: settings.metadata, textWidth: font.textWidth);
      const metadata = ScoreMetadata(title: title, copyright: '© Łódź');
      final score = Score.simple(
          notes: 'c4:q d4 e4 f4', lyrics: 'Żół- ty ко- нь', metadata: metadata);
      const metrics = PageMetrics(width: 119, height: 168);
      final paged = layoutPages(score, wide,
          metrics: metrics, firstPageTop: titleBlockHeight(metadata));
      final pdf = pagedLayoutToPdf(paged,
          musicFont: bravura, metadata: metadata, textFont: font);
      final ops = contents(pdf).single;
      expect(ops, contains('<${gids(title)}> Tj'));
      expect(ops, contains('<${gids('© Łódź')}> Tj'));
      expect(ops, contains('<${gids('ко')}> Tj'));
      expect(ops, isNot(contains('?')));

      // Where poppler is installed, it reads the text back as Unicode.
      final dir = Directory.systemTemp.createTempSync('pdf_text_font');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/song.pdf')..writeAsBytesSync(pdf);
      final ProcessResult extracted;
      try {
        extracted = Process.runSync('pdftotext', [file.path, '-'],
            stdoutEncoding: utf8);
      } on ProcessException {
        return;
      }
      expect(extracted.exitCode, 0);
      expect(extracted.stdout, contains(title));
      expect(extracted.stdout, contains('© Łódź'));
      expect(extracted.stdout, contains('ко'));
    }, skip: skip);

    test('an OpenType/CFF font is embedded as FontFile3', () {
      const otf = '/usr/share/texmf/fonts/opentype/public/tex-gyre/'
          'texgyrepagella-regular.otf';
      if (!File(otf).existsSync()) {
        markTestSkipped('no $otf on this system');
        return;
      }
      final pdf = scoreLayoutToPdf(textLayout(),
          musicFont: bravura,
          textFont: PdfTextFont(File(otf).readAsBytesSync(), bold: ttf));
      final text = latin1.decode(pdf);
      expect(
          text,
          matches(RegExp('/Subtype /CIDFontType0 /BaseFont '
              r'/[A-Z]{6}\+TeXGyrePagella-Regular')));
      // The bold face is its own font, here the TrueType one.
      expect(
          text,
          matches(RegExp(
              r'/Subtype /CIDFontType2 /BaseFont /[A-Z]{6}\+DejaVuSans')));
      expect(RegExp(r'/FontFile3 ').allMatches(text), hasLength(2));
      expect(contents(pdf).single, isNot(contains('?')));
    }, skip: skip);

    test('the standard faces are untouched without one', () {
      final pdf = scoreLayoutToPdf(textLayout(), musicFont: bravura);
      final text = latin1.decode(pdf);
      expect(
          text, contains('/BaseFont /Times-Bold /Encoding /WinAnsiEncoding'));
      expect(text, isNot(contains('/ToUnicode')));
      // Past Latin-1, Times has no glyph: ř, – and Ż print as `?`.
      expect(contents(pdf).single, contains('(Dvo?\xe1k ? ?yczenie) Tj'));
    });
  });
}
