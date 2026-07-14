/// Flutter-backed PNG render harness, driven by `partitura_cli`.
///
/// Not a real test — it is run via `flutter test tool/render_png.dart` (the
/// only way to reach `dart:ui` from a command line) with the job described by
/// environment variables, and writes a PNG file as its side effect:
///
///   PARTITURA_IN           input path (.musicxml / .mid)
///   PARTITURA_OUT          output .png path
///   PARTITURA_TAB          "1" to render tablature
///   PARTITURA_GRAND        "1" to render a two-staff grand staff (MusicXML)
///   PARTITURA_MULTIPART    "1" to render a multi-part document (all parts)
///   PARTITURA_WIDTH        multi-part line-break width in staff spaces
///   PARTITURA_HIDE_EMPTY   "1" to drop empty staves per system (multi-part)
///   PARTITURA_TUNING       std | dropD | bass
///   PARTITURA_STAFF_SPACE  pixels per staff space
///
/// It fails (non-zero exit) on a bad job so the CLI can report the error.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

void main() {
  final env = Platform.environment;
  final inPath = env['PARTITURA_IN'];
  final outPath = env['PARTITURA_OUT'];
  final tab = env['PARTITURA_TAB'] == '1';
  final tuning = switch (env['PARTITURA_TUNING']) {
    'dropD' => Tuning.dropDGuitar,
    'bass' => Tuning.standardBass,
    _ => Tuning.standardGuitar,
  };
  final staffSpace =
      double.tryParse(env['PARTITURA_STAFF_SPACE'] ?? '12') ?? 12;

  testWidgets('render png', (tester) async {
    if (inPath == null || outPath == null) {
      fail('PARTITURA_IN and PARTITURA_OUT must be set');
    }
    TestWidgetsFlutterBinding.ensureInitialized();

    final metadata = SmuflMetadata.fromJson(jsonDecode(
            File('assets/smufl/bravura_metadata.json').readAsStringSync())
        as Map<String, Object?>);
    Bravura.debugOverrideMetadata(metadata);
    final fontBytes = File('assets/fonts/Bravura.otf').readAsBytesSync();
    await (FontLoader('packages/partitura/Bravura')
          ..addFont(Future.value(ByteData.view(fontBytes.buffer))))
        .load();
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final roboto = flutterRoot == null
        ? null
        : File(
            '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
    final theme = (roboto?.existsSync() ?? false)
        ? PartituraTheme.standard.copyWith(textFontFamily: 'Roboto')
        : PartituraTheme.standard;
    if (roboto?.existsSync() ?? false) {
      final bytes = roboto!.readAsBytesSync();
      await (FontLoader('Roboto')
            ..addFont(Future.value(ByteData.view(bytes.buffer))))
          .load();
    }

    final settings = LayoutSettings(metadata: metadata);
    late final List<int> png;

    if (env['PARTITURA_GRAND'] == '1') {
      // A two-staff grand staff (e.g. optical music recognition output).
      final grand = grandStaffFromMusicXml(File(inPath).readAsStringSync());
      final layout = layoutGrandStaff(grand, settings);
      await tester.runAsync(() async {
        png = await renderGrandStaffLayoutToPng(layout,
            staffSpace: staffSpace, theme: theme);
      });
    } else if (env['PARTITURA_MULTIPART'] == '1') {
      // A multi-part document: every part, line-broken into stacked systems.
      final maxWidth = double.tryParse(env['PARTITURA_WIDTH'] ?? '') ?? 120.0;
      final wrapped = layoutStaffSystemSystems(
          _loadStaffSystem(inPath), settings,
          maxWidth: maxWidth,
          hideEmptyStaves: env['PARTITURA_HIDE_EMPTY'] == '1');
      await tester.runAsync(() async {
        png = await renderStaffSystemSystemsToPng(wrapped,
            staffSpace: staffSpace, theme: theme);
      });
    } else {
      final lower = inPath.toLowerCase();
      final score = lower.endsWith('.mid') || lower.endsWith('.midi')
          ? scoreFromMidi(File(inPath).readAsBytesSync())
          : scoreFromMusicXml(File(inPath).readAsStringSync());
      final layout = tab
          ? const TabLayoutEngine().layout(score, tuning, settings)
          : const LayoutEngine().layout(score, settings);
      await tester.runAsync(() async {
        png = await renderLayoutToPng(layout,
            staffSpace: staffSpace, theme: theme);
      });
    }
    File(outPath).writeAsBytesSync(png);
  });
}

/// Loads a multi-part [StaffSystem] from [path], picking the importer by
/// extension (MusicXML/MXL, MEI, kern, ABC) — mirrors the CLI's dispatch.
StaffSystem _loadStaffSystem(String path) {
  final file = File(path);
  final lower = path.toLowerCase();
  if (lower.endsWith('.mxl')) {
    return staffSystemFromMusicXml(readMusicXmlFromMxl(file.readAsBytesSync()));
  }
  if (lower.endsWith('.mei')) {
    return staffSystemFromMei(file.readAsStringSync());
  }
  if (lower.endsWith('.krn') || lower.endsWith('.kern')) {
    return staffSystemFromKern(file.readAsStringSync());
  }
  if (lower.endsWith('.abc')) {
    return staffSystemFromAbc(file.readAsStringSync());
  }
  return staffSystemFromMusicXml(file.readAsStringSync());
}
