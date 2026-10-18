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

import 'support/layout_lint.dart';

/// Live sweep over a local corpus of REAL third-party scores.
///
/// Opt-in: set `CRISP_NOTATION_CORPUS` to a directory of `.mxl`, `.ly`,
/// `.krn`, `.mscx`, `.mei` and `.abc` files (searched recursively) and run
/// `dart test test/live_corpus_test.dart`. Skipped otherwise — the corpus is
/// not redistributable and does not live in the repo. Locally it is a copy of
/// CometBeat's music library (`music-db-backup-*` on the storage box):
/// ~1,700 MusicXML exports from MuseScore, Finale, Sibelius & co., Mutopia
/// LilyPond, and samples of the NIFC kern and MuseScore quartet sets, plus
/// the music-encoding project's MEI sample encodings (ECL-2.0) and 1,000
/// tunes of a held-out ABC set used for parser robustness only.
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
/// Staff line count, read from the drawn staff lines (full-width, id-less
/// horizontal lines at integer heights).
int staffLineCountOf(ScoreLayout l) {
  final ys = <double>{
    for (final ln in l.primitives.whereType<LinePrimitive>())
      if (ln.elementId == null &&
          ln.from.y == ln.to.y &&
          (ln.from.x - ln.to.x).abs() > l.width * 0.9)
        ln.from.y
  };
  return ys.isEmpty ? 5 : ys.length;
}

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
    // Uncompressed MusicXML: the LilyPond MusicXML test suite (MIT) and the
    // W3C examples in `musicxml-testsuite/`, one feature per file.
    '.xml': (f) {
      final xml = f.readAsStringSync();
      xmls[f.path] = xml;
      return scoreFromMusicXml(xml);
    },
    '.musicxml': (f) {
      final xml = f.readAsStringSync();
      xmls[f.path] = xml;
      return scoreFromMusicXml(xml);
    },
    '.ly': (f) => scoreFromLilyPond(f.readAsStringSync()),
    '.krn': (f) => scoreFromKern(f.readAsStringSync()),
    '.mscx': (f) => scoreFromMscx(f.readAsStringSync()),
    '.mei': (f) => scoreFromMei(f.readAsStringSync()),
    // A held-out ABC set for parser robustness only, never shipped.
    '.abc': (f) => scoreFromAbc(f.readAsStringSync()),
  };
  // Documents with no music at all (MEI header/metadata examples) are not
  // scores; their reader rejecting them is correct, not a parse failure.
  bool noMusic(Object e) =>
      e is FormatException && e.message.startsWith('No <score>');
  // Extensionless files (the nightly sweep's STATUS sits in the corpus dir)
  // are simply not scores.
  String extOf(String path) {
    final name = path.substring(path.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot);
  }

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
        // The LilyPond source checkout the test suite was copied out of.
        .where((f) => !f.path.contains('/ly-src/'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final notScores = <File>{};
    for (final file in files) {
      // Not third-party data: CometBeat's library backup holds, next to each
      // OpenScore quartet's `.mscx`, a stale single-part `sq<id>.mxl` that an
      // old crisp_notation conversion wrote (no `<software>` tag — OpenScore's
      // real exports all say MuseScore — and the old writer's slur numbering).
      // CometBeat never serves them; counted here they read as a broken
      // exporter, so they are left out rather than ceilinged.
      if (file.path.endsWith('.mxl') &&
          RegExp(r'/sq\d+\.mxl$').hasMatch(file.path) &&
          !readMusicXmlFromMxl(file.readAsBytesSync()).contains('<software>')) {
        notScores.add(file);
        continue;
      }
      try {
        scores[file.path] = readers[extOf(file.path)]!(file);
      } on Object catch (e) {
        if (noMusic(e)) notScores.add(file);
        // Anything else is counted by 'every file parses' below.
      }
    }
    files.removeWhere(notScores.contains);
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

  // Beyond the notes: the marks that render. Counts of slurs, dynamics,
  // hairpins, lyrics, ottavas and pedals, the annotation texts, tempo marks,
  // repeats/voltas and navigation, before and after a MusicXML round trip.
  // Only renderable marks count: a slur or hairpin whose ends exist in this
  // score (a single-staff read keeps other staves' slurs dangling), slurs
  // between notes (a slur from a rest cannot draw), non-blank text.
  //
  // Ceilings per format (share of files losing anything), just above today's
  // rate. LilyPond is the known gap: a separate `\new Dynamics` context's
  // spacer-rest marks land on another staff's rests, plus tempo restated per
  // bar and "Fine" text read back as a navigation mark (docs/HARDENING.md).
  test('marks survive a MusicXML round trip (per-format ceilings)', () {
    Map<String, String> marksOf(Score s) {
      final order = <String, int>{};
      final notes = <String>{};
      var k = 0;
      for (final m in s.measures) {
        for (var v = 0; v < 4; v++) {
          for (final e in m.voiceAt(v)) {
            if (e.id == null) continue;
            order[e.id!] = k++;
            if (e is NoteElement) notes.add(e.id!);
          }
        }
      }
      bool span(String a, String b, {bool notesOnly = false}) {
        final x = order[a], y = order[b];
        if (x == null || y == null || y < x) return false;
        return !notesOnly || (notes.contains(a) && notes.contains(b));
      }

      return {
        // Distinct slurs: a source that writes one slur several times over
        // the same notes (#14) is read as one.
        'slurs': '${{
          for (final x in s.slurs)
            if (x.startId != x.endId &&
                span(x.startId, x.endId, notesOnly: true))
              (x.startId, x.endId)
        }.length}',
        'dynamics':
            '${s.dynamics.where((d) => order.containsKey(d.elementId)).length}',
        'hairpins':
            '${s.hairpins.where((h) => span(h.startId, h.endId)).length}',
        'lyrics':
            '${s.lyrics.where((l) => order.containsKey(l.elementId)).length}',
        'ottavas': '${s.ottavas.where((o) => span(o.startId, o.endId)).length}',
        'pedals': '${s.pedals.where((p) => span(p.startId, p.endId)).length}',
        'annotations': (s.annotations
                .where((a) =>
                    order.containsKey(a.elementId) && a.text.trim().isNotEmpty)
                .map((a) => a.text.trim())
                .toList()
              ..sort())
            .join('|'),
        'tempo': [s.tempo?.bpm, for (final m in s.measures) m.tempoChange?.bpm]
            .whereType<double>()
            .join(','),
        'repeats': [
          for (final m in s.measures)
            '${m.startRepeat ? 1 : 0}${m.endRepeat ? 1 : 0}${m.volta ?? 0}'
        ].join(),
        'navigation':
            [for (final m in s.measures) m.navigation?.name ?? ''].join(','),
      };
    }

    const ceilings = {
      '.mxl': 0.005,
      '.krn': 0.005,
      '.abc': 0.01,
      '.mscx': 0.05,
      '.mei': 0.05,
      '.ly': 0.25,
    };
    final lossy = <String, List<String>>{};
    final counted = <String, int>{};
    for (final MapEntry(key: path, value: score) in scores.entries) {
      final ext = extOf(path);
      counted[ext] = (counted[ext] ?? 0) + 1;
      final Score back;
      try {
        back = scoreFromMusicXml(scoreToMusicXml(score));
      } on Object {
        (lossy[ext] ??= []).add('$path: round trip threw');
        continue;
      }
      final a = marksOf(score), b = marksOf(back);
      final lost = [
        for (final k in a.keys)
          if (a[k] != b[k]) k
      ];
      if (lost.isNotEmpty) {
        (lossy[ext] ??= []).add('${path.split('/').last}: ${lost.join(', ')}');
      }
    }
    for (final MapEntry(key: ext, value: n) in counted.entries) {
      final bad = lossy[ext] ?? const <String>[];
      expect(bad.length / n, lessThanOrEqualTo(ceilings[ext] ?? 0.0),
          reason: '$ext: ${bad.length} of $n files lose marks:\n'
              '${bad.take(15).join('\n')}');
    }
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

  // The multi-part writer: a piano's staves become one part with
  // `<staves>n</staves>` (and a chord across them keeps its one stem). Every
  // part's note onsets must come back, exactly. (25 drifted on the first
  // run, all older than the multi-staff part: lower voices' tuplets written
  // unscaled, and bar rests of a bar's own length written as plain whole
  // rests.) Every cross-staff chord keeps its link: its lower half is
  // written with its upper half, ahead of its staff's earlier music, and
  // the reader places it by onset (2 were lost while the writer kept such
  // halves on their own staff: the LilyPond test suite's 43d and 43h).
  test('every multi-part score survives a multi-part MusicXML round trip', () {
    List<String> onsets(Score s) => [
          for (final n in playbackTimeline(s, expandRepeats: false))
            if (!n.isRest) '${n.start}',
        ];
    final failures = <String>[];
    final linksLost = <String>[];
    var multiStaff = 0;
    for (final MapEntry(key: path, value: xml) in xmls.entries) {
      MultiPartScore doc;
      try {
        doc = multiPartScoreFromMusicXml(xml);
      } on Object {
        continue; // parse failures are 'every file parses''s business
      }
      try {
        final written = multiPartToMusicXml(doc);
        if (written.contains('<staves>')) multiStaff++;
        final back = multiPartScoreFromMusicXml(written);
        var same = back.parts.length == doc.parts.length;
        for (var i = 0; same && i < doc.parts.length; i++) {
          same =
              onsets(back.parts[i]).join(',') == onsets(doc.parts[i]).join(',');
        }
        if (!same) failures.add(path);
        if (back.crossStaffChords.length != doc.crossStaffChords.length) {
          linksLost.add(path);
        }
      } on Object catch (e) {
        failures.add('$path: ${e.runtimeType}: $e');
      }
    }
    // ignore: avoid_print
    print('multi-part round trip: $multiStaff multi-staff parts written, '
        '${failures.length} of ${xmls.length} differ, '
        '${linksLost.length} lose cross-staff chord links');
    expect(multiStaff, greaterThan(0));
    expect(failures, isEmpty, reason: failures.take(20).join('\n'));
    expect(linksLost, isEmpty, reason: linksLost.take(20).join('\n'));
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
        // A spacer has no id; count the bar's first addressable element.
        final firstId = m.elements.map((e) => e.id).nonNulls.firstOrNull;
        if (!m.endRepeat || m.volta != null || firstId == null) continue;
        checked++;
        // Passes through the bar = timeline entries for its first element.
        final passes = timeline.where((n) => n.elementId == firstId).length;
        if (passes < 2) failures.add('$path bar ${i + 1} played $passes×');
      }
    }
    expect(checked, greaterThan(0));
    expect(failures, isEmpty,
        reason: '${failures.length} of $checked :| bars not repeated:\n'
            '${failures.take(20).join('\n')}');
  }, skip: skip);

  // Curve geometry against the noteheads, the checks that found the
  // hairpin-under-slur, barline, rest-voice, cross-clef-tie and
  // crossing-voice-tie bugs:
  //   I1  every tie runs from a notehead to a notehead (0 allowed);
  //   I3  no tie runs through another notehead (ratchet: voice crossings
  //       where both sides collide remain, ~0.08% of ties);
  //   I2  no slur strays past its designed arch from the ink it may clear
  //       (notes, beams, tuplet/volta brackets, other curves; NOT barlines,
  //       staff lines, hairpins or dynamics). Per-format ceilings, see below.
  test('curves: ties land on heads, slurs keep near their own voice', () {
    final meta = settings.metadata;
    var ties = 0, slurs = 0;
    final i1 = <String>[], i2 = <String>[], i3 = <String>[];
    final slursByExt = <String, int>{}, i2ByExt = <String, int>{};
    for (final MapEntry(key: path, value: score) in scores.entries) {
      final ScoreLayout l;
      try {
        l = const LayoutEngine().layout(score, settings);
      } on Object {
        continue; // counted by the layout test below
      }
      final name = path.split('/').last;
      // (id, centreX, left, right, y) per notehead
      final heads = <(String, double, double, double, double)>[
        for (final g in l.primitives.whereType<GlyphPrimitive>())
          if (g.elementId != null && g.smuflName.startsWith('notehead'))
            () {
              final w = meta.bBoxOf(g.smuflName).width * g.scale;
              return (
                g.elementId!,
                g.position.x + w / 2,
                g.position.x,
                g.position.x + w,
                g.position.y
              );
            }(),
      ];
      final lv = {for (final v in score.laissezVibrer) v.noteId};
      final voiceOf = <String, int>{
        for (final m in score.measures)
          for (var v = 0; v < 4; v++)
            for (final e in m.voiceAt(v))
              if (e.id != null) e.id!: v,
      };
      final barOf = <String, int>{
        for (var b = 0; b < score.measures.length; b++)
          for (var v = 0; v < 4; v++)
            for (final e in score.measures[b].voiceAt(v))
              if (e.id != null) e.id!: b,
      };
      (double, double) extent(CurvePrimitive c) {
        var lo = double.infinity, hi = double.negativeInfinity;
        for (var k = 0; k <= 20; k++) {
          final t = k / 20, u = 1 - t;
          final y = u * u * u * c.start.y +
              3 * u * u * t * c.control1.y +
              3 * u * t * t * c.control2.y +
              t * t * t * c.end.y;
          lo = min(lo, y);
          hi = max(hi, y);
        }
        return (lo, hi);
      }

      // Indexed lookups: scanning every head per tie and every region per
      // slur made this check quadratic per score (it timed out on the large
      // quartets).
      String key(double x) => x.toStringAsFixed(4);
      final headsById =
          <String, List<(String, double, double, double, double)>>{};
      final headsByRight =
          <String, List<(String, double, double, double, double)>>{};
      final headsByLeft =
          <String, List<(String, double, double, double, double)>>{};
      for (final h in heads) {
        (headsById[h.$1] ??= []).add(h);
        (headsByRight[key(h.$4 + 0.15)] ??= []).add(h);
        (headsByLeft[key(h.$3 - 0.15)] ??= []).add(h);
      }
      final byCentre = [...heads]..sort((a, b) => a.$2.compareTo(b.$2));
      final centres = [for (final h in byCentre) h.$2];
      int lowerBound(List<double> xs, double x) {
        var lo = 0, hi = xs.length;
        while (lo < hi) {
          final mid = (lo + hi) >> 1;
          if (xs[mid] < x) {
            lo = mid + 1;
          } else {
            hi = mid;
          }
        }
        return lo;
      }

      final curves = l.primitives.whereType<CurvePrimitive>().toList();
      final slurCurvesByStart = <String, List<CurvePrimitive>>{};
      for (final c in curves) {
        if ((c.thickness - 0.2).abs() < 1e-9) {
          (slurCurvesByStart[key(c.start.x)] ??= []).add(c);
        }
      }
      // Each element's own ink (glyphs incl. articulations, stems, ledger
      // lines), as layout clears it. The hit-test regions are narrower.
      final inkById = <String, (double, double, double, double)>{};
      void addInk(String id, double l0, double t0, double r0, double b0) {
        final cur = inkById[id];
        inkById[id] = cur == null
            ? (l0, t0, r0, b0)
            : (
                min(cur.$1, l0),
                min(cur.$2, t0),
                max(cur.$3, r0),
                max(cur.$4, b0)
              );
      }

      for (final g in l.primitives.whereType<GlyphPrimitive>()) {
        if (g.elementId == null || voiceOf[g.elementId] == null) continue;
        final box = meta.bBoxOf(g.smuflName);
        addInk(
            g.elementId!,
            g.position.x + box.swX * g.scale,
            g.position.y - box.neY * g.scale,
            g.position.x + box.neX * g.scale,
            g.position.y - box.swY * g.scale);
      }
      for (final ln in l.primitives.whereType<LinePrimitive>()) {
        if (ln.elementId == null || voiceOf[ln.elementId] == null) continue;
        addInk(ln.elementId!, min(ln.from.x, ln.to.x), min(ln.from.y, ln.to.y),
            max(ln.from.x, ln.to.x), max(ln.from.y, ln.to.y));
      }
      // Sorted by left edge; a slur's window takes every element whose ink
      // OVERLAPS its span (an element's ink can reach far right through a
      // lyric extender, so its centre is no guide).
      final regions = [
        for (final MapEntry(key: id, value: (l0, t0, r0, b0))
            in inkById.entries)
          (l0, r0, id, t0, b0)
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      final regionLefts = [for (final r in regions) r.$1];
      // Ink that belongs to no element but that a slur may legitimately
      // clear: beams, tuplet brackets and numbers, volta brackets, ties and
      // other slurs. NOT barlines, staff lines, hairpins or dynamics: a slur
      // arching over those is exactly the bug this check exists to catch.
      final staffBottom = staffLineCountOf(l) - 1.0;
      final obstacles = <(double, double, double, double)>[
        for (final bm in l.primitives.whereType<BeamPrimitive>())
          (
            min(bm.start.x, bm.end.x),
            max(bm.start.x, bm.end.x),
            min(bm.start.y, bm.end.y) - bm.thickness / 2,
            max(bm.start.y, bm.end.y) + bm.thickness / 2,
          ),
        for (final g in l.primitives.whereType<GlyphPrimitive>())
          if (g.elementId == null && g.smuflName.startsWith('tuplet'))
            (
              g.position.x,
              g.position.x + 1.0,
              g.position.y - 1.5,
              g.position.y
            ),
        for (final ln in l.primitives.whereType<LinePrimitive>())
          if (ln.elementId == null &&
              // horizontal brackets, or short vertical hooks — not barlines
              // (full staff height), staff lines (full width) or hairpins
              // (sloped)
              ((ln.from.y == ln.to.y && (ln.from.x - ln.to.x).abs() < 40) ||
                  (ln.from.x == ln.to.x &&
                      (ln.from.y - ln.to.y).abs() < staffBottom - 0.5)))
            (
              min(ln.from.x, ln.to.x),
              max(ln.from.x, ln.to.x),
              min(ln.from.y, ln.to.y),
              max(ln.from.y, ln.to.y),
            ),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      final obstacleLefts = [for (final o in obstacles) o.$1];
      final curveExtents = [
        for (final c in curves)
          if ((c.thickness - 0.2).abs() < 1e-9 ||
              (c.thickness - 0.18).abs() < 1e-9)
            (c, min(c.start.x, c.end.x), max(c.start.x, c.end.x), extent(c))
      ];

      for (final c in curves) {
        if ((c.thickness - 0.18).abs() > 1e-9) continue;
        final from = (headsByRight[key(c.start.x)] ?? const [])
            .where((h) => ((c.start.y - h.$5).abs() - 0.6).abs() < 1e-6);
        if (from.isEmpty || lv.contains(from.first.$1)) continue;
        ties++;
        final landed = (headsByLeft[key(c.end.x)] ?? const [])
            .any((h) => ((c.end.y - h.$5).abs() - 0.6).abs() < 1e-6);
        if (!landed) i1.add('$name: tie from ${from.first.$1}');
        final (top, bottom) = extent(c);
        final x0 = min(c.start.x, c.end.x), x1 = max(c.start.x, c.end.x);
        for (var k = lowerBound(centres, x0 + 0.05);
            k < byCentre.length && centres[k] < x1 - 0.05;
            k++) {
          final h = byCentre[k];
          if (h.$5 > top && h.$5 < bottom) {
            i3.add('$name: tie from ${from.first.$1} through ${h.$1}');
            break;
          }
        }
      }
      for (final slur in score.slurs) {
        final v = voiceOf[slur.startId];
        if (v == null || v != voiceOf[slur.endId]) continue;
        // Ordinary slurs only. A slur over more than three bars is rare as a
        // real phrase mark; the designed-arch model is not meant for those.
        if ((barOf[slur.endId] ?? 0) - (barOf[slur.startId] ?? 0) > 3) continue;
        final a = headsById[slur.startId], b = headsById[slur.endId];
        if (a == null || b == null) continue;
        final match = (slurCurvesByStart[key(a.first.$2)] ?? const [])
            .where((c) => (c.end.x - b.first.$2).abs() < 1e-6);
        if (match.length != 1) continue;
        final c = match.single;
        var lo = double.infinity, hi = double.negativeInfinity;
        for (var k = lowerBound(regionLefts, c.start.x - 60);
            k < regions.length && regionLefts[k] <= c.end.x + 1;
            k++) {
          final (_, r0, id, t0, b0) = regions[k];
          // Any voice's ink is a legitimate obstacle here; voice-specific
          // placement (#2) is pinned by multivoice_curve_side_test.
          if (r0 < c.start.x - 1) continue;
          lo = min(lo, t0);
          hi = max(hi, b0);
        }
        for (var k = lowerBound(obstacleLefts, c.start.x - 40);
            k < obstacles.length && obstacleLefts[k] <= c.end.x;
            k++) {
          final (ol, or, ot, ob) = obstacles[k];
          if (or <= c.start.x || ol >= c.end.x) continue;
          lo = min(lo, ot);
          hi = max(hi, ob);
        }
        // Other curves strictly inside this slur's span (a nested slur or a
        // tie under it) are obstacles too.
        for (final (other, ol, or, (ot, ob)) in curveExtents) {
          if (identical(other, c) ||
              ol < c.start.x - 0.5 ||
              or > c.end.x + 0.5) {
            continue;
          }
          lo = min(lo, ot);
          hi = max(hi, ob);
        }
        if (!lo.isFinite) continue;
        slurs++;
        slursByExt[extOf(path)] = (slursByExt[extOf(path)] ?? 0) + 1;
        // The layout's designed reach: endpoints 0.35 off the ink (long
        // slurs pushed to the staff edge), clearance 0.4, then the arch.
        final span = (c.end.x - c.start.x).abs();
        final arch = 0.55 + min(2.7, span * 0.045);
        // +0.75: the clearance the layout keeps over an obstacle it arches
        // across (its long-slur sampler).
        final up = arch + 2.0 + (span > 12 ? max(0.0, lo + 0.65) : 0.0);
        final down = arch + 2.0 + (span > 12 ? max(0.0, 4.65 - hi) : 0.0);
        final (top, bottom) = extent(c);
        if (top < lo - up || bottom > hi + down) {
          i2.add('$name: slur ${slur.startId}->${slur.endId}');
          i2ByExt[extOf(path)] = (i2ByExt[extOf(path)] ?? 0) + 1;
        }
      }
    }
    expect(ties, greaterThan(0));
    expect(slurs, greaterThan(0));
    expect(i1, isEmpty,
        reason: '${i1.length} of $ties ties miss a notehead:\n'
            '${i1.take(20).join('\n')}');
    expect(i3.length / ties, lessThan(0.002),
        reason: '${i3.length} of $ties ties cross a notehead:\n'
            '${i3.take(20).join('\n')}');
    // Per format, just above today's rates.
    const slurCeilings = {
      '.abc': 0.01,
      '.mei': 0.01,
      '.ly': 0.01,
      '.mscx': 0.01,
      '.krn': 0.015,
      // 0.002 until stated beams (0.10.0): a vocal line's eighths keep their
      // flags as written, and slurs ending on them arch higher than over the
      // meter's beams did (48 of 16,130, 0.30%).
      '.mxl': 0.0035,
    };
    for (final MapEntry(key: ext, value: n) in slursByExt.entries) {
      final over = i2ByExt[ext] ?? 0;
      expect(over / n, lessThanOrEqualTo(slurCeilings[ext] ?? 0.01),
          reason: '$ext: $over of $n slurs overshoot:\n'
              '${i2.where((x) => x.contains('$ext:')).take(15).join('\n')}');
    }
  }, skip: skip);

  // The engraving rules of `support/layout_lint.dart`, over every staff of
  // every score: as one line and broken into lines (a continuation line ends
  // differently from the piece). Found on its first run: staff lines past
  // the closing barline (90% of the MusicXML files), a plain barline left in
  // front of a start repeat (1,071 bars), empty bars stacking their barlines,
  // a two-voice column's accidentals drawn twice, and a crash on theoretical
  // keys (8+ sharps). Ceilings per rule only go down.
  test('every staff keeps the engraving rules (layout lint)', () {
    const ceilings = {
      'barline-group': 0,
      'repeat-dots': 0,
      'closing': 0,
      // One element's primitive drawn twice: 411 on the first run (chords
      // naming a pitch twice, hairpins listed twice), now merged in layout.
      'duplicate': 0,
      'collision': 0,
      // A notehead crossed by another voice's stem: voices interlocking or
      // crossing without moving aside, or stems pointing the wrong way —
      // 28,249 on the first run, 237 since stated stems and same-direction
      // voices move apart (docs/COMPARISON.md), 0 since grace notes lead
      // into the whole column (195) and a voice moved aside clears a
      // chord's far-side head (42).
      'voice-collision': 0,
      // Staves of a system whose bars do not close together: 10,213 on the
      // first run, 1 since voices that move apart take shared columns, 0
      // since a measure repeat's bar closes at the system's column.
      'misaligned': 0,
    };
    final counts = <String, int>{};
    final examples = <String, List<String>>{};
    void lint(String path, ScoreLayout l, Measure last, bool closes) {
      for (final issue
          in lintLayout(l, settings, closes: closes, lastMeasure: last)) {
        counts[issue.rule] = (counts[issue.rule] ?? 0) + 1;
        final list = examples[issue.rule] ??= [];
        if (list.length < 10) list.add('$path: $issue');
      }
    }

    for (final MapEntry(key: path, value: score) in scores.entries) {
      final xml = xmls[path];
      final List<Score> staves;
      final StaffSystem? system;
      try {
        system = xml == null ? null : staffSystemFromMusicXml(xml);
        staves = system?.staves ?? [score];
      } on Object {
        continue; // counted by the parse tests
      }
      if (system != null && system.staves.length > 1) {
        try {
          final wrapped =
              layoutStaffSystemSystems(system, settings, maxWidth: 100);
          for (final (k, line) in wrapped.systems.indexed) {
            for (final m in systemMisalignments(line.layout)) {
              counts['misaligned'] = (counts['misaligned'] ?? 0) + 1;
              final list = examples['misaligned'] ??= [];
              if (list.length < 10) list.add('$path [line $k]: $m');
            }
          }
        } on Object catch (e) {
          if (e is! Error && e is! Exception) rethrow;
        }
      }
      for (final staff in staves) {
        if (staff.measures.isEmpty) continue;
        try {
          lint(path, const LayoutEngine().layout(staff, settings),
              staff.measures.last, true);
          final systems = layoutSystems(staff, settings, maxWidth: 100).systems;
          for (final (k, sys) in systems.indexed) {
            lint('$path [line $k]', sys.layout, staff.measures[sys.lastMeasure],
                k == systems.length - 1);
          }
        } on Object catch (e) {
          // Layout failures are counted by '#2 #3' below.
          if (e is! Error && e is! Exception) rethrow;
        }
      }
    }
    for (final MapEntry(key: rule, value: ceiling) in ceilings.entries) {
      final n = counts[rule] ?? 0;
      print('lint $rule: $n (ceiling $ceiling)');
      expect(n, lessThanOrEqualTo(ceiling),
          reason: '$rule over its ceiling:\n'
              '${(examples[rule] ?? []).join('\n')}');
    }
    final unknown = counts.keys.toSet().difference(ceilings.keys.toSet());
    expect(unknown, isEmpty, reason: 'rules without a ceiling');
  }, skip: skip);

  // Barlines, repeats and voltas four ways, for each MusicXML file's first
  // part: what the file says (read here from the raw XML), what the reader
  // made of it, what the layout draws (`barlineMismatches`), and what a
  // MusicXML round trip keeps. A bar drawn twice (#19), lost, or of the wrong
  // kind shows up as a boundary whose strokes differ from its measure's.
  test('barlines: source, model, drawing and round trip agree', () {
    const styles = {
      'regular': BarlineStyle.normal,
      'light-light': BarlineStyle.doubleBar,
      'light-heavy': BarlineStyle.finalBar,
      'heavy': BarlineStyle.heavy,
      'heavy-light': BarlineStyle.reverseFinal,
      'dashed': BarlineStyle.dashed,
      'dotted': BarlineStyle.dotted,
      'tick': BarlineStyle.tick,
      'short': BarlineStyle.short,
      'none': BarlineStyle.none,
    };
    String describe(Measure m) => [
          if (m.startRepeat) '|:',
          if (m.endRepeat) ':|' else m.barline.name,
          if (m.volta != null) 'volta ${m.volta}',
        ].join(' ');
    final model = <String>[], drawn = <String>[], roundTrip = <String>[];
    var bars = 0, files = 0;
    for (final MapEntry(key: path, value: xml) in xmls.entries) {
      final score = scores[path];
      if (score == null) continue;
      final XmlNode part;
      try {
        part = parseXml(xml).child('part')!;
      } on Object {
        continue;
      }
      final source = part.childrenNamed('measure').toList();
      // A multi-measure rest folds its bars into one (#11): indices differ.
      if (source.length != score.measures.length) continue;
      files++;
      // An ending covers every bar from its `start` up to its `stop` or
      // `discontinue` (or a `:|`); a `|:` opens a new section.
      int? openVolta;
      for (final (i, xmlMeasure) in source.indexed) {
        var start = false, end = false, closes = false;
        BarlineStyle? style;
        final barlines = xmlMeasure.childrenNamed('barline').toList();
        int? volta = barlines.any((b) =>
                b.attributes['location'] == 'left' &&
                b.child('repeat')?.attributes['direction'] == 'forward')
            ? null
            : openVolta;
        for (final b in barlines) {
          final direction = b.child('repeat')?.attributes['direction'];
          if (direction == 'forward') start = true;
          if (direction == 'backward') end = true;
          final ending = b.child('ending');
          switch (ending?.attributes['type']) {
            case 'start':
              // The first pass it is taken on ("1, 2" and "1 2" both list).
              volta = [
                for (final n in (ending!.attributes['number'] ?? '1')
                    .split(RegExp(r'[,\s]+')))
                  if (int.tryParse(n) case final v? when v >= 1) v,
              ].firstOrNull;
              closes = false;
            case 'stop' || 'discontinue':
              if (b.attributes['location'] == 'left') {
                volta = null;
              } else {
                closes = true;
              }
          }
          if (b.attributes['location'] != 'left' && b.child('repeat') == null) {
            style = styles[b.childText('bar-style')] ?? style;
          }
        }
        openVolta = closes || end ? null : volta;
        final want = Measure(const [],
            startRepeat: start,
            endRepeat: end,
            volta: volta,
            barline: style ?? BarlineStyle.normal);
        final got = score.measures[i];
        bars++;
        if (describe(want) != describe(got)) {
          model.add('$path bar ${i + 1}: file "${describe(want)}", '
              'read "${describe(got)}"');
        }
      }
      for (final m in barlineMismatches(
          const LayoutEngine().layout(score, settings), score, settings)) {
        drawn.add('$path $m');
      }
      try {
        final back = scoreFromMusicXml(scoreToMusicXml(score));
        for (var i = 0; i < score.measures.length; i++) {
          final a = describe(score.measures[i]);
          final b =
              i < back.measures.length ? describe(back.measures[i]) : 'missing';
          if (a != b) roundTrip.add('$path bar ${i + 1}: "$a" -> "$b"');
        }
      } on Object catch (e) {
        roundTrip.add('$path: $e');
      }
    }
    print('barlines: $bars bars in $files files; model ${model.length}, '
        'drawn ${drawn.length}, round trip ${roundTrip.length}');
    expect(bars, greaterThan(10000));
    for (final (name, list, ceiling) in [
      ('model', model, 0),
      ('drawn', drawn, 0),
      ('round trip', roundTrip, 0),
    ]) {
      expect(list.length, lessThanOrEqualTo(ceiling),
          reason: '$name: ${list.length} mismatches:\n'
              '${list.take(20).join('\n')}');
    }
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
            case GlyphPrimitive(:final smuflName)
                when !smuflCodepoints.containsKey(smuflName):
              // #10: a glyph without a codepoint crashed painting.
              failures.add('$path: no codepoint for glyph $smuflName');
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

  // LilyPond's OWN reading of each Mutopia file, as ground truth: the
  // `ly-oracle/` directory beside the corpus holds `oracle.json`, made by
  // compiling every `.ly` to MIDI with the real LilyPond (`make.sh`, after
  // convert-ly on a copy) and summarising each track (`summarize.py`). A file
  // AGREES when its note count is within 2%, its length within a quarter and
  // its pitch histogram within 5% — with repeats expanded or as written,
  // whichever LilyPond did, and at concert pitch.
  //
  // It is what found music read twice as long (`\partcombine`, a `\global`
  // of spacers), an octave off (`\transpose` ignored, the relative reference
  // after `<< >>`), and whole staves read as silence (`guitar_staff`). The
  // floor only rises; the files that still disagree are mostly the oracle's
  // own artefacts — a MIDI-only `\score` that transposes, ChordNames tracks.
  final oracleFile = root == null ? null : File('$root/ly-oracle/oracle.json');
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
      for (final n in playbackTimeline(s, expandRepeats: expand)) {
        final e = byId[n.elementId];
        if (e == null) continue;
        // MIDI ends with its last note: a trailing rest or skip plays nothing.
        end = max(end, (n.start + n.duration).toDouble() * 4);
        final before = prev[n.elementId];
        for (final p in e.pitches) {
          // A tied-into pitch is one held note, as in MIDI.
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
        continue;
      }
      final oNotes = tracks.fold<int>(0, (a, t) => a + (t['notes'] as int));
      final oEnd = tracks.map((t) => (t['end'] as num).toDouble()).reduce(max);
      final oHist = <int, int>{};
      for (final t in tracks) {
        (t['pitches'] as Map).forEach((k, v) => oHist[int.parse(k as String)] =
            (oHist[int.parse(k)] ?? 0) + (v as int));
      }
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
                0, (a, k) => a + ((h[k] ?? 0) - (oHist[k] ?? 0)).abs()) /
            max(1, oNotes);
        if ((n - oNotes).abs() <= 0.02 * oNotes &&
            (e - oEnd).abs() <= 1.0 &&
            pitchErr <= 0.05) {
          agree++;
          break;
        }
      }
    }
    // ignore: avoid_print
    print('LilyPond oracle: $agree / $total files agree');
    expect(crashes, isEmpty, reason: crashes.take(10).join('\n'));
    expect(total, greaterThan(300));
    // Ratchet (2026-10-06: 123 of 374, from 13 before the oracle existed;
    // 2026-10-18: 290, kept in step with lilypond_oracle_test.dart).
    expect(agree, greaterThanOrEqualTo(290));
  },
      skip: skip ??
          (oracleFile!.existsSync()
              ? null
              : 'no ly-oracle/oracle.json beside the corpus'));

  // ---------------------------------------------------------------- #8–#14

  test('#11 a multi-measure rest counts its bars once', () {
    // Every MusicXML part with a <multiple-rest>: the bars the score stands
    // for equal the bars the file has. Folding the covered bars into the
    // multi-rest used to sit beside keeping them, counting the silence twice.
    var checked = 0;
    final failures = <String>[];
    for (final MapEntry(key: path, value: xml) in xmls.entries) {
      if (!xml.contains('<multiple-rest>')) continue;
      final score = scores[path]!;
      final part = RegExp(r'<part[ >][\s\S]*?</part>').firstMatch(xml)![0]!;
      final fileBars = RegExp(r'<measure[ >]').allMatches(part).length;
      final modelBars =
          score.measures.fold<int>(0, (n, m) => n + (m.multiRest ?? 1));
      checked++;
      if (fileBars != modelBars) {
        failures.add('$path: file $fileBars bars, model $modelBars');
      }
    }
    // ignore: avoid_print
    print('#11: $checked parts with multi-rests');
    expect(failures, isEmpty, reason: failures.take(10).join('\n'));
  }, skip: skip);

  // A tempo that is only a playback setting (`<sound tempo>` with no
  // `<metronome>`) prints nothing, as the reference engravers agree.
  test('#12 every score with a printed tempo draws its metronome mark', () {
    var checked = 0;
    final failures = <String>[];
    for (final MapEntry(key: path, value: score) in scores.entries) {
      if (score.tempo?.printed != true || score.measures.isEmpty) continue;
      if (score.measures.first.multiRest != null) continue;
      final layout = const LayoutEngine().layout(score, settings);
      checked++;
      if (!layout.primitives
          .whereType<GlyphPrimitive>()
          .any((g) => g.smuflName.startsWith('metNote'))) {
        failures.add(path);
      }
    }
    // ignore: avoid_print
    print('#12: $checked scores with a printed tempo');
    expect(checked, greaterThan(100));
    expect(failures, isEmpty, reason: failures.take(10).join('\n'));
  }, skip: skip);

  test('#13 a lower part inherits the top part\'s tempo', () {
    var checked = 0;
    final failures = <String>[];
    for (final MapEntry(key: path, value: xml) in xmls.entries) {
      if (RegExp('<score-part ').allMatches(xml).length < 2) continue;
      final top = scores[path]!;
      if (top.tempo == null) continue;
      final last = RegExp('<score-part ').allMatches(xml).length - 1;
      final Score lower;
      try {
        lower = scoreFromMusicXml(xml, partIndex: last);
      } on Object catch (e) {
        failures.add('$path: part $last: $e');
        continue;
      }
      checked++;
      if (lower.tempo == null) failures.add('$path: part $last has no tempo');
    }
    // ignore: avoid_print
    print('#13: $checked multi-part scores with a tempo');
    expect(failures, isEmpty, reason: failures.take(10).join('\n'));
  }, skip: skip);

  test('#8 a slur with a stated side is drawn on that side', () {
    var checked = 0;
    final failures = <String>[];
    for (final MapEntry(key: path, value: score) in scores.entries) {
      final stated = [
        for (final sl in score.slurs)
          if (sl.placement != SlurPlacement.auto) sl
      ];
      if (stated.isEmpty) continue;
      // One slur at a time, so each drawn curve is that slur's.
      for (final sl in stated.take(3)) {
        final one = score.copyWith(slurs: [sl]);
        final ScoreLayout layout;
        try {
          layout = const LayoutEngine().layout(one, settings);
        } on Object {
          continue; // layout failures are the #2 #3 test's business
        }
        // The slur's curve: the one running from its first note to its last
        // (ties are curves too, and may be wider).
        // Measured from the noteheads: a note's hit box also spans its
        // lyric syllable, which shifts its centre.
        double? headX(String id) {
          for (final g in layout.primitives.whereType<GlyphPrimitive>()) {
            if (g.elementId == id && g.smuflName.startsWith('notehead')) {
              return g.position.x + 0.6;
            }
          }
          return null;
        }

        final hx = headX(sl.startId), hy = headX(sl.endId);
        if (hx == null || hy == null) continue;
        // Closest to both ends: a tie leaving the slur's last note starts
        // near it too.
        final fx = hx, tx = hy;
        double miss(CurvePrimitive c) =>
            (c.start.x - fx).abs() + (c.end.x - tx).abs();
        final drawn = layout.primitives.whereType<CurvePrimitive>().toList();
        if (drawn.isEmpty) continue;
        final c = drawn.reduce((a, b) => miss(a) <= miss(b) ? a : b);
        if (miss(c) > 4) continue;
        // The arc's middle against the middle of its ends: a slur's control
        // points follow the line of its ends, so over a leap the first one
        // can sit above the start of a slur that still bows below.
        final middle =
            (c.start.y + 3 * c.control1.y + 3 * c.control2.y + c.end.y) / 8;
        final up = middle < (c.start.y + c.end.y) / 2;
        checked++;
        if (up != (sl.placement == SlurPlacement.above)) {
          failures.add('$path: ${sl.startId}->${sl.endId} '
              '${sl.placement.name} drawn ${up ? 'above' : 'below'}');
        }
      }
    }
    // ignore: avoid_print
    print('#8: $checked slurs with a stated side');
    expect(checked, greaterThan(50));
    expect(failures.length / checked, lessThan(0.01),
        reason: failures.take(10).join('\n'));
  }, skip: skip);

  test('#14 a chord\'s tremolo sits on its free stem, clear of the heads', () {
    var checked = 0;
    final failures = <String>[];
    for (final MapEntry(key: path, value: score) in scores.entries) {
      final chordTremolos = {
        for (final m in score.measures)
          for (final e in m.elements)
            if (e is NoteElement && e.tremolo != null && e.pitches.length > 1)
              e.id,
      };
      if (chordTremolos.isEmpty) continue;
      final layout = const LayoutEngine().layout(score, settings);
      for (final g in layout.primitives.whereType<GlyphPrimitive>()) {
        if (!g.smuflName.startsWith('tremolo') ||
            !chordTremolos.contains(g.elementId)) {
          continue;
        }
        final heads = [
          for (final h in layout.primitives.whereType<GlyphPrimitive>())
            if (h.elementId == g.elementId &&
                h.smuflName.startsWith('notehead'))
              h.position.y,
        ];
        if (heads.length < 2) continue;
        checked++;
        final lo = heads.reduce(min), hi = heads.reduce(max);
        if (g.position.y > lo + 0.25 && g.position.y < hi - 0.25) {
          failures.add('$path: ${g.elementId} strokes between its heads');
        }
      }
    }
    // ignore: avoid_print
    print('#14: $checked chord tremolos');
    expect(failures, isEmpty, reason: failures.take(10).join('\n'));
  }, skip: skip);

  test('#14 tuplet numbers sit outside the staff', () {
    var checked = 0;
    final failures = <String>[];
    for (final MapEntry(key: path, value: score) in scores.entries) {
      if (!score.measures.any((m) => m.tuplets.isNotEmpty)) continue;
      final ScoreLayout layout;
      try {
        layout = const LayoutEngine().layout(score, settings);
      } on Object {
        continue;
      }
      for (final g in layout.primitives.whereType<GlyphPrimitive>()) {
        if (!RegExp(r'^tuplet\d$').hasMatch(g.smuflName)) continue;
        checked++;
        final box = settings.metadata.bBoxOf(g.smuflName);
        final top = g.position.y - box.neY, bottom = g.position.y - box.swY;
        // Overlapping the band between the top (0) and bottom (4) lines.
        if (bottom > 0.05 && top < 3.95) {
          failures.add('$path: ${g.smuflName} at y ${g.position.y}');
        }
      }
    }
    // ignore: avoid_print
    print('#14: $checked tuplet digits');
    expect(checked, greaterThan(100));
    expect(failures.length / checked, lessThan(0.001),
        reason: failures.take(10).join('\n'));
  }, skip: skip);
}
