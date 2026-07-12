# partitura_cli

Command-line tool for the [partitura](https://github.com/CrispStrobe/partitura)
music notation libraries: inspect, convert (MusicXML ↔ MIDI) and render scores
to SVG — all pure Dart.

## Usage

```
dart run partitura_cli:partitura <command> [arguments]
```

| Command | Purpose |
|---|---|
| `info <in>` | Summarize a score (clef, meter, sizes, timeline length) |
| `timeline <in> [--bpm N] [--no-expand]` | Print the playback timeline (repeats/jumps unfolded unless `--no-expand`) |
| `convert <in> <out>` | Convert between MusicXML and MIDI (formats inferred from the extensions) |
| `render <in> <out.svg> [options]` | Render to SVG (notation, or `--tab` for tablature) |

Input formats are inferred from file extensions — `.xml`/`.musicxml`,
`.mxl` (zipped MusicXML), `.mei` (MEI), `.krn`/`.kern` (Humdrum), `.mid`/`.midi`,
`.abc` (ABC notation), `.mscx`/`.mscz` (MuseScore), `.gp` (7/8) / `.gpx` (6) /
`.gp5` / `.gp4` / `.gp3` (and raw `.gpif`), and plain-text tab
`.tab`/`.crd`/`.txt` — and can be overridden with `--from` (`musicxml` / `mxl` /
`mei` / `kern` / `midi` / `abc` / `mscx` / `mscz` / `gp` / `gpx` / `gp5` /
`gp4` / `gp3` / `gpif` / `asciitab`). Output formats use `--to` or the output
extension (`.svg`, `.png`, `.mid`, `.musicxml`, `.mxl`, `.mei`, `.krn`,
`.ly` (LilyPond, export only), `.abc`, `.mscx`, `.mscz`, `.gp`, `.gpif`). All formats
funnel through one score model, so any pair round-trips transparently for the
data they share. Plain-text tab is a lossy import; use `--tuning` to set the
tuning (also for `.gp`), and `--infer-rhythm` to guess durations from the tab's
horizontal spacing (otherwise all notes are eighths).

### `render` options

| Option | Meaning |
|---|---|
| `--tab` | Render as guitar/bass tablature |
| `--tuning <std\|dropD\|bass>` | Tab tuning (default `std`) |
| `--staff-space <px>` | Pixels per staff space (default 12) |
| `--metadata <path>` | SMuFL font metadata JSON (auto-located in the repo otherwise) |
| `--no-embed-font` | Do not embed the engraving font in the SVG |

By default the engraving font is embedded via `@font-face`, so the SVG renders
anywhere.

**PNG**: give the output a `.png` extension. Rasterizing needs a font
rasterizer, so the tool delegates to the Flutter SDK (it runs
`flutter test tool/render_png.dart` in the `partitura` package, located
automatically). The Flutter SDK must be on `PATH`; SVG needs only the Dart SDK.

## Examples

```
dart run partitura_cli:partitura info song.musicxml
dart run partitura_cli:partitura convert song.musicxml song.mid
dart run partitura_cli:partitura convert song.gp song.musicxml    # .gp (7/8)
dart run partitura_cli:partitura convert song.mscz song.musicxml  # MuseScore
dart run partitura_cli:partitura convert song.musicxml song.mxl   # zipped MusicXML
dart run partitura_cli:partitura convert song.mei song.musicxml   # MEI
dart run partitura_cli:partitura convert song.krn song.musicxml   # Humdrum **kern
dart run partitura_cli:partitura convert song.musicxml song.ly    # LilyPond (export)
dart run partitura_cli:partitura render song.musicxml song.svg
dart run partitura_cli:partitura render song.musicxml song.png       # needs Flutter
dart run partitura_cli:partitura render riff.musicxml riff.svg --tab --tuning dropD
dart run partitura_cli:partitura render riff.tab riff.svg --tab      # import ASCII tab
```
