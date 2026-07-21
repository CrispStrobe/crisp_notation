# crisp_notation_cli

Command-line tool for the [crisp_notation](https://github.com/CrispStrobe/crisp_notation)
music notation libraries: inspect scores, convert between a dozen formats
(MusicXML / `.mxl` / MEI / `**kern` / MIDI / MuseScore / the `.gp` tablature
family / ABC, plus LilyPond and braille-music export), render to SVG or PNG (notation or tab), and
recognize sheet-music images (OMR) — all pure Dart (OMR and PNG aside).

Part of a three-package family: [crisp_notation_core](https://pub.dev/packages/crisp_notation_core) (pure-Dart engine) · [crisp_notation](https://pub.dev/packages/crisp_notation) (Flutter rendering) · [crisp_notation_cli](https://pub.dev/packages/crisp_notation_cli) (CLI).

## Install

```sh
dart pub global activate crisp_notation_cli
```

Then run the `crisp_notation` command directly (or
`dart run crisp_notation_cli:crisp_notation` inside a project that depends on it).

## Usage

```
crisp_notation <command> [arguments]
```

| Command | Purpose |
|---|---|
| `info <in>` | Summarize a score (clef, meter, sizes, timeline length) |
| `timeline <in> [--bpm N] [--no-expand]` | Print the playback timeline (repeats/jumps unfolded unless `--no-expand`) |
| `convert <in> <out>` | Convert between any supported pair (formats inferred from the extensions, or `--from`/`--to`) |
| `render <in> <out.svg> [options]` | Render to SVG (notation, or `--tab` for tablature) |
| `omr <image> <out> --model <smt.gguf> [--single]` | Optical music recognition: a staff-notation image → score (`.musicxml`/`.mxl`/`.krn`) via the CrispEmbed Sheet Music Transformer |

Input formats are inferred from file extensions — `.xml`/`.musicxml`,
`.mxl` (zipped MusicXML), `.mei` (MEI), `.krn`/`.kern` (Humdrum), `.mid`/`.midi`,
`.abc` (ABC notation), `.mscx`/`.mscz` (MuseScore), `.gp` (7/8) / `.gpx` (6) /
`.gp5` / `.gp4` / `.gp3` (and raw `.gpif`), and plain-text tab
`.tab`/`.crd`/`.txt` — and can be overridden with `--from` (`musicxml` / `mxl` /
`mei` / `kern` / `midi` / `abc` / `mscx` / `mscz` / `gp` / `gpx` / `gp5` /
`gp4` / `gp3` / `gpif` / `asciitab`). Output formats use `--to` or the output
extension (`.svg`, `.png`, `.mid`, `.musicxml`, `.mxl`, `.mei`, `.krn`,
`.ly` (LilyPond, export only), `.brl` (braille music, export only), `.abc`, `.mscx`, `.mscz`, `.gp`, `.gpif`). All formats
funnel through one score model, so any pair round-trips transparently for the
data they share — the `.gp` GPIF path is high-fidelity (voice 2, tuplets, key
signature, dynamics, grace notes, articulations, lyrics and the tab techniques
all survive), and the binary `.gp3`–`.gp5` readers reject malformed input with a
`FormatException` rather than crashing (fuzz-tested). Plain-text tab is a lossy
import; use `--tuning` to set the tuning (also for `.gp`), and `--infer-rhythm`
to guess durations from the tab's horizontal spacing (otherwise all notes are
eighths).

### `render` options

| Option | Meaning |
|---|---|
| `--tab` | Render as guitar/bass tablature |
| `--tuning <std\|dropD\|bass>` | Tab tuning (default `std`) |
| `--track <n>` | Which track to import from a `.gp`/`.gpif` |
| `--infer-rhythm` | Guess note durations from tab spacing (plain-text tab input) |
| `--staff-space <px>` | Pixels per staff space (default 12) |
| `--metadata <path>` | SMuFL font metadata JSON (auto-located in the repo otherwise) |
| `--no-embed-font` | Do not embed the engraving font in the SVG |
| `--width <spaces>` | Max system width in staff spaces for multi-part scores (default 120) |
| `--no-system-context` | Omit multi-staff instrument labels and line-start bar numbers |
| `--no-title` | Omit imported title/composer page text |
| `--hide-empty` | Drop empty staves per system (multi-part) |
| `--single` | Force the single-part path (import the first part only) |

By default the engraving font is embedded via `@font-face`, so the SVG renders
anywhere.

**PNG**: give the output a `.png` extension. Rasterizing needs a font
rasterizer, so the tool delegates to the Flutter SDK (it runs
`flutter test tool/render_png.dart` in the `crisp_notation` package, located
automatically). The Flutter SDK must be on `PATH`; SVG needs only the Dart SDK.

### `omr` — optical music recognition

Recognizes a staff-notation image (PNG/JPEG) into a score via
[CrispEmbed](https://github.com/CrispStrobe/CrispEmbed) over FFI. The image is
decoded in pure Dart; the **engine is auto-detected** from the model:

- **Sheet Music Transformer** → `bekern` tokens → a two-staff `GrandStaff`
  (or a single staff with `--single`);
- **Polyphonic-TrOMR** → *semantic* notation → a single polyphonic `Score`;
- **Flova** (handwritten / whiteboard) → LilyPond "simple notes" → an unmetered
  single-staff `Score`.

Output is `.musicxml`, `.mxl`, `.krn`, `.svg`, or `.png` — the last two render
the notation (a grand staff for SMT, a single staff for TrOMR;
`--staff-space`/`--no-embed-font` apply as in `render`). `.png` needs the
Flutter SDK (it rasterizes via `flutter test`), like `render`.

| Option | Meaning |
|---|---|
| `--model <gguf\|name>` | OMR GGUF path, or a name that auto-downloads from Hugging Face to a cache — `smt-grandstaff` / `tromr` / `flova` (or set `CRISP_NOTATION_OMR_MODEL`) |
| `--lib <path>` | `libcrispembed` shared library (or set `CRISPEMBED_LIB`) |
| `--single` | Import only the first spine (single staff, not a grand staff) |
| `--page` | Full-page scan: split it into staff systems (horizontal-projection band detection) and recognize each, concatenating the results into one score |
| `--threads <n>` | Inference threads (default: auto) |

Needs the native `libcrispembed` at runtime (built from CrispEmbed); the rest of
the CLI is pure Dart.

## Examples

```
dart run crisp_notation_cli:crisp_notation info song.musicxml
dart run crisp_notation_cli:crisp_notation convert song.musicxml song.mid
dart run crisp_notation_cli:crisp_notation convert song.gp song.musicxml    # .gp (7/8)
dart run crisp_notation_cli:crisp_notation convert song.mscz song.musicxml  # MuseScore
dart run crisp_notation_cli:crisp_notation convert song.musicxml song.mxl   # zipped MusicXML
dart run crisp_notation_cli:crisp_notation convert song.mei song.musicxml   # MEI
dart run crisp_notation_cli:crisp_notation convert song.krn song.musicxml   # Humdrum **kern
dart run crisp_notation_cli:crisp_notation convert song.musicxml song.ly    # LilyPond (export)
dart run crisp_notation_cli:crisp_notation convert song.musicxml song.brl   # braille music (export)
dart run crisp_notation_cli:crisp_notation render song.musicxml song.svg
dart run crisp_notation_cli:crisp_notation render song.musicxml song.png       # needs Flutter
dart run crisp_notation_cli:crisp_notation render riff.musicxml riff.svg --tab --tuning dropD
dart run crisp_notation_cli:crisp_notation render riff.tab riff.svg --tab      # import ASCII tab
dart run crisp_notation_cli:crisp_notation omr scan.png score.musicxml --model smt-grandstaff.gguf  # scan → score
```
