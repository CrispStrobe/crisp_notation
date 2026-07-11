import 'dart:typed_data';

import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Whether [haystack] contains [needle] as a contiguous subsequence.
bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

int _u16(Uint8List b, int at) => (b[at] << 8) | b[at + 1];

void main() {
  group('MIDI export', () {
    test('emits a well-formed format-0 header', () {
      final midi = scoreToMidi(
        Score.simple(timeSignature: TimeSignature.fourFour, notes: 'c4:q'),
        ticksPerQuarter: 480,
      );
      // "MThd" + length 6.
      expect(midi.sublist(0, 4), [0x4D, 0x54, 0x68, 0x64]);
      expect(midi.sublist(4, 8), [0, 0, 0, 6]);
      expect(_u16(midi, 8), 0); // format 0
      expect(_u16(midi, 10), 1); // one track
      expect(_u16(midi, 12), 480); // division
      // A track chunk follows the 14-byte header.
      expect(midi.sublist(14, 18), [0x4D, 0x54, 0x72, 0x6B]);
    });

    test('writes a note on/off pair for each pitch', () {
      final midi = scoreToMidi(Score.simple(notes: 'c4:q')); // C4 = 60
      expect(_contains(midi, [0x90, 60, 80]), isTrue); // note on
      expect(_contains(midi, [0x80, 60, 0x40]), isTrue); // note off
    });

    test('a chord emits one note-on per pitch', () {
      final midi = scoreToMidi(Score.simple(notes: 'c4+e4+g4:q'));
      for (final key in [60, 64, 67]) {
        expect(_contains(midi, [0x90, key, 80]), isTrue);
      }
    });

    test('tempo meta encodes microseconds per quarter', () {
      // 120 bpm → 500000 µs = 0x07A120.
      final midi = scoreToMidi(Score.simple(notes: 'c4:q'), quarterBpm: 120);
      expect(_contains(midi, [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]), isTrue);
      // 60 bpm → 1000000 µs = 0x0F4240.
      final slow = scoreToMidi(Score.simple(notes: 'c4:q'), quarterBpm: 60);
      expect(_contains(slow, [0xFF, 0x51, 0x03, 0x0F, 0x42, 0x40]), isTrue);
    });

    test('time-signature meta reflects the score meter', () {
      final midi = scoreToMidi(
        Score.simple(timeSignature: const TimeSignature(6, 8), notes: 'c4:q'),
      );
      // nn=6, dd=log2(8)=3, cc=24, bb=8.
      expect(_contains(midi, [0xFF, 0x58, 0x04, 6, 3, 24, 8]), isTrue);
    });

    test('an unmetered score writes no time-signature meta', () {
      final midi = scoreToMidi(Score.simple(notes: 'c4:q'));
      expect(_contains(midi, [0xFF, 0x58]), isFalse);
    });

    test('voice 2 is written on MIDI channel 1', () {
      final midi = scoreToMidi(Score.simple(notes: 'c5:q ; c4:q'));
      expect(_contains(midi, [0x91, 60, 80]), isTrue); // C4 on channel 1
    });

    test('ends with an end-of-track meta event', () {
      final midi = scoreToMidi(Score.simple(notes: 'c4:q'));
      expect(midi.sublist(midi.length - 3), [0xFF, 0x2F, 0x00]);
    });

    test('repeats unfold into the exported notes', () {
      // A repeated single-note bar exports the note twice.
      final midi = scoreToMidi(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: '!repeat c4:w !endrepeat',
      ));
      var count = 0;
      for (var i = 0; i + 3 <= midi.length; i++) {
        if (midi[i] == 0x90 && midi[i + 1] == 60 && midi[i + 2] == 80) count++;
      }
      expect(count, 2);
    });

    test('deterministic', () {
      final a = scoreToMidi(Score.simple(notes: 'c4:q d4 e4'));
      final b = scoreToMidi(Score.simple(notes: 'c4:q d4 e4'));
      expect(a, b);
    });
  });
}
