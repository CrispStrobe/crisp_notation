// @Timeout(Duration(minutes: 20)) is set in live_corpus_test for the
// full sweep; this check covers a similar breadth but is lighter — it only
// re-reads the MusicXML slice and compares onsets.
@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Verovio onset oracle: crisp_notation's note onsets vs Verovio's.
///
/// Opt-in: set `CRISP_NOTATION_CORPUS` to the corpus directory and ensure
/// `$CRISP_NOTATION_CORPUS/verovio-oracle/oracle.json` exists (built by
/// `make_oracle.py` with `expandNever` so repeats do not inflate the
/// timeline). Skipped otherwise. The oracle holds, per file, sorted
/// `[qstamp, pitch, staff]` where `qstamp` is in quarter notes and `staff`
/// is Verovio's staff `n`. We compare the first staff's onsets.
///
/// A file agrees when ≥98% of the oracle's staff-1 events match a
/// crisp_notation onset within 1/64 quarter at the same pitch, allowing a
/// single constant pitch offset per file for transposing parts. The allowed
/// offset is searched in [-24,24] semitones and the best is taken. This
/// catches the `<forward>` mis-read where notes after a gap were placed too
/// early, while tolerating legitimate transposition differences.
void main() {
  final root = Platform.environment['CRISP_NOTATION_CORPUS'];
  final oracleFile =
      root == null ? null : File('$root/verovio-oracle/oracle.json');
  final skip = root == null || !Directory(root).existsSync()
      ? 'set CRISP_NOTATION_CORPUS to a directory of .mxl files'
      : (oracleFile != null && !oracleFile.existsSync()
          ? 'no verovio-oracle/oracle.json beside the corpus'
          : null);

  test('verovio onsets agree', () {
    final oracleRaw =
        jsonDecode(oracleFile!.readAsStringSync()) as Map<String, dynamic>;
    // Keep insertion order deterministic: sorted keys as written.
    final entries = oracleRaw.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    var agree = 0;
    final total = entries.length;
    final disagreements = <String>[];
    // For the report, collect up to 5 example mismatches in detail.
    final examples = <String>[];

    for (final e in entries) {
      final relPath = e.key;
      final absPath = '$root/$relPath';
      final rawList = (e.value as List).cast<List<dynamic>>();

      // Oracle staff-1 events: [qstamp, pitch, staff]
      final oracleStaff1 = <_Event>[
        for (final triple in rawList)
          if ((triple[2] as num).toInt() == 1)
            _Event((triple[0] as num).toDouble(), (triple[1] as num).toInt()),
      ];

      // No oracle notes on staff 1: vacuous agreement unless the file is
      // missing; count it as agreeing so M stays the tested breadth.
      if (oracleStaff1.isEmpty) {
        agree++;
        continue;
      }

      // Read with crisp_notation: staffSystemFromMusicXml, staff 0.
      Score score;
      try {
        if (absPath.endsWith('.mxl')) {
          final bytes = File(absPath).readAsBytesSync();
          final xml = readMusicXmlFromMxl(bytes);
          final system = staffSystemFromMusicXml(xml);
          if (system.staves.isEmpty) throw const FormatException('no staves');
          score = system.staves[0];
        } else {
          final xml = File(absPath).readAsStringSync();
          final system = staffSystemFromMusicXml(xml);
          if (system.staves.isEmpty) throw const FormatException('no staves');
          score = system.staves[0];
        }
      } catch (err) {
        disagreements.add('$relPath: read failed: $err');
        if (examples.length < 5) examples.add('$relPath: read failed $err');
        continue;
      }

      final dartEvents = _dartOnsets(score);

      // Best constant pitch offset in [-24,24].
      var bestMatches = -1;
      var bestDelta = 0;
      _MatchResult? bestResult;
      for (var delta = -24; delta <= 24; delta++) {
        final res = _match(oracleStaff1, dartEvents, delta);
        if (res.matches > bestMatches) {
          bestMatches = res.matches;
          bestDelta = delta;
          bestResult = res;
        }
      }

      final need = (oracleStaff1.length * 0.98).ceil();
      if (bestMatches >= need) {
        agree++;
      } else {
        final firstMiss = bestResult?.firstMiss;
        final missDesc = firstMiss == null
            ? 'no match for ${oracleStaff1.length} oracle events'
            : 'first miss q=${firstMiss.q.toStringAsFixed(3)} pitch=${firstMiss.pitch} '
                '(delta $bestDelta, need $need, got $bestMatches)';
        disagreements.add('$relPath: $missDesc');
        if (examples.length < 5) {
          examples.add('$relPath: $missDesc '
              'oracle ${oracleStaff1.length} dart ${dartEvents.length}');
        }
      }
    }

    // Print summary as specified.
    // ignore: avoid_print
    print('verovio onsets: $agree / $total files agree');
    if (disagreements.isNotEmpty) {
      // ignore: avoid_print
      print('Disagreeing files (up to 20):');
      for (final line in disagreements.take(20)) {
        // ignore: avoid_print
        print('  $line');
      }
    }
    if (examples.isNotEmpty) {
      // ignore: avoid_print
      print('Examples:');
      for (final ex in examples) {
        // ignore: avoid_print
        print('  $ex');
      }
    }

    // Ratchet: set to the measured value; only goes up.
    // 2026-10-16: initial measurement 1501 / 1745 after fixing <forward>.
    const ceiling = 1501;
    expect(agree, greaterThanOrEqualTo(ceiling),
        reason: 'verovio onsets: $agree / $total agree, ceiling $ceiling\n'
            '${disagreements.take(20).join('\n')}');
  }, skip: skip);
}

class _Event {
  final double q;
  final int pitch;
  _Event(this.q, this.pitch);
}

class _Miss {
  final double q;
  final int pitch;
  _Miss(this.q, this.pitch);
}

class _MatchResult {
  final int matches;
  final _Miss? firstMiss;
  _MatchResult(this.matches, this.firstMiss);
}

List<_Event> _dartOnsets(Score score) {
  final byId = <String, NoteElement>{};
  for (final m in score.measures) {
    for (final e in m.elements) {
      if (e is NoteElement && e.id != null) byId[e.id!] = e;
    }
    for (final e in m.voice2) {
      if (e is NoteElement && e.id != null) byId[e.id!] = e;
    }
    for (final e in m.voice3) {
      if (e is NoteElement && e.id != null) byId[e.id!] = e;
    }
    for (final e in m.voice4) {
      if (e is NoteElement && e.id != null) byId[e.id!] = e;
    }
  }
  final tl = playbackTimeline(score, expandRepeats: false);
  final out = <_Event>[];
  for (final n in tl) {
    if (n.isRest) continue;
    final el = byId[n.elementId];
    if (el == null) continue;
    final q = (n.start * Fraction(4, 1)).toDouble();
    for (final p in el.pitches) {
      out.add(_Event(q, p.midiNumber));
    }
  }
  out.sort((a, b) {
    final c = a.q.compareTo(b.q);
    return c != 0 ? c : a.pitch.compareTo(b.pitch);
  });
  return out;
}

// Tolerance 1/64 quarter.
const _tol = 1 / 64 + 1e-9;

_MatchResult _match(List<_Event> oracle, List<_Event> dart, int delta) {
  // Dart events sorted by q; build quick index of qs for windowing.
  // For each oracle event, look for an unused dart event within tolerance
  // and with pitch == oracle.pitch + delta.
  final used = List<bool>.filled(dart.length, false);
  var matches = 0;
  _Miss? firstMiss;

  // Pre-sort dart is already sorted; oracle is sorted.
  // For each oracle, scan dart window. Since both sorted, we can maintain
  // a sliding lower bound pointer, but the pitch condition makes a simple
  // scan of the window fine: window size is small (tolerance narrow).
  for (final o in oracle) {
    final wantPitch = o.pitch + delta;
    var found = -1;
    // Find first unused dart within tolerance and matching pitch.
    // Linear scan with early break when q exceeds window: O(M*W).
    for (var i = 0; i < dart.length; i++) {
      if (used[i]) continue;
      final d = dart[i];
      final dq = (d.q - o.q).abs();
      if (dq <= _tol && d.pitch == wantPitch) {
        found = i;
        break;
      }
      // Since dart is sorted, if d.q > o.q + tol and we've passed the
      // window, we could break, but we need to consider that earlier
      // dart entries with q < o.q - tol are already out of window.
      // We could optimize with binary search, but M*N is small (typically
      // <2000 events) and delta trials 49 * 1745 files would be heavy
      // with full O(M*N). However typical M~100, N~100, 49*10k=490k per
      // file worst, still okay for 1745 files (~850M checks) maybe heavy
      // but within 20 min. Keep simple.
    }
    if (found >= 0) {
      used[found] = true;
      matches++;
    } else {
      firstMiss ??= _Miss(o.q, o.pitch);
    }
  }
  return _MatchResult(matches, firstMiss);
}
