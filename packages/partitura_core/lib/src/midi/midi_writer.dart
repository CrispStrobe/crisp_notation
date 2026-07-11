/// Standard MIDI File (SMF) export off the playback timeline.
///
/// Contract-safe: partitura never produces audio — this emits a format-0
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

/// Note-on velocity used for every exported note.
const int _velocity = 80;

/// Serializes [score] to Standard MIDI File (format 0) bytes.
///
/// [quarterBpm] sets the single tempo (quarter-note beats per minute);
/// [ticksPerQuarter] is the file's timing resolution (480 divides the common
/// tuplets cleanly). Voice 1 is written on MIDI channel 0, voice 2 on channel
/// 1. Chords emit one note per pitch. The timeline is unfolded
/// ([playbackTimeline]), so a two-bar repeat exports as four bars of notes.
/// Grace notes carry no time and are omitted. Deterministic.
Uint8List scoreToMidi(
  Score score, {
  double quarterBpm = 120,
  int ticksPerQuarter = 480,
}) {
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
  final usPerQuarter = (60000000 / quarterBpm).round();
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

  var maxTick = 0;
  for (final note in playbackTimeline(score)) {
    if (note.isRest) continue;
    final element = byId[note.elementId];
    if (element == null) continue;
    final channel = note.voice == 1 ? 1 : 0;
    final onTick = _ticks(note.start, ticksPerQuarter);
    final durTicks = _ticks(note.duration, ticksPerQuarter);
    final offTick = onTick + (durTicks < 1 ? 1 : durTicks);
    if (offTick > maxTick) maxTick = offTick;
    for (final pitch in element.pitches) {
      final key = pitch.midiNumber.clamp(0, 127);
      add(onTick, 2, [0x90 | channel, key, _velocity]);
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
