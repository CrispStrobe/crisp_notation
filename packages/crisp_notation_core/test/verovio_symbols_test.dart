// Verovio symbol counts: per-bar rests and accidentals.
//
// For each MusicXML file, Verovio's MEI (staff n=1) gives the ground truth
// per measure: how many rests (rest/mRest/multiRest) and how many written
// accidentals (accid + note@accid, excluding grace) it prints. Crisp's
// layout should draw the same numbers. Counting what is actually drawn
// (GlyphPrimitive with smuflName rest*/accidental*) per bar catches
// missing or extra symbols — a real engraving bug.
//
// Opt-in: needs CRISP_NOTATION_CORPUS and verovio-oracle/symbols.json.
@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

void main() {
  final root = Platform.environment['CRISP_NOTATION_CORPUS'];
  final symbolsFile =
      root == null ? null : File('$root/verovio-oracle/symbols.json');
  final skip = root == null || !Directory(root).existsSync()
      ? 'set CRISP_NOTATION_CORPUS to a directory of .mxl files'
      : (symbolsFile != null && !symbolsFile.existsSync()
          ? 'no verovio-oracle/symbols.json beside the corpus'
          : null);

  // Settings as spec: same as svg_test.dart.
  late final LayoutSettings settings;
  setUpAll(() {
    if (skip != null) return;
    final raw = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    final meta =
        SmuflMetadata.fromJson(jsonDecode(raw) as Map<String, Object?>);
    settings = LayoutSettings(metadata: meta);
  });

  test('verovio symbols agree', () {
    final raw =
        jsonDecode(symbolsFile!.readAsStringSync()) as Map<String, dynamic>;
    final entries = raw.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    var agree = 0;
    final total = entries.length;
    final disagreements = <String>[];
    // For report: split by kind
    var restOnly = 0;
    var accOnly = 0;
    var both = 0;
    var barCountMismatch = 0;
    final examplesByKind = <String, List<String>>{
      'rest': [],
      'accidental': [],
      'bar count': [],
      'both': [],
    };

    // Also collect detailed disagreements for CRISP_SYMBOLS_REPORT
    final reportLines = <String>[];

    for (final e in entries) {
      final relPath = e.key;
      final absPath = '$root/$relPath';
      final verovioPerBar =
          (e.value as List).map((pair) => (pair as List).cast<int>()).toList();
      // Each entry is [rests, accidentals]

      Score score;
      try {
        if (absPath.endsWith('.mxl')) {
          final bytes = File(absPath).readAsBytesSync();
          final xml = readMusicXmlFromMxl(bytes);
          final system = staffSystemFromMusicXml(xml);
          if (system.staves.isEmpty) throw const FormatException('no staves');
          score = system.staves[0];
        } else {
          final xml = File(absPath).readAsStringSync();
          final system = staffSystemFromMusicXml(xml);
          if (system.staves.isEmpty) throw const FormatException('no staves');
          score = system.staves[0];
        }
      } catch (err) {
        // Reading failed counts as disagreeing with reason bar count? But we
        // have no crisp bars to compare; count as bar count mismatch.
        barCountMismatch++;
        final line =
            '$relPath: bar 0 verovio ${verovioPerBar.isNotEmpty ? verovioPerBar[0] : [
                0,
                0
              ]} crisp [] bar count';
        disagreements.add(line);
        reportLines.add(line);
        continue;
      }

      ScoreLayout layout;
      try {
        layout = const LayoutEngine().layout(score, settings);
      } catch (err) {
        barCountMismatch++;
        final line =
            '$relPath: bar 0 verovio ${verovioPerBar.isNotEmpty ? verovioPerBar[0] : [
                0,
                0
              ]} crisp [] bar count (layout failed: $err)';
        disagreements.add(line);
        reportLines.add(line);
        continue;
      }

      final regions = layout.measureRegions;
      // Check bar count mismatch first
      if (regions.length != verovioPerBar.length) {
        barCountMismatch++;
        final line =
            '$relPath: bar 0 verovio [${verovioPerBar.length} bars] crisp [${regions.length} bars] bar count';
        disagreements.add(line);
        reportLines.add(line);
        // For report, collect example
        if (examplesByKind['bar count']!.length < 2) {
          examplesByKind['bar count']!.add(
              '$relPath: verovio ${verovioPerBar.length} bars vs crisp ${regions.length} bars');
        }
        continue;
      }

      // Count glyphs per bar in crisp layout
      final crispPerBar = _countPerBar(layout);

      // Compare per bar
      var fileAgrees = true;
      var firstDiffIndex = -1;
      List<int>? vFirst;
      List<int>? cFirst;
      String? diffKind;
      for (var i = 0; i < verovioPerBar.length; i++) {
        final v = verovioPerBar[i];
        final c = crispPerBar[i];
        if (v[0] != c[0] || v[1] != c[1]) {
          fileAgrees = false;
          firstDiffIndex = i;
          vFirst = v;
          cFirst = c;
          if (v[0] != c[0] && v[1] != c[1]) {
            both++;
            diffKind = 'both';
          } else if (v[0] != c[0]) {
            restOnly++;
            diffKind = 'rest';
          } else {
            accOnly++;
            diffKind = 'accidental';
          }
          break;
        }
      }

      if (fileAgrees) {
        agree++;
      } else {
        final line =
            '$relPath: bar $firstDiffIndex verovio $vFirst crisp $cFirst $diffKind';
        disagreements.add(line);
        reportLines.add(line);
        if (diffKind != null && examplesByKind[diffKind]!.length < 3) {
          examplesByKind[diffKind]!.add(line);
        }
      }
    }

    // Print as spec: verovio symbols: A / N files agree
    // ignore: avoid_print
    print('verovio symbols: $agree / $total files agree');
    if (disagreements.isNotEmpty) {
      // ignore: avoid_print
      print('Disagreeing files (up to 20):');
      for (final line in disagreements.take(20)) {
        // ignore: avoid_print
        print('  $line');
      }
      // ignore: avoid_print
      print(
          'Split: rest-only $restOnly, accidental-only $accOnly, both $both, bar count $barCountMismatch');
    }

    // Write to CRISP_SYMBOLS_REPORT if set
    final reportPath = Platform.environment['CRISP_SYMBOLS_REPORT'];
    if (reportPath != null && reportPath.isNotEmpty) {
      final f = File(reportPath);
      f.createSync(recursive: true);
      f.writeAsStringSync(reportLines.join('\n'));
    }

    // Ratchet: floor is measured value; only goes up.
    // 2026-10-16: 1474 / 1745 after measuring with Verovio 6.3; 1635 once a
    // note tied over the barline keeps no accidental.
    const floor = 1635;
    expect(agree, greaterThanOrEqualTo(floor),
        reason: 'verovio symbols: $agree / $total agree, floor $floor\n'
            '${disagreements.take(20).join('\n')}');
  }, skip: skip);
}

/// Count per bar: rests and accidentals from glyphs in that bar.
///
/// A glyph belongs to a bar if its x is within [region.startX, region.endX)
/// except the last bar includes its endX. We count:
///   rests: smuflName starts with 'rest'
///   accidentals: smuflName starts with 'accidental'
/// Grace notes are drawn with scale 0.6; we exclude those glyphs if we can
/// tell (scale != 1.0). Otherwise we would over-count grace accidentals.
List<List<int>> _countPerBar(ScoreLayout layout) {
  final regions = layout.measureRegions;
  final perBar = List.generate(regions.length, (_) => [0, 0]);

  for (final p in layout.primitives) {
    if (p is! GlyphPrimitive) continue;
    final name = p.smuflName;
    final isRest = name.startsWith('rest');
    final isAcc = name.startsWith('accidental');
    if (!isRest && !isAcc) continue;
    // Exclude grace glyphs if we can tell: grace is drawn at 0.6 scale.
    // Without this, a grace accidental would be counted as a written one.
    // If we cannot tell (scale always 1.0 for some glyphs), we note it.
    if (p.scale != 1.0) continue;
    // Also exclude glyphs with no elementId that are key-signature
    // accidentals? Those have no elementId and are at start of staff, but
    // they would fall in first bar and inflate counts. We exclude them
    // because they are not per-note accidentals.
    // The crisp layout draws key-sig accidentals with no elementId.
    if (p.elementId == null) continue;

    final x = p.position.x;
    for (var i = 0; i < regions.length; i++) {
      final r = regions[i];
      final inBar = i == regions.length - 1
          ? x >= r.startX && x <= r.endX
          : x >= r.startX && x < r.endX;
      if (inBar) {
        if (isRest) perBar[i][0] += 1;
        if (isAcc) perBar[i][1] += 1;
        break;
      }
    }
  }
  return perBar;
}
