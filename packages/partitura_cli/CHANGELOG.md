# Changelog

## 0.4.1-dev.1 (in progress)

- **Offline `render` for the standalone binary** (hardening G1): the Bravura
  SMuFL metadata is now embedded in the CLI (DEFLATE-compressed + base64,
  ~136 KB, inflated at runtime via the existing pure-Dart `inflate`), so a
  released `partitura` binary renders SVG without the repo checkout or a
  `--metadata` path. Resolution order is unchanged (`--metadata` → repo →
  embedded); when it falls back to the embedded copy there is no font file, so
  the SVG references the engraving font by name instead of inlining it.
  Regenerate the embed with `tool/embed_metadata.dart`.

- **Braille music output**: `convert --to brl` (or a `.brl` output path) writes
  Unicode braille-music notation via the new core `scoreToBraille`.

## 0.4.0 (2026-07-13)

First tagged release. The `partitura` CLI: inspect scores; convert between
MusicXML / `.mxl` / MEI / `**kern` / MIDI / MuseScore / the `.gp` tablature
family / ABC (plus LilyPond export); render to SVG or PNG (notation or tab); and
optical music recognition (`omr`) routing three CrispEmbed engines
(Sheet Music Transformer, Polyphonic-TrOMR, Flova) through one command, with
full-page segmentation (`--page`) and model auto-download by name. The OMR
pipeline is also exposed as a reusable library (`package:partitura_cli/omr.dart`).
