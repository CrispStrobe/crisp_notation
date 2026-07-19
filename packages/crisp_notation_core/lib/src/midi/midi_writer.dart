/// Standard MIDI File (SMF) export off the playback timeline.
///
/// Contract-safe: crisp_notation never produces audio — this emits a format-0
/// `.mid` byte stream (note on/off with tempo and time-signature meta) that a
/// consumer's own synth or DAW can play. It reuses [playbackTimeline], so
/// repeats, voltas and D.C./D.S./Coda jumps are unfolded into the MIDI just as
/// they are for the on-screen cursor.
library;

import 'dart:typed_data';

import '../model/element.dart';
import '../model/score.dart';
import '../playback/playback_timeline.dart';
import '../theory/fraction.dart';

/// Default note-on velocity — used for a note with no dynamic in force. Equal
/// to mezzo-forte, so a score that carries no dynamics exports byte-for-byte as
/// before.
const int _velocity = 80;

/// Note-on velocity per graduated dynamic level. `mf` == [_velocity] so an
/// unmarked score is unchanged. Levels absent here fall back to [_velocity].
const Map<DynamicLevel, int> _dynamicVelocity = {
  DynamicLevel.pppp: 8,
  DynamicLevel.ppp: 20,
  DynamicLevel.pp: 33,
  DynamicLevel.p: 49,
  DynamicLevel.mp: 64,
  DynamicLevel.mf: 80,
  DynamicLevel.f: 96,
  DynamicLevel.ff: 112,
  DynamicLevel.fff: 122,
  DynamicLevel.ffff: 127,
  // Accent-type marks — a strong attack on that one note (see [_momentary]).
  DynamicLevel.sf: 112,
  DynamicLevel.sfz: 118,
  DynamicLevel.sffz: 124,
  DynamicLevel.fz: 112,
  DynamicLevel.rf: 100,
  DynamicLevel.fp: 96, // forte attack; the piano tail isn't modeled
};

/// Dynamics that accent a single note rather than setting a lasting level — so
/// they do NOT carry forward to following notes the way p/f/… do.
const Set<DynamicLevel> _momentary = {
  DynamicLevel.sf,
  DynamicLevel.sfz,
  DynamicLevel.sffz,
  DynamicLevel.fz,
  DynamicLevel.rf,
  DynamicLevel.fp,
};

/// Serializes [score] to Standard MIDI File (format 0) bytes.
///
/// [quarterBpm] sets the single tempo (quarter-note beats per minute). When
/// omitted it falls back to the score's own [Score.tempo] (normalized to
/// quarter-notes-per-minute), then to 120 — so an exported file plays at the
/// notated tempo instead of a fixed default. [ticksPerQuarter] is the file's
/// timing resolution (480 divides the common tuplets cleanly). Voice 1 is
/// written on MIDI channel 0, voice 2 on channel 1. Chords emit one note per
/// pitch. The timeline is unfolded ([playbackTimeline]), so a two-bar repeat
/// exports as four bars of notes. Grace notes carry no time and are omitted.
/// Deterministic.
Uint8List scoreToMidi(
  Score score, {
  double? quarterBpm,
  int ticksPerQuarter = 480,
}) {
  final bpm = quarterBpm ?? score.tempo?.quarterBpm ?? 120;
  final byId = <String, NoteElement>{};
  for (final measure in score.measures) {
    for (final element in [...measure.elements, ...measure.voice2]) {
      if (element is NoteElement && element.id != null) {
        byId[element.id!] = element;
      }
    }
  }

  // (tick, order, sequence, bytes). `order` groups events at the same tick:
  // meta (0) before note-off (1) before note-on (2) before end-of-track (3).
  final events = <(int, int, int, List<int>)>[];
  var seq = 0;
  void add(int tick, int order, List<int> bytes) {
    events.add((tick, order, seq++, bytes));
  }

  // Tempo meta: microseconds per quarter note.
  final usPerQuarter = (60000000 / bpm).round();
  add(0, 0, [
    0xFF, 0x51, 0x03, //
    (usPerQuarter >> 16) & 0xFF,
    (usPerQuarter >> 8) & 0xFF,
    usPerQuarter & 0xFF,
  ]);

  // Time-signature meta (only when the score is metered).
  final ts = score.timeSignature;
  if (ts != null) {
    add(0, 0, [
      0xFF, 0x58, 0x04, //
      ts.beats,
      _log2(ts.beatUnit),
      24, // MIDI clocks per metronome click
      8, // 32nd notes per quarter
    ]);
  }

  // Dynamics reach velocity: a graduated mark (p/f/…) sets a level that lasts
  // until the next one (tracked in timeline order below); an accent mark
  // (sf/sfz/fp/…) hits only its own note. Accent/marcato articulations bump the
  // attack; staccato shortens the note-off. A score with neither is unchanged.
  final dynAt = <String, DynamicLevel>{
    for (final d in score.dynamics) d.elementId: d.level,
  };
  var level = DynamicLevel.mf; // the default → _velocity

  var maxTick = 0;
  var lastMeasure = -1;
  var currentUs = usPerQuarter; // µs/quarter currently in effect
  for (final note in playbackTimeline(score)) {
    // Mid-score tempo changes: on entering a measure whose `Measure.tempoChange`
    // differs from the tempo currently in effect, emit a tempo meta at its
    // (unfolded) start tick — so an accelerando/ritardando is exported, and a
    // repeat's tempo carries forward like a performer would take it. Checked
    // before the rest-skip because a measure can begin with a rest.
    if (note.measureIndex != lastMeasure) {
      lastMeasure = note.measureIndex;
      final change = note.measureIndex < score.measures.length
          ? score.measures[note.measureIndex].tempoChange
          : null;
      if (change != null) {
        final us = (60000000 / change.quarterBpm).round();
        if (us != currentUs) {
          add(_ticks(note.start, ticksPerQuarter), 0, [
            0xFF, 0x51, 0x03, //
            (us >> 16) & 0xFF,
            (us >> 8) & 0xFF,
            us & 0xFF,
          ]);
          currentUs = us;
        }
      }
    }
    if (note.isRest) continue;
    final element = byId[note.elementId];
    if (element == null) continue;

    final mark = dynAt[element.id];
    int baseVelocity;
    if (mark == null) {
      baseVelocity = _dynamicVelocity[level] ?? _velocity;
    } else if (_momentary.contains(mark)) {
      baseVelocity = _dynamicVelocity[mark] ?? _velocity; // one-note accent
    } else {
      level = mark; // lasting change
      baseVelocity = _dynamicVelocity[mark] ?? _velocity;
    }
    if (element.articulations.contains(Articulation.marcato)) {
      baseVelocity += 20;
    } else if (element.articulations.contains(Articulation.accent)) {
      baseVelocity += 15;
    }
    final velocity = baseVelocity.clamp(1, 127);

    final channel = note.voice == 1 ? 1 : 0;
    final onTick = _ticks(note.start, ticksPerQuarter);
    var durTicks = _ticks(note.duration, ticksPerQuarter);
    // Staccato: detach the note by cutting its sounding length ~in half.
    if (element.articulations.contains(Articulation.staccato)) {
      durTicks = (durTicks * 0.5).round();
    }
    final offTick = onTick + (durTicks < 1 ? 1 : durTicks);
    if (offTick > maxTick) maxTick = offTick;
    for (final pitch in element.pitches) {
      final key = pitch.midiNumber.clamp(0, 127);
      add(onTick, 2, [0x90 | channel, key, velocity]);
      add(offTick, 1, [0x80 | channel, key, 0x40]);
    }
  }

  add(maxTick, 3, [0xFF, 0x2F, 0x00]); // end of track

  events.sort((a, b) {
    if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
    if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
    return a.$3.compareTo(b.$3);
  });

  final track = <int>[];
  var previous = 0;
  for (final (tick, _, _, bytes) in events) {
    _writeVarLen(track, tick - previous);
    track.addAll(bytes);
    previous = tick;
  }

  final out = <int>[];
  out.addAll(const [0x4D, 0x54, 0x68, 0x64]); // "MThd"
  _writeUint32(out, 6);
  _writeUint16(out, 0); // format 0
  _writeUint16(out, 1); // one track
  _writeUint16(out, ticksPerQuarter);
  out.addAll(const [0x4D, 0x54, 0x72, 0x6B]); // "MTrk"
  _writeUint32(out, track.length);
  out.addAll(track);
  return Uint8List.fromList(out);
}

/// Rounds a whole-note [time] to an integer tick count (a whole note is
/// 4 × [ticksPerQuarter]). Exact rational rounding, no floating point.
int _ticks(Fraction time, int ticksPerQuarter) {
  final num = time.numerator * 4 * ticksPerQuarter;
  final den = time.denominator;
  return (num + den ~/ 2) ~/ den;
}

int _log2(int value) {
  var v = value;
  var result = 0;
  while (v > 1) {
    v >>= 1;
    result++;
  }
  return result;
}

void _writeVarLen(List<int> out, int value) {
  var v = value < 0 ? 0 : value;
  final buffer = <int>[v & 0x7F];
  v >>= 7;
  while (v > 0) {
    buffer.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.addAll(buffer.reversed);
}

void _writeUint32(List<int> out, int value) {
  out.add((value >> 24) & 0xFF);
  out.add((value >> 16) & 0xFF);
  out.add((value >> 8) & 0xFF);
  out.add(value & 0xFF);
}

void _writeUint16(List<int> out, int value) {
  out.add((value >> 8) & 0xFF);
  out.add(value & 0xFF);
}
