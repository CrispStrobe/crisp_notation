/// Multi-bar rests for a printed part.
library;

import 'element.dart';
import 'measure.dart';
import 'score.dart';

/// A part as a player reads it.
extension MultiRests on Score {
  /// This score with every run of two or more silent bars drawn as one
  /// multi-bar rest — how an instrumental part is printed, where a full
  /// score keeps each empty bar.
  ///
  /// A bar is silent when every voice holds only rests and none of them
  /// carries a mark (text, dynamic, hairpin, pedal, chord symbol, …). A run
  /// stops before a bar that changes clef, key, meter or tempo, opens a
  /// repeat or a volta, carries a navigation mark, is a pickup or has its
  /// own length, and after a bar that ends a repeat or has a barline other
  /// than a plain one — the places a player needs to see. The merged bar
  /// keeps its first bar's changes and rest, and its last bar's ending.
  Score withMultiRests() {
    final marked = <String>{
      for (final a in annotations) a.elementId,
      for (final d in dynamics) d.elementId,
      for (final c in chordSymbols) c.elementId,
      for (final l in lyrics) l.elementId,
      for (final b in breathMarks) b.noteId,
      for (final f in figuredBass) f.noteId,
      for (final h in hairpins) ...[h.startId, h.endId],
      for (final s in slurs) ...[s.startId, s.endId],
      for (final o in ottavas) ...[o.startId, o.endId],
      for (final p in pedals) ...[p.startId, p.endId],
    };
    bool silent(Measure m) =>
        m.measureRepeat == null &&
        m.voices.every((v) => v.every((e) => e is RestElement)) &&
        m.voices.expand((v) => v).every((e) => !marked.contains(e.id)) &&
        m.inlineClefs.isEmpty;
    // A bar a run may continue into: nothing at its start a player must see.
    bool continues(Measure m) =>
        m.clefChange == null &&
        m.keyChange == null &&
        m.timeChange == null &&
        m.tempoChange == null &&
        !m.startRepeat &&
        m.volta == null &&
        m.navigation == null &&
        !m.pickup &&
        m.actualDuration == null;
    // A bar a run must end with.
    bool closes(Measure m) => m.endRepeat || m.barline != BarlineStyle.normal;

    final out = <Measure>[];
    var i = 0;
    while (i < measures.length) {
      final first = measures[i];
      if (!silent(first) ||
          first.pickup ||
          first.actualDuration != null ||
          first.navigation != null) {
        out.add(first);
        i++;
        continue;
      }
      var count = first.multiRest ?? 1;
      var j = i + 1;
      var last = first;
      while (!closes(last) &&
          j < measures.length &&
          silent(measures[j]) &&
          continues(measures[j])) {
        last = measures[j];
        count += last.multiRest ?? 1;
        j++;
      }
      if (count < 2) {
        out.add(first);
      } else {
        // Keep the first bar's anchor rest; `copyWith` cannot clear a
        // field, so the ending is set on a rebuilt bar.
        final rest = first.elements.whereType<RestElement>().take(1).toList();
        out.add(Measure(
          rest,
          clefChange: first.clefChange,
          keyChange: first.keyChange,
          timeChange: first.timeChange,
          tempoChange: first.tempoChange,
          startRepeat: first.startRepeat,
          volta: first.volta,
          voltaNumbers: first.voltaNumbers,
          voltaText: first.voltaText,
          voltaOpenEnd: first.voltaOpenEnd,
          multiRest: count,
          endRepeat: last.endRepeat,
          barline: last.barline,
        ));
      }
      i = j;
    }
    return copyWith(measures: out);
  }
}
