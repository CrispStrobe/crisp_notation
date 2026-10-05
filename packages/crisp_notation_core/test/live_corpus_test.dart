@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crisp_notation_core/crisp_notation_core.dart';
// The sweep re-reads raw MusicXML to state its invariants independently of
// the reader under test.
import 'package:crisp_notation_core/src/musicxml/xml_reader.dart';
import 'package:test/test.dart';

/// Live sweep over a local corpus of REAL third-party scores.
///
/// Opt-in: set `CRISP_NOTATION_CORPUS` to a directory of `.mxl`, `.ly`,
/// `.krn` and `.mscx` files (searched recursively) and run
/// `dart test test/live_corpus_test.dart`. Skipped otherwise — the corpus is
/// not redistributable and does not live in the repo. Locally it is a copy of
/// CometBeat's music library (`music-db-backup-*` on the storage box):
/// ~1,700 MusicXML exports from MuseScore, Finale, Sibelius & co., Mutopia
/// LilyPond, and samples of the NIFC kern and MuseScore quartet sets.
///
/// Every format: each file parses, lays out with finite geometry, and
/// survives a MusicXML round trip with its note sequence intact. Plus,
/// pinning bugs that only showed on real exports:
///
/// - **#4** every printed `<metronome>` is read as its bar's tempo, whichever
///   `<direction-type>` block it sits in;
/// - **#1** every bar closed by `:|` (outside a volta) plays at least twice
///   when repeats are expanded — with or without an opening `|:`;
/// - **#2 / #3** every file lays out, with finite tie, slur and beam geometry
///   (which also caught a key-change crash in table-less clefs, and text
///   anchored on a rest — 14% of the LilyPond files — failing layout).
void main() {
  final root = Platform.environment['CRISP_NOTATION_CORPUS'];
  final skip = root == null || !Directory(root).existsSync()
      ? 'set CRISP_NOTATION_CORPUS to a directory of .mxl files'
      : null;

  late final List<File> files;
  late final LayoutSettings settings;
  final scores = <String, Score>{};
  final xmls = <String, String>{}; // MusicXML sources, for the #4 invariant
  final readers = <String, Score Function(File)>{
    '.mxl': (f) {
      final xml = readMusicXmlFromMxl(f.readAsBytesSync());
      xmls[f.path] = xml;
      return scoreFromMusicXml(xml);
    },
    '.ly': (f) => scoreFromLilyPond(f.readAsStringSync()),
    '.krn': (f) => scoreFromKern(f.readAsStringSync()),
    '.mscx': (f) => scoreFromMscx(f.readAsStringSync()),
  };
  String extOf(String path) => path.substring(path.lastIndexOf('.'));

  setUpAll(() {
    if (skip != null) return;
    final metadata =
        File('../crisp_notation/assets/smufl/bravura_metadata.json')
            .readAsStringSync();
    settings = LayoutSettings(
        metadata: SmuflMetadata.fromJson(
            jsonDecode(metadata) as Map<String, Object?>));
    files = Directory(root!)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => readers.containsKey(extOf(f.path)))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      try {
        scores[file.path] = readers[extOf(file.path)]!(file);
      } on Object {
        // Counted by 'every file parses' below.
      }
    }
  });

  test('every file parses, in every format', () {
    expect(files, isNotEmpty);
    final failures = [
      for (final f in files)
        if (!scores.containsKey(f.path)) f.path
    ];
    expect(failures, isEmpty,
        reason: '${failures.length} of ${files.length} failed to parse:\n'
            '${failures.take(20).join('\n')}');
  }, skip: skip);

  test('every score survives a MusicXML round trip, note for note', () {
    List<String> notesOf(Score s) => [
          for (final m in s.measures)
            for (final e in m.elements)
              if (e is NoteElement)
                '${e.pitches.join('+')}/${e.duration}'
              else if (e is RestElement)
                'r/${e.duration}'
        ];
    final failures = <String>[];
    for (final MapEntry(key: path, value: score) in scores.entries) {
      try {
        final back = scoreFromMusicXml(scoreToMusicXml(score));
        final want = notesOf(score), got = notesOf(back);
        if (got.join(' ') != want.join(' ')) {
          var i = 0;
          while (i < want.length && i < got.length && want[i] == got[i]) {
            i++;
          }
          failures.add('$path: note ${i + 1} '
              '${i < want.length ? want[i] : '-'} -> '
              '${i < got.length ? got[i] : '-'}');
        }
      } on Object catch (e) {
        failures.add('$path: ${e.runtimeType}: $e');
      }
    }
    expect(failures, isEmpty,
        reason: '${failures.length} of ${scores.length} round trips differ:\n'
            '${failures.take(20).join('\n')}');
  }, skip: skip);

  test('#4 every printed <metronome> on staff 1 of part 1 is the bar tempo',
      () {
    // Mirrors the reader: per bar, the FIRST direction stating a tempo sets
    // it, and within a direction a printed <metronome> beats <sound tempo>.
    // Most exporters write both, so merely "has a tempo" passed even when the
    // metronome was lost — the <sound> fallback (in quarter-notes) stood in,
    // e.g. 31.5 for a printed eighth = 63. The value must match the print.
    final failures = <String>[];
    var checked = 0;
    for (final MapEntry(key: path, value: xml) in xmls.entries) {
      final score = scores[path];
      if (score == null) continue;
      final part = parseXml(xml).child('part');
      if (part == null) continue;
      final measures = part.childrenNamed('measure').toList();
      // The reader may split or merge bars (pickups, multi-rests); only
      // compare files whose bar count lines up one-to-one.
      if (measures.length != score.measures.length) continue;
      for (var i = 0; i < measures.length; i++) {
        double? printed;
        for (final d in measures[i].childrenNamed('direction')) {
          if ((int.tryParse(d.childText('staff') ?? '1') ?? 1) != 1) continue;
          XmlNode? metronome;
          for (final t in d.childrenNamed('direction-type')) {
            metronome ??= t.child('metronome');
          }
          final bpm = double.tryParse(metronome?.childText('per-minute') ?? '');
          if (bpm != null && metronome!.child('beat-unit') != null) {
            printed = bpm;
            break;
          }
          final sound =
              double.tryParse(d.child('sound')?.attributes['tempo'] ?? '');
          if (sound != null && sound > 0) break; // an earlier tempo wins
        }
        if (printed == null) continue;
        checked++;
        final tempo = i == 0 ? score.tempo : score.measures[i].tempoChange;
        if (tempo?.bpm != printed) {
          failures.add('$path bar ${i + 1}: printed $printed, read '
              '${tempo?.bpm}');
        }
      }
    }
    expect(checked, greaterThan(0));
    expect(failures, isEmpty,
        reason: '${failures.length} of $checked tempo marks lost:\n'
            '${failures.take(20).join('\n')}');
  }, skip: skip);

  test('#1 every bar closed by :| plays at least twice when expanded', () {
    final failures = <String>[];
    var checked = 0;
    for (final MapEntry(key: path, value: score) in scores.entries) {
      final List<PlaybackNote> timeline;
      try {
        timeline = playbackTimeline(score);
      } on ArgumentError {
        continue; // a D.S. with no segno etc. — malformed navigation
      } on StateError {
        continue; // cyclic jumps
      }
      for (var i = 0; i < score.measures.length; i++) {
        final m = score.measures[i];
        if (!m.endRepeat || m.volta != null || m.elements.isEmpty) continue;
        checked++;
        // Passes through the bar = timeline entries for its first element.
        final firstId = m.elements.first.id;
        final passes = timeline.where((n) => n.elementId == firstId).length;
        if (passes < 2) failures.add('$path bar ${i + 1} played $passes×');
      }
    }
    expect(checked, greaterThan(0));
    expect(failures, isEmpty,
        reason: '${failures.length} of $checked :| bars not repeated:\n'
            '${failures.take(20).join('\n')}');
  }, skip: skip);

  test('#2 #3 every score lays out with finite curve and beam geometry', () {
    final failures = <String>[];
    var curves = 0, beams = 0;
    bool finite(Point<double> p) => p.x.isFinite && p.y.isFinite;
    for (final MapEntry(key: path, value: score) in scores.entries) {
      try {
        final layout = const LayoutEngine().layout(score, settings);
        for (final p in layout.primitives) {
          switch (p) {
            case CurvePrimitive(
                :final start,
                :final control1,
                :final control2,
                :final end
              ):
              curves++;
              if (![start, control1, control2, end].every(finite)) {
                failures.add('$path: non-finite curve');
              }
            case BeamPrimitive(:final start, :final end):
              beams++;
              if (!finite(start) || !finite(end) || end.x <= start.x) {
                failures.add('$path: degenerate beam $start → $end');
              }
            default:
          }
        }
      } on Object catch (e) {
        failures.add('$path: ${e.runtimeType}: $e');
      }
    }
    expect(curves, greaterThan(0));
    expect(beams, greaterThan(0));
    expect(failures, isEmpty,
        reason:
            '${failures.length} failures:\n${failures.take(20).join('\n')}');
  }, skip: skip);
}
