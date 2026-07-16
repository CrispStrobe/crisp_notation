// Layout-engine benchmark and regression gate.
//
// **Run AOT** for production-representative numbers — a Flutter release build is
// AOT-compiled, and `dart run` (JIT) reports warmup cost that is 10–40x wrong
// (metadata parse reads 480ms under JIT, 11ms AOT):
//
//   dart compile exe benchmark/layout_benchmark.dart -o /tmp/lb && /tmp/lb
//
// It prints a table and then checks two things, exiting non-zero on failure:
//
//  1. **Scaling stays linear.** The 800-bar / 100-bar time ratio must stay well
//     under quadratic. This is a *ratio*, so it is independent of how fast the
//     machine is — a slow CI runner and a fast laptop agree on it — which makes
//     it a non-flaky gate that still catches an accidental O(n^2) pass (the
//     ratio would jump from ~8 to ~60+).
//  2. **A generous absolute ceiling**, as a coarse backstop for a gross slowdown.
//
// Baseline (Apple silicon, AOT, 2026-07): ~130 us/bar, 800 bars ~= 93 ms,
// SmuflMetadata.fromJson ~= 11 ms. See docs/PERF.md.
import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';

double _bench(void Function() f, {int warmup = 20, required int iters}) {
  for (var i = 0; i < warmup; i++) {
    f();
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < iters; i++) {
    f();
  }
  sw.stop();
  return sw.elapsedMicroseconds / iters / 1000; // ms per call
}

Score _score(int bars) => Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes:
          List.generate(bars, (_) => 'c4:e d4:e e4:e f4:e g4:e a4:e b4:e c5:e')
              .join(' | '),
    );

void main() {
  final metaJson = File('../crisp_notation/assets/smufl/bravura_metadata.json')
      .readAsStringSync();
  final decoded = jsonDecode(metaJson) as Map<String, Object?>;

  final parseMs =
      _bench(() => SmuflMetadata.fromJson(decoded), warmup: 5, iters: 50);
  stdout.writeln(
      'SmuflMetadata.fromJson          ${parseMs.toStringAsFixed(2)} ms');

  final settings = LayoutSettings(metadata: SmuflMetadata.fromJson(decoded));
  const engine = LayoutEngine();

  final timings = <int, double>{};
  for (final bars in [1, 25, 100, 200, 400, 800]) {
    final score = _score(bars);
    final iters = bars >= 400 ? 30 : 100;
    final ms = _bench(() => engine.layout(score, settings), iters: iters);
    timings[bars] = ms;
    final notes = bars * 8;
    stdout.writeln('layout ${bars.toString().padLeft(3)} bars / '
        '${notes.toString().padLeft(4)} notes    '
        '${ms.toStringAsFixed(2).padLeft(7)} ms    '
        '${(notes / (ms / 1000) / 1000).toStringAsFixed(0).padLeft(4)}k notes/s');
  }

  // Gate 1 — linearity (runner-speed-independent ratio).
  final ratio = timings[800]! / timings[100]!;
  // 800/100 = 8x the work. Linear -> ~8; observed 3x (warm laptop) to 11x (cold
  // CI runner, where the 100-bar case is disproportionately cache-favoured). The
  // ceiling is set well above that spread so the gate never flakes, while still
  // catching the thing it exists for: an accidental O(n^2) pass reads ~64x here.
  const maxRatio = 32.0;
  stdout.writeln('\nscaling: 800-bar / 100-bar = '
      '${ratio.toStringAsFixed(1)}x work-ratio (linear ~= 8, ceiling $maxRatio)');

  // Gate 2 — coarse absolute backstop. Local AOT ~= 93 ms at 800 bars; a CI
  // runner is a few times slower, so 1500 ms leaves >10x headroom.
  const maxAbsMs = 1500.0;
  final abs800 = timings[800]!;

  var failed = false;
  if (ratio > maxRatio) {
    stderr.writeln('REGRESSION: layout scaling is superlinear '
        '(${ratio.toStringAsFixed(1)}x > $maxRatio) — likely an O(n^2) pass.');
    failed = true;
  }
  if (abs800 > maxAbsMs) {
    stderr.writeln('REGRESSION: 800-bar layout ${abs800.toStringAsFixed(0)} ms '
        '> ${maxAbsMs.toStringAsFixed(0)} ms ceiling.');
    failed = true;
  }
  if (failed) exit(1);
  stdout.writeln('OK — layout is linear and within budget.');
}
