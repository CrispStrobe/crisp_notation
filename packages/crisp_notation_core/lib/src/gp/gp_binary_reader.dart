/// Reader for the legacy GPIF binary formats `.gp3`, `.gp4` and `.gp5`.
///
/// This is an independent, clean-room implementation written from the
/// **publicly documented** byte layout of the GPIF container — the
/// community reverse-engineering references (dGuitar's *GP4 File Format
/// Description*, the editor-on-fire *GP5.10 format* notes, TadaoYamaoka's
/// Kaitai `gp5_file_format` spec and the TuxGuitar file-format
/// documentation) — cross-checked byte-for-byte against
/// the vendored fixture corpus in `crisp_notation_cli/test/data/gp`. A file format's
/// on-disk layout is factual, not authored; nothing here is derived from any
/// particular decoder's source code.
///
/// The reader decodes the version header, the (skipped-but-aligned) score-info,
/// notice, lyric, RSE, page-setup and mix-table blocks, per-track tunings, the
/// master-bar table (time signatures and repeats) and, per beat, notes as
/// **string + fret → pitch** through each track's tuning — with durations,
/// rests, chords and the common playing techniques (bend, slide → glissando,
/// hammer-on/pull-off → slur, vibrato, palm-mute, let-ring, dead note and the
/// natural / artificial / pinch harmonics). Blocks the model does not represent
/// are parsed only as far as needed to stay byte-aligned, then discarded.
///
/// Web-safe: depends only on `dart:typed_data` and the repository's own model
/// and theory libraries.
library;

import 'dart:typed_data';

import '../layout/multi_part.dart';
import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/pitch.dart';
import '../theory/time_signature.dart';

/// Parses a `.gp5` file (version tag `v5.x`) into a [Score], reading the
/// [trackIndex]-th track (default 0).
Score gp5ToScore(Uint8List bytes, {int trackIndex = 0}) =>
    _GpReader(bytes, trackIndex).read();

/// Parses a `.gp4` file (version tag `v4.x`) into a [Score].
Score gp4ToScore(Uint8List bytes, {int trackIndex = 0}) =>
    _GpReader(bytes, trackIndex).read();

/// Parses a `.gp3` file (version tag `v3.x`) into a [Score].
Score gp3ToScore(Uint8List bytes, {int trackIndex = 0}) =>
    _GpReader(bytes, trackIndex).read();

/// Parses a GPIF `.gp3`/`.gp4`/`.gp5` file into a [MultiPartScore] — one
/// part per track (the `gpNToScore` helpers read a single [trackIndex]). The
/// version is auto-detected, so this covers all three. Track 0 is parsed first
/// to learn the track count, then each remaining track is read.
MultiPartScore gpToMultiPart(Uint8List bytes) {
  final probe = _GpReader(bytes, 0);
  final parts = <Score>[probe.read()]; // reading sets probe.trackCount
  for (var t = 1; t < probe.trackCount; t++) {
    parts.add(_GpReader(bytes, t).read());
  }
  return MultiPartScore(parts);
}

/// Sequential little-endian cursor over a GPIF byte buffer. Reading past
/// the end throws a [FormatException] rather than returning zeros or looping.
class _Cursor {
  final Uint8List _b;
  int _p = 0;

  _Cursor(this._b);

  bool get atEnd => _p >= _b.length;

  int _need(int n) {
    if (_p + n > _b.length) {
      throw FormatException(
          'GPIF data ends mid-record (need $n byte(s) at offset $_p)');
    }
    return _p;
  }

  int u8() {
    final at = _need(1);
    _p += 1;
    return _b[at];
  }

  int s8() {
    final v = u8();
    return v >= 128 ? v - 256 : v;
  }

  int i16() {
    final at = _need(2);
    _p += 2;
    return _b[at] | (_b[at + 1] << 8);
  }

  int i32() {
    final at = _need(4);
    _p += 4;
    final v =
        _b[at] | (_b[at + 1] << 8) | (_b[at + 2] << 16) | (_b[at + 3] << 24);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  void skip(int n) {
    _need(n);
    _p += n;
  }

  /// A byte-length-prefixed string stored in a fixed [field]-byte area: one
  /// length byte, then exactly [field] content bytes (the string is the first
  /// `length` of them).
  String fixedString(int field) {
    final len = u8();
    _need(field);
    final take = len < field ? len : field;
    final s = String.fromCharCodes(_b, _p, _p + take);
    _p += field;
    return s;
  }

  /// A string prefixed by a 32-bit total length and an inner byte length
  /// (`int totalLen`, `byte strLen`, `strLen` bytes). Common to the score-info
  /// and template blocks.
  String intByteString() {
    i32();
    final len = u8();
    _need(len);
    final s = String.fromCharCodes(_b, _p, _p + len);
    _p += len;
    return s;
  }

  /// A string prefixed only by a 32-bit length (`int len`, `len` bytes) — the
  /// lyric-line encoding.
  void skipIntString() {
    final len = i32();
    if (len > 0) skip(len);
  }
}

/// The natural-or-sharp spelling of a MIDI note number, matching the rest of
/// the importer stack (C, C♯, D, … B).
Pitch _pitchFromMidi(int key) {
  const table = [
    (Step.c, 0), (Step.c, 1), (Step.d, 0), (Step.d, 1), //
    (Step.e, 0), (Step.f, 0), (Step.f, 1), (Step.g, 0),
    (Step.g, 1), (Step.a, 0), (Step.a, 1), (Step.b, 0),
  ];
  final (step, alter) = table[key % 12];
  return Pitch(step, alter: alter, octave: key ~/ 12 - 1);
}

/// The rhythmic base for a GPIF duration code (whole = −2 … 64th = 4).
DurationBase _durationBase(int code) {
  switch (code) {
    case -2:
      return DurationBase.whole;
    case -1:
      return DurationBase.half;
    case 0:
      return DurationBase.quarter;
    case 1:
      return DurationBase.eighth;
    case 2:
      return DurationBase.sixteenth;
    case 3:
      return DurationBase.thirtySecond;
    case 4:
      return DurationBase.sixtyFourth;
    default:
      return DurationBase.quarter;
  }
}

/// Per-note decode result, used to attach techniques after the element (and
/// its id) exists.
class _Note {
  final int string;
  final int fret;
  final int type; // 1 normal, 2 tie, 3 dead
  bool bend = false;
  bool hammer = false;
  bool slide = false;
  bool letRing = false;
  bool palmMute = false;
  bool vibrato = false;
  TabNoteStyle? harmonic;

  _Note(this.string, this.fret, this.type);
}

/// Whether a beat's beat-level effects imply a vibrato and/or a (natural)
/// harmonic — the form `.gp3` uses for effects that later formats moved onto
/// the note.
class _BeatFx {
  final bool vibrato;
  final bool harmonic;
  const _BeatFx(this.vibrato, this.harmonic);
}

/// A single-pass decoder for one GPIF binary file.
class _GpReader {
  final _Cursor c;
  final int trackIndex;

  late final bool v3;
  late final bool v4;
  late final bool v5;
  late final bool v510;

  int measureCount = 0;
  int trackCount = 0;
  final List<TimeSignature?> _measureTime = [];

  // Per-track tunings (MIDI, tuning order: index 0 = highest string).
  final List<List<int>> _tunings = [];

  // Output accumulators.
  final List<Measure> _measures = [];
  final List<Bend> _bends = [];
  final List<Slur> _slurs = [];
  final List<TabVoicing> _voicings = []; // preserve the file's human fingering
  final List<Glissando> _glissandos = [];
  final List<Vibrato> _vibratos = [];
  final Set<String> _vibratoIds = {};
  final List<PalmMute> _palmMutes = [];
  final List<LetRing> _letRings = [];
  final List<TabNoteMark> _tabNoteMarks = [];

  // A hammer-on/pull-off (slur) or slide (glissando) connects the beat that
  // carries it to the next note element in reading order.
  String? _pendingHammer;
  String? _pendingSlide;

  // Running palm-mute / let-ring bracket spans over consecutive notes.
  String? _pmStart, _pmPrev;
  String? _lrStart, _lrPrev;

  int _nextId = 0;

  _GpReader(Uint8List bytes, this.trackIndex) : c = _Cursor(bytes);

  String _newId() => 'e${_nextId++}';

  Score read() {
    _readHeader();
    _readMasterBars();
    _readTracks();
    _readBody();
    _flushSpans();

    final measures = _measures.isEmpty
        ? [
            const Measure([RestElement(NoteDuration.whole)])
          ]
        : _measures;
    return Score(
      clef: Clef.treble,
      timeSignature: _measureTime.isNotEmpty && _measureTime.first != null
          ? _measureTime.first
          : TimeSignature.fourFour,
      measures: measures,
      bends: _bends,
      slurs: _slurs,
      glissandos: _glissandos,
      vibratos: _vibratos,
      palmMutes: _palmMutes,
      letRings: _letRings,
      tabNoteMarks: _tabNoteMarks,
      tabVoicings: _voicings,
    );
  }

  // ---- Header ----------------------------------------------------------------

  void _readHeader() {
    final version = c.fixedString(30);
    v3 = version.contains('v3.');
    v4 = version.contains('v4.');
    v5 = version.contains('v5.');
    v510 = version.contains('v5.1');
    if (!v3 && !v4 && !v5) {
      throw FormatException('not a GPIF file: "$version"');
    }

    // Score information: title, subtitle, artist, album, (words, music) or
    // (author), copyright, tab author, instructions.
    final infoCount = v5 ? 9 : 8;
    for (var i = 0; i < infoCount; i++) {
      c.intByteString();
    }
    final notices = c.i32();
    for (var i = 0; i < notices; i++) {
      c.intByteString();
    }
    if (!v5) c.u8(); // global triplet-feel flag (gp3/gp4)

    if (v4 || v5) {
      // Lyrics: associated track, then 5 lines (start bar + int-string).
      c.i32();
      for (var i = 0; i < 5; i++) {
        c.i32();
        c.skipIntString();
      }
    }

    if (v510) {
      // RSE master effect: master volume, reserved int, 11 EQ/gain bytes.
      c.i32();
      c.i32();
      c.skip(11);
    }

    if (v5) {
      // Page setup: metrics, score proportion, header/footer bitmask, then the
      // header/footer template strings and a tempo-name string.
      c.skip(24);
      c.i32();
      c.i16();
      for (var i = 0; i < 10; i++) {
        c.intByteString();
      }
      c.intByteString(); // tempo name
    }

    c.i32(); // tempo
    if (v510) c.u8(); // hide-tempo flag

    if (v3) {
      c.i32(); // key signature
    } else {
      c.s8(); // key signature
      c.i32(); // octave
    }

    c.skip(64 * 12); // 64 MIDI channels × 12 bytes

    if (v5) {
      c.skip(19 * 2); // musical-direction symbol positions
      c.i32(); // master reverb
    }

    measureCount = c.i32();
    trackCount = c.i32();
  }

  // ---- Master bars -----------------------------------------------------------

  void _readMasterBars() {
    var num = 4, den = 4;
    for (var m = 0; m < measureCount; m++) {
      if (v5 && m > 0) c.u8(); // inter-bar separator

      final flags = c.u8();
      var timeChanged = false;
      if (flags & 0x01 != 0) {
        num = c.u8();
        timeChanged = true;
      }
      if (flags & 0x02 != 0) {
        den = c.u8();
        timeChanged = true;
      }
      if (flags & 0x08 != 0) c.u8(); // repeat-close count
      if (flags & 0x20 != 0) {
        c.intByteString(); // marker name
        c.skip(4); // marker colour
      }
      // gp3/gp4 carry the alternate-ending count inline; in gp5 it lives in the
      // fixed two-byte tail below (the alt-ending value when 0x10 is set, else a
      // pad byte — followed by the triplet-feel byte), so it is not read here.
      if (flags & 0x10 != 0 && !v5) c.u8(); // alternate-ending count
      if (flags & 0x40 != 0) {
        c.s8(); // key
        c.u8(); // major/minor
      }
      if (v5 && (flags & 0x03) != 0) c.skip(4); // beam-group bytes
      if (v5) c.skip(2); // alt-ending/pad byte + triplet-feel byte

      if (!timeChanged) {
        _measureTime.add(null);
      } else {
        // GUARD:gp-time-sig >>> malformed bytes can hand us a garbage
        // denominator (not a power of two in 1..16) that trips TimeSignature's
        // assertion with an uncatchable _AssertionError — reject cleanly instead.
        if (num < 1 ||
            num > 32 ||
            den < 1 ||
            den > 16 ||
            (den & (den - 1)) != 0) {
          throw FormatException('invalid GP time signature $num/$den');
        }
        // GUARD:gp-time-sig <<<
        _measureTime.add(TimeSignature(num, den));
      }
    }
  }

  // ---- Tracks ----------------------------------------------------------------

  void _readTracks() {
    for (var t = 0; t < trackCount; t++) {
      // Leading blank byte: before the first track always, and before every
      // track in v5.00 (v5.10 emits it only ahead of track 0). Mirrors the
      // version split the RSE-properties block below already makes.
      if (v5 && (t == 0 || !v510)) c.u8();
      c.u8(); // track flags
      c.fixedString(40); // name
      c.i32(); // string count
      final tuning = [for (var s = 0; s < 7; s++) c.i32()];
      c.i32(); // port
      c.i32(); // primary channel
      c.i32(); // effect channel
      c.i32(); // fret count
      c.i32(); // capo
      c.skip(4); // colour
      if (v5) {
        // RSE / track properties. v5.10 carries a 16-byte RSE instrument block
        // plus a 4-byte equalizer and two RSE effect strings; v5.00 has a
        // 15-byte instrument block, no equalizer and no effect strings.
        // (The v5.00 layout is documented but unverified — no v5.00 fixture.)
        c.skip(v510 ? 49 : 44);
        if (v510) {
          c.intByteString(); // RSE effect name
          c.intByteString(); // RSE effect category
        }
      }
      _tunings.add(tuning);
    }
    // Padding between the track list and the beat data: one byte in v5.10, two
    // in v5.00.
    final padding = v510 ? 1 : 2;
    for (var i = 0; i < padding && v5 && !c.atEnd; i++) {
      c.u8();
    }
  }

  List<int> get _tuning => trackIndex < _tunings.length
      ? _tunings[trackIndex]
      : const [64, 59, 55, 50, 45, 40, 0];

  int _tuningOf(int string) {
    final t = _tuning;
    return string < t.length ? t[string] : 0;
  }

  // ---- Body ------------------------------------------------------------------

  void _readBody() {
    final voices = v5 ? 2 : 1;
    for (var m = 0; m < measureCount; m++) {
      final elements = <MusicElement>[];
      final voice2 = <MusicElement>[];
      for (var t = 0; t < trackCount; t++) {
        for (var v = 0; v < voices; v++) {
          final primary = t == trackIndex && v == 0;
          final target = primary ? elements : (v == 1 ? voice2 : null);
          final beats = c.i32();
          for (var b = 0; b < beats; b++) {
            _readBeat(target, primary);
          }
        }
        if (v5 && !c.atEnd) c.u8(); // per-measure/track separator
      }
      _measures.add(Measure(
        elements,
        voice2: voice2,
        timeChange: m < _measureTime.length ? _measureTime[m] : null,
      ));
    }
  }

  void _readBeat(List<MusicElement>? target, bool primary) {
    final flags = c.u8();
    var rest = false;
    if (flags & 0x40 != 0) {
      c.u8(); // rest / empty status
      rest = true;
    }
    final durCode = c.s8();
    if (flags & 0x20 != 0) c.i32(); // tuplet
    if (flags & 0x02 != 0) _skipChord();
    if (flags & 0x04 != 0) c.intByteString(); // beat text

    var beatFx = const _BeatFx(false, false);
    if (flags & 0x08 != 0) beatFx = _readBeatEffects();
    if (flags & 0x10 != 0) _skipMixTable();

    final mask = c.u8();
    final notes = <_Note>[];
    for (var s = 0; s < 7; s++) {
      if (mask & (1 << (6 - s)) != 0) {
        notes.add(_readNote(s));
      }
    }
    if (v5) {
      // Beat trailer: a two-byte display-flags word; bit 0x0800 adds one byte.
      final beatFlags2 = c.i16();
      if (beatFlags2 & 0x0800 != 0) c.u8();
    }

    if (!primary || target == null) return;

    final duration = NoteDuration(
      _durationBase(durCode),
      dots: flags & 0x01 != 0 ? 1 : 0,
    );

    if (rest || notes.isEmpty) {
      final id = _newId();
      target.add(RestElement(duration, id: id));
      _advanceSpans(id, false, false);
      return;
    }

    // Keep (pitch, string) paired through the by-pitch sort so the string
    // assignment can be recorded as a TabVoicing (preserves the file's fingering).
    final placed = [
      for (final n in notes)
        (_pitchFromMidi(_tuningOf(n.string) + n.fret), n.string)
    ]..sort((a, b) => a.$1.midiNumber.compareTo(b.$1.midiNumber));
    final pitches = [for (final p in placed) p.$1];
    final id = _newId();
    target.add(NoteElement(pitches: pitches, duration: duration, id: id));
    _voicings.add(TabVoicing(id, [for (final p in placed) p.$2]));

    // A pending hammer / slide from an earlier beat resolves onto this note.
    if (_pendingHammer != null) {
      _slurs.add(Slur(_pendingHammer!, id));
      _pendingHammer = null;
    }
    if (_pendingSlide != null) {
      _glissandos.add(Glissando(_pendingSlide!, id));
      _pendingSlide = null;
    }

    var elementPalmMute = false, elementLetRing = false;
    var elementHammer = false, elementSlide = false;
    for (final n in notes) {
      if (n.type == 3) _tabNoteMarks.add(TabNoteMark(id, TabNoteStyle.dead));
      final harmonic =
          n.harmonic ?? (beatFx.harmonic ? TabNoteStyle.harmonic : null);
      if (harmonic != null) _tabNoteMarks.add(TabNoteMark(id, harmonic));
      if (n.bend) _bends.add(Bend(id));
      if ((n.vibrato || beatFx.vibrato) && _vibratoIds.add(id)) {
        _vibratos.add(Vibrato(id));
      }
      if (n.palmMute) elementPalmMute = true;
      if (n.letRing) elementLetRing = true;
      if (n.hammer) elementHammer = true;
      if (n.slide) elementSlide = true;
    }
    if (elementHammer) _pendingHammer = id;
    if (elementSlide) _pendingSlide = id;

    _advanceSpans(id, elementPalmMute, elementLetRing);
  }

  // ---- Palm-mute / let-ring bracket spans ------------------------------------

  void _advanceSpans(String id, bool palmMute, bool letRing) {
    if (palmMute) {
      _pmStart ??= id;
      _pmPrev = id;
    } else if (_pmStart != null) {
      _palmMutes.add(PalmMute(_pmStart!, _pmPrev!));
      _pmStart = _pmPrev = null;
    }
    if (letRing) {
      _lrStart ??= id;
      _lrPrev = id;
    } else if (_lrStart != null) {
      _letRings.add(LetRing(_lrStart!, _lrPrev!));
      _lrStart = _lrPrev = null;
    }
  }

  void _flushSpans() {
    if (_pmStart != null) _palmMutes.add(PalmMute(_pmStart!, _pmPrev!));
    if (_lrStart != null) _letRings.add(LetRing(_lrStart!, _lrPrev!));
    _pmStart = _pmPrev = _lrStart = _lrPrev = null;
  }

  // ---- Notes -----------------------------------------------------------------

  _Note _readNote(int string) {
    final flags = c.u8();
    var type = 1;
    if (flags & 0x20 != 0) type = c.u8();
    // gp3/4 place the time-independent duration (2 bytes) here, before the
    // dynamic; gp5 places it (an 8-byte double) AFTER the fingering — reading it
    // here fed the fret from the middle of that double, so a note with the flag
    // came back at a garbage pitch.
    if (!v5 && flags & 0x01 != 0) c.skip(2);
    if (flags & 0x10 != 0) c.u8(); // dynamic
    var fret = 0;
    if (flags & 0x20 != 0) fret = c.u8();
    if (flags & 0x80 != 0) c.skip(2); // left/right fingering
    if (v5 && flags & 0x01 != 0) c.skip(8); // gp5 time-independent duration
    if (v5) c.u8(); // gp5 second note-flags byte

    final note = _Note(string, fret, type);
    if (flags & 0x08 != 0) _readNoteEffects(note);
    return note;
  }

  void _readNoteEffects(_Note note) {
    if (v3) {
      final e = c.u8();
      if (e & 0x01 != 0) {
        note.bend = true;
        _skipBend();
      }
      if (e & 0x02 != 0) note.hammer = true;
      if (e & 0x04 != 0) note.slide = true;
      if (e & 0x08 != 0) note.letRing = true;
      if (e & 0x10 != 0) c.skip(4); // grace
      return;
    }

    final e1 = c.u8();
    final e2 = c.u8();
    if (e1 & 0x01 != 0) {
      note.bend = true;
      _skipBend();
    }
    if (e1 & 0x02 != 0) note.hammer = true;
    if (e1 & 0x08 != 0) note.letRing = true;
    if (e1 & 0x10 != 0) c.skip(v5 ? 5 : 4); // grace
    // e2 & 0x01: staccato (flag only)
    if (e2 & 0x02 != 0) note.palmMute = true;
    if (e2 & 0x04 != 0) c.u8(); // tremolo picking
    if (e2 & 0x08 != 0) {
      note.slide = true;
      c.u8(); // slide type
    }
    if (e2 & 0x10 != 0) note.harmonic = _readHarmonic();
    if (e2 & 0x20 != 0) c.skip(2); // trill
    if (e2 & 0x40 != 0) note.vibrato = true;
  }

  TabNoteStyle _readHarmonic() {
    final h = c.u8();
    if (v5) {
      // 1 natural, 2 artificial (+3 bytes), 3 tapped (+1), 4 pinch, 5 semi.
      switch (h) {
        case 2:
          c.skip(3);
          return TabNoteStyle.artificialHarmonic;
        case 3:
          c.u8();
          return TabNoteStyle.harmonic;
        case 4:
          return TabNoteStyle.pinchHarmonic;
        default:
          return TabNoteStyle.harmonic;
      }
    }
    // gp4: 1 natural, 3 tapped, 4 pinch, 5 semi, 15/17/22 artificial.
    if (h == 4) return TabNoteStyle.pinchHarmonic;
    if (h >= 15) return TabNoteStyle.artificialHarmonic;
    return TabNoteStyle.harmonic;
  }

  void _skipBend() {
    c.u8(); // type
    c.i32(); // value
    final points = c.i32();
    for (var i = 0; i < points; i++) {
      c.i32(); // position
      c.i32(); // value
      c.u8(); // vibrato
    }
  }

  // ---- Beat sub-blocks -------------------------------------------------------

  _BeatFx _readBeatEffects() {
    if (v3) {
      final b = c.u8();
      if (b & 0x20 != 0) {
        c.u8(); // string-effect kind
        c.i32(); // tremolo-bar / effect value
      }
      if (b & 0x40 != 0) c.skip(2); // stroke up/down
      final vibrato = b & 0x03 != 0;
      final harmonic = b & 0x0C != 0;
      return _BeatFx(vibrato, harmonic);
    }
    final b1 = c.u8();
    final b2 = c.u8();
    if (b1 & 0x20 != 0) c.u8(); // string-effect type
    if (b2 & 0x04 != 0) _skipBend(); // tremolo bar
    if (b1 & 0x40 != 0) c.skip(2); // stroke
    if (b2 & 0x02 != 0) c.u8(); // pickstroke
    return _BeatFx(b1 & 0x03 != 0, false);
  }

  void _skipMixTable() {
    c.s8(); // instrument
    if (v5) c.skip(16); // RSE volume/pan/... ints
    final vol = c.s8();
    final pan = c.s8();
    final chorus = c.s8();
    final reverb = c.s8();
    final phaser = c.s8();
    final tremolo = c.s8();
    if (v5) c.intByteString(); // tempo name
    final tempo = c.i32();
    for (final ch in [vol, pan, chorus, reverb, phaser, tremolo]) {
      if (ch >= 0) c.u8();
    }
    if (tempo >= 0) {
      c.u8(); // tempo transition
      if (v5) c.u8(); // hide tempo
    }
    if (v4 || v5) c.u8(); // applied-tracks bitmask
    if (v5) {
      c.u8(); // padding
      if (v510) {
        c.intByteString();
        c.intByteString();
      }
    }
  }

  void _skipChord() {
    final format = c.u8();
    if (format & 0x01 != 0) {
      // GP4/GP5 "new" chord diagram — a fixed 107-byte record.
      c.skip(106);
    } else {
      // GP3 legacy chord diagram: name, then a first fret; the six per-string
      // frets are present only when the diagram is anchored (first fret != 0).
      c.intByteString(); // name
      if (c.i32() != 0) {
        for (var s = 0; s < 6; s++) {
          c.i32(); // fret per string
        }
      }
    }
  }
}
