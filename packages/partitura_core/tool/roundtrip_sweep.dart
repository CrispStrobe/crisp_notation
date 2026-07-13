// Round-trip fidelity sweep over a directory of real scores.
//
//   dart run tool/roundtrip_sweep.dart <dir> [<dir> …]
//
// For every score it can import to a single `Score`, it pushes that score out
// through each writer and back through the matching reader, then measures how
// much of the note content survived — a real-corpus companion to
// `test/roundtrip_fidelity_test.dart` (which uses synthetic probes). Prints a
// per-format table: exact round-trips, average note-multiset preservation, and
// how many inputs threw on the way out-and-back.
//
// Note-level, order-independent: it compares the *multiset* of (sorted MIDI
// numbers, duration) across all parts/voices, so voice re-ordering doesn't
// count as a loss. This is a diagnostic tool, not a committed test (the corpus
// lives outside the repo).
import 'dart:io';
import 'dart:typed_data';

import 'package:partitura_core/partitura_core.dart';

/// One (writer, reader) round-trippable format.
class Fmt {
  Fmt(this.name, this.write, this.read);
  final String name;
  final String Function(Score) write;
  final Score Function(String) read;
}

final _formats = <Fmt>[
  Fmt('MusicXML', scoreToMusicXml, scoreFromMusicXml),
  Fmt('MEI', scoreToMei, scoreFromMei),
  Fmt('kern', scoreToKern, scoreFromKern),
  Fmt('ABC', scoreToAbc, scoreFromAbc),
  Fmt('MuseScore', scoreToMscx, scoreFromMscx),
  Fmt('MIDI', (s) => String.fromCharCodes(scoreToMidi(s)),
      (s) => scoreFromMidi(Uint8List.fromList(s.codeUnits))),
];

/// Multiset of `<sorted-midi>@<dur>` note keys across the whole score.
Map<String, int> _notes(Score s) {
  final bag = <String, int>{};
  for (final m in s.measures) {
    for (final e in m.elements) {
      if (e is NoteElement) {
        final midis = e.pitches.map((p) => p.midiNumber).toList()..sort();
        final key = '${midis.join(',')}@${e.duration.toFraction()}';
        bag[key] = (bag[key] ?? 0) + 1;
      }
    }
  }
  return bag;
}

/// Fraction of the original note multiset preserved after a round-trip (0..1).
double _preserved(Map<String, int> a, Map<String, int> b) {
  if (a.isEmpty) return b.isEmpty ? 1 : 0;
  var kept = 0, total = 0;
  for (final entry in a.entries) {
    total += entry.value;
    kept += entry.value < (b[entry.key] ?? 0) ? entry.value : (b[entry.key] ?? 0);
  }
  return kept / total;
}

Score? _import(File f) {
  final path = f.path.toLowerCase();
  try {
    if (path.endsWith('.xml') || path.endsWith('.musicxml')) {
      return scoreFromMusicXml(f.readAsStringSync());
    } else if (path.endsWith('.mxl')) {
      return scoreFromMusicXml(readMusicXmlFromMxl(f.readAsBytesSync()));
    } else if (path.endsWith('.mei')) {
      return scoreFromMei(f.readAsStringSync());
    } else if (path.endsWith('.krn') || path.endsWith('.kern')) {
      return scoreFromKern(f.readAsStringSync());
    } else if (path.endsWith('.abc')) {
      return scoreFromAbc(f.readAsStringSync());
    } else if (path.endsWith('.mid') || path.endsWith('.midi')) {
      return scoreFromMidi(f.readAsBytesSync());
    }
  } catch (_) {
    return null; // un-importable input; not what this tool measures
  }
  return null;
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/roundtrip_sweep.dart <dir> …');
    exit(64);
  }
  final files = <File>[];
  for (final dir in args) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final e in d.listSync(recursive: true)) {
      if (e is File) files.add(e);
    }
  }

  // Per format: [exactRoundTrips, sumPreserved, imported, threw].
  final stat = {
    for (final f in _formats) f.name: <String, num>{'exact': 0, 'sum': 0, 'n': 0, 'threw': 0}
  };
  var imported = 0;

  for (final f in files) {
    final score = _import(f);
    if (score == null) continue;
    imported++;
    final want = _notes(score);
    for (final fmt in _formats) {
      final s = stat[fmt.name]!;
      try {
        final back = fmt.read(fmt.write(score));
        final ratio = _preserved(want, _notes(back));
        s['n'] = s['n']! + 1;
        s['sum'] = s['sum']! + ratio;
        if (ratio == 1.0) s['exact'] = s['exact']! + 1;
      } catch (_) {
        s['threw'] = s['threw']! + 1;
      }
    }
  }

  stdout.writeln('\nRound-trip fidelity over $imported imported scores '
      '(${files.length} files scanned)\n');
  stdout.writeln('  format      exact     avg-preserved   threw');
  stdout.writeln('  ---------   -------   -------------   -----');
  for (final fmt in _formats) {
    final s = stat[fmt.name]!;
    final n = s['n']!;
    final avg = n == 0 ? 0.0 : s['sum']! / n;
    final exactPct = n == 0 ? 0.0 : 100 * s['exact']! / n;
    stdout.writeln('  ${fmt.name.padRight(9)}   '
        '${'${(exactPct).toStringAsFixed(0)}%'.padLeft(4)} '
        '(${s['exact']}/$n)   '
        '${(100 * avg).toStringAsFixed(1).padLeft(9)}%   '
        '${s['threw'].toString().padLeft(5)}');
  }
}
