// tool/guitarset_symbolic_eval.dart
//
// Does `HarmonicWeighting.durationWeightedPerBar` actually help, measured
// THROUGH `analyze()` rather than through a standalone selection rule?
//
//   dart run tool/guitarset_symbolic_eval.dart <dir-with-jams>
//
// The improvement it was built on was measured by calling `identifyChord`
// directly with different pitch selections. That is evidence the IDEA works, not
// evidence the LIBRARY FUNCTION does — `analyze` wraps the identifier in slicing,
// non-chord-tone recovery, merging and key context, any of which could eat the
// gain. This closes that gap.
//
// Input is GuitarSet's `note_midi` annotations (CC BY 4.0), scored against its
// chord annotations with the MIREX-style majmin reduction, duration-weighted —
// the same ruler the app's audio evaluations use, so all of these numbers sit on
// one scale.
//
// ⚠️ MODELLING NOTE, because it bounds what this proves. One `Measure` is built
// per annotated chord segment, and each note's sounding time within that segment
// is quantised to the nearest note VALUE. That preserves the relative weighting
// the algorithm uses, which is what is under test, but it is not a faithful
// transcription — real meter, ties and barlines are absent. For the corpus case
// (`BB-X1`) the input is a real score and strictly cleaner than this.

import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';

int? _rootPc(String s) {
  const base = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  if (s.isEmpty) return null;
  var pc = base[s[0].toUpperCase()];
  if (pc == null) return null;
  for (final ch in s.substring(1).split('')) {
    if (ch == '#') pc = pc! + 1;
    if (ch == 'b') pc = pc! - 1;
  }
  return (pc! % 12 + 12) % 12;
}

String? _refSuffix(String q) => switch (q.split('(').first) {
      'maj' || '' => '',
      'min' => 'm',
      'maj7' => 'maj7',
      'min7' => 'm7',
      '7' => '7',
      'sus4' => 'sus4',
      'sus2' => 'sus2',
      'dim' => 'dim',
      'aug' => 'aug',
      'hdim7' => 'm7b5',
      'dim7' => 'dim7',
      'maj6' => '6',
      'min6' => 'm6',
      _ => null,
    };

String? _majmin(String? s) => switch (s) {
      '' || 'maj7' || '6' || '7' => 'maj',
      'm' || 'm7' || 'm6' => 'min',
      _ => null,
    };

/// The note value closest to [fraction] of the segment.
NoteDuration _quantise(double fraction) {
  const table = <(double, DurationBase)>[
    (1.0, DurationBase.whole),
    (0.5, DurationBase.half),
    (0.25, DurationBase.quarter),
    (0.125, DurationBase.eighth),
    (0.0625, DurationBase.sixteenth),
  ];
  var best = table.first;
  for (final t in table) {
    if ((t.$1 - fraction).abs() < (best.$1 - fraction).abs()) best = t;
  }
  return NoteDuration(best.$2);
}

class _T {
  double w = 0, named = 0, root = 0, majmin = 0, exact = 0;
  String p(double v) =>
      w == 0 ? ' n/a' : '${(100 * v / w).toStringAsFixed(1)}%';
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: guitarset_symbolic_eval.dart <dir>');
    exit(2);
  }
  final files = Directory(args.first)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.jams'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final perSlice = _T(), weighted = _T();
  var segments = 0;

  for (final f in files) {
    final jams = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final anns = (jams['annotations'] as List).cast<Map<String, dynamic>>();
    final chordAnns = anns.where((a) => a['namespace'] == 'chord').toList();
    final notes = <Map<String, dynamic>>[
      for (final a in anns)
        if (a['namespace'] == 'note_midi')
          ...(a['data'] as List).cast<Map<String, dynamic>>(),
    ];
    if (chordAnns.isEmpty || notes.isEmpty) continue;
    final ref = (chordAnns.last['data'] as List).cast<Map<String, dynamic>>();

    for (final obs in ref) {
      final value = (obs['value'] as String?) ?? '';
      if (!value.contains(':')) continue;
      final pc = _rootPc(value.split(':').first);
      final suffix = _refSuffix(value.split(':')[1].split('/').first);
      if (pc == null || suffix == null) continue;
      final refMm = _majmin(suffix);
      if (refMm == null) continue;
      final t0 = (obs['time'] as num).toDouble();
      final dur = (obs['duration'] as num).toDouble();
      if (dur < 0.5) continue;
      final t1 = t0 + dur;

      // One bar per annotated chord, notes weighted by how long they sound in it.
      final elements = <MusicElement>[];
      var i = 0;
      for (final n in notes) {
        final s = (n['time'] as num).toDouble();
        final e = s + (n['duration'] as num).toDouble();
        final overlap = (e < t1 ? e : t1) - (s > t0 ? s : t0);
        if (overlap <= 0) continue;
        elements.add(
          NoteElement(
            pitches: [Pitch.fromMidi((n['value'] as num).round())],
            duration: _quantise(overlap / dur),
            id: 'n${i++}',
          ),
        );
      }
      if (elements.isEmpty) continue;
      segments++;

      final score = Score(clef: Clef.treble, measures: [Measure(elements)]);
      for (final (mode, t) in [
        (HarmonicWeighting.perSlice, perSlice),
        (HarmonicWeighting.durationWeightedPerBar, weighted),
      ]) {
        t.w += dur;
        final a = analyze(score, weighting: mode);
        final chord = a.segments
            .map((s) => s.chord)
            .whereType<ChordAnalysis>()
            .firstOrNull;
        if (chord == null) continue;
        t.named += dur;
        final gotPc =
            ((chord.root.step.semitonesFromC + chord.root.alter) % 12 + 12) %
                12;
        final gotSuffix = chord.type.suffix;
        if (gotPc == pc) t.root += dur;
        if (gotPc == pc && _majmin(gotSuffix) == refMm) t.majmin += dur;
        if (gotPc == pc && gotSuffix == suffix) t.exact += dur;
      }
    }
  }

  stdout.writeln('=== analyze() end to end, $segments segments ===\n');
  void row(String label, _T t) => stdout.writeln(
        '  ${label.padRight(26)} named ${t.p(t.named).padLeft(6)}   '
        'root ${t.p(t.root).padLeft(6)}   majmin ${t.p(t.majmin).padLeft(6)}   '
        'FULL ${t.p(t.exact).padLeft(6)}',
      );
  row('perSlice (the default)', perSlice);
  row('durationWeightedPerBar', weighted);
  final d = weighted.w == 0
      ? 0.0
      : 100 * (weighted.majmin / weighted.w - perSlice.majmin / perSlice.w);
  stdout.writeln('\n  majmin delta: ${d >= 0 ? '+' : ''}'
      '${d.toStringAsFixed(1)}pp');
}
