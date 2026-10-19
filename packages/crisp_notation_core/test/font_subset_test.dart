import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:crisp_notation_core/src/pdf/font_subset.dart';
import 'package:test/test.dart';

import 'pdf_export_test.dart' show unicodeTrueType;

void main() {
  final bravura =
      File('../crisp_notation/assets/fonts/Bravura.otf').readAsBytesSync();
  final metrics = FontMetrics.parse(bravura);
  final used = {
    for (final c in [0xE050, 0xE0A4, 0xE262, 0xE083]) metrics.glyphIdOf(c),
  };

  group('a CFF font (Bravura)', () {
    final subset = subsetFont(bravura, used)!;

    test('shrinks to a fraction of the file', () {
      expect(subset.length, lessThan(bravura.length ~/ 4));
    });

    test('keeps glyph ids, the cmap and every advance width', () {
      final after = FontMetrics.parse(subset);
      expect(after.unitsPerEm, metrics.unitsPerEm);
      for (final c in [0xE050, 0xE0A4, 0xE262, 0xE083, 0xE1D5]) {
        final gid = metrics.glyphIdOf(c);
        expect(after.glyphIdOf(c), gid);
        expect(after.advanceOfGlyph(gid), metrics.advanceOfGlyph(gid));
      }
    });

    test('is the same bytes for the same glyphs', () {
      expect(subsetFont(bravura, {...used}), subset);
      expect(subsetTag(used), subsetTag(used.toList().reversed));
      expect(subsetTag(used), matches(RegExp(r'^[A-Z]{6}$')));
      expect(subsetTag(used), isNot(subsetTag({...used, 1})));
    });
  });

  final ttfPath = unicodeTrueType();
  test('a TrueType font keeps the glyphs drawn and their components', () {
    final ttf = File(ttfPath!).readAsBytesSync();
    final m = FontMetrics.parse(ttf);
    // Ǻ is a composite in DejaVu Sans (A, ring, acute).
    final gids = {for (final c in 'Ǻř'.runes) m.glyphIdOf(c)};
    final subset = subsetFont(ttf, gids)!;
    expect(subset.length, lessThan(ttf.length ~/ 4));
    final after = FontMetrics.parse(subset);
    for (final g in gids) {
      expect(after.advanceOfGlyph(g), m.advanceOfGlyph(g));
    }
  }, skip: ttfPath == null ? 'no DejaVuSans.ttf on this system' : null);

  test('a file that is no font is left to be embedded whole', () {
    expect(subsetFont(List.filled(64, 0), {1}), isNull);
  });

  test('an SVG keeps only the glyphs its text uses of each embedded font', () {
    final metadata = SmuflMetadata.fromJson(jsonDecode(
        File('../crisp_notation/assets/smufl/bravura_metadata.json')
            .readAsStringSync()) as Map<String, Object?>);
    final layout = const LayoutEngine().layout(
        Score.simple(notes: 'c4:q d4 e4 f4'),
        LayoutSettings(metadata: metadata));
    final uri = 'data:font/otf;base64,${base64Encode(bravura)}';
    final whole = scoreToSvg(layout, fontFaceDataUri: uri);
    final svg = subsetSvgFonts(whole);
    expect(svg.length, lessThan(whole.length ~/ 4));
    // Outside the font the document is unchanged.
    final font = RegExp(r'base64,([\w+/=]+)\)');
    expect(svg.replaceAll(font, ''), whole.replaceAll(font, ''));
    final embedded = FontMetrics.parse(base64Decode(font.firstMatch(svg)![1]!));
    final clef = 0xE050; // gClef, drawn on every staff
    expect(svg, contains(String.fromCharCode(clef)));
    expect(embedded.glyphIdOf(clef), metrics.glyphIdOf(clef));
    // Without an embedded font there is nothing to do.
    final plain = scoreToSvg(layout);
    expect(subsetSvgFonts(plain), plain);
  });
}
