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

/// Rasterizes a laid-out [GrandStaffLayout] (two staves) to PNG bytes — the
/// raster counterpart to `grandStaffToSvg`. The upper and lower staves are
/// stacked [GrandStaffLayout.staffGap] spaces apart, sharing the same painter,
/// so a recognized/imported grand staff renders both staves. Parameters match
/// [renderLayoutToPng].
Future<Uint8List> renderGrandStaffLayoutToPng(
  GrandStaffLayout layout, {
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
  // Same stacking as grandStaffToSvg: shift the upper ink top to y = 0, and the
  // lower staff's top line to (upper bottom line = 4) + staffGap below it.
  painter.paintLayout(
      canvas, Offset(0, -layout.upper.top * staffSpace), layout.upper);
  painter.paintLayout(
      canvas,
      Offset(0, (4 - layout.upper.top + layout.staffGap) * staffSpace),
      layout.lower);
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

/// Rasterizes a laid-out [StaffSystemLayout] (N staves) to PNG bytes — the
/// raster counterpart to `staffSystemToSvg`. The staves are stacked
/// [StaffSystemLayout.staffGap] spaces apart and the systemic barlines are
/// connected through each [BarlineGroup] (breaking between groups), so an
/// imported multi-part score renders every part. Parameters match
/// [renderLayoutToPng].
Future<Uint8List> renderStaffSystemLayoutToPng(
  StaffSystemLayout layout, {
  double staffSpace = 12,
  PartituraTheme theme = PartituraTheme.standard,
  Set<String> highlightedIds = const {},
  Color background = const Color(0xFFFFFFFF),
}) async {
  final width = (layout.width * staffSpace).ceil().clamp(1, 1 << 20);
  final height = (layout.height * staffSpace).ceil().clamp(1, 1 << 20);
  return _rasterize(width, height, background, (canvas, painter) {
    // Shift the whole system so its top-most ink sits at y = 0.
    _paintStaffSystem(canvas, painter, layout, 0, staffSpace, theme.staffColor);
  }, theme, staffSpace, highlightedIds);
}

/// Rasterizes a line-broken [StaffSystemSystems] (a multi-part document) to PNG
/// bytes — the raster counterpart to `staffSystemSystemsToSvg`. Each system is
/// stacked [systemGap] staff-spaces below the previous one. Parameters match
/// [renderLayoutToPng].
Future<Uint8List> renderStaffSystemSystemsToPng(
  StaffSystemSystems wrapped, {
  double staffSpace = 12,
  double systemGap = 8,
  PartituraTheme theme = PartituraTheme.standard,
  Set<String> highlightedIds = const {},
  Color background = const Color(0xFFFFFFFF),
}) async {
  final width = (wrapped.maxWidth * staffSpace).ceil().clamp(1, 1 << 20);
  final height =
      (wrapped.heightWith(systemGap) * staffSpace).ceil().clamp(1, 1 << 20);
  return _rasterize(width, height, background, (canvas, painter) {
    var y = 0.0;
    for (final system in wrapped.systems) {
      _paintStaffSystem(
          canvas, painter, system.layout, y, staffSpace, theme.staffColor);
      y += (system.layout.height + systemGap) * staffSpace;
    }
  }, theme, staffSpace, highlightedIds);
}

/// Paints one [layout]'s staves at [baseY] px (its top-most ink lands there),
/// then the systemic barlines connected through each group — the raster twin of
/// the SVG `_emitStaffSystem`.
void _paintStaffSystem(Canvas canvas, LayoutPainter painter,
    StaffSystemLayout layout, double baseY, double staffSpace, Color color) {
  for (var i = 0; i < layout.staves.length; i++) {
    final offsetY = baseY + (layout.staffTop(i) - layout.top) * staffSpace;
    painter.paintLayout(canvas, Offset(0, offsetY), layout.staves[i]);
  }
  final spans = layout.barlineSpans;
  final xs = layout.barlineXs;
  if (spans.isEmpty || xs.isEmpty) return;
  final paint = Paint()
    ..color = color
    ..strokeWidth = 0.16 * staffSpace;
  for (final x in xs) {
    for (final span in spans) {
      canvas.drawLine(
        Offset(x * staffSpace, baseY + (span.top - layout.top) * staffSpace),
        Offset(x * staffSpace, baseY + (span.bottom - layout.top) * staffSpace),
        paint,
      );
    }
  }
}

/// Records [paint] onto a [width]×[height] canvas (filled with [background])
/// and encodes it to PNG bytes.
Future<Uint8List> _rasterize(
  int width,
  int height,
  Color background,
  void Function(Canvas canvas, LayoutPainter painter) paint,
  PartituraTheme theme,
  double staffSpace,
  Set<String> highlightedIds,
) async {
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
  paint(canvas, painter);
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
