import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Reference values below were computed independently with `fontTools`
/// (`python3 -c "from fontTools.ttLib import TTFont; ..."`), reading the
/// same `head`/`hmtx`/`cmap`/`name` tables through a different library —
/// not by re-running this reader — so an agreement is a real cross-check.
void main() {
  group('FontMetrics (TrueType, DejaVu Sans)', () {
    const path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
    final file = File(path);
    final skip = file.existsSync() ? null : 'no $path on this system';

    late FontMetrics metrics;
    setUpAll(() {
      if (skip != null) return;
      metrics = FontMetrics.parse(file.readAsBytesSync());
    });

    test('unitsPerEm and family name', () {
      expect(metrics.unitsPerEm, 2048);
      expect(metrics.familyName, 'DejaVu Sans');
    }, skip: skip);

    test('widthOf matches an independently computed sum of advances', () {
      // fontTools: sum(hmtx[cmap[ord(c)]].advanceWidth for c in s) / unitsPerEm.
      expect(
          metrics.widthOf('Hello, World!', 1.0), closeTo(13303 / 2048, 1e-9));
      expect(metrics.widthOf('crisp_notation 1234', 1.0),
          closeTo(20323 / 2048, 1e-9));
    }, skip: skip);

    test('widthOf scales linearly with size', () {
      final unit = metrics.widthOf('crisp_notation', 1.0);
      expect(metrics.widthOf('crisp_notation', 10.0), closeTo(unit * 10, 1e-9));
      expect(metrics.widthOf('crisp_notation', 0.0), 0.0);
    }, skip: skip);

    test('an unmapped code point measures as glyph 0 (.notdef)', () {
      // U+10FFFF is not in any common Latin font's cmap.
      final notdef = metrics.advanceOfGlyph(0);
      expect(metrics.widthOf('\u{10FFFF}', 1.0), closeTo(notdef / 2048, 1e-9));
    }, skip: skip);

    test('textWidthFromFont returns a closure over the same metrics', () {
      final widthFn = textWidthFromFont(file.readAsBytesSync());
      expect(widthFn('Hello, World!', 1.0),
          closeTo(metrics.widthOf('Hello, World!', 1.0), 1e-9));
    }, skip: skip);

    test('usable as LayoutSettings.textWidth', () {
      final widthFn = textWidthFromFont(file.readAsBytesSync());
      expect(widthFn, isA<double Function(String, double)>());
    }, skip: skip);
  });

  group('FontMetrics (OpenType/CFF, Bravura)', () {
    // Bundled with the Flutter package; present in every checkout.
    const path = '../crisp_notation/assets/fonts/Bravura.otf';
    final file = File(path);
    final skip = file.existsSync() ? null : 'no $path beside this checkout';

    late FontMetrics metrics;
    setUpAll(() {
      if (skip != null) return;
      metrics = FontMetrics.parse(file.readAsBytesSync());
    });

    test('unitsPerEm and family name (OTTO sanity)', () {
      expect(metrics.unitsPerEm, 1000);
      expect(metrics.familyName, 'Bravura');
    }, skip: skip);

    test('cmap format 4 (BMP): space maps to a glyph with advance 100', () {
      // fontTools: cmap[0x20] -> 'space', hmtx['space'] == (100, 0).
      final gid = metrics.glyphIdOf(0x20);
      expect(gid, isNot(0));
      expect(metrics.advanceOfGlyph(gid), 100);
    }, skip: skip);

    test(
        'cmap format 12 (beyond the BMP): U+1D100 maps to a glyph with '
        'advance 37', () {
      // fontTools: cmap[0x1D100] -> 'u1D100', hmtx['u1D100'] == (37, 0) — in
      // Bravura's Musical Symbols block, only reachable via format 12.
      final gid = metrics.glyphIdOf(0x1D100);
      expect(gid, isNot(0));
      expect(metrics.advanceOfGlyph(gid), 37);
    }, skip: skip);

    test('an ASCII letter (absent from Bravura) falls back to glyph 0', () {
      // Bravura carries no Latin letters; 'A' must resolve to .notdef, not
      // throw or silently measure as 0 width from a missing entry.
      expect(metrics.glyphIdOf(0x41), 0);
      expect(metrics.widthOf('A', 1.0), metrics.advanceOfGlyph(0) / 1000);
    }, skip: skip);
  });

  group('FontMetrics.parse errors', () {
    test('rejects a file too short to be sfnt', () {
      expect(() => FontMetrics.parse(const [1, 2, 3]),
          throwsA(isA<FormatException>()));
    });

    test('rejects bytes with no recognized sfnt tag', () {
      final bytes = List<int>.filled(16, 0);
      expect(() => FontMetrics.parse(bytes), throwsA(isA<FormatException>()));
    });
  });
}
