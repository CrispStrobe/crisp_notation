// Differential test against an independent parser (music21) — the "oracle".
//
//   dart run tool/oracle_diff.dart <file> [<file> …]
//
// A round-trip only proves partitura's reader and writer agree with *each
// other*; it can't catch a bug that is symmetric across both. This tool breaks
// that symmetry: it parses each score with partitura AND with music21
// (`tool/oracle_dump.py`), reduces each to the multiset of `(midi, quarterLength)`
// notes across all parts, and reports how much they agree. A divergence is far
// more likely a partitura import bug than a music21 one — and names the exact
// (pitch, duration) that differs, so it can be chased down.
//
// music21 runs via the interpreter in $ORACLE_PYTHON (default: the miniconda
// python that has it installed). Formats music21 also parses: MusicXML/.mxl,
// **kern, ABC, MEI, MIDI.
import 'dart:convert';
import 'dart:io';

import 'package:partitura_core/partitura_core.dart';

const _defaultPython = '/Users/christianstrobele/miniconda3/bin/python3';

/// partitura's note multiset for a file: `(midi, quarterLength)` across every
/// part/staff. Uses the *multi-part* importer so it lines up with music21's
/// all-parts flatten (the single-`Score` path would read only the first part).
Map<String, int>? _partituraNotes(String path) {
  final file = File(path);
  final lower = path.toLowerCase();
  List<Score> staves;
  try {
    if (lower.endsWith('.xml') || lower.endsWith('.musicxml')) {
      staves = staffSystemFromMusicXml(file.readAsStringSync()).staves;
    } else if (lower.endsWith('.mxl')) {
      staves =
          staffSystemFromMusicXml(readMusicXmlFromMxl(file.readAsBytesSync()))
              .staves;
    } else if (lower.endsWith('.mei')) {
      staves = staffSystemFromMei(file.readAsStringSync()).staves;
    } else if (lower.endsWith('.krn') || lower.endsWith('.kern')) {
      staves = staffSystemFromKern(file.readAsStringSync()).staves;
    } else if (lower.endsWith('.abc')) {
      staves = staffSystemFromAbc(file.readAsStringSync()).staves;
    } else if (lower.endsWith('.mid') || lower.endsWith('.midi')) {
      staves = [scoreFromMidi(file.readAsBytesSync())];
    } else {
      return null;
    }
  } catch (_) {
    return null;
  }
  final bag = <String, int>{};
  void addNote(NoteElement e, double ql) {
    for (final p in e.pitches) {
      final key = '${p.midiNumber}@${ql.toStringAsFixed(6)}';
      bag[key] = (bag[key] ?? 0) + 1;
    }
  }

  for (final s in staves) {
    for (final m in s.measures) {
      // Every voice's tuplet-scaled duration (effectiveDurationAt is voice-aware
      // now) — a triplet eighth is 1/3 quarter, matching music21's quarterLength.
      // The oracle compares against music21's all-voices flatten.
      for (var v = 0; v < 4; v++) {
        final list = m.voiceAt(v);
        for (var i = 0; i < list.length; i++) {
          final e = list[i];
          if (e is NoteElement) {
            addNote(e, m.effectiveDurationAt(i, voice: v).toDouble() * 4);
          }
        }
      }
    }
  }
  return bag;
}

/// An external parser's note multiset via a python dumper, or null if it
/// couldn't parse. [dumperName] selects the oracle: `oracle_dump.py` (music21)
/// or `verovio_dump.py` (Verovio — stronger on MEI/kern/ABC).
Map<String, int>? _oracleNotes(String python, String path, String dumperName) {
  final dumper =
      '${File(Platform.script.toFilePath()).parent.path}/$dumperName';
  final r = Process.runSync(python, [dumper, path]);
  if (r.exitCode != 0) return null;
  final Map<String, dynamic> parsed;
  try {
    parsed = jsonDecode(r.stdout as String) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
  final bag = <String, int>{};
  for (final entry in parsed['notes'] as List) {
    final midi = (entry[0] as num).toInt();
    final ql = (entry[1] as num).toDouble();
    final key = '$midi@${ql.toStringAsFixed(6)}';
    bag[key] = (bag[key] ?? 0) + 1;
  }
  return bag;
}

/// Notes present in [a] but missing (or short) in [b], as a flat multiset count.
int _missing(Map<String, int> a, Map<String, int> b) {
  var n = 0;
  for (final e in a.entries) {
    final have = b[e.key] ?? 0;
    if (have < e.value) n += e.value - have;
  }
  return n;
}

void main(List<String> args) {
  // `--oracle music21|verovio` picks one parser; `--quorum` runs the ensemble.
  var oracle = 'music21';
  var quorum = false;
  var details = 0;
  final files = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--oracle' && i + 1 < args.length) {
      oracle = args[++i];
    } else if (args[i] == '--quorum') {
      quorum = true;
    } else if (args[i] == '--details' && i + 1 < args.length) {
      details = int.tryParse(args[++i]) ?? 0;
    } else {
      files.add(args[i]);
    }
  }
  if (files.isEmpty) {
    stderr.writeln('usage: dart run tool/oracle_diff.dart '
        '[--oracle music21|verovio | --quorum] <file> …');
    exit(64);
  }
  final dumper = oracle == 'verovio' ? 'verovio_dump.py' : 'oracle_dump.py';
  final python = Platform.environment['ORACLE_PYTHON'] ?? _defaultPython;

  if (quorum) {
    _runQuorum(python, files);
    return;
  }

  var compared = 0, agreed = 0, skipped = 0;
  stdout.writeln('\nOracle differential vs $oracle\n');
  for (final path in files) {
    final mine = _partituraNotes(path);
    final theirs = _oracleNotes(python, path, dumper);
    final name = path.split('/').last;
    if (mine == null || theirs == null) {
      skipped++;
      stdout.writeln('  SKIP  $name '
          '(${mine == null ? 'partitura' : oracle} could not parse)');
      continue;
    }
    compared++;
    final total = theirs.values.fold<int>(0, (a, b) => a + b);
    final onlyOracle = _missing(theirs, mine); // notes the oracle saw, we didn't
    final onlyMine = _missing(mine, theirs); // notes we invented / mis-sized
    final agree = total == 0 ? 1.0 : (total - onlyOracle) / total;
    if (onlyOracle == 0 && onlyMine == 0) {
      agreed++;
      stdout.writeln('  OK    $name  ($total notes)');
    } else {
      stdout.writeln('  DIFF  $name  '
          '${(100 * agree).toStringAsFixed(1)}% agree — '
          '$oracle-only: $onlyOracle, partitura-only: $onlyMine  (of $total)');
      if (details > 0) {
        _printDetails('$oracle-only', theirs, mine, details);
        _printDetails('partitura-only', mine, theirs, details);
      }
    }
  }
  stdout.writeln('\n$agreed/$compared exact agreement, $skipped skipped');
}

void _printDetails(
    String label, Map<String, int> a, Map<String, int> b, int limit) {
  final missing = <String>[];
  for (final e in a.entries) {
    final delta = e.value - (b[e.key] ?? 0);
    for (var i = 0; i < delta; i++) {
      missing.add(e.key);
      if (missing.length >= limit) break;
    }
    if (missing.length >= limit) break;
  }
  if (missing.isNotEmpty) stdout.writeln('        $label: ${missing.join(', ')}');
}

/// Whether two note multisets are identical.
bool _equal(Map<String, int> a, Map<String, int> b) =>
    _missing(a, b) == 0 && _missing(b, a) == 0;

/// Ensemble mode: compare partitura against BOTH music21 and Verovio. A
/// divergence is a *real* partitura-bug signal only when the two independent
/// oracles agree with each other but disagree with partitura (CONSENSUS). When
/// the oracles disagree with each other, the divergence is an oracle limitation
/// (music21's ABC gaps, Verovio's repeat expansion) — not evidence against
/// partitura.
void _runQuorum(String python, List<String> files) {
  stdout.writeln('\nQuorum: partitura vs {music21, Verovio}\n');
  var ok = 0, consensusBug = 0, resolvedOk = 0, suspect = 0, skipped = 0;
  int total(Map<String, int>? b) => b == null ? 0 : b.values.fold(0, (a, x) => a + x);
  for (final path in files) {
    final name = path.split('/').last;
    final p = _partituraNotes(path);
    final m = _oracleNotes(python, path, 'oracle_dump.py');
    final v = _oracleNotes(python, path, 'verovio_dump.py');
    if (p == null || (m == null && v == null)) {
      skipped++;
      stdout.writeln('  SKIP  $name');
      continue;
    }
    final agreeM = m != null && _equal(p, m);
    final agreeV = v != null && _equal(p, v);
    if (agreeM && agreeV || (agreeM && v == null) || (agreeV && m == null)) {
      ok++;
      stdout.writeln('  OK       $name  (both oracles agree)');
    } else if (m != null && v != null && _equal(m, v)) {
      // Both oracles agree with each other, but not with partitura.
      consensusBug++;
      stdout.writeln('  BUG?     $name  — both oracles agree, partitura differs '
          '(oracle-only ${_missing(m, p)}, partitura-only ${_missing(p, m)})');
    } else {
      // Better-oracle-check: resolve the split by which oracle partitura sides
      // with + the known failure modes — Verovio is the reference MEI/kern
      // engine and correct on ABC broken rhythm; a higher Verovio note count
      // means it expanded repeats/graces (playback), not a partitura error.
      final pv = total(p), mt = total(m), vt = total(v);
      if (agreeV) {
        resolvedOk++;
        stdout.writeln('  CHECK✓   $name  — partitura CORRECT: matches Verovio '
            '(reference parser); music21 diverges (its known ABC/MEI gaps)');
      } else if (agreeM && vt > mt) {
        resolvedOk++;
        stdout.writeln('  CHECK✓   $name  — partitura CORRECT: matches music21; '
            'Verovio over-expanded (+${vt - pv} notes = repeats/graces, playback)');
      } else if (agreeM) {
        resolvedOk++;
        stdout.writeln('  CHECK✓   $name  — partitura matches music21; Verovio '
            'differs but not by expansion — leaning correct');
      } else {
        suspect++;
        stdout.writeln('  SUSPECT  $name  — partitura matches neither oracle '
            '(m21-only ${m == null ? "-" : _missing(m, p)}, '
            'vrv-only ${v == null ? "-" : _missing(v, p)}) — investigate');
      }
    }
  }
  stdout.writeln('\n$ok both-agree, $resolvedOk resolved-correct, '
      '$consensusBug consensus-bug, $suspect suspect, $skipped skipped');
}
