/// Playback-cursor API: a deterministic timeline of element onsets so
/// apps can drive `highlightedIds` in sync with their own audio.
///
/// crisp_notation never produces sound (by design) — this module only
/// answers "which element ids sound when", in exact musical time.
library;

import 'dart:math';

import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/pitch.dart';

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

  /// The pitches a chord symbol sounds, for an entry that voices one (see
  /// `playbackTimeline`'s `voiceChordSymbols`): then [elementId] is the note
  /// the symbol stands over. Null for an ordinary element.
  final List<Pitch>? chordPitches;

  /// Creates a timeline entry.
  const PlaybackNote({
    required this.elementId,
    required this.start,
    required this.duration,
    required this.isRest,
    required this.voice,
    required this.measureIndex,
    this.chordPitches,
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
      other.measureIndex == measureIndex &&
      _samePitches(other.chordPitches, chordPitches);

  static bool _samePitches(List<Pitch>? a, List<Pitch>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
      elementId,
      start,
      duration,
      isRest,
      voice,
      measureIndex,
      chordPitches == null ? null : Object.hashAll(chordPitches!));

  @override
  String toString() =>
      'PlaybackNote($elementId @ $start + $duration, m$measureIndex'
      '${isRest ? ', rest' : ''}${voice == 1 ? ', v2' : ''})';
}

/// Converts a whole-note time to seconds at [quarterBpm] beats (quarter
/// notes) per minute — the usual tempo convention.
double secondsFor(Fraction wholeNotes, {required double quarterBpm}) =>
    wholeNotes.numerator / wholeNotes.denominator * 4 * 60 / quarterBpm;

/// The sounding MIDI pitch numbers of the note elements in [ids] — for driving
/// an instrument visualizer (piano keyboard / fretboard) from the playback
/// cursor's currently-highlighted ids. Each id maps to its
/// `NoteElement.pitches` (a chord contributes every pitch); rests, grace notes
/// and unknown ids contribute nothing. Scans every voice.
Set<int> pitchesForElements(Score score, Iterable<String> ids) {
  final want = ids is Set<String> ? ids : ids.toSet();
  if (want.isEmpty) return const {};
  final out = <int>{};
  for (final measure in score.measures) {
    for (final voice in [
      measure.elements,
      measure.voice2,
      measure.voice3,
      measure.voice4,
    ]) {
      for (final element in voice) {
        if (element is NoteElement &&
            element.id != null &&
            want.contains(element.id)) {
          for (final pitch in element.pitches) {
            out.add(pitch.midiNumber);
          }
        }
      }
    }
  }
  return out;
}

/// Flattens [score] into a timeline of element onsets sorted by start
/// (ties broken by voice), in exact whole-note [Fraction] time.
///
/// With [expandRepeats] (default), the score is linearized into performance
/// order: repeat barlines play their segment twice and voltas select their
/// pass (a `volta: 1` measure plays only on the first pass, `volta: 2` only
/// on the second; one listing several passes plays on each), nested repeats
/// expand via a stack (the inner repeat completes before the outer jumps
/// back), and navigation marks execute
/// their jumps (see [_navExpandedOrder] for the
/// supported D.C. / D.S. / To Coda / Fine semantics). Ties stay separate
/// entries — highlight both noteheads while the sound sustains. Grace notes
/// carry no time of their own. An element id appears once per pass, so ids
/// can repeat in the returned list when repeats or jumps are expanded.
///
/// With `expandRepeats: false` the measures play once in document order and
/// all repeat/navigation structure is ignored.
///
/// With [voiceChordSymbols], every chord symbol also sounds, as a block chord
/// in root position from middle C up (a slash bass below it) — the
/// way LilyPond's MIDI plays a ChordNames track — from the note it stands
/// over until the next symbol (the last until the end). Those entries carry
/// [PlaybackNote.chordPitches] and [PlaybackNote.voice] 4.
List<PlaybackNote> playbackTimeline(Score score,
    {bool expandRepeats = true, bool voiceChordSymbols = false}) {
  final measures = score.measures;
  final order = expandRepeats
      ? _navExpandedOrder(measures)
      : [for (var i = 0; i < measures.length; i++) i];

  final result = <PlaybackNote>[];
  var measureStart = Fraction(0, 1);
  var meter = score.timeSignature;
  for (final index in order) {
    // A measure-repeat bar (a simile sign) sounds the bar it repeats; with
    // repeats unexpanded it stays silent, as LilyPond's default MIDI plays a
    // percent repeat.
    final measure =
        measures[expandRepeats ? _measureRepeatSource(measures, index) : index];
    meter = measures[index].timeChange ?? meter;

    // A voice that is one whole rest rests the whole bar, whatever the meter
    // (a whole rest in 9/8 or 3/8 is a bar rest, by convention).
    final bar = measure.capacityGiven(meter);
    Fraction durationAt(List<MusicElement> voice, int i, int v) =>
        bar != null && voice.length == 1 && _isBarRest(voice.single)
            ? bar
            : measure.effectiveDurationAt(i, voice: v);

    var voice1End = measureStart;
    var clock = measureStart;
    for (var i = 0; i < measure.elements.length; i++) {
      final element = measure.elements[i];
      final duration = durationAt(measure.elements, i, 0);
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
    for (var i = 0; i < measure.voice2.length; i++) {
      final element = measure.voice2[i];
      final duration = durationAt(measure.voice2, i, 1);
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

    // Voices 3–4 — now tuplet-aware too (via effectiveDurationAt per voice).
    final extraEnds = <Fraction>[];
    for (final (v, elements) in [(2, measure.voice3), (3, measure.voice4)]) {
      clock = measureStart;
      for (var i = 0; i < elements.length; i++) {
        final element = elements[i];
        final duration = durationAt(elements, i, v);
        if (element.id != null) {
          result.add(PlaybackNote(
            elementId: element.id!,
            start: clock,
            duration: duration,
            isRest: element is RestElement,
            voice: v,
            measureIndex: index,
          ));
        }
        clock = clock + duration;
      }
      extraEnds.add(clock);
    }

    var measureEnd = [voice1End, voice2End, ...extraEnds]
        .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    if (measure.multiRest != null && meter != null) {
      // A multi-measure rest lasts its N bars, whatever anchor rest it keeps.
      measureEnd = measureStart +
          Fraction(meter.beats * measure.multiRest!, meter.beatUnit);
    } else if (measureEnd == measureStart && meter != null) {
      // Empty measure: advance by the current meter.
      measureEnd = measureStart + Fraction(meter.beats, meter.beatUnit);
    }
    measureStart = measureEnd;
  }

  if (voiceChordSymbols && score.chordSymbols.isNotEmpty) {
    result.addAll(_voicedChordSymbols(score, result));
  }
  result.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    return a.voice.compareTo(b.voice);
  });
  return result;
}

/// Semitones above the root of each [ChordSymbolKind], in root position.
const _chordIntervals = {
  ChordSymbolKind.major: [0, 4, 7],
  ChordSymbolKind.minor: [0, 3, 7],
  ChordSymbolKind.diminished: [0, 3, 6],
  ChordSymbolKind.augmented: [0, 4, 8],
  ChordSymbolKind.dominantSeventh: [0, 4, 7, 10],
  ChordSymbolKind.majorSeventh: [0, 4, 7, 11],
  ChordSymbolKind.minorSeventh: [0, 3, 7, 10],
  ChordSymbolKind.halfDiminishedSeventh: [0, 3, 6, 10],
  ChordSymbolKind.diminishedSeventh: [0, 3, 6, 9],
  ChordSymbolKind.minorMajorSeventh: [0, 3, 7, 11],
  ChordSymbolKind.sixth: [0, 4, 7, 9],
  ChordSymbolKind.minorSixth: [0, 3, 7, 9],
  ChordSymbolKind.dominantNinth: [0, 4, 7, 10, 14],
  ChordSymbolKind.suspendedFourth: [0, 5, 7],
  ChordSymbolKind.suspendedSecond: [0, 2, 7],
};

/// One entry per sounding of each chord symbol's note in [timeline]: the
/// chord's pitches, held until the next chord symbol starts.
List<PlaybackNote> _voicedChordSymbols(
    Score score, List<PlaybackNote> timeline) {
  final symbolOf = {for (final c in score.chordSymbols) c.elementId: c};
  final hits = [
    for (final n in timeline)
      if (symbolOf[n.elementId] case final c?) (n, c),
  ]..sort((a, b) => a.$1.start.compareTo(b.$1.start));
  if (hits.isEmpty) return const [];
  final end =
      timeline.fold<Fraction>(Fraction.zero, (e, n) => n.end > e ? n.end : e);
  return [
    for (var k = 0; k < hits.length; k++)
      if ((k + 1 < hits.length ? hits[k + 1].$1.start : end) - hits[k].$1.start
          case final length when length > Fraction.zero)
        PlaybackNote(
          elementId: hits[k].$1.elementId,
          start: hits[k].$1.start,
          duration: length,
          isRest: false,
          voice: 4,
          measureIndex: hits[k].$1.measureIndex,
          chordPitches: _chordPitches(hits[k].$2),
        ),
  ];
}

List<Pitch> _chordPitches(ChordSymbol chord) {
  // The root's pitch class from middle C up (MIDI 60 to 71), as LilyPond's
  // chord mode voices it; a slash bass stands just below the root.
  final root =
      60 + Pitch(chord.root.step, alter: chord.root.alter).midiNumber % 12;
  int? bass;
  if (chord.bass case final b?) {
    final below = (root - Pitch(b.step, alter: b.alter).midiNumber) % 12;
    bass = root - (below == 0 ? 12 : below);
  }
  return [
    if (bass != null) Pitch.fromMidi(bass),
    for (final i in _chordIntervals[chord.quality] ?? const [0, 4, 7])
      Pitch.fromMidi(root + i),
  ];
}

bool _isBarRest(MusicElement e) =>
    e is RestElement &&
    !e.hidden &&
    e.duration.base == DurationBase.whole &&
    e.duration.dots == 0;

/// One open repeat during expansion: where its `|:` sits and how many jumps
/// back it still owes. A plain repeat owes one (body plays twice); the `pass`
/// derived from the remaining jumps drives volta-bracket selection.
class _RepeatFrame {
  final int start;

  /// Jumps back this repeat still owes; one for a plain `:|` (body plays
  /// twice), more when its endings name later passes ("1., 2." then "3.").
  int jumpsLeft;

  /// The `:|` measure this frame jumped back from, once it has. A frame whose
  /// last pass ends in a volta bracket is never closed by its own `:|` (the
  /// final ending plays past it), so a LATER `:|` seeing an exhausted frame
  /// with a different end knows the frame is stale, not its own.
  int? end;
  _RepeatFrame(this.start, {int passes = 2})
      : _passes = passes,
        jumpsLeft = passes - 1;

  final int _passes;

  /// 1 on the first time through the body, 2 after the first jump back, …
  int get pass => _passes - jumpsLeft;
}

/// How many times the repeat whose body starts at [start] is played: twice,
/// or as often as the highest pass its endings name — an ending marked
/// "1., 2." followed by "3." plays the body three times.
int _repeatPasses(List<Measure> measures, int start) {
  var end = start;
  while (end < measures.length && !measures[end].endRepeat) {
    end++;
  }
  if (end >= measures.length || measures[end].volta == null) return 2;
  // The run of endings around that `:|`: back to its first ending, then on
  // through the later ones (which may close with `:|` of their own).
  var first = end;
  while (first > start && measures[first - 1].volta != null) {
    first--;
  }
  var last = end;
  while (last + 1 < measures.length &&
      measures[last + 1].volta != null &&
      !measures[last + 1].startRepeat) {
    last++;
  }
  var passes = 2;
  for (var k = first; k <= last; k++) {
    for (final pass in measures[k].voltaPasses) {
      passes = max(passes, pass);
    }
  }
  return passes;
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

/// The bar a measure-repeat bar at [index] sounds: the one [Measure.
/// measureRepeat] bars back, followed back through repeat signs; [index]
/// itself for an ordinary bar (or a sign with nothing before it).
int _measureRepeatSource(List<Measure> measures, int index) {
  var at = index;
  for (var guard = 0; guard < measures.length; guard++) {
    final n = measures[at].measureRepeat;
    if (n == null || at - n < 0) return at;
    at -= n;
  }
  return index;
}

/// The measure indices in performance order, expanding repeat barlines,
/// voltas and navigation-mark jumps.
///
/// Supported jump semantics (the common cases):
///
/// - **Repeat barlines** expand via a stack, so **nested** repeats
///   (`|: … |: … :| … :|`) unfold correctly — the inner repeat completes each
///   time before the outer jumps back. **Voltas** select their bracket by the
///   enclosing repeat's pass number.
/// - An **end repeat with no matching start** (`… :|` with no `|:` before it,
///   the usual way a piece's opening section is written) repeats from the end
///   of the previous repeated section — the measure after the last closed
///   `:|` or final volta ending — or from the first measure if there is none.
/// - **D.C.** (da capo) returns to the first measure; **D.S.** (dal segno)
///   returns to the [NavigationMark.segno] measure. The instruction sits at
///   the end of its measure (that measure is played, then the jump happens),
///   and fires **once**.
/// - **al Fine** variants stop after the [NavigationMark.fine] measure (which
///   is otherwise ignored on the first pass); **al Coda** variants arm the
///   [NavigationMark.toCoda] mark so that the next time it is reached, play
///   jumps to the [NavigationMark.coda] measure and continues to the end.
/// - After a D.C./D.S. return the score plays **straight through** — repeat
///   barlines and voltas are not re-expanded (their brackets are moot on the
///   return pass). This is the standard "play repeats off on D.C./D.S."
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
  // A stack of active repeat frames so nested `|: … |: … :| … :|` structures
  // expand correctly (the inner repeat completes before the outer jumps back).
  // Each frame counts the jumps it still owes; a plain repeat owes one (so its
  // body plays twice). `pass` for a volta is the innermost frame's pass.
  final repeats = <_RepeatFrame>[];
  // Where an unmatched `:|` jumps back to: just past the last repeated
  // section (its closing `:|` or the final volta ending), else the top.
  var sectionStart = 0;
  var navReturned = false; // a D.C./D.S. jump has already fired
  var codaArmed = false; // an al Coda return is waiting for `toCoda`
  var stopAtFine = false; // an al Fine return will stop at `fine`
  final guardLimit = measures.length * 6 + 100;
  var guard = 0;

  while (i < measures.length) {
    // A cycle of jumps (malformed marks) stops playback where it is rather
    // than throwing: an imported score must still play.
    if (++guard > guardLimit) break;
    final measure = measures[i];
    final nav = measure.navigation;

    // Repeat/volta expansion runs only on the primary pass; after a
    // D.C./D.S. return the score plays straight through.
    if (!navReturned) {
      // Open a repeat frame on its start barline (but not when we have just
      // jumped back to it — the frame is already open).
      if (measure.startRepeat && (repeats.isEmpty || repeats.last.start != i)) {
        repeats.add(_RepeatFrame(i, passes: _repeatPasses(measures, i)));
      }
      // Play has moved past the final ending of an exhausted repeat: that
      // repeat is over, so its pass number must not select later voltas.
      while (repeats.isNotEmpty &&
          repeats.last.jumpsLeft == 0 &&
          measure.volta == null &&
          i > repeats.last.end!) {
        repeats.removeLast();
      }
      // A volta bracket is played only on its own pass of the enclosing repeat.
      final pass = repeats.isEmpty ? 1 : repeats.last.pass;
      final volta = measure.volta;
      if (volta != null && !measure.voltaPasses.contains(pass)) {
        i++;
        continue;
      }
      // The final ending of a volta-bracketed repeat closes that section.
      if (volta != null && repeats.isNotEmpty && repeats.last.jumpsLeft == 0) {
        sectionStart = i + 1;
      }
    }

    order.add(i);

    // Stop at Fine once an al Fine jump has armed it.
    if (stopAtFine && nav == NavigationMark.fine) break;

    // Jump to the coda once an al Coda jump has armed it.
    // With no coda to jump to, the "To Coda" mark is read as text and play
    // goes on: a file whose coda was lost still plays.
    if (codaArmed && nav == NavigationMark.toCoda && codaIndex != null) {
      codaArmed = false;
      i = codaIndex;
      continue;
    }

    // Repeat barline (primary pass only): jump back to the innermost open
    // repeat's start until it has paid its jumps, then close the frame.
    if (!navReturned && measure.endRepeat) {
      // An exhausted frame that ended at a different `:|` was closed by a volta
      // ending, not by this barline — drop it.
      while (repeats.isNotEmpty &&
          repeats.last.jumpsLeft == 0 &&
          repeats.last.end != i) {
        repeats.removeLast();
      }
      // No open `|:` — this `:|` implies one at the start of its section.
      if (repeats.isEmpty) {
        repeats.add(_RepeatFrame(sectionStart,
            passes: _repeatPasses(measures, sectionStart)));
      }
      final frame = repeats.last;
      if (frame.jumpsLeft > 0) {
        frame.jumpsLeft -= 1;
        frame.end = i;
        i = frame.start;
        continue;
      }
      repeats.removeLast();
      sectionStart = i + 1;
    }

    // D.C./D.S. return instruction — fires once, then plays straight through.
    if (!navReturned && (_isDaCapo(nav) || _isDalSegno(nav))) {
      navReturned = true;
      stopAtFine = _isAlFine(nav);
      codaArmed = _isAlCoda(nav);
      if (_isDalSegno(nav)) {
        // No segno: the D.S. is read as text and play goes on, as when a
        // file's sign was lost (a LilyPond source playing straight through).
        if (segnoIndex == null) {
          navReturned = false;
          stopAtFine = false;
          codaArmed = false;
          i++;
          continue;
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
