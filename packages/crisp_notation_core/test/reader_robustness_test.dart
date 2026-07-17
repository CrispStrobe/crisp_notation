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

  // ZIP/DEFLATE container readers: a corrupt archive names offsets and lengths
  // past the buffer. Mutating a valid archive (which keeps the end-of-directory
  // magic, so the parser reaches those fields) once leaked RangeErrors out of
  // the ZIP central-directory walk.
  test('container readers reject malformed bytes cleanly ($seeds mutations)',
      () {
    final rng = Random(3);
    final gp = writeGpFromGpif(scoreToGpif(_sample(rng)));
    final mscz = writeMsczFromMscx(scoreToMscx(_sample(rng)));

    Uint8List mutateBytes(Uint8List b) {
      final l = b.toList();
      switch (rng.nextInt(5)) {
        case 0:
          l.removeRange(rng.nextInt(l.length), l.length);
        case 1:
          final at = rng.nextInt(l.length);
          l.removeRange(at, min(l.length, at + 1 + rng.nextInt(20)));
        case 2:
          for (var k = 0; k < 1 + rng.nextInt(10); k++) {
            l[rng.nextInt(l.length)] = rng.nextInt(256);
          }
        case 3:
          l.insert(rng.nextInt(l.length), rng.nextInt(256));
        default:
          l.removeRange(0, rng.nextInt(l.length));
      }
      return Uint8List.fromList(l);
    }

    final readers = <String, void Function(Uint8List)>{
      'readMscxFromMscz': readMscxFromMscz,
      'readGpifFromGp': readGpifFromGp,
      'readMusicXmlFromMxl': (b) => readMusicXmlFromMxl(b),
      'inflate': (b) => inflate(b),
    };
    for (var i = 0; i < seeds; i++) {
      final gpMut = mutateBytes(gp);
      final msczMut = mutateBytes(mscz);
      readers.forEach((name, read) {
        for (final input in [gpMut, msczMut]) {
          try {
            read(input);
          } on FormatException {
            // clean rejection — the contract
          } catch (e) {
            fail('$name crashed on malformed bytes with ${e.runtimeType} '
                '(should be a FormatException).');
          }
        }
      });
    }
  });

  // The .gpx container (Guitar Pro 6, a BCFZ/BCFS bit-and-sector codec) has no
  // writer to seed valid samples from, so fuzz it with short headers and
  // magic-prefixed garbage. A short BCFZ (just the 4-byte magic, no length
  // field) once overran the little-endian reader with a RangeError.
  test('readGpifFromGpx rejects malformed .gpx cleanly', () {
    final inputs = <Uint8List>[
      // Every truncation of a BCFZ/BCFS header past the 4-byte magic.
      for (final magic in ['BCFZ', 'BCFS'])
        for (var n = 4; n <= 16; n++)
          Uint8List.fromList(
              [...magic.codeUnits, for (var i = 4; i < n; i++) i & 0xFF]),
    ];
    final rng = Random(88);
    for (var i = 0; i < 4000; i++) {
      final magic = rng.nextBool() ? 'BCFZ' : 'BCFS';
      inputs.add(Uint8List.fromList([
        ...magic.codeUnits,
        for (var k = 0; k < rng.nextInt(500); k++) rng.nextInt(256),
      ]));
    }
    for (final input in inputs) {
      try {
        readGpifFromGpx(input);
      } on FormatException {
        // clean rejection — the contract
      } catch (e) {
        fail('readGpifFromGpx crashed with ${e.runtimeType} '
            '(should be a FormatException) on ${input.length} bytes.');
      }
    }
  });
}
