@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Verovio onset oracle: the first staff's note onsets as crisp_notation
/// reads them, against Verovio's timing map of the same file.
///
/// Opt-in: `CRISP_NOTATION_CORPUS` names the corpus, and
/// `$CRISP_NOTATION_CORPUS/verovio-oracle/oracle.json` holds, per file,
/// `[qstamp, midi pitch, staff]` (quarter notes, repeats not expanded,
/// grace notes left out) — built by `tool/verovio_oracle/make_oracle.py`.
///
/// A file agrees when 98% of Verovio's staff-1 notes find a crisp_notation
/// note within 1/64 quarter at the same pitch, allowing one constant pitch
/// offset per file (a transposing part written at sounding pitch). Set
/// `CRISP_ORACLE_REPORT` to a path to get every disagreeing file listed.
void main() {
  final root = Platform.environment['CRISP_NOTATION_CORPUS'];
  final oracleFile =
      root == null ? null : File('$root/verovio-oracle/oracle.json');
  final skip = root == null || !Directory(root).existsSync()
      ? 'set CRISP_NOTATION_CORPUS to the corpus directory'
      : (!oracleFile!.existsSync()
          ? 'no verovio-oracle/oracle.json in the corpus'
          : null);

  test('note onsets agree with Verovio', () {
    final oracle =
        jsonDecode(oracleFile!.readAsStringSync()) as Map<String, dynamic>;
    final paths = oracle.keys.toList()..sort();
    var agree = 0;
    final disagreements = <String>[];
    for (final path in paths) {
      final expected = [
        for (final e in (oracle[path] as List).cast<List<dynamic>>())
          if ((e[2] as num).toInt() == 1)
            _Event((e[0] as num).toDouble(), (e[1] as num).toInt()),
      ];
      if (expected.isEmpty) {
        agree++;
        continue;
      }
      final List<_Event> actual;
      try {
        final file = File('$root/$path');
        final xml = path.endsWith('.mxl')
            ? readMusicXmlFromMxl(file.readAsBytesSync())
            : file.readAsStringSync();
        final staves = staffSystemFromMusicXml(xml).staves;
        if (staves.isEmpty) throw const FormatException('no staves');
        actual = _onsets(staves.first);
      } on Object catch (e) {
        disagreements.add('$path: read failed: $e');
        continue;
      }
      final need = (expected.length * 0.98).ceil();
      var best = _match(expected, actual, 0);
      var bestDelta = 0;
      for (var delta = -24; best.matches < need && delta <= 24; delta++) {
        if (delta == 0) continue;
        final m = _match(expected, actual, delta);
        if (m.matches > best.matches) (best, bestDelta) = (m, delta);
      }
      if (best.matches >= need) {
        agree++;
      } else {
        final miss = best.firstMiss!;
        disagreements.add('$path: ${best.matches}/${expected.length} '
            '(crisp ${actual.length}), first miss at quarter '
            '${miss.q.toStringAsFixed(3)} pitch ${miss.pitch}'
            '${bestDelta == 0 ? '' : ' (offset $bestDelta)'}');
      }
    }
    // ignore: avoid_print
    print('verovio onsets: $agree / ${paths.length} files agree');
    final report = Platform.environment['CRISP_ORACLE_REPORT'];
    if (report != null) {
      File(report).writeAsStringSync(disagreements.join('\n'));
    }

    // A ratchet: raise it as fixes land, never lower it.
    // 2026-10-16: 1501 / 1745 at the first measurement; 1645 once grace
    // notes may start on the beat; 1678 after whole-bar rests fill the bar.
    const floor = 1678;
    expect(agree, greaterThanOrEqualTo(floor),
        reason: disagreements.take(20).join('\n'));
  }, skip: skip);
}

class _Event {
  final double q;
  final int pitch;

  /// How much later Verovio may start this note: a note after grace notes
  /// starts on the beat in crisp_notation (the graces take time before it)
  /// but after the graces in Verovio, which plays them on the beat.
  final double slack;

  const _Event(this.q, this.pitch, [this.slack = 0]);
}

/// Every sounding note of [score] as (quarter-note onset, MIDI pitch), in
/// document order (repeats not expanded), sorted by onset.
List<_Event> _onsets(Score score) {
  final byId = <String, NoteElement>{
    for (final m in score.measures)
      for (final e in [...m.elements, ...m.voice2, ...m.voice3, ...m.voice4])
        if (e is NoteElement && e.id != null) e.id!: e,
  };
  final out = <_Event>[
    for (final n in playbackTimeline(score, expandRepeats: false))
      if (!n.isRest && byId[n.elementId] != null)
        for (final p in byId[n.elementId]!.pitches)
          _Event(
              (n.start * Fraction(4, 1)).toDouble(),
              p.midiNumber,
              byId[n.elementId]!.graceNotes.isEmpty
                  ? 0
                  : (n.duration * Fraction(2, 1)).toDouble()),
  ]..sort((a, b) => a.q.compareTo(b.q));
  return out;
}

const _tolerance = 1 / 64 + 1e-9;

/// How many of [expected] find an unused note of [actual] (both sorted by
/// onset) within [_tolerance] (and its slack) at pitch + [delta]; and the first that does not.
({int matches, _Event? firstMiss}) _match(
    List<_Event> expected, List<_Event> actual, int delta) {
  final used = List<bool>.filled(actual.length, false);
  final slack = actual.fold<double>(0, (m, a) => a.slack > m ? a.slack : m);
  var matches = 0;
  _Event? firstMiss;
  var low = 0;
  for (final e in expected) {
    while (low < actual.length && actual[low].q < e.q - slack - _tolerance) {
      low++;
    }
    var found = false;
    for (var i = low;
        i < actual.length && actual[i].q <= e.q + _tolerance;
        i++) {
      final a = actual[i];
      if (!used[i] &&
          a.pitch == e.pitch + delta &&
          e.q >= a.q - _tolerance &&
          e.q <= a.q + a.slack + _tolerance) {
        used[i] = true;
        found = true;
        break;
      }
    }
    if (found) {
      matches++;
    } else {
      firstMiss ??= e;
    }
  }
  return (matches: matches, firstMiss: firstMiss);
}
