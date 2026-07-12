/// SMuFL glyph name → codepoint table.
///
/// The table now lives in `partitura_core` (pure reference data shared by the
/// Flutter painter and the SVG emitter). This library re-exports it so the
/// historical import path `package:partitura/src/rendering/smufl_glyphs.dart`
/// and the `smuflCodepoints` symbol keep working.
library;

export 'package:partitura_core/partitura_core.dart' show smuflCodepoints;
