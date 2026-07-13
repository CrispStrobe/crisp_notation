/// Music theory model, score document model and deterministic layout engine
/// for the partitura music notation libraries. Pure Dart — no Flutter
/// dependency.
///
/// The theory layer provides the pedagogical vocabulary ([Pitch],
/// [NoteDuration], [KeySignature], [TimeSignature], [Interval], [Scale],
/// [Triad], [Key] with [HarmonicFunction]); the model layer the score
/// document tree ([Score], [Measure], [MusicElement]). The layout engine
/// (in progress, HANDOVER.md §4.2) turns a [Score] into a flat display list
/// in staff-space coordinates.
library;

export 'src/abc/abc_reader.dart';
export 'src/abc/abc_writer.dart';
export 'src/gp/gp_binary_reader.dart';
export 'src/gp/gpif.dart';
export 'src/humdrum/kern_reader.dart';
export 'src/humdrum/kern_writer.dart';
export 'src/interchange/deflate.dart';
export 'src/interchange/gp_container.dart';
export 'src/interchange/inflate.dart';
export 'src/interchange/mscz_container.dart';
export 'src/interchange/mxl_container.dart';
export 'src/interchange/zip.dart';
export 'src/layout/grand_staff.dart';
export 'src/layout/layout_engine.dart' show LayoutEngine;
export 'src/layout/layout_settings.dart';
export 'src/layout/multi_part.dart';
export 'src/layout/multi_system.dart';
export 'src/layout/page_layout.dart';
export 'src/layout/score_layout.dart';
export 'src/layout/staff_system.dart';
export 'src/layout/tab_layout.dart';
export 'src/lilypond/lilypond_writer.dart';
export 'src/mei/mei_reader.dart';
export 'src/mei/mei_writer.dart';
export 'src/midi/midi_reader.dart';
export 'src/midi/midi_writer.dart';
export 'src/model/element.dart';
export 'src/model/measure.dart';
export 'src/model/score.dart';
export 'src/musescore/musescore_reader.dart';
export 'src/musescore/musescore_writer.dart';
export 'src/musicxml/musicxml_reader.dart';
export 'src/musicxml/musicxml_writer.dart';
export 'src/playback/playback_timeline.dart';
export 'src/smufl/glyph_names.dart';
export 'src/smufl/smufl_codepoints.dart';
export 'src/smufl/smufl_metadata.dart';
export 'src/svg/svg_export.dart';
export 'src/tablature/ascii_tab_reader.dart';
export 'src/tablature/chord_diagram.dart';
export 'src/theory/chord_analysis.dart';
export 'src/theory/clef.dart';
export 'src/theory/duration.dart';
export 'src/theory/fraction.dart';
export 'src/theory/interval.dart';
export 'src/theory/key.dart';
export 'src/theory/key_finding.dart';
export 'src/theory/key_signature.dart';
export 'src/theory/pitch.dart';
export 'src/theory/scale.dart';
export 'src/theory/set_theory.dart';
export 'src/theory/time_signature.dart';
export 'src/theory/tone_row.dart';
export 'src/theory/transposition.dart';
export 'src/theory/triad.dart';
export 'src/theory/tuning.dart';
