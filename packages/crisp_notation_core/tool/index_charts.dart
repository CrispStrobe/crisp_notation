// tool/index_charts.dart
//
// Emits a chart index for every db.json row whose FILE CARRIES ITS OWN chord
// symbols. Inference is deliberately excluded.
//
//   dart run tool/index_charts.dart <music-db-root> <out.json>
//
// 🔴 EXACT ONLY. A chart read from an engraver's own chord symbols and a chart
// inferred from the notes are not the same kind of object, and the inference is
// currently unreliable on polyphonic sources — `analyze()` takes a single Score,
// so a multi-staff work arrives with its staves collapsed into voices and the
// slices mix parts. Indexing inferred charts today would put known-bad data into
// a corpus several agents depend on, so a row with no own-symbols is simply
// skipped and stays absent rather than being filled with a guess.

import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';

/// ChordPro carries its chords inline as `[G]`. crisp_notation has no ChordPro
/// reader, and the format is small enough that extracting the symbols honestly
/// needs no parser — the bracketed tokens ARE the chords, in order.
List<String> _chordProSymbols(String text) {
  final out = <String>[];
  for (final m in RegExp(r'\[([^\]]+)\]').allMatches(text)) {
    final t = m.group(1)!.trim();
    // Directives use braces, so anything bracketed is a chord — but guard
    // against annotations like [x2] that are not.
    if (RegExp(r'^[A-G][b#]?').hasMatch(t)) out.add(t);
  }
  return out;
}

/// The chord symbols a file states for itself, in order, or null when it states
/// none.
List<String>? ownSymbols(String path) {
  final lower = path.toLowerCase();
  try {
    if (lower.endsWith('.txt') || lower.endsWith('.cho')) {
      final syms = _chordProSymbols(File(path).readAsStringSync());
      return syms.isEmpty ? null : syms;
    }
    final bytes = File(path).readAsBytesSync();
    String text() => File(path).readAsStringSync();
    Score? s;
    if (lower.endsWith('.mxl')) {
      s = scoreFromMusicXml(readMusicXmlFromMxl(bytes));
    } else if (lower.endsWith('.musicxml') || lower.endsWith('.xml')) {
      s = scoreFromMusicXml(text());
    } else if (lower.endsWith('.ly')) {
      s = scoreFromLilyPond(text());
    } else if (lower.endsWith('.mscz')) {
      s = scoreFromMscx(readMscxFromMscz(bytes));
    } else if (lower.endsWith('.mscx')) {
      s = scoreFromMscx(text());
    }
    if (s == null || s.chordSymbols.isEmpty) return null;

    // In bar order, so the list reads as a chart rather than as file order.
    final barOf = <String, int>{};
    for (var i = 0; i < s.measures.length; i++) {
      for (final v in [
        s.measures[i].elements,
        s.measures[i].voice2,
        s.measures[i].voice3,
        s.measures[i].voice4,
      ]) {
        for (final e in v) {
          if (e is NoteElement && e.id != null) barOf[e.id!] = i;
        }
      }
    }
    final withBar = [
      for (final c in s.chordSymbols)
        if (barOf[c.elementId] != null) (barOf[c.elementId]!, c.text),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return withBar.isEmpty ? null : [for (final e in withBar) e.$2];
  } catch (_) {
    return null;
  }
}

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: index_charts.dart <music-db-root> <out.json>');
    exit(2);
  }
  final root = args[0];
  final db = jsonDecode(File('$root/db.json').readAsStringSync()) as List;

  final index = <String, Object?>{};
  var scanned = 0, withChords = 0;
  final bySource = <String, int>{};

  for (final row in db.cast<Map<String, dynamic>>()) {
    final path = row['path'] as String?;
    final id = row['id'] as String?;
    if (path == null || id == null) continue;
    final full = '$root/$path';
    if (!File(full).existsSync()) continue;
    scanned++;
    final syms = ownSymbols(full);
    if (syms == null || syms.isEmpty) continue;
    withChords++;
    final src = (row['source'] ?? '?').toString();
    bySource[src] = (bySource[src] ?? 0) + 1;
    index[id] = {
      'symbols': syms,
      'count': syms.length,
      'distinct': syms.toSet().length,
      // Provenance of the CHART itself, not of the file: 'file' means an
      // engraver wrote these chords. Nothing here is inferred.
      'origin': 'file',
    };
    if (scanned % 2000 == 0) {
      stderr.writeln('  … $scanned scanned, $withChords with chords');
    }
  }

  File(args[1]).writeAsStringSync(jsonEncode(index));
  stdout.writeln('scanned $scanned rows; $withChords carry their own chords');
  final top = bySource.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in top.take(12)) {
    stdout.writeln('  ${e.value.toString().padLeft(5)}  ${e.key}');
  }
}
