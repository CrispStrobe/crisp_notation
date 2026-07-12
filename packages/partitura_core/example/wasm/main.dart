/// Browser entry point: compiles `partitura_core` to WebAssembly and exposes a
/// couple of pure conversion functions to JavaScript via `dart:js_interop`.
///
/// After the module is instantiated and `invoke`d, JS can call:
///   partituraConvert(notes, format) -> String   // format: musicxml|mscx|abc
///   partituraInfo(notes)            -> String    // one-line summary
/// where `notes` is a `Score.simple` DSL string (e.g. `"c4:q d4 e4 f4 | g4:h a4"`).
///
/// Build with `build.sh`; open `index.html` over http. Layout/SVG are omitted
/// here because they need a SMuFL metadata JSON asset; the text codecs need no
/// assets, which keeps this demo self-contained.
library;

import 'dart:js_interop';

import 'package:partitura_core/partitura_core.dart';

@JS('partituraConvert')
external set _convertFn(JSFunction value);

@JS('partituraInfo')
external set _infoFn(JSFunction value);

String _convert(String notes, String format) {
  try {
    final score = Score.simple(notes: notes);
    return switch (format) {
      'musicxml' => scoreToMusicXml(score),
      'mscx' => scoreToMscx(score),
      'abc' => scoreToAbc(score),
      _ => 'error: unknown format "$format" (musicxml|mscx|abc)',
    };
  } on FormatException catch (e) {
    return 'error: ${e.message}';
  }
}

String _info(String notes) {
  try {
    final score = Score.simple(notes: notes);
    final elements =
        score.measures.fold<int>(0, (n, m) => n + m.elements.length);
    return '${score.measures.length} measures, $elements elements, '
        'clef ${score.clef.name}, meter ${score.timeSignature ?? 'unmetered'}';
  } on FormatException catch (e) {
    return 'error: ${e.message}';
  }
}

void main() {
  _convertFn = ((JSString notes, JSString format) =>
      _convert(notes.toDart, format.toDart).toJS).toJS;
  _infoFn = ((JSString notes) => _info(notes.toDart).toJS).toJS;
}
