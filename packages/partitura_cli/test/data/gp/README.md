# Guitar Pro test fixtures

These are small, technique-focused Guitar Pro files used as read-path
regression fixtures for partitura's importers (GP5 binary, GP6 `.gpx`,
GP7/8 `.gp`).

## Provenance & license

The files are vendored from the [alphaTab](https://github.com/CoderLine/alphaTab)
project's test corpus:

> Copyright © Daniel Kuschny and Contributors.
> Licensed under the Mozilla Public License, Version 2.0 (MPL-2.0).

MPL-2.0 is a file-level copyleft: these individual files remain under
MPL-2.0 and carry no viral effect on the rest of this repository. Their
license text is available at <https://www.mozilla.org/en-US/MPL/2.0/>.

Only trivial, authored technique demos are vendored here (chords, bends,
slides) — no real songs. If you modify a file, keep it under MPL-2.0.

## Files

| File | Version | Exercises |
|---|---|---|
| `chords.gp5` | Guitar Pro 5 (binary) | multi-note chords across measures |
| `bends.gp5`  | Guitar Pro 5 (binary) | string bends |
| `chords.gpx` | Guitar Pro 6 (BCFZ/BCFS) | chords |
| `slides.gpx` | Guitar Pro 6 (BCFZ/BCFS) | slides (glissando) |
| `chords.gp`  | Guitar Pro 7/8 (GPIF in ZIP) | chords |
| `bends.gp`   | Guitar Pro 7/8 (GPIF in ZIP) | string bends |
