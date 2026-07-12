# `.gp` test fixtures

These are small, technique-focused `.gp` files used as read-path
regression fixtures for partitura's importers (`.gp3`/`.gp4`/`.gp5` binary,
`.gpx` (v6), `.gp` (v7/8)).

## Provenance & license

The files are vendored from the [alphaTab](https://github.com/CoderLine/alphaTab)
project's test corpus:

> Copyright © Daniel Kuschny and Contributors.
> Licensed under the Mozilla Public License, Version 2.0 (MPL-2.0).

MPL-2.0 is a file-level copyleft: these individual files remain under
MPL-2.0 and carry no viral effect on the rest of this repository. Their
license text is available at <https://www.mozilla.org/en-US/MPL/2.0/>.

Only trivial, authored technique demos are vendored here (notes, chords,
bends, slides, hammer-ons, harmonics, dead notes) — no real songs. If you
modify a file, keep it under MPL-2.0.

## Files

| File | Version | Exercises |
|---|---|---|
| `notes.gp3` / `.gp4` | `.gp3` / `.gp4` (binary) | a bar of notes + rests |
| `bends.gp3` / `.gp4` | `.gp3` / `.gp4` (binary) | string bends |
| `slides.gp3` / `.gp4` | `.gp3` / `.gp4` (binary) | slides (glissando) |
| `hammer.gp3` / `.gp4` | `.gp3` / `.gp4` (binary) | hammer-on / pull-off (slur) |
| `harmonics.gp3` / `.gp4` | `.gp3` / `.gp4` (binary) | harmonics (beat-level in `.gp3`) |
| `harmonic-types.gp4` | `.gp4` (binary) | natural / artificial / pinch harmonics |
| `dead.gp3` / `.gp4` | `.gp3` / `.gp4` (binary) | dead (muted) notes |
| `vibrato.gp3` / `.gp4` / `.gp5` | `.gp3` / `.gp4` / `.gp5` (binary) | vibrato (all three agree) |
| `effects.gp3` / `.gp4` / `.gp5` | `.gp3` / `.gp4` / `.gp5` (binary) | mixed bundle: palm mute + let ring spans |
| `chords.gp5` | `.gp5` (binary) | multi-note chords across measures |
| `bends.gp5`  | `.gp5` (binary) | string bends |
| `chords.gpx` | `.gpx` (v6, BCFZ/BCFS) | chords |
| `slides.gpx` | `.gpx` (v6, BCFZ/BCFS) | slides (glissando) |
| `chords.gp`  | `.gp` (v7/8, GPIF in ZIP) | chords |
| `bends.gp`   | `.gp` (v7/8, GPIF in ZIP) | string bends |
