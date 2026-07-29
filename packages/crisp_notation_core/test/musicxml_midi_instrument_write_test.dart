// A part's General-MIDI voice survives a MusicXML round trip.
//
// It did not before. Every reader here fills `ScoreMetadata.midiProgram` and
// `isPercussion` — MusicXML, MuseScore, MEI — and per-part voicing is built on
// them, but the MusicXML writer emitted no `<midi-instrument>` at all. So a
// score with a bass part and a piano part reopened with both on the default
// voice: the information survived every read and died on the first save, which
// is the worst place to lose it (the save is what you keep).
//
// `musicxml_midi_program_test.dart` covers the READ. This covers the write, and
// the round trip that is the point of having both.

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

Score _part({int? program, bool percussion = false, String? name}) =>
    Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4',
      metadata: ScoreMetadata(
        instrument: name,
        midiProgram: program,
        isPercussion: percussion,
      ),
    );

void main() {
  group('a single part', () {
    test('its program round-trips', () {
      // 32 is Acoustic Bass — a voice nobody would confuse with the default.
      final back = scoreFromMusicXml(
        scoreToMusicXml(_part(program: 32, name: 'Bass')),
      );
      expect(back.metadata.midiProgram, 32);
      expect(back.metadata.instrument, 'Bass');
    });

    test('program 0 is written, not treated as absent', () {
      // 0 is Acoustic Grand Piano — a real choice, and the classic off-by-null:
      // MusicXML numbers programs from 1, so 0 must come back as 1 in the file
      // and 0 again in the model.
      final xml = scoreToMusicXml(_part(program: 0, name: 'Piano'));
      expect(xml, contains('<midi-program>1</midi-program>'));
      expect(scoreFromMusicXml(xml).metadata.midiProgram, 0);
    });

    test('the top of the range survives', () {
      final xml = scoreToMusicXml(_part(program: 127));
      expect(xml, contains('<midi-program>128</midi-program>'));
      expect(scoreFromMusicXml(xml).metadata.midiProgram, 127);
    });

    test('percussion round-trips, on channel 10', () {
      // Channel 10 IS the drum flag, in this reader and in General MIDI.
      final xml = scoreToMusicXml(_part(percussion: true, name: 'Drums'));
      expect(xml, contains('<midi-channel>10</midi-channel>'));
      expect(scoreFromMusicXml(xml).metadata.isPercussion, isTrue);
    });

    test('a part with no voice gains no markup at all', () {
      // The upgrade guarantee: a score that never declared a voice must export
      // exactly as it did, or every existing file's diff changes for nothing.
      final xml = scoreToMusicXml(_part(name: 'Music'));
      expect(xml, isNot(contains('midi-instrument')));
      expect(xml, isNot(contains('score-instrument')));
    });
  });

  group('several parts keep their OWN voices', () {
    MultiPartScore band() => MultiPartScore([
          _part(program: 0, name: 'Piano'),
          _part(program: 32, name: 'Bass'),
          _part(percussion: true, name: 'Drums'),
        ]);

    test('each program comes back on the right part', () {
      final back = multiPartScoreFromMusicXml(multiPartToMusicXml(band()));
      expect(back.parts[0].metadata.midiProgram, 0);
      expect(back.parts[1].metadata.midiProgram, 32);
      expect(back.parts[2].metadata.isPercussion, isTrue);
    });

    test('a pitched part never lands on channel 10', () {
      // It would read back as drums — the failure mode of a naive
      // "channel = index + 1".
      final many = MultiPartScore([
        for (var i = 0; i < 12; i++) _part(program: i, name: 'Part $i'),
      ]);
      final back = multiPartScoreFromMusicXml(multiPartToMusicXml(many));
      for (var i = 0; i < 12; i++) {
        expect(
          back.parts[i].metadata.isPercussion,
          isFalse,
          reason: 'part $i must not read back as drums',
        );
        expect(back.parts[i].metadata.midiProgram, i);
      }
    });

    test('a mixed band: only the drum part is percussion', () {
      final back = multiPartScoreFromMusicXml(multiPartToMusicXml(band()));
      expect(
        back.parts.map((p) => p.metadata.isPercussion),
        [false, false, true],
      );
    });

    test('parts without a voice stay bare, beside parts that have one', () {
      final mixed = MultiPartScore([
        _part(name: 'Melody'),
        _part(program: 32, name: 'Bass'),
      ]);
      final back = multiPartScoreFromMusicXml(multiPartToMusicXml(mixed));
      expect(back.parts[0].metadata.midiProgram, isNull);
      expect(back.parts[1].metadata.midiProgram, 32);
    });
  });

  test('the document still parses as a whole after the addition', () {
    // A `<midi-instrument>` must reference a `<score-instrument>` with the same
    // id; writing one without the other is the easy way to produce a file other
    // programs reject while ours reads it back happily.
    final xml = multiPartToMusicXml(
      MultiPartScore([_part(program: 40, name: 'Violin')]),
    );
    expect(xml, contains('<score-instrument id="P1-I1">'));
    expect(xml, contains('<midi-instrument id="P1-I1">'));
    expect(scoreFromMusicXml(xml).metadata.midiProgram, 40);
  });
}
