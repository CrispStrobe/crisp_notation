import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

/// Loads the Bravura font and its metadata from the package assets so
/// rendering works in widget/golden tests (which have no async asset
/// loading and no fonts by default).
Future<void> setUpPartituraForTests() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final metadataSource =
      File('assets/smufl/bravura_metadata.json').readAsStringSync();
  Bravura.debugOverrideMetadata(
    SmuflMetadata.fromJson(
      jsonDecode(metadataSource) as Map<String, Object?>,
    ),
  );

  final fontBytes = File('assets/fonts/Bravura.otf').readAsBytesSync();
  // Package fonts resolve to the family 'packages/<package>/<family>'.
  final loader = FontLoader('packages/partitura/Bravura')
    ..addFont(Future.value(ByteData.view(fontBytes.buffer)));
  await loader.load();

  // A real text font for lyric/annotation goldens (the framework's
  // default test font draws boxes). Taken from the local Flutter SDK;
  // themes opt in via `textFontFamily: 'Roboto'`.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final roboto = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
    if (roboto.existsSync()) {
      final bytes = roboto.readAsBytesSync();
      final robotoLoader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await robotoLoader.load();
    }
  }
}
