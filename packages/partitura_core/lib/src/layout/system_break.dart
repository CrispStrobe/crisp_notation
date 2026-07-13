/// Shared line-breaking helpers: per-measure running clef/key/time state and
/// slicing a [Score] to a measure range with the correct restated state and
/// only the spans that fit inside the slice. Used by both the single-part
/// (`layoutSystems`) and multi-part (`layoutMultiPartSystems`) line breakers.
library;

import '../model/measure.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/key_signature.dart';
import '../theory/time_signature.dart';

/// The clef, key and time signature current at the start of each measure of a
/// [Score] (index `i` is the state entering measure `i`; index `measureCount`
/// is the trailing state).
class SystemBreakState {
  /// Clef entering each measure.
  final List<Clef> clefAt;

  /// Key signature entering each measure.
  final List<KeySignature> keyAt;

  /// Time signature entering each measure (null = unmetered).
  final List<TimeSignature?> timeAt;

  const SystemBreakState._(this.clefAt, this.keyAt, this.timeAt);

  /// Computes the running state for [score].
  factory SystemBreakState.of(Score score) {
    final measureCount = score.measures.length;
    final clefAt = List<Clef>.filled(measureCount + 1, score.clef);
    final keyAt =
        List<KeySignature>.filled(measureCount + 1, score.keySignature);
    final timeAt =
        List<TimeSignature?>.filled(measureCount + 1, score.timeSignature);
    for (var i = 0; i < measureCount; i++) {
      final measure = score.measures[i];
      clefAt[i + 1] = measure.clefChange ?? clefAt[i];
      keyAt[i + 1] = measure.keyChange ?? keyAt[i];
      timeAt[i + 1] = measure.timeChange ?? timeAt[i];
      if (measure.clefChange != null) clefAt[i] = clefAt[i + 1];
      if (measure.keyChange != null) keyAt[i] = keyAt[i + 1];
      if (measure.timeChange != null) timeAt[i] = timeAt[i + 1];
    }
    return SystemBreakState._(clefAt, keyAt, timeAt);
  }
}

/// Whether the time signature is drawn on a system starting at [firstMeasure]:
/// on the first system, and where a system starts on an explicit change (the
/// change glyph moves into the leading segment).
bool drawsTimeAt(Score score, int firstMeasure) =>
    firstMeasure == 0 || score.measures[firstMeasure].timeChange != null;

/// A sub-score of measures [first]..[last] with the correct starting state
/// (from [state]) and only the spans that fit entirely inside the slice.
Score sliceScore(Score score, int first, int last, SystemBreakState state) {
  final measures = <Measure>[];
  for (var i = first; i <= last; i++) {
    var measure = score.measures[i];
    if (i == first &&
        (measure.clefChange != null ||
            measure.keyChange != null ||
            measure.timeChange != null)) {
      // The change is expressed by the system's leading state instead.
      measure = Measure(
        measure.elements,
        voice2: measure.voice2,
        tuplets: measure.tuplets,
        startRepeat: measure.startRepeat,
        endRepeat: measure.endRepeat,
        volta: measure.volta,
        multiRest: measure.multiRest,
        navigation: measure.navigation,
      );
    }
    measures.add(measure);
  }

  final ids = <String>{
    for (final measure in measures) ...[
      for (final element in measure.elements)
        if (element.id != null) element.id!,
      for (final element in measure.voice2)
        if (element.id != null) element.id!,
    ],
  };
  return Score(
    clef: state.clefAt[first],
    keySignature: state.keyAt[first],
    // The time signature shows on the first system and where it changes.
    // Kept even when not drawn — beaming windows derive from it.
    timeSignature: state.timeAt[first],
    measures: measures,
    slurs: [
      for (final slur in score.slurs)
        if (ids.contains(slur.startId) && ids.contains(slur.endId)) slur,
    ],
    dynamics: [
      for (final marking in score.dynamics)
        if (ids.contains(marking.elementId)) marking,
    ],
    hairpins: [
      for (final hairpin in score.hairpins)
        if (ids.contains(hairpin.startId) && ids.contains(hairpin.endId))
          hairpin,
    ],
    lyrics: [
      for (final lyric in score.lyrics)
        if (ids.contains(lyric.elementId)) lyric,
    ],
    annotations: [
      for (final annotation in score.annotations)
        if (ids.contains(annotation.elementId)) annotation,
    ],
    glissandos: [
      for (final gliss in score.glissandos)
        if (ids.contains(gliss.startId) && ids.contains(gliss.endId)) gliss,
    ],
    pedals: [
      for (final pedal in score.pedals)
        if (ids.contains(pedal.startId) && ids.contains(pedal.endId)) pedal,
    ],
    featheredBeams: [
      for (final fb in score.featheredBeams)
        if (ids.contains(fb.startId) && ids.contains(fb.endId)) fb,
    ],
    beamSlants: [
      for (final bs in score.beamSlants)
        if (ids.contains(bs.startId) && ids.contains(bs.endId)) bs,
    ],
    bends: [
      for (final bend in score.bends)
        if (ids.contains(bend.noteId)) bend,
    ],
    vibratos: [
      for (final vibrato in score.vibratos)
        if (ids.contains(vibrato.noteId)) vibrato,
    ],
    palmMutes: [
      for (final pm in score.palmMutes)
        if (ids.contains(pm.startId) && ids.contains(pm.endId)) pm,
    ],
    letRings: [
      for (final lr in score.letRings)
        if (ids.contains(lr.startId) && ids.contains(lr.endId)) lr,
    ],
    tabNoteMarks: [
      for (final tm in score.tabNoteMarks)
        if (ids.contains(tm.noteId)) tm,
    ],
    tabVoicings: [
      for (final tv in score.tabVoicings)
        if (ids.contains(tv.noteId)) tv,
    ],
    taps: [
      for (final tap in score.taps)
        if (ids.contains(tap.noteId)) tap,
    ],
    tremoloBars: [
      for (final tb in score.tremoloBars)
        if (ids.contains(tb.noteId)) tb,
    ],
    chordDiagrams: [
      for (final cd in score.chordDiagrams)
        if (ids.contains(cd.elementId)) cd,
    ],
    crossStaff: [
      for (final cs in score.crossStaff)
        if (ids.contains(cs.noteId)) cs,
    ],
  );
}
