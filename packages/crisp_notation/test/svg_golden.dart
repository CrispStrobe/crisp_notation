import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Portable engraving goldens.
///
/// The PNG goldens are rasterised by the host, so they are a local,
/// macOS-only gate (CI waives the pixel compare — see flutter_test_config).
/// That left engraving GEOMETRY ungated in CI. These goldens close the gap:
/// the same score is laid out by the pure-Dart engine and serialised with
/// [scoreToSvg], whose coordinates are rounded to 3 decimals — text that is
/// byte-identical on every host, so it gates on Linux CI too.
///
/// Regenerate with the same flag as the PNGs (`flutter test --update-goldens`),
/// or — on a non-macOS host, where that flag would also overwrite the PNG
/// baselines with the wrong rasteriser — update ONLY the SVGs with
/// `CI=true UPDATE_SVG_GOLDENS=1 flutter test test/golden_test.dart`.
/// Review the `.svg` diff like code: it shows exactly which primitive moved.
void expectSvgGolden(String name, Score score) {
  final svg = scoreToSvg(
    const LayoutEngine().layout(score, LayoutSettings(metadata: _metadata)),
  );
  final file = File('test/goldens_svg/$name.svg');
  if (autoUpdateGoldenFiles ||
      Platform.environment['UPDATE_SVG_GOLDENS'] == '1') {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(svg);
    return;
  }
  if (!file.existsSync()) {
    fail('missing SVG golden ${file.path} — run '
        '`CI=true UPDATE_SVG_GOLDENS=1 flutter test test/golden_test.dart`');
  }
  final expected = file.readAsStringSync();
  if (svg == expected) return;
  // Point at the first differing line rather than dumping two whole SVGs.
  final got = const LineSplitter().convert(svg);
  final want = const LineSplitter().convert(expected);
  var line = 0;
  while (line < got.length && line < want.length && got[line] == want[line]) {
    line++;
  }
  fail('SVG golden ${file.path} differs at line ${line + 1}:\n'
      '  expected: ${line < want.length ? want[line] : '<end of file>'}\n'
      '  actual:   ${line < got.length ? got[line] : '<end of file>'}\n'
      'If the change is intended, run `CI=true UPDATE_SVG_GOLDENS=1 '
      'flutter test test/golden_test.dart` and review the .svg diff.');
}

final SmuflMetadata _metadata = SmuflMetadata.fromJson(
  jsonDecode(File('assets/smufl/bravura_metadata.json').readAsStringSync())
      as Map<String, Object?>,
);
