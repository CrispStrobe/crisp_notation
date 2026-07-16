# Performance

The layout engine (`crisp_notation_core`) is the hot path: an interactive editor
relayouts on every edit and drag, so its cost bounds the frame rate. This note
records the measured baseline, the benchmark, and one methodology trap.

## Measure AOT, never `dart run`

A Flutter **release** build is AOT-compiled. Benchmarking under `dart run` (JIT)
reports compilation warmup, not release performance — and the gap is not a small
constant:

| Measured under | `SmuflMetadata.fromJson` | 1-bar layout floor |
|---|---|---|
| `dart run` (JIT) | **480 ms** | **11 ms** |
| `dart compile exe` (AOT) | **~11 ms** | **~0.03 ms** |

The JIT numbers are 40x and 350x too slow. An optimization pass driven by them
would have chased a font-parse cost and a fixed per-layout floor that **do not
exist in production**. Always AOT-compile the benchmark:

```sh
cd packages/crisp_notation_core
dart compile exe benchmark/layout_benchmark.dart -o /tmp/lb && /tmp/lb
```

## Baseline (Apple silicon, AOT, 2026-07)

```
SmuflMetadata.fromJson    ~11 ms   (once per font load; cached by Bravura.load)
layout, per bar           ~130 us/bar, flat from 25 to 800 bars
layout, 800 bars          ~93 ms
```

Layout is **O(n)** in the number of elements — cost per bar is flat across the
whole range, with no fixed-cost floor and no superlinear tail. For interactive
editing a screenful is tens of bars (a few ms), comfortably inside a 60 fps
budget; whole-score relayout only becomes visible on very large scores (hundreds
of bars), where the structural win would be incremental relayout (relayout only
the changed measure range), not constant-factor tuning.

## Regression gate

`benchmark/layout_benchmark.dart` prints the table and then fails (exit 1) on:

1. **Superlinear scaling** — the 800-bar / 100-bar time *ratio* exceeds 32x
   (linear is ~8x; observed 3x on a warm laptop to 11x on a cold CI runner).
   Because it is a ratio, it is independent of how fast the machine is, so it
   does not flake on a slow runner while still catching an accidental O(n²)
   pass, which reads ~64x at this scale.
2. **A gross absolute slowdown** — 800-bar layout over 1500 ms (>10x the local
   baseline; a coarse backstop).

CI runs it AOT-compiled on every push (the `layout-benchmark` job).
