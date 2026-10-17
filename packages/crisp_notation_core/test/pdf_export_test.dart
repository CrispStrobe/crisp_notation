import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

late final LayoutSettings settings;
late final List<int> bravura;

/// The decoded content streams of [pdf], one per page, in order.
List<String> contents(Uint8List pdf) {
  final text = latin1.decode(pdf);
  final out = <String>[];
  final stream = RegExp(r'/Length (\d+) /Filter /FlateDecode >>\nstream\n');
  for (final m in stream.allMatches(text)) {
    final length = int.parse(m[1]!);
    final body = pdf.sublist(m.end, m.end + length);
    final decoded = latin1.decode(zlib.decode(body), allowInvalid: true);
    if (decoded.contains(' Tf ') || decoded.contains(' m ')) out.add(decoded);
  }
  return out;
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

  test('timesTextWidth measures with Times-Roman\'s metrics', () {
    // Adobe's AFM: W is 944/1000 em, i 278/1000.
    expect(timesTextWidth('W', 2), closeTo(1.888, 1e-9));
    expect(timesTextWidth('Wi', 1), closeTo(1.222, 1e-9));
    // Narrower than the safe estimate the layout uses when the font is
    // unknown — what lets a PDF set lyrics tighter.
    expect(timesTextWidth('amour', 1.6),
        lessThan(2 * estimateTextHalfWidth('amour', 1.6)));
  });
}
