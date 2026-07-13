import 'dart:ui' show Color;

import 'package:partitura_core/partitura_core.dart';

import 'editor_mark.dart';

/// The outcome of a play-the-right-note comparison ([evaluateDrill]).
class DrillResult {
  /// Per-expected-element overlay marks to feed a view's `errorOverlay`:
  /// `correctColor` when every pitch of the element was played, `wrongColor`
  /// when one or more of its pitches was missing.
  final Map<String, EditorMark> overlay;

  /// MIDI pitches the player sounded that no expected element wanted.
  final Set<int> extraPitches;

  /// Expected MIDI pitches that the player did not sound.
  final Set<int> missingPitches;

  /// Creates a drill result.
  const DrillResult({
    required this.overlay,
    required this.extraPitches,
    required this.missingPitches,
  });

  /// Whether every expected pitch was played and nothing extra sounded.
  bool get isPerfect => extraPitches.isEmpty && missingPitches.isEmpty;
}

/// Compares what the player *should* have sounded against what they *did*, for
/// a play-the-right-note drill (Phase 3.7). partitura supplies only the
/// highlighting; the MIDI input is the app's.
///
/// [expectedIds] are the score element ids the player is meant to hit right now
/// (e.g. the notes the cursor is on); [played] is the set of MIDI numbers the
/// player is currently sounding. Each expected element becomes an
/// [EditorMark] — [correctColor] if all its pitches are in [played], else
/// [wrongColor] — ready for `errorOverlay` / `ScoreEditorController.setMarks`.
/// Rests and unknown ids are ignored. See [ScoreEditorController.showDrill] to
/// apply the result in one call.
DrillResult evaluateDrill({
  required Score score,
  required Iterable<String> expectedIds,
  required Set<int> played,
  Color correctColor = const Color(0xFF388E3C),
  Color wrongColor = const Color(0xFFD32F2F),
}) {
  final overlay = <String, EditorMark>{};
  final expectedPitches = <int>{};
  final missing = <int>{};
  for (final id in expectedIds) {
    final pitches = pitchesForElements(score, {id});
    if (pitches.isEmpty) continue; // rest / grace / unknown id
    expectedPitches.addAll(pitches);
    final notPlayed = pitches.where((p) => !played.contains(p)).toSet();
    missing.addAll(notPlayed);
    overlay[id] = notPlayed.isEmpty
        ? EditorMark(correctColor, message: 'correct')
        : EditorMark(wrongColor,
            message: 'missing ${notPlayed.length} note'
                '${notPlayed.length == 1 ? '' : 's'}');
  }
  return DrillResult(
    overlay: overlay,
    extraPitches: played.difference(expectedPitches),
    missingPitches: missing,
  );
}
