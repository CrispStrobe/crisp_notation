import 'dart:io';
import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Average simultaneously-sounding notes — the texture, not the chord rate.
double simultaneity(Score s) {
  var notes = 0, events = 0;
  for (final m in s.measures) {
    for (final voice in [m.elements, m.voice2, m.voice3, m.voice4]) {
      for (final e in voice) {
        if (e is NoteElement) {
          notes += e.pitches.length;
          events++;
        }
      }
    }
  }
  return events == 0 ? 0 : notes / events;
}

/// Voices actually used.
int voiceCount(Score s) {
  var n = 0;
  for (final v in [0, 1, 2, 3]) {
    final used = s.measures.any((m) => switch (v) {
          0 => m.elements.whereType<NoteElement>().isNotEmpty,
          1 => m.voice2.whereType<NoteElement>().isNotEmpty,
          2 => m.voice3.whereType<NoteElement>().isNotEmpty,
          _ => m.voice4.whereType<NoteElement>().isNotEmpty,
        });
    if (used) n++;
  }
  return n;
}

void main(List<String> a) {
  for (final dir in a) {
    final files = Directory(dir).listSync().whereType<File>().toList()
      ..sort((x, y) => x.path.compareTo(y.path));
    final sims = <double>[], vcs = <int>[];
    for (final f in files.take(40)) {
      Score? s;
      try {
        final t = f.readAsStringSync();
        s = f.path.endsWith('.ly')
            ? scoreFromLilyPond(t)
            : (f.path.endsWith('.mscx') ? scoreFromMscx(t) : null);
      } catch (_) {}
      if (s == null || s.measures.isEmpty) continue;
      sims.add(simultaneity(s));
      vcs.add(voiceCount(s));
    }
    sims.sort();
    vcs.sort();
    stdout.writeln('${dir.split('/').last}: median simultaneity '
        '${sims.isEmpty ? 0 : sims[sims.length ~/ 2].toStringAsFixed(2)}   '
        'median voices ${vcs.isEmpty ? 0 : vcs[vcs.length ~/ 2]}   '
        '(n=${sims.length})');
  }
}
