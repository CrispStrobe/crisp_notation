import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:partitura_core/partitura_core.dart';

import 'layout_painter.dart';
import 'theme.dart';

/// Rasterizes a laid-out [layout] to PNG bytes using the Flutter engine.
///
/// This is the raster counterpart to the pure-Dart `scoreToSvg` — it needs
/// `dart:ui`, so it runs inside a Flutter binding (an app, or `flutter test`).
/// The engraving font must already be registered (call [MusicFonts.load] for
/// the theme's [MusicFont], or the
/// test setup) or glyphs render as blank boxes.
///
/// [staffSpace] is the pixel size of one staff space; [theme] colors the ink
/// (highlights via [highlightedIds]); [background] fills the page (pass a
/// transparent color for no fill). Works for both notation
/// ([LayoutEngine]) and tablature ([TabLayoutEngine]) layouts.
Future<Uint8List> renderLayoutToPng(
  ScoreLayout layout, {
  double staffSpace = 12,
  PartituraTheme theme = PartituraTheme.standard,
  Set<String> highlightedIds = const {},
  Color background = const Color(0xFFFFFFFF),
}) async {
  final width = (layout.width * staffSpace).ceil().clamp(1, 1 << 20);
  final height = (layout.height * staffSpace).ceil().clamp(1, 1 << 20);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (background.a > 0) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = background,
    );
  }

  final painter = LayoutPainter(
    theme: theme,
    scale: staffSpace,
    highlightedIds: highlightedIds,
  );
  painter.paintLayout(canvas, Offset(0, -layout.top * staffSpace), layout);
  painter.dispose();

  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('failed to encode PNG');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
