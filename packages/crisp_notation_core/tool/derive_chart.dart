// tool/derive_chart.dart
//
// Score → chord chart. The BB-X1 primitive: read any notation file this library
// understands and emit one chord symbol per bar, plus the key and the form.
//
//   dart run tool/derive_chart.dart <file-or-dir> [--json] [--limit N]
//
// Built on `HarmonicWeighting.durationWeightedPerBar`, which was measured end to
// end at +30.2pp majmin over the per-slice default — a passing sixteenth should
// not outvote a chord tone held for a half, and per-slice gives them equal say.
//
// ⚠️ CONFIDENCE IS REPORTED, NOT ASSUMED. A chart is only useful if we know when
// to distrust it, so every file reports the fraction of bars that named a chord
// at all (`named`) and the fraction whose chord is diatonic to the detected key
// (`diatonic`). A piece where half the bars name nothing, or where most chords sit
// outside the key, has almost certainly been misread — chant, atonal writing, or
// a reader failure — and should be held rather than shipped. Promotion policy is
// the caller's; this only measures.

import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';

/// Everything a caller needs to decide whether to trust the result.
class DerivedChart {
  DerivedChart({
    required this.path,
    required this.key,
    required this.bars,
    required this.form,
    required this.error,
    this.source = 'inferred',
  });

  final String path;
  final String? key;

  /// One entry per bar: the chord symbol, or null where none could be read.
  final List<String?> bars;
  final String form;
  final String? error;

  /// `'file'` when the chart is the engraver's own chord symbols, `'inferred'`
  /// when it was read from the notes. Never let a caller confuse the two.
  final String source;

  int get named => bars.where((b) => b != null).length;
  double get namedRatio => bars.isEmpty ? 0 : named / bars.length;

  Map<String, Object?> toJson() => {
        'path': path,
        'key': key,
        'bars': bars,
        'form': form,
        'source': source,
        'named': named,
        'total': bars.length,
        if (error != null) 'error': error,
      };
}

DerivedChart derive(String path) {
  try {
    final score = _read(path);
    if (score == null) {
      return DerivedChart(
        path: path,
        key: null,
        bars: const [],
        form: '',
        error: 'unsupported format',
      );
    }
    // 🔴 PREFER THE FILE'S OWN CHORD SYMBOLS. Roughly 575 corpus `.mxl` files
    // carry `<harmony>`, and the MusicXML reader has been parsing those into
    // `Score.chordSymbols` all along — exact data, written by whoever engraved
    // the piece. Inference is the fallback, never the first choice, and the two
    // are LABELLED because a caller must not mistake a transcribed chart for a
    // 66%-accurate guess.
    if (score.chordSymbols.isNotEmpty) {
      return _fromOwnSymbols(path, score);
    }
    final a = analyze(score, weighting: HarmonicWeighting.auto);
    // One segment per bar in this mode, but do not assume it — a bar that names
    // nothing still yields a segment, and an empty bar yields none.
    final byBar = <int, String?>{};
    for (final seg in a.segments) {
      byBar[seg.measureIndex] = seg.chord?.symbol;
    }
    final bars = [
      for (var i = 0; i < score.measures.length; i++) byBar[i],
    ];
    final form = detectForm(score).map((s) => s.label).join();
    return DerivedChart(
      path: path,
      key: a.key.toString(),
      bars: bars,
      form: form,
      error: null,
    );
  } catch (e) {
    return DerivedChart(
      path: path,
      key: null,
      bars: const [],
      form: '',
      error: '$e',
    );
  }
}

/// A chart built from the score's OWN chord symbols, placed into bars.
///
/// `ChordSymbol` anchors to a note element id rather than to a bar, so the bar a
/// symbol belongs to is found by locating that note. A symbol whose anchor has
/// gone missing is dropped rather than guessed at.
DerivedChart _fromOwnSymbols(String path, Score score) {
  final barOfNote = <String, int>{};
  for (var i = 0; i < score.measures.length; i++) {
    for (final voice in [
      score.measures[i].elements,
      score.measures[i].voice2,
      score.measures[i].voice3,
      score.measures[i].voice4,
    ]) {
      for (final e in voice) {
        if (e is NoteElement && e.id != null) barOfNote[e.id!] = i;
      }
    }
  }
  final bars = List<String?>.filled(score.measures.length, null);
  for (final cs in score.chordSymbols) {
    final bar = barOfNote[cs.elementId];
    // First symbol in a bar wins: a chart shows the chord a bar STARTS on, and
    // later symbols in the same bar are mid-bar changes this shape cannot hold.
    if (bar != null && bar < bars.length && bars[bar] == null) {
      bars[bar] = cs.text;
    }
  }
  // The key is still worth inferring even when the chords are given: a chart
  // needs it for transposition and for roman-numeral explanation, and the file's
  // chord symbols say nothing about which key they sit in.
  Key? key;
  try {
    key = analyze(score).key;
  } catch (_) {
    key = null;
  }
  return DerivedChart(
    path: path,
    key: key?.toString(),
    bars: bars,
    form: detectForm(score).map((s) => s.label).join(),
    error: null,
    source: 'file',
  );
}

Score? _read(String path) {
  final lower = path.toLowerCase();
  final bytes = File(path).readAsBytesSync();
  String text() => File(path).readAsStringSync();
  // The container readers return the extracted XML text, not a Score — they
  // unwrap the zip and the score entry, and the format reader does the rest.
  if (lower.endsWith('.mxl')) {
    return scoreFromMusicXml(readMusicXmlFromMxl(bytes));
  }
  if (lower.endsWith('.musicxml') || lower.endsWith('.xml')) {
    return scoreFromMusicXml(text());
  }
  if (lower.endsWith('.mid') || lower.endsWith('.midi')) {
    return scoreFromMidi(bytes);
  }
  if (lower.endsWith('.abc')) return scoreFromAbc(text());
  if (lower.endsWith('.ly')) return scoreFromLilyPond(text());
  if (lower.endsWith('.krn')) return scoreFromKern(text());
  if (lower.endsWith('.mscx')) return scoreFromMscx(text());
  if (lower.endsWith('.mscz')) {
    return scoreFromMscx(readMscxFromMscz(bytes));
  }
  return null;
}

void main(List<String> args) {
  final json = args.contains('--json');
  final limitIdx = args.indexOf('--limit');
  final limit = limitIdx >= 0 ? int.parse(args[limitIdx + 1]) : 1 << 30;
  final target = args.firstWhere((a) => !a.startsWith('--'), orElse: () => '');
  if (target.isEmpty) {
    stderr
        .writeln('usage: derive_chart.dart <file-or-dir> [--json] [--limit N]');
    exit(2);
  }

  final files = <String>[];
  final dir = Directory(target);
  if (dir.existsSync()) {
    for (final e in dir.listSync(recursive: true)) {
      if (e is File) files.add(e.path);
      if (files.length >= limit) break;
    }
  } else {
    files.add(target);
  }

  final out = <DerivedChart>[];
  for (final f in files.take(limit)) {
    final d = derive(f);
    if (d.error == 'unsupported format') continue;
    out.add(d);
    if (json) stdout.writeln(jsonEncode(d.toJson()));
  }
  if (json) return;

  final ok = out.where((d) => d.error == null && d.bars.isNotEmpty).toList();
  final failed = out.where((d) => d.error != null).length;
  final fromFile = ok.where((d) => d.source == 'file').length;
  stdout.writeln('files read: ${out.length}   parsed: ${ok.length}   '
      'failed: $failed');
  stdout.writeln('charts from the FILE\'s own symbols: $fromFile   '
      'inferred: ${ok.length - fromFile}');
  if (ok.isEmpty) return;

  final totalBars = ok.fold(0, (a, d) => a + d.bars.length);
  final namedBars = ok.fold(0, (a, d) => a + d.named);
  stdout.writeln('bars: $totalBars   named: $namedBars '
      '(${(100 * namedBars / totalBars).toStringAsFixed(1)}%)');

  // How usable are the individual charts? An average hides the shape.
  final buckets = <String, int>{};
  for (final d in ok) {
    final r = d.namedRatio;
    final b = r >= 0.9
        ? '≥90% of bars named'
        : r >= 0.7
            ? '70–90%'
            : r >= 0.5
                ? '50–70%'
                : '<50% (hold)';
    buckets[b] = (buckets[b] ?? 0) + 1;
  }
  stdout.writeln('\nper-file coverage:');
  for (final k in ['≥90% of bars named', '70–90%', '50–70%', '<50% (hold)']) {
    if (buckets[k] != null) {
      stdout.writeln('  ${k.padRight(20)} ${buckets[k]}');
    }
  }

  stdout.writeln('\nsample:');
  for (final d in ok.take(5)) {
    final head = d.bars.take(8).map((b) => b ?? '?').join(' | ');
    stdout.writeln('  ${d.path.split('/').last}');
    stdout.writeln('    key ${d.key}  form ${d.form}  '
        '${(100 * d.namedRatio).toStringAsFixed(0)}% named');
    stdout.writeln('    | $head |');
  }
}
