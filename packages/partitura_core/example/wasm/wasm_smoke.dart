/// A WebAssembly compatibility smoke test for `partitura_core`.
///
/// It exercises the model, theory and every asset-free interchange codec, then
/// prints `WASM SMOKE OK`. It uses **no** `dart:io` / `dart:html` / `dart:ffi`
/// — only the web-safe core — so the same file both runs on the Dart VM
/// (`dart run`) and compiles + runs under `dart compile wasm` (dart2wasm /
/// WasmGC). See `build.sh` and `README.md`.
///
/// (Layout/SVG also work in WASM, but need a SMuFL metadata JSON passed in, so
/// they are left out of this asset-free smoke.)
library;

import 'dart:typed_data';

import 'package:partitura_core/partitura_core.dart';

/// A 56-byte raw-DEFLATE stream (from `dart:io`'s encoder) that inflates to
/// `'partitura inflates inside WebAssembly, no dart:io. ' * 3` (153 chars) —
/// proof the pure-Dart [inflate] runs in WASM on real compressed bytes.
const _deflated = [
  43, 72, 44, 42, 201, 44, 41, 45, 74, 84, 200, 204, 75, 203, 73, 44, 73, //
  45, 86, 200, 204, 43, 206, 76, 73, 85, 8, 79, 77, 114, 44, 46, 78, 205, //
  77, 202, 169, 212, 81, 200, 203, 87, 72, 73, 44, 42, 177, 202, 204, 215, //
  83, 40, 160, 139, 22, 0
];

void main() {
  final source = Score.simple(
    clef: Clef.treble,
    keySignature: const KeySignature(2),
    timeSignature: TimeSignature.fourFour,
    notes: 'c4:q d4 e4 f4 | g4:h a4:h ; c4:w',
    lyrics: 'do re mi fa sol la',
  );

  // Every codec funnels through the one Score, so each round-trips its subset.
  final musicXml = scoreFromMusicXml(scoreToMusicXml(source));
  final musescore = scoreFromMscx(scoreToMscx(source));
  final mei = scoreFromMei(scoreToMei(source));
  final kern = scoreFromKern(scoreToKern(source));
  final lily = scoreToLilyPond(source); // export-only
  final abc = scoreFromAbc(scoreToAbc(source));
  final midi = scoreFromMidi(scoreToMidi(source));
  final gpif = scoreFromGpif(scoreToGpif(source));

  // Theory: transposition preserves pitch count and spelling arithmetic.
  final up = source.transposedBy(const Interval(IntervalQuality.major, 3));

  // The (audio-free) playback timeline linearizes the score.
  final timeline = playbackTimeline(source);

  // Pure-Dart inflate + the ZIP container run in WASM too (no dart:io): inflate
  // a real DEFLATE stream, and round-trip a Score through a `.mscz` archive.
  final inflated = String.fromCharCodes(inflate(Uint8List.fromList(_deflated)));
  final viaMscz =
      scoreFromMscx(readMscxFromMscz(writeMsczFromMscx(scoreToMscx(source))));
  final viaMxl = scoreFromMusicXml(
      readMusicXmlFromMxl(writeMusicXmlToMxl(scoreToMusicXml(source))));

  int noteCount(Score s) => s.measures
      .expand((m) => [...m.elements, ...m.voice2])
      .whereType<NoteElement>()
      .length;

  final checks = <String, bool>{
    'MusicXML round-trip': noteCount(musicXml) == noteCount(source),
    'MuseScore round-trip': noteCount(musescore) == noteCount(source),
    'MEI round-trip': noteCount(mei) == noteCount(source),
    // kern is single-spine, so it keeps voice 1 (the source has a 2nd voice).
    'Humdrum kern round-trip': noteCount(kern) >= 6,
    'LilyPond export': lily.contains('\\version') && lily.contains('\\clef'),
    'ABC round-trip': noteCount(abc) >= 5,
    'MIDI round-trip': noteCount(midi) >= 5,
    'GPIF round-trip': noteCount(gpif) >= 1,
    'transpose keeps notes': noteCount(up) == noteCount(source),
    'timeline non-empty': timeline.isNotEmpty,
    'inflate (RFC 1951)':
        inflated.length == 153 && inflated.startsWith('partitura inflates'),
    '.mscz container round-trip': noteCount(viaMscz) == noteCount(source),
    '.mxl container round-trip': noteCount(viaMxl) == noteCount(source),
  };

  for (final entry in checks.entries) {
    print('${entry.value ? 'ok  ' : 'FAIL'} ${entry.key}');
  }

  if (checks.values.every((v) => v)) {
    print('WASM SMOKE OK (${checks.length} checks, '
        '${timeline.length} timeline events)');
  } else {
    print('WASM SMOKE FAILED');
    throw StateError('smoke checks failed');
  }
}
