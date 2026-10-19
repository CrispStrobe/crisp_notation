/// Cutting the fonts an SVG document embeds down to the characters it uses.
library;

import 'dart:convert';

import '../layout/font_metrics.dart';
import '../pdf/font_subset.dart';

/// `url(data:<font type>;base64,<bytes>)` in an `@font-face` rule.
final _fontUri =
    RegExp(r'url\(data:((?:font|application)/[\w.+-]+);base64,([\w+/=]+)\)');

/// [svg] with every font it embeds as a base64 `data:` URI (the engraving
/// font of `fontFaceDataUri`, an `EmbeddedTextFont`) cut down to the glyphs
/// of the characters the document's text uses — so a self-contained SVG
/// carries a few kilobytes of Bravura rather than half a megabyte.
///
/// The characters are taken from the whole document outside the fonts,
/// which can only keep a few glyphs too many. A font that cannot be subset
/// (see [subsetFont]) is left as it is.
///
/// ⚠️ The fonts lose their shaping tables (`GSUB`, `GPOS`, `kern`): a
/// browser then sets each character as its own glyph, unkerned — as the
/// layout measured it ([FontMetrics.widthOf]).
String subsetSvgFonts(String svg) {
  final used = svg.replaceAll(_fontUri, '').runes.toSet();
  return svg.replaceAllMapped(_fontUri, (m) {
    final bytes = base64Decode(m[2]!);
    final FontMetrics metrics;
    try {
      metrics = FontMetrics.parse(bytes);
    } on FormatException {
      return m[0]!;
    } on RangeError {
      return m[0]!;
    }
    final glyphs = {for (final r in used) metrics.glyphIdOf(r)};
    final subset = subsetFont(bytes, glyphs);
    if (subset == null) return m[0]!;
    return 'url(data:${m[1]};base64,${base64Encode(subset)})';
  });
}
