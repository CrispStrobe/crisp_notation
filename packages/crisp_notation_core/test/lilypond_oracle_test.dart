library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// LilyPond reader vs LilyPond's own MIDI (ly-oracle).
///
/// Opt-in exactly like verovio_oracle_test.dart: set `CRISP_NOTATION_CORPUS`
/// to the corpus directory and have `$CRISP_NOTATION_CORPUS/ly-oracle/oracle.json`
/// beside it (made by compiling every `.ly` to MIDI with the real LilyPond
/// and summarising each track). Set `CRISP_LY_REPORT` to a path to get every
/// disagreeing file listed with WHY (notes ours vs LilyPond, end ours vs
/// theirs, pitch error, crash message).
void main() {
  final root = Platform.environment['CRISP_NOTATION_CORPUS'];
  final oracleFile = root == null ? null : File('$root/ly-oracle/oracle.json');
  final skip = root == null || !Directory(root).existsSync()
      ? 'set CRISP_NOTATION_CORPUS to the corpus directory'
      : (!oracleFile!.existsSync()
          ? 'no ly-oracle/oracle.json in the corpus'
          : null);

  test('LilyPond: the reader agrees with LilyPond\'s own MIDI', () {
    final oracle = jsonDecode(oracleFile!.readAsStringSync()) as Map;
    final lyRoot = '$root/mutopia';
    final byKey = <String, File>{
      for (final f in Directory(lyRoot).listSync(recursive: true))
        if (f is File && f.path.endsWith('.ly'))
          f.path
              .substring(lyRoot.length + 1)
              .replaceAll('/', '_')
              .replaceAll(RegExp(r'\.ly$'), ''): f,
    };

    (int, double, Map<int, int>) summary(Score s, bool expand) {
      final byId = <String, NoteElement>{};
      final prev = <String, MusicElement?>{};
      // A tie over the barline is one held note too: the voice's last element
      // carries from one bar into the next.
      final last = List<MusicElement?>.filled(4, null);
      for (final m in s.measures) {
        for (var v = 0; v < 4; v++) {
          for (final e in m.voiceAt(v)) {
            if (e is NoteElement && e.id != null) {
              byId[e.id!] = e;
              prev[e.id!] = last[v];
            }
            last[v] = e;
          }
        }
      }
      var notes = 0;
      var end = 0.0;
      final hist = <int, int>{};
      // LilyPond's MIDI strikes a pitch once when two voices of one staff
      // start it together (unisons, `<c c>`): its MIDI walker merges them.
      final struck = <(Fraction, int)>{};
      for (final n in playbackTimeline(s,
          expandRepeats: expand, voiceChordSymbols: true)) {
        // A ChordNames track: LilyPond's MIDI plays it, on a track of its own.
        if (n.chordPitches case final chord?) {
          end = max(end, (n.start + n.duration).toDouble() * 4);
          for (final p in chord) {
            notes++;
            hist[p.midiNumber] = (hist[p.midiNumber] ?? 0) + 1;
          }
          continue;
        }
        final e = byId[n.elementId];
        if (e == null) continue;
        // MIDI ends with its last note: a trailing rest or skip plays nothing.
        end = max(end, (n.start + n.duration).toDouble() * 4);
        final before = prev[n.elementId];
        for (final p in e.pitches) {
          if (before is NoteElement &&
              before.tieToNext &&
              before.pitches.contains(p)) {
            continue;
          }
          if (!struck.add((n.start, p.midiNumber))) continue;
          notes++;
          hist[p.midiNumber] = (hist[p.midiNumber] ?? 0) + 1;
        }
        for (final g in e.graceNotes) {
          notes++;
          hist[g.midiNumber] = (hist[g.midiNumber] ?? 0) + 1;
        }
      }
      return (notes, end, hist);
    }

    var total = 0, agree = 0;
    final crashes = <String>[];
    final disagreements = <String>[];

    for (final MapEntry(:key, :value) in oracle.entries) {
      final tracks = (value as List).cast<Map<String, dynamic>>();
      final file = byKey[key];
      if (tracks.isEmpty || file == null) continue;
      total++;
      final MultiPartScore mp;
      try {
        mp = multiPartFromLilyPond(file.readAsStringSync(), playback: true);
      } on Object catch (e) {
        crashes.add('$key: $e');
        disagreements.add('$key: CRASH $e');
        continue;
      }
      final oNotes = tracks.fold<int>(0, (a, t) => a + (t['notes'] as int));
      final oEnd = tracks.map((t) => (t['end'] as num).toDouble()).reduce(max);
      final oHist = <int, int>{};
      for (final t in tracks) {
        (t['pitches'] as Map).forEach(
          (k, v) => oHist[int.parse(k as String)] =
              (oHist[int.parse(k)] ?? 0) + (v as int),
        );
      }
      var matched = false;
      // Track best disagreement details for reporting
      int bestNotes = 0;
      double bestEnd = 0;
      double bestPitchErr = 0;
      var expandedWhy = '';
      for (final expand in [true, false]) {
        var n = 0;
        var e = 0.0;
        final h = <int, int>{};
        for (final part in mp.parts) {
          final (pn, pe, ph) = summary(part.atConcertPitch(), expand);
          n += pn;
          e = max(e, pe);
          ph.forEach((k, v) => h[k] = (h[k] ?? 0) + v);
        }
        final pitchErr = {...h.keys, ...oHist.keys}.fold<int>(
              0,
              (a, k) => a + ((h[k] ?? 0) - (oHist[k] ?? 0)).abs(),
            ) /
            max(1, oNotes);
        if ((n - oNotes).abs() <= 0.02 * oNotes &&
            (e - oEnd).abs() <= 1.0 &&
            pitchErr <= 0.05) {
          agree++;
          matched = true;
          break;
        }
        // Keep last (expand=false) for reporting if neither matched
        if (expand) {
          expandedWhy = ' [unfolded: notes $n, end ${e.toStringAsFixed(1)}, '
              'pitchErr ${pitchErr.toStringAsFixed(3)}]';
        }
        bestNotes = n;
        bestEnd = e;
        bestPitchErr = pitchErr;
      }
      if (!matched) {
        final notesOk = (bestNotes - oNotes).abs() <= 0.02 * oNotes;
        final endOk = (bestEnd - oEnd).abs() <= 1.0;
        final pitchOk = bestPitchErr <= 0.05;
        final why = <String>[];
        if (!notesOk) why.add('notes $bestNotes vs $oNotes');
        if (!endOk) {
          why.add(
            'end ${bestEnd.toStringAsFixed(1)} vs ${oEnd.toStringAsFixed(1)}',
          );
        }
        if (!pitchOk) why.add('pitchErr ${bestPitchErr.toStringAsFixed(3)}');
        if (why.isEmpty) why.add('unknown');
        disagreements.add('$key: ${why.join(', ')}$expandedWhy');
      }
    }
    // ignore: avoid_print
    print('LilyPond oracle: $agree / $total files agree');
    final report = Platform.environment['CRISP_LY_REPORT'];
    if (report != null) {
      // Include crashes already in disagreements; write all disagreements
      File(report).writeAsStringSync(disagreements.join('\n'));
    }

    expect(crashes, isEmpty, reason: crashes.take(10).join('\n'));
    expect(total, greaterThan(300));
    // Ratchet (2026-10-06: 123 of 374, from 13 before the oracle existed;
    // 2026-10-17: 124 once a score-level \transposition in \midi is read, 152
    // with `q` chord repeats; 2026-10-18: 190 once a unison struck by two
    // voices of a staff counts once, as LilyPond's MIDI plays it; 210 once the
    // end is the last note's, not a trailing rest's; 242 once a pickup in voice
    // 1 times every voice; 254 once a tie over the barline counts as the one
    // held note it is; 256 once a pickup stated in one staff times the others;
    // 258 once `s1*0` takes no time; 269 once a voice's inner voices survive a
    // second voice beside it; 290 once the comparison reads the score LilyPond
    // plays; 291 once staves behind \relative are found; 292 once a mid-piece
    // \partial starts a bar; 298 once \unfoldRepeats is honoured; 304 once a
    // pitched rest is a rest; 305 once \relative without a pitch reckons from
    // f; 308 once \repeat unfold keeps its octaves; 314 once <b,g> is two
    // pitches; 316 once a note crossing the barline is cut into tied notes; 318
    // once d8cis is two notes; 319 once a grace's duration carries on; 322 once
    // a grace spacer or chord takes no time; 324 once a repeat body need not be
    // braced; 328 once \unfoldRepeats is honoured anywhere; 329 once a percent
    // repeat takes its time; 332 once e'd is two notes; 335 once fingerings in
    // a chord are not pitches; 337 once a voice split after a triplet starts on
    // time; 338 once a resting voice keeps out of a full bar; 339 once c8*2/3
    // is a triplet eighth; 341 once \transposition is no music; 343 once a
    // Dynamics line beside a lone staff is not its music; 344 once a named
    // staff re-entered goes on; 346 once R2. * 7 keeps its multiplier; 348 once
    // R\breve*4 keeps its multiplier; 349 once \tuplet takes a span duration;
    // 354 once a ChordNames track sounds, as LilyPond plays it).
    expect(
      agree,
      greaterThanOrEqualTo(354),
      reason: disagreements.take(20).join('\n'),
    );
  }, skip: skip);
}
