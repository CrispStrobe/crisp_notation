# Changelog

## 0.13.0 (2026-10-19)

Built on `crisp_notation_core` 0.13.0: `convert` and `render` read LilyPond
chord tracks, nested tuplets and `\scaleDurations` (431 of 433 Mutopia files
agree with LilyPond's MIDI), and MusicXML from MuseScore with a staff in its
own time signature.

## 0.12.0 (2026-10-19)

Built on `crisp_notation_core` 0.12.0: the LilyPond reader fixes of this
round reach `convert` and `render` (419 of 433 Mutopia files agree with
LilyPond's MIDI), and MIDI export plays measure-repeat bars.

## 0.11.0 (2026-10-18)

Built on `crisp_notation_core` 0.11.0: tighter, LilyPond-like spacing in
multi-staff PDF and SVG (the first system alone is indented for the
instrument names), endings, dynamics above vocal lines, stated beams over
barlines without stem clashes, and the LilyPond, MusicXML and MEI reader
fixes of this round.

## 0.10.0 (2026-10-17)

Built on `crisp_notation_core` 0.10.0: MusicXML beams as written, staves and
systems spaced by their ink (voice-and-piano PDFs take about a third fewer
pages), volta labels and open endings, and the LilyPond `q`, `\skip` and
`\incipit` fixes.

- A line-broken instrument name is sized by its widest line.
- `render <in> <out.pdf> --text-font <path.ttf|.otf>` now applies to PDF
  output too: the layout measures text in the font and the PDF embeds it
  (with a ToUnicode map), so lyrics and titles outside Latin-1 print instead
  of turning into `?`. Without `--text-font` a PDF still prints Times.
- `render <in> <out.svg> --text-font <path.ttf|.otf>` measures lyrics and
  markings in the given font (via `crisp_notation_core`'s `textWidthFromFont`)
  instead of the wide generic estimate, and embeds it in the SVG as a second
  `@font-face` (suppressed by `--no-embed-font`, same as the engraving font).
- PDF output measures lyrics and text in Times, the face it prints, so songs
  set tighter (fewer systems) than the safe SVG estimate allows.

## 0.9.0 (2026-10-17)

Built on `crisp_notation_core` 0.9.0; `convert` writes a piano as one
two-staff MusicXML part.

- `render <voice.mei> <out.svg|pdf> --mensural` engraves white mensural
  notation.

## 0.8.0 (2026-10-17)

Built on `crisp_notation_core` 0.8.0.

- `--style <sheet.json>` renders SVG and PDF in a house style.
- `render <chant.gabc> <out.svg|pdf> --square` engraves Gregorian chant in
  square notation (lines of `--width` spaces as SVG, pages as PDF).
- `render <in> <out.pdf>` writes paged vector PDF — A4 or `--paper letter`,
  `--staff-pt` points per staff space, the title on page one, every part of
  a multi-part score; `--font` names the music font to embed.

## 0.7.2 (2026-10-16)

Built on `crisp_notation_core` 0.7.2: `render` and `convert` read MusicXML
`<forward>` (voices after a gap were placed too early in 60% of real files),
keep both halves of cross-staff piano chords, align multi-staff barlines, and
`render` draws braces, brackets and a grand staff's joined barlines in SVG,
without a metronome mark for a playback-only tempo.

## 0.7.1 (2026-10-13)

Built on `crisp_notation_core` 0.7.1: `render` no longer doubles the closing
barline of a piece that ends on a repeat (#19), stops the staff at an explicit
closing barline, draws start repeats without a stray barline before them, and
keeps note names on every wrapped line. `convert` reads MusicXML keys beyond
seven sharps or flats.

## 0.7.0 (2026-10-06)

Built on `crisp_notation_core` 0.7.0, with fixes for GitHub issues #8–#14:
- `render` draws staccatissimo and quarter-tone accidentals (they had no
  codepoint) and metronome marks.
- `render` places slurs over mixed stems above, puts dynamics and touching
  hairpins on one line, and sits chord tremolos on the free stem.
- `convert` keeps multi-measure rests and their text, counting the covered bars once.
- A live test runs these through the compiled binary.

## 0.6.0 (2026-10-06)

Built on `crisp_notation_core` 0.6.0.

- **LilyPond input**: `info`, `convert`, `timeline` and `render` read `.ly`
  files (`--from ly`); `render` draws every staff of a multi-staff score.
  This uses core's LilyPond reader, which now matches LilyPond's own MIDI
  output on 123 of 374 Mutopia files, up from 13.
- MusicXML written by `convert` names its encoder
  (`<software>crisp_notation</software>`).
- Cross-staff beams in `render` slant with the figure and draw 16th-note and
  shorter beam levels.

## 0.5.0 (2026-10-05)

Built on `crisp_notation_core` 0.5.0. Every import, export and render picks up
its fixes. Highlights for the CLI: MusicXML tempo text and metronome marks
split across `<direction-type>` blocks are both kept, and `timeline` now repeats
a section closed by an end repeat with no start repeat. Ties, slurs and beams in
`render` follow standard engraving in chords and two-voice bars, and LilyPond
and kern files with text over a rest render instead of failing.

- **GABC (Gregorian chant) input**: `info`, `convert` and `render` read `.gabc`
  files, via core's new clean-room reader.
- **kern breve, long and maxima durations** (`0`, `00`, `000`) are parsed.
- Live regression tests run each of these fixes through the compiled binary.

## 0.4.3 (2026-07-15)

- **First pub.dev release.** Install with
  `dart pub global activate crisp_notation_cli` to get the `crisp_notation`
  command (inspect, convert between MusicXML/MEI/kern/MIDI/MuseScore/GP/ABC with
  LilyPond & braille export, render to SVG/PNG, and OMR). Added a usage example.
  `render ... .png` needs the Flutter SDK; `omr` needs the native
  `libcrispembed` — SVG/convert/info are pure Dart.

## 0.4.1 (2026-07-14)

- **Sheet title rendering**: multi-staff `render` outputs include imported
  title/composer page text by default; pass `--no-title` to suppress it.

- **Offline `render` for the standalone binary** (hardening G1): the Bravura
  SMuFL metadata is now embedded in the CLI (DEFLATE-compressed + base64,
  ~136 KB, inflated at runtime via the existing pure-Dart `inflate`), so a
  released `crisp_notation` binary renders SVG without the repo checkout or a
  `--metadata` path. Resolution order is unchanged (`--metadata` → repo →
  embedded); when it falls back to the embedded copy there is no font file, so
  the SVG references the engraving font by name instead of inlining it.
  Regenerate the embed with `tool/embed_metadata.dart`.

- **Braille music output**: `convert --to brl` (or a `.brl` output path) writes
  Unicode braille-music notation via the new core `scoreToBraille`.

## 0.4.0 (2026-07-13)

First tagged release. The `crisp_notation` CLI: inspect scores; convert between
MusicXML / `.mxl` / MEI / `**kern` / MIDI / MuseScore / the `.gp` tablature
family / ABC (plus LilyPond export); render to SVG or PNG (notation or tab); and
optical music recognition (`omr`) routing three CrispEmbed engines
(Sheet Music Transformer, Polyphonic-TrOMR, Flova) through one command, with
full-page segmentation (`--page`) and model auto-download by name. The OMR
pipeline is also exposed as a reusable library (`package:crisp_notation_cli/omr.dart`).
