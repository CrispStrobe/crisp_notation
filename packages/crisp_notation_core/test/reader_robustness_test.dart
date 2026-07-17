import 'dart:math';
import 'dart:typed_data';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Reader robustness: an importer must never crash on malformed input. Take a
/// valid document, mutate it every which way (truncate, delete runs, corrupt
/// digits, drop close-tags/brackets, inject bytes), and assert every reader
/// either parses something *or* rejects it with a [FormatException] — never a
/// raw RangeError / TypeError / StateError leaking out of the parser.
///
/// Deterministic (fixed seeds), so a failure names the mutation that crashed.
/// This guards the XML tokenizer's end-of-input bound, MusicXML's `<pitch>`
/// null-guards and the kern empty-token guard.

Score _sample(Random r) {
  final els = <MusicElement>[
    for (var i = 0; i < 4; i++)
      NoteElement(
          pitches: [Pitch(Step.values[r.nextInt(7)], octave: 4)],
          duration: NoteDuration.quarter,
          id: 'e$i'),
  ];
  return Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [Measure(els)]);
}

String _mutate(String doc, Random r) {
  if (doc.isEmpty) return doc;
  final chars = doc.split('');
  switch (r.nextInt(5)) {
    case 0:
      return doc.substring(0, r.nextInt(doc.length));
    case 1:
      final at = r.nextInt(chars.length);
      chars.removeRange(at, min(chars.length, at + 1 + r.nextInt(10)));
      return chars.join();
    case 2:
      return doc.replaceAllMapped(
          RegExp(r'\d'), (m) => r.nextInt(4) == 0 ? 'x' : m[0]!);
    case 3:
      return doc.replaceAll(r.nextInt(2) == 0 ? '>' : '}', '');
    default:
      final at = r.nextInt(chars.length);
      chars.insert(at, String.fromCharCode(r.nextInt(120)));
      return chars.join();
  }
}

void main() {
  final readers = <String, (String Function(Score), Score Function(String))>{
    'MusicXML': (scoreToMusicXml, scoreFromMusicXml),
    'MEI': (scoreToMei, scoreFromMei),
    'kern': (scoreToKern, scoreFromKern),
    'ABC': (scoreToAbc, scoreFromAbc),
    'MuseScore': (scoreToMscx, scoreFromMscx),
  };

  const seeds = 2000;

  readers.forEach((name, codec) {
    test('$name rejects malformed input cleanly ($seeds mutations)', () {
      final rng = Random(1);
      for (var i = 0; i < seeds; i++) {
        final doc = codec.$1(_sample(rng));
        final mutated = _mutate(doc, rng);
        try {
          codec.$2(mutated); // parsed leniently — acceptable
        } on FormatException {
          // clean rejection — the contract
        } catch (e) {
          fail('$name crashed on malformed input with ${e.runtimeType} '
              '(should be a FormatException).\nInput: '
              '${mutated.replaceAll('\n', r'\n')}');
        }
      }
    });
  });

  // Binary readers: a corrupt byte stream must also reject cleanly — and must
  // never hang. (A garbage time-signature meta once spun scoreFromMidi's
  // note-packing loop forever; if that regresses this test times out.)
  test('MIDI rejects malformed bytes cleanly ($seeds mutations)', () {
    final rng = Random(2);
    for (var i = 0; i < seeds; i++) {
      final bytes = scoreToMidi(_sample(rng)).toList();
      if (bytes.isEmpty) continue;
      switch (rng.nextInt(5)) {
        case 0:
          bytes.removeRange(rng.nextInt(bytes.length), bytes.length);
        case 1:
          final at = rng.nextInt(bytes.length);
          bytes.removeRange(at, min(bytes.length, at + 1 + rng.nextInt(12)));
        case 2:
          for (var k = 0; k < 1 + rng.nextInt(8); k++) {
            bytes[rng.nextInt(bytes.length)] = rng.nextInt(256);
          }
        case 3:
          bytes.insert(rng.nextInt(bytes.length), rng.nextInt(256));
        default:
          bytes.removeRange(0, rng.nextInt(bytes.length));
      }
      try {
        scoreFromMidi(Uint8List.fromList(bytes));
      } on FormatException {
        // clean rejection — the contract
      } catch (e) {
        fail('MIDI crashed on malformed bytes with ${e.runtimeType} '
            '(should be a FormatException).');
      }
    }
  });
}
