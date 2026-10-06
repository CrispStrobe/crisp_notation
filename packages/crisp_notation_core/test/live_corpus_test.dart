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
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final notScores = <File>{};
    for (final file in files) {
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
        'slurs':
            '${s.slurs.where((x) => x.startId != x.endId && span(x.startId, x.endId, notesOnly: true)).length}',
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
        // real phrase mark, and in this corpus mostly an exporter's misnumbered
        // stops (38 files pair every stop with a start several slurs back;
        // their MuseScore originals have no slur longer than a bar). The
        // designed-arch model is not meant for those.
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
    // Per format, just above today's rates. MusicXML stays high: 38 corpus
    // files from an unknown exporter number every slur stop one past its
    // start (start 6/stop 1, start 1/stop 2, …), so by the MusicXML rules
    // each stop closes a slur begun several slurs earlier, and the bogus
    // overlapping slurs stack (their MuseScore originals are fine). No
    // reliable signal separates them from legitimate multi-voice numbering,
    // so the reader keeps the spec. The other formats are near zero.
    const slurCeilings = {
      '.abc': 0.01,
      '.mei': 0.01,
      '.ly': 0.01,
      '.mscx': 0.01,
      '.krn': 0.015,
      '.mxl': 0.25,
    };
    for (final MapEntry(key: ext, value: n) in slursByExt.entries) {
      final over = i2ByExt[ext] ?? 0;
      expect(over / n, lessThanOrEqualTo(slurCeilings[ext] ?? 0.01),
          reason: '$ext: $over of $n slurs overshoot:\n'
              '${i2.where((x) => x.contains('$ext:')).take(15).join('\n')}');
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
      for (final m in s.measures) {
        for (var v = 0; v < 4; v++) {
          MusicElement? last;
          for (final e in m.voiceAt(v)) {
            if (e is NoteElement && e.id != null) {
              byId[e.id!] = e;
              prev[e.id!] = last;
            }
            last = e;
          }
        }
      }
      var notes = 0;
      var end = 0.0;
      final hist = <int, int>{};
      for (final n in playbackTimeline(s, expandRepeats: expand)) {
        end = max(end, (n.start + n.duration).toDouble() * 4);
        final e = byId[n.elementId];
        if (e == null) continue;
        final before = prev[n.elementId];
        for (final p in e.pitches) {
          // A tied-into pitch is one held note, as in MIDI.
          if (before is NoteElement &&
              before.tieToNext &&
              before.pitches.contains(p)) {
            continue;
          }
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
        mp = multiPartFromLilyPond(file.readAsStringSync());
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
    // Ratchet (2026-10-06: 123 of 374, from 13 before the oracle existed).
    expect(agree, greaterThanOrEqualTo(123));
  },
      skip: skip ??
          (oracleFile!.existsSync()
              ? null
              : 'no ly-oracle/oracle.json beside the corpus'));
}
