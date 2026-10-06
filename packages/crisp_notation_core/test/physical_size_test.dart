import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Physical staff and paper sizes: staff spaces ↔ millimetres.
void main() {
  test('a spatium converts between millimetres and staff spaces', () {
    const s = Spatium(1.75);
    expect(s.staffHeight, 7.0);
    expect(s.toSpaces(7), 4);
    expect(s.toMillimetres(4), 7);
    // 1.75 mm at 300 dpi is about 20.7 device pixels.
    expect(s.pixelsPerSpace(300), closeTo(20.67, 0.01));
    expect(Spatium.staffHeight(7), s);
  });

  test('rastral sizes run from 9.2 mm down to 3.7 mm staves', () {
    expect(Spatium.rastral(0).staffHeight, closeTo(9.2, 1e-9));
    expect(Spatium.rastral(3).staffHeight, closeTo(7.0, 1e-9));
    expect(Spatium.rastral(8).staffHeight, closeTo(3.7, 1e-9));
    for (var i = 0; i < 8; i++) {
      expect(Spatium.rastral(i).millimetres,
          greaterThan(Spatium.rastral(i + 1).millimetres));
    }
    expect(() => Spatium.rastral(9), throwsRangeError);
  });

  test('paper sizes and landscape', () {
    expect(PaperSize.a4.width, 210);
    expect(PaperSize.a4.landscape, const PaperSize(297, 210));
    expect(PaperSize.letter.height, closeTo(279.4, 1e-9));
  });

  test('page metrics on A4 at a 7 mm staff', () {
    final m = pageMetricsFor(PaperSize.a4, Spatium.staffHeight(7));
    expect(m.width, closeTo(120, 1e-9)); // 210 / 1.75
    expect(m.height, closeTo(169.714, 1e-3));
    expect(m.marginLeft, closeTo(15 / 1.75, 1e-9));
    expect(m.contentWidth, closeTo((210 - 30) / 1.75, 1e-9));
  });

  test('an SVG can be sized in millimetres for true-size printing', () {
    final settings = LayoutSettings(
        metadata: SmuflMetadata.fromJson(jsonDecode(
            File('../crisp_notation/assets/smufl/bravura_metadata.json')
                .readAsStringSync()) as Map<String, Object?>));
    final layout = const LayoutEngine().layout(
        Score(clef: Clef.treble, measures: [
          Measure([RestElement(NoteDuration.whole, id: 'r')])
        ]),
        settings);
    final plain = scoreToSvg(layout, staffSpace: 10);
    final sized =
        scoreToSvg(layout, staffSpace: 10, physicalSize: const Spatium(1.75));
    final w = RegExp(r'width="([\d.]+)mm"').firstMatch(sized);
    expect(w, isNotNull);
    expect(double.parse(w![1]!), closeTo(layout.width * 1.75, 0.01));
    expect(sized, contains('viewBox="0 0 ${_px(layout.width * 10)}'));
    expect(plain, isNot(contains('mm"')));
    // The drawing itself is identical.
    String body(String svg) => svg.substring(svg.indexOf('viewBox'));
    expect(body(sized), body(plain));
  });
}

String _px(double v) {
  final s = v.toStringAsFixed(3);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}
