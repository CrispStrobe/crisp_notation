# Guitar Pro binary reader — provenance & clean-room plan

## Why this exists

`gp_binary_reader.dart` currently documents itself as *"ported from the
reference layout in PyGuitarPro."* **PyGuitarPro is LGPL-3.0.** A literal
port/translation of its implementation would make this file a derivative work,
which is incompatible with the repository's MIT license.

Legal note (not legal advice): a *file format* is functional/factual and is not
itself copyrightable, and reverse-engineering a format for interoperability is
generally permissible. The risk here is narrow — whether PyGuitarPro's **creative
expression** (its specific code structure, decomposition, naming, comments) was
translated rather than the format merely being *implemented*. To remove all
doubt we do a **clean-room reimplementation**.

## The contract (what the reader must do)

Inputs → outputs, format-defined and therefore not copyrightable:

- `gp5ToScore(Uint8List, {int trackIndex})` → `Score` for a `.gp5` (v5.x) file.
- `gp4ToScore(...)` / `gp3ToScore(...)` → the `.gp4` / `.gp3` deltas.
- Must decode: version header; score-info/notice/lyric blocks (skipped, kept
  byte-aligned); page setup; tempo/key; per-track tunings; master bars (time
  signatures, repeats); and, per beat, notes as **string+fret → pitch** using
  the track tuning, with durations (whole…64th + dots), rests, chords, and the
  common note techniques (bend, slide→glissando, hammer/pull→slur, vibrato,
  palm-mute, let-ring, dead, natural/artificial/pinch harmonic).
- Everything else (effects, RSE, mix-table) is parsed only far enough to stay
  byte-aligned, then discarded.

The **behavioural safety net** is:
- `partitura_cli/test/gp_contract_test.dart` — exact pitches, durations, chord
  voicings and measures for real fixtures (the factual decode result).
- `partitura_cli/test/gp_fixtures_test.dart` — technique/element counts.
- `partitura_core/test/gp5_test.dart` — header rejection + a hand-built minimal.

## Clean-room process

1. **Specification** (this doc + the tests) states the contract. The format's
   byte layout is taken from **independent, public** reverse-engineering
   documentation (e.g. TuxGuitar, DGuitar, the community "Guitar Pro format"
   notes) — **not** from PyGuitarPro's source.
2. **Rewrite** `gp_binary_reader.dart` from scratch against that specification
   and the tests. The implementing agent must **not** consult PyGuitarPro's
   source, nor copy the current (potentially-tainted) file's structure — only
   the format spec, the fixtures (byte analysis) and the contract tests.
3. **Verify** every test above still passes; the decode result is identical
   because it is dictated by the format, not by any implementation.
4. **Reword** the file header to cite the public format specification and the
   test corpus, dropping the "ported from PyGuitarPro" language.

## Also review

- `gpif.dart` calls its target the "reference structure" and is validated
  against the alphaTab corpus (**MPL-2.0** — weaker, file-level copyleft; GPIF
  is XML, so its element layout is more clearly factual). Lower risk, but audit
  the header language for the same reason.
