/// Playback-cursor API: a deterministic timeline of element onsets so
/// apps can drive `highlightedIds` in sync with their own audio.
///
/// partitura never produces sound (HANDOVER contract) — this module only
/// answers "which element ids sound when", in exact musical time.
library;

import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/fraction.dart';

/// One entry of a [playbackTimeline]: an element and its exact time span.
class PlaybackNote {
  /// The element's id (`e0`, `e1`, …).
  final String elementId;

  /// Onset in whole-note units from the start of playback.
  final Fraction start;

  /// Sounding duration in whole-note units (tuplet-scaled where the
  /// measure defines a tuplet).
  final Fraction duration;

  /// Whether the element is a rest (apps usually skip highlighting).
  final bool isRest;

  /// Voice the element belongs to: 0 (voice 1) or 1 (voice 2).
  final int voice;

  /// Index of the measure in `Score.measures` this element came from
  /// (repeated passes reference the same original measure).
  final int measureIndex;

  /// Creates a timeline entry.
  const PlaybackNote({
    required this.elementId,
    required this.start,
    required this.duration,
    required this.isRest,
    required this.voice,
    required this.measureIndex,
  });

  /// Time when the element stops sounding.
  Fraction get end => start + duration;

  @override
  bool operator ==(Object other) =>
      other is PlaybackNote &&
      other.elementId == elementId &&
      other.start == start &&
      other.duration == duration &&
      other.isRest == isRest &&
      other.voice == voice &&
      other.measureIndex == measureIndex;

  @override
  int get hashCode =>
      Object.hash(elementId, start, duration, isRest, voice, measureIndex);

  @override
  String toString() =>
      'PlaybackNote($elementId @ $start + $duration, m$measureIndex'
      '${isRest ? ', rest' : ''}${voice == 1 ? ', v2' : ''})';
}

/// Converts a whole-note time to seconds at [quarterBpm] beats (quarter
/// notes) per minute — the usual tempo convention.
double secondsFor(Fraction wholeNotes, {required double quarterBpm}) =>
    wholeNotes.numerator / wholeNotes.denominator * 4 * 60 / quarterBpm;

/// Flattens [score] into a timeline of element onsets sorted by start
/// (ties broken by voice), in exact whole-note [Fraction] time.
///
/// With [expandRepeats] (default), the score is linearized into performance
/// order: repeat barlines play their segment twice and voltas select their
/// pass (a `volta: 1` measure plays only on the first pass, `volta: 2` only
/// on the second — deeper nested repeats are out of scope), and
/// navigation marks execute their jumps (see [_navExpandedOrder] for the
/// supported D.C. / D.S. / To Coda / Fine semantics). Ties stay separate
/// entries — highlight both noteheads while the sound sustains. Grace notes
/// carry no time of their own. An element id appears once per pass, so ids
/// can repeat in the returned list when repeats or jumps are expanded.
///
/// With `expandRepeats: false` the measures play once in document order and
/// all repeat/navigation structure is ignored.
List<PlaybackNote> playbackTimeline(Score score, {bool expandRepeats = true}) {
  final measures = score.measures;
  final order = expandRepeats
      ? _navExpandedOrder(measures)
      : [for (var i = 0; i < measures.length; i++) i];

  final result = <PlaybackNote>[];
  var measureStart = Fraction(0, 1);
  var meter = score.timeSignature;
  for (final index in order) {
    final measure = measures[index];
    meter = measure.timeChange ?? meter;

    var voice1End = measureStart;
    var clock = measureStart;
    for (var i = 0; i < measure.elements.length; i++) {
      final element = measure.elements[i];
      final duration = measure.effectiveDurationAt(i);
      if (element.id != null) {
        result.add(PlaybackNote(
          elementId: element.id!,
          start: clock,
          duration: duration,
          isRest: element is RestElement,
          voice: 0,
          measureIndex: index,
        ));
      }
      clock = clock + duration;
    }
    voice1End = clock;

    clock = measureStart;
    for (final element in measure.voice2) {
      final (numerator, denominator) = element.duration.fraction;
      final duration = Fraction(numerator, denominator);
      if (element.id != null) {
        result.add(PlaybackNote(
          elementId: element.id!,
          start: clock,
          duration: duration,
          isRest: element is RestElement,
          voice: 1,
          measureIndex: index,
        ));
      }
      clock = clock + duration;
    }
    final voice2End = clock;

    var measureEnd =
        voice1End.compareTo(voice2End) >= 0 ? voice1End : voice2End;
    if (measureEnd == measureStart && meter != null) {
      // Empty or multi-rest measure: advance by the current meter.
      final bars = measure.multiRest ?? 1;
      measureEnd = measureStart + Fraction(meter.beats * bars, meter.beatUnit);
    }
    measureStart = measureEnd;
  }

  result.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    return a.voice.compareTo(b.voice);
  });
  return result;
}

bool _isDaCapo(NavigationMark? n) =>
    n == NavigationMark.daCapo ||
    n == NavigationMark.daCapoAlFine ||
    n == NavigationMark.daCapoAlCoda;

bool _isDalSegno(NavigationMark? n) =>
    n == NavigationMark.dalSegno ||
    n == NavigationMark.dalSegnoAlFine ||
    n == NavigationMark.dalSegnoAlCoda;

bool _isAlFine(NavigationMark? n) =>
    n == NavigationMark.daCapoAlFine || n == NavigationMark.dalSegnoAlFine;

bool _isAlCoda(NavigationMark? n) =>
    n == NavigationMark.daCapoAlCoda || n == NavigationMark.dalSegnoAlCoda;

/// The measure indices in performance order, expanding repeat barlines,
/// voltas and navigation-mark jumps.
///
/// Supported jump semantics (one level, the common cases):
///
/// - **D.C.** (da capo) returns to the first measure; **D.S.** (dal segno)
///   returns to the [NavigationMark.segno] measure. The instruction sits at
///   the end of its measure (that measure is played, then the jump happens),
///   and fires **once**.
/// - **al Fine** variants stop after the [NavigationMark.fine] measure (which
///   is otherwise ignored on the first pass); **al Coda** variants arm the
///   [NavigationMark.toCoda] mark so that the next time it is reached, play
///   jumps to the [NavigationMark.coda] measure and continues to the end.
/// - After a D.C./D.S. return the score plays **straight through** — inner
///   repeat barlines and voltas are not re-expanded (their brackets are moot
///   on the return pass). This is the standard "play repeats off on D.C./D.S."
///   default and keeps the linearization unambiguous.
///
/// Throws [ArgumentError] for a D.S. with no segno or an *al Coda* with no
/// coda target (a malformed score — nothing degrades silently), and
/// [StateError] if the jumps fail to terminate (a cyclic structure).
List<int> _navExpandedOrder(List<Measure> measures) {
  int? indexOf(NavigationMark target) {
    for (var i = 0; i < measures.length; i++) {
      if (measures[i].navigation == target) return i;
    }
    return null;
  }

  final segnoIndex = indexOf(NavigationMark.segno);
  final codaIndex = indexOf(NavigationMark.coda);

  final order = <int>[];
  var i = 0;
  var repeatStart = 0;
  var pass = 1;
  var navReturned = false; // a D.C./D.S. jump has already fired
  var codaArmed = false; // an al Coda return is waiting for `toCoda`
  var stopAtFine = false; // an al Fine return will stop at `fine`
  final guardLimit = measures.length * 6 + 100;
  var guard = 0;

  while (i < measures.length) {
    if (++guard > guardLimit) {
      throw StateError('navigation jumps do not terminate (cyclic?)');
    }
    final measure = measures[i];
    final nav = measure.navigation;

    // Repeat/volta expansion runs only on the primary pass; after a
    // D.C./D.S. return the score plays straight through.
    if (!navReturned) {
      if (measure.startRepeat && pass == 1) repeatStart = i;
      final volta = measure.volta;
      if (volta != null && volta != pass) {
        i++;
        continue;
      }
    }

    order.add(i);

    // Stop at Fine once an al Fine jump has armed it.
    if (stopAtFine && nav == NavigationMark.fine) break;

    // Jump to the coda once an al Coda jump has armed it.
    if (codaArmed && nav == NavigationMark.toCoda) {
      if (codaIndex == null) {
        throw ArgumentError('al Coda navigation with no coda target');
      }
      codaArmed = false;
      i = codaIndex;
      continue;
    }

    // Repeat barline (primary pass only).
    if (!navReturned && measure.endRepeat) {
      if (pass == 1) {
        pass = 2;
        i = repeatStart;
        continue;
      }
      pass = 1;
      repeatStart = i + 1;
    }

    // D.C./D.S. return instruction — fires once, then plays straight through.
    if (!navReturned && (_isDaCapo(nav) || _isDalSegno(nav))) {
      navReturned = true;
      stopAtFine = _isAlFine(nav);
      codaArmed = _isAlCoda(nav);
      if (_isDalSegno(nav)) {
        if (segnoIndex == null) {
          throw ArgumentError('D.S. navigation with no segno target');
        }
        i = segnoIndex;
      } else {
        i = 0; // da capo
      }
      continue;
    }

    i++;
  }
  return order;
}

/// The element ids sounding at [time] (rests excluded) — a convenience
/// for driving `highlightedIds` from a position in seconds mapped back
/// to whole notes.
Set<String> soundingAt(List<PlaybackNote> timeline, Fraction time) => {
      for (final note in timeline)
        if (!note.isRest &&
            note.start.compareTo(time) <= 0 &&
            time.compareTo(note.end) < 0)
          note.elementId,
    };
