import 'dart:typed_data';

import 'package:crisp_notation_core/crisp_notation_core.dart';
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

  group('MIDI import', () {
    List<Pitch> pitchesOf(Measure m) =>
        m.elements.whereType<NoteElement>().expand((n) => n.pitches).toList();

    test('rejects non-MIDI bytes', () {
      expect(() => scoreFromMidi(Uint8List.fromList([1, 2, 3, 4])),
          throwsFormatException);
    });

    test('round-trips a melody (pitches and durations)', () {
      final source = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4',
      );
      final back = scoreFromMidi(scoreToMidi(source));
      expect(back.measures, hasLength(1));
      final notes = back.measures.single.elements.whereType<NoteElement>();
      expect(notes.map((n) => n.pitches.single.toString()),
          ['C4', 'D4', 'E4', 'F4']);
      expect(notes.map((n) => n.duration), everyElement(NoteDuration.quarter));
    });

    test('round-trips a chord', () {
      final back = scoreFromMidi(scoreToMidi(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4+e4+g4:w',
      )));
      final chord =
          back.measures.single.elements.whereType<NoteElement>().single;
      expect(chord.pitches.map((p) => p.toString()), ['C4', 'E4', 'G4']);
    });

    test('sharps round-trip exactly; flats come back as sharps', () {
      final back = scoreFromMidi(scoreToMidi(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'f#4:q g4 a4 bb4',
      )));
      final names = pitchesOf(back.measures.single).map((p) => p.toString());
      // bb4 (MIDI 70) is spelled A#4 on the way back (enharmonic, documented).
      expect(names, ['F#4', 'G4', 'A4', 'A#4']);
    });

    test('splits across measures with ties', () {
      // Eight quarters → two 4/4 measures.
      final back = scoreFromMidi(scoreToMidi(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:q d4 e4 f4 | g4:q a4 b4 c5',
      )));
      expect(back.measures, hasLength(2));
      expect(pitchesOf(back.measures[1]).map((p) => p.toString()),
          ['G4', 'A4', 'B4', 'C5']);
    });

    test('a single note longer than a measure is split and tied', () {
      // A breve (two whole notes) sounds as one MIDI note spanning two 4/4
      // bars; import splits it into two whole notes bound by a tie.
      final back = scoreFromMidi(scoreToMidi(Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c4:b',
      )));
      expect(back.measures, hasLength(2));
      final first = back.measures[0].elements.whereType<NoteElement>().last;
      expect(first.tieToNext, isTrue);
      expect(first.duration, NoteDuration.whole);
      final second = back.measures[1].elements.whereType<NoteElement>().single;
      expect(second.tieToNext, isFalse);
    });

    test('recovers the time signature from the file', () {
      final back = scoreFromMidi(scoreToMidi(Score.simple(
        timeSignature: const TimeSignature(3, 4),
        notes: 'c4:q d4 e4',
      )));
      expect(back.timeSignature, const TimeSignature(3, 4));
    });

    test('parses running status (repeated note-on status byte)', () {
      // MThd + one MTrk with two note-ons sharing a 0x90 running status.
      final track = <int>[
        0x00, 0x90, 60, 0x40, // note on C4
        0x60, 62, 0x40, //       running status: note on D4 (no 0x90)
        0x60, 60, 0x00, //       running status: C4 off (vel 0)
        0x00, 62, 0x00, //       running status: D4 off
        0x00, 0xFF, 0x2F, 0x00, // end of track
      ];
      final bytes = <int>[
        0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 0x00,
        0x60, // MThd, tpq 96
        0x4D, 0x54, 0x72, 0x6B, //                                     MTrk
        0, 0, 0, track.length,
        ...track,
      ];
      final score = scoreFromMidi(Uint8List.fromList(bytes));
      final names = score.measures
          .expand((m) => m.elements)
          .whereType<NoteElement>()
          .map((n) => n.pitches.single.toString())
          .toList();
      expect(names, containsAll(['C4', 'D4']));
    });

    test('an empty MIDI yields one empty (whole-rest) measure', () {
      final back = scoreFromMidi(scoreToMidi(Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.fourFour,
        measures: const [Measure([])],
      )));
      expect(back.measures.single.elements.single, isA<RestElement>());
    });

    test('an out-of-range time-signature meta falls back to 4/4 (no hang)', () {
      // Regression: a corrupt time-signature meta with a beat-unit exponent
      // outside 1…16 (here 2^24) built a meter whose zero measure-capacity
      // spun the note-packing loop forever. The reader now ignores it via
      // TimeSignature.tryParse and defaults to 4/4.
      final track = <int>[
        0x00, 0xFF, 0x58, 0x04, 0x36, 0x18, 0x08, 0x00, // time sig 54/2^24
        0x00, 0x90, 60, 0x40, //                            note on C4
        0x60, 60, 0x00, //                                  note off
        0x00, 0xFF, 0x2F, 0x00, //                          end of track
      ];
      final bytes = <int>[
        0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 0x00, 0x60, // MThd
        0x4D, 0x54, 0x72, 0x6B, 0, 0, 0, track.length, ...track, //   MTrk
      ];
      final score = scoreFromMidi(Uint8List.fromList(bytes));
      expect(score.timeSignature, TimeSignature.fourFour);
    });
  });
}
