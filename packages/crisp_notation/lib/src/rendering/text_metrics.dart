import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:flutter/painting.dart';

/// A [LayoutSettings.textWidth] measurer for [fontFamily] (null: the
/// platform's default face), so lyrics and annotations are spaced by the real
/// font the views draw with rather than the layout's estimate.
///
/// Width is linear in font size, so each string is measured once at a
/// reference size and cached; the measurer for a family is shared.
double Function(String text, double size) textWidthFor(String? fontFamily) =>
    _measurers.putIfAbsent(fontFamily ?? '', () {
      final widths = <String, double>{};
      return (String text, double size) {
        final perUnit = widths.putIfAbsent(text, () {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(fontFamily: fontFamily, fontSize: _reference),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final w = painter.width / _reference;
          painter.dispose();
          return w;
        });
        return perUnit * size;
      };
    });

const double _reference = 100;
final _measurers = <String, double Function(String, double)>{};
