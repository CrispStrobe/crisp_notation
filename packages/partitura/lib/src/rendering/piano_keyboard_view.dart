import 'package:flutter/widgets.dart';

import 'theme.dart';

/// A piano-keyboard visualizer (Phase 3.1) — draws an octave range of keys and
/// lights up the ones currently sounding. Pair it with the playback cursor:
/// feed `highlightedPitches` the MIDI numbers of the sounding notes (e.g. from
/// `pitchesForElements(score, cursorIds)`), and the keyboard follows along.
///
/// partitura never makes sound — this only *shows* which keys are down. The
/// widget sizes itself to `whiteKeyCount * whiteKeyWidth` by `height`; wrap it
/// in a `FittedBox` to scale to a box.
class PianoKeyboardView extends StatelessWidget {
  /// MIDI numbers of the keys to light up (middle C = 60).
  final Set<int> highlightedPitches;

  /// Leftmost key, inclusive (default C3 = 48). Snapped down to a white key.
  final int firstMidi;

  /// Rightmost key, inclusive (default C6 = 84). Snapped up to a white key.
  final int lastMidi;

  /// Per-pitch highlight color override — e.g. one color per hand. Falls back
  /// to [highlightColor] (then `theme.highlightColor`) for pitches not listed.
  final Map<int, Color>? pitchColors;

  /// Highlight color for lit keys when not overridden by [pitchColors]; null
  /// uses `theme.highlightColor`.
  final Color? highlightColor;

  /// Colors (staff/ink) and defaults.
  final PartituraTheme theme;

  /// Pixel width of one white key.
  final double whiteKeyWidth;

  /// Pixel height of the keyboard.
  final double height;

  /// Creates a piano-keyboard visualizer.
  const PianoKeyboardView({
    super.key,
    this.highlightedPitches = const {},
    this.firstMidi = 48,
    this.lastMidi = 84,
    this.pitchColors,
    this.highlightColor,
    this.theme = PartituraTheme.standard,
    this.whiteKeyWidth = 16,
    this.height = 80,
  });

  static const _whitePcs = {0, 2, 4, 5, 7, 9, 11};
  static bool _isWhite(int midi) => _whitePcs.contains(midi % 12);

  @override
  Widget build(BuildContext context) {
    // Snap the range to white keys so both edges are full keys.
    var lo = firstMidi;
    while (!_isWhite(lo)) {
      lo--;
    }
    var hi = lastMidi;
    while (!_isWhite(hi)) {
      hi++;
    }
    var whites = 0;
    for (var m = lo; m <= hi; m++) {
      if (_isWhite(m)) whites++;
    }
    return CustomPaint(
      size: Size(whites * whiteKeyWidth, height),
      painter: _PianoPainter(
        firstMidi: lo,
        lastMidi: hi,
        highlightedPitches: highlightedPitches,
        pitchColors: pitchColors,
        highlightColor: highlightColor ?? theme.highlightColor,
        inkColor: theme.staffColor,
        whiteKeyWidth: whiteKeyWidth,
      ),
    );
  }
}

class _PianoPainter extends CustomPainter {
  _PianoPainter({
    required this.firstMidi,
    required this.lastMidi,
    required this.highlightedPitches,
    required this.pitchColors,
    required this.highlightColor,
    required this.inkColor,
    required this.whiteKeyWidth,
  });

  final int firstMidi;
  final int lastMidi;
  final Set<int> highlightedPitches;
  final Map<int, Color>? pitchColors;
  final Color highlightColor;
  final Color inkColor;
  final double whiteKeyWidth;

  Color? _litColor(int midi) {
    if (!highlightedPitches.contains(midi)) return null;
    return pitchColors?[midi] ?? highlightColor;
  }

  // White keys before [midi] from firstMidi (its slot index).
  int _whiteIndex(int midi) {
    var n = 0;
    for (var m = firstMidi; m < midi; m++) {
      if (PianoKeyboardView._isWhite(m)) n++;
    }
    return n;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = whiteKeyWidth;
    final h = size.height;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = inkColor;

    // White keys first (full height), then black keys on top.
    for (var m = firstMidi; m <= lastMidi; m++) {
      if (!PianoKeyboardView._isWhite(m)) continue;
      final x = _whiteIndex(m) * w;
      final rect = Rect.fromLTWH(x, 0, w, h);
      final lit = _litColor(m);
      canvas.drawRect(rect, Paint()..color = lit ?? const Color(0xFFFFFFFF));
      canvas.drawRect(rect, border);
    }

    final blackW = w * 0.62;
    final blackH = h * 0.62;
    for (var m = firstMidi; m <= lastMidi; m++) {
      if (PianoKeyboardView._isWhite(m)) continue;
      // A black key is centered on the boundary right of the white key m-1.
      final centerX = _whiteIndex(m) * w;
      final rect = Rect.fromLTWH(centerX - blackW / 2, 0, blackW, blackH);
      final lit = _litColor(m);
      canvas.drawRect(rect, Paint()..color = lit ?? inkColor);
      if (lit != null) {
        // Keep a thin dark outline so a lit black key still reads as one.
        canvas.drawRect(rect, border);
      }
    }
  }

  @override
  bool shouldRepaint(_PianoPainter old) =>
      old.firstMidi != firstMidi ||
      old.lastMidi != lastMidi ||
      old.whiteKeyWidth != whiteKeyWidth ||
      old.highlightColor != highlightColor ||
      old.inkColor != inkColor ||
      !_setEq(old.highlightedPitches, highlightedPitches) ||
      !_mapEq(old.pitchColors, pitchColors);

  static bool _setEq(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  static bool _mapEq(Map<int, Color>? a, Map<int, Color>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}
