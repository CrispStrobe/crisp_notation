/// Standard MIDI File (SMF) import → [Score].
///
/// This is a **lossy** decoder: MIDI carries no note spelling, clef, key
/// signature, beaming, ties, articulations or voices, so the result is a
/// single-staff, single-voice reconstruction — pitches spelled with sharps in
/// the treble clef, onsets and durations quantized to a sixteenth-note grid,
/// simultaneous notes merged into chords, and durations packed into measures
/// (by the file's time signature, default 4/4) with ties across barlines.
/// It round-trips the *pitches and quantized rhythm* of simple scores; it is
/// not a faithful inverse of every notated detail.
library;

import 'dart:typed_data';

import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/pitch.dart';
import '../theory/time_signature.dart';

/// One decoded note: absolute start/end ticks and MIDI key.
class _Note {
  final int start;
  final int end;
  final int key;
  _Note(this.start, this.end, this.key);
}

/// One reconstructed event: a chord (or rest) of a whole number of
/// sixteenth-note units.
class _Ev {
  final bool isRest;
  final int units;
  final List<int> keys; // sorted MIDI keys (empty for a rest)
  _Ev(this.isRest, this.units, this.keys);
}

/// Parses Standard MIDI File [bytes] into a [Score].
///
/// Supports format 0 and 1 (all tracks are merged into one part). Throws a
/// [FormatException] on a malformed file or an unsupported SMPTE (negative)
/// division. See the library doc for the lossy reconstruction rules.
Score scoreFromMidi(Uint8List bytes) {
  final r = _ByteReader(bytes);
  if (!r.matchAscii('MThd')) {
    throw const FormatException('not a MIDI file (missing MThd)');
  }
  final headerLen = r.u32();
  if (headerLen < 6) throw const FormatException('bad MThd length');
  r.u16(); // format (0/1/2 — treated the same: merge all tracks)
  final ntrks = r.u16();
  final division = r.u16();
  r.skip(headerLen - 6);
  if (division & 0x8000 != 0 || division == 0) {
    throw const FormatException('unsupported MIDI division (SMPTE or zero)');
  }
  final tpq = division;

  final notes = <_Note>[];
  TimeSignature? timeSignature;

  for (var t = 0; t < ntrks; t++) {
    if (!r.matchAscii('MTrk')) {
      throw const FormatException('malformed track (missing MTrk)');
    }
    final len = r.u32();
    final trackEnd = r.pos + len;
    var tick = 0;
    int? status;
    // (channel << 8 | key) -> queue of note-on start ticks (FIFO).
    final pending = <int, List<int>>{};

    void noteOn(int channel, int key, int velocity) {
      if (velocity == 0) {
        _noteOff(pending, notes, channel, key, tick);
      } else {
        pending.putIfAbsent(channel << 8 | key, () => <int>[]).add(tick);
      }
    }

    while (r.pos < trackEnd) {
      tick += r.varLen();
      var b = r.u8();
      if (b < 0x80) {
        if (status == null) {
          throw const FormatException('running status with no prior status');
        }
        r.pos--; // the byte is data; reuse the running status
        b = status;
      } else if (b < 0xF0) {
        status = b;
      }

      if (b == 0xFF) {
        final type = r.u8();
        final mlen = r.varLen();
        final data = r.take(mlen);
        if (type == 0x58 && data.length >= 2) {
          timeSignature ??= TimeSignature(data[0], 1 << data[1]);
        }
        continue;
      } else if (b == 0xF0 || b == 0xF7) {
        r.skip(r.varLen());
        continue;
      }

      final message = b & 0xF0;
      final channel = b & 0x0F;
      switch (message) {
        case 0x80:
          final key = r.u8();
          r.u8();
          _noteOff(pending, notes, channel, key, tick);
        case 0x90:
          final key = r.u8();
          noteOn(channel, key, r.u8());
        case 0xA0:
        case 0xB0:
        case 0xE0:
          r.u8();
          r.u8();
        case 0xC0:
        case 0xD0:
          r.u8();
        default:
          throw FormatException(
              'unexpected MIDI status 0x${b.toRadixString(16)}');
      }
    }
    r.pos = trackEnd;
  }

  final ts = timeSignature ?? TimeSignature.fourFour;
  return _buildScore(notes, tpq, ts);
}

/// Resolves a note-off against the earliest matching pending note-on.
void _noteOff(Map<int, List<int>> pending, List<_Note> notes, int channel,
    int key, int tick) {
  final queue = pending[channel << 8 | key];
  if (queue == null || queue.isEmpty) return;
  final start = queue.removeAt(0);
  if (tick > start) notes.add(_Note(start, tick, key));
}

Score _buildScore(List<_Note> notes, int tpq, TimeSignature ts) {
  final unitTicks = tpq / 4; // a sixteenth note, in ticks
  int toUnits(int ticks) => (ticks / unitTicks).round();

  // Group notes that start on the same grid unit into a chord; the group's
  // duration is its longest member.
  final groupKeys = <int, List<int>>{};
  final groupDur = <int, int>{};
  for (final note in notes) {
    final startUnit = toUnits(note.start);
    final dur = toUnits(note.end) - startUnit;
    final d = dur < 1 ? 1 : dur;
    (groupKeys[startUnit] ??= <int>[]).add(note.key);
    final existing = groupDur[startUnit];
    groupDur[startUnit] = existing == null || d > existing ? d : existing;
  }

  final onsets = groupKeys.keys.toList()..sort();
  final events = <_Ev>[];
  var cursor = 0;
  for (var i = 0; i < onsets.length; i++) {
    final u = onsets[i];
    if (u > cursor) {
      events.add(_Ev(true, u - cursor, const []));
      cursor = u;
    }
    final next = i + 1 < onsets.length ? onsets[i + 1] : u + groupDur[u]!;
    var dur = groupDur[u]!;
    if (dur > next - u) dur = next - u;
    if (dur < 1) dur = 1;
    events.add(_Ev(false, dur, groupKeys[u]!..sort()));
    cursor = u + dur;
  }

  final cap = ts.beats * 16 ~/ ts.beatUnit; // sixteenth units per measure
  final measures = <Measure>[];
  var current = <MusicElement>[];
  var filled = 0;
  var idCounter = 0;

  for (final ev in events) {
    // Split the event across barlines and into binary note values, so ties
    // can bind the fragments of one sounding note.
    final fragments = <int>[]; // each a power-of-two unit count
    var remaining = ev.units;
    var probe = filled;
    while (remaining > 0) {
      final space = cap - probe;
      final take = remaining < space ? remaining : space;
      fragments.addAll(_decomposeUnits(take));
      remaining -= take;
      probe += take;
      if (probe == cap) probe = 0;
    }

    for (var k = 0; k < fragments.length; k++) {
      final duration = _durationOfUnits(fragments[k]);
      final id = 'e${idCounter++}';
      if (ev.isRest) {
        current.add(RestElement(duration, id: id));
      } else {
        current.add(NoteElement(
          pitches: [for (final key in ev.keys) _pitchFromMidi(key)],
          duration: duration,
          tieToNext: k != fragments.length - 1,
          id: id,
        ));
      }
      filled += fragments[k];
      if (filled == cap) {
        measures.add(Measure(current));
        current = <MusicElement>[];
        filled = 0;
      }
    }
  }
  if (current.isNotEmpty) measures.add(Measure(current));
  if (measures.isEmpty) {
    measures.add(Measure([RestElement(NoteDuration.whole, id: 'e0')]));
  }

  return Score(clef: Clef.treble, timeSignature: ts, measures: measures);
}

/// Decomposes [units] sixteenth-note units into a descending list of
/// power-of-two note-value sizes (16 = whole … 1 = sixteenth).
List<int> _decomposeUnits(int units) {
  final out = <int>[];
  var remaining = units;
  for (final size in const [16, 8, 4, 2, 1]) {
    while (remaining >= size) {
      out.add(size);
      remaining -= size;
    }
  }
  return out;
}

NoteDuration _durationOfUnits(int units) => switch (units) {
      16 => NoteDuration.whole,
      8 => NoteDuration.half,
      4 => NoteDuration.quarter,
      2 => NoteDuration.eighth,
      _ => NoteDuration.sixteenth,
    };

/// Spells a MIDI key as a [Pitch] using sharps (the common default).
Pitch _pitchFromMidi(int key) {
  const table = [
    (Step.c, 0), (Step.c, 1), (Step.d, 0), (Step.d, 1), //
    (Step.e, 0), (Step.f, 0), (Step.f, 1), (Step.g, 0),
    (Step.g, 1), (Step.a, 0), (Step.a, 1), (Step.b, 0),
  ];
  final (step, alter) = table[key % 12];
  return Pitch(step, alter: alter, octave: key ~/ 12 - 1);
}

/// A minimal big-endian byte cursor over a [Uint8List].
class _ByteReader {
  final Uint8List bytes;
  int pos = 0;
  _ByteReader(this.bytes);

  int u8() {
    if (pos >= bytes.length) throw const FormatException('unexpected end');
    return bytes[pos++];
  }

  int u16() => (u8() << 8) | u8();

  int u32() => (u8() << 24) | (u8() << 16) | (u8() << 8) | u8();

  /// Reads a MIDI variable-length quantity.
  int varLen() {
    var value = 0;
    for (var i = 0; i < 4; i++) {
      final b = u8();
      value = (value << 7) | (b & 0x7F);
      if (b & 0x80 == 0) return value;
    }
    throw const FormatException('variable-length quantity too long');
  }

  List<int> take(int n) {
    if (pos + n > bytes.length) throw const FormatException('unexpected end');
    final slice = bytes.sublist(pos, pos + n);
    pos += n;
    return slice;
  }

  void skip(int n) => pos += n;

  bool matchAscii(String tag) {
    if (pos + tag.length > bytes.length) return false;
    for (var i = 0; i < tag.length; i++) {
      if (bytes[pos + i] != tag.codeUnitAt(i)) return false;
    }
    pos += tag.length;
    return true;
  }
}
