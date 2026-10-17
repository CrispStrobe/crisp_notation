# crisp_notation and CometBeat beside established notation tools

*Written 2026-10-16. A factual comparison, at the owner's request, of what
these tools do — not marketing. It is the one place in this repo that names
other notation software beyond file formats. Engraving findings come from
rendering the same real scores (OpenScore Lieder, the MusicXML tutorial) with
crisp_notation, LilyPond 2.24 and Verovio 6.3 and reading the differences;
capabilities of the other tools are as documented by their projects.*

The tools are different kinds of thing, so "best for" matters more than a
feature count:

| Tool | License | Kind | Best for |
|---|---|---|---|
| **crisp_notation** | MIT | Dart/Flutter library + CLI | Interactive notation inside apps (tap, drag, highlight), interchange, theory |
| **CometBeat** | — | Flutter app built on crisp_notation | Learning music (age 6+): games, ear training, play-along, a touch score editor |
| LilyPond | GPL | Text-to-score compiler | Professional engraving and publishing |
| MuseScore Studio | GPL | Desktop WYSIWYG editor | Graphical editing and general-purpose notation |
| Frescobaldi | GPL | Editor for LilyPond source | Writing LilyPond with point-and-click, preview, tools |
| Denemo | GPL | Graphical front end with LilyPond engraving | Keyboard/MIDI note entry, typeset by LilyPond |
| ABC + abcm2ps | GPL | Text format + typesetter | Folk tunes, lead sheets, tune books |

## Capabilities

✓ = yes, ◐ = partial, ✗ = no. "via LilyPond" = the tool produces it by
running LilyPond.

| | crisp_notation | CometBeat | LilyPond | MuseScore Studio | Frescobaldi | Denemo | ABC + abcm2ps |
|---|---|---|---|---|---|---|---|
| **Input** | | | | | | | |
| Text language | ◐ a compact note DSL; reads ABC/LilyPond | ✗ | ✓ `.ly` | ✗ | ✓ `.ly`, with completion | ◐ commands | ✓ ABC |
| Mouse / touch entry | ◐ hooks (tap, drag, ghost note) for apps | ✓ touch editor | ✗ | ✓ | ◐ point-and-click to source | ✓ | ✗ |
| Keyboard step entry | ✗ (app's job) | ✓ step entry | ✗ | ✓ | ✗ | ✓ | ✗ |
| MIDI keyboard entry | ✗ (app's job) | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ |
| Scan / photo (OMR) | ✓ | ✓ | ✗ | ✗ (separate service) | ✗ | ✗ | ✗ |
| Sung / played pitch | ✗ | ✓ mic pitch detection | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Engraving** | | | | | | | |
| Automatic layout quality | ◐ good for teaching material; gaps below | ◐ = crisp_notation | ✓ reference quality | ✓ | via LilyPond | via LilyPond | ◐ |
| Spacing, collisions | ◐ skyline collision avoidance, scored slurs, quanted beams, stem-direction optical spacing, staves spaced by their ink | ◐ = crisp_notation | ✓ optical spacing, scored slurs, beam quanting | ✓ | via LilyPond | via LilyPond | ◐ |
| Line / page breaking | ✓ optimised (whole-piece fit, no widows) | ✓ = crisp_notation | ✓ optimised | ✓ | via LilyPond | via LilyPond | ◐ |
| House styles | ✓ presets and JSON style sheets | ✗ | ✓ | ✓ | via LilyPond | via LilyPond | ✓ `%%` directives |
| Early music (mensural, chant neumes) | ✓ square-notation chant, white mensural | ✗ | ✓ | ◐ | via LilyPond | via LilyPond | ✗ |
| Tablature | ✓ with techniques | ✓ | ✓ | ✓ | via LilyPond | via LilyPond | ✗ |
| **Output** | | | | | | | |
| Vector PDF | ✓ pure Dart, font embedded | ✓ | ✓ | ✓ | via LilyPond | via LilyPond | ✓ via PostScript |
| SVG / PNG | ✓ | ✓ PNG | ✓ | ✓ | via LilyPond | via LilyPond | ✓ SVG |
| MIDI | ✓ | ✓ | ✓ | ✓ | via LilyPond | ✓ | ✓ abc2midi |
| Audio render | ✗ by design (timing map) | ✓ WAV/MP3, SoundFonts | ✗ | ✓ | ✗ | ✓ | ✗ |
| Braille | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| **Interchange** | | | | | | | |
| MusicXML in / out | ✓ / ✓ | ✓ / ✓ | ◐ in (musicxml2ly) / ✗ | ✓ / ✓ | ◐ in / ✗ | ◐ in | ✗ |
| MEI, kern, ABC, LilyPond, MuseScore, Guitar Pro | ✓ read and write | ✓ via crisp_notation | ◐ ABC/MIDI in | ◐ MEI, Guitar Pro in | ✗ | ✗ | ◐ |
| **Use** | | | | | | | |
| Interactive in an app (hit regions, highlight, playback cursor) | ✓ | ✓ | ✗ | ✓ its own UI | ◐ | ✓ its own UI | ✗ |
| Embeddable library | ✓ | — | ✗ (a program) | ✗ | ✗ | ✗ | ◐ (abcjs is the web library) |
| Web, mobile | ✓ (Flutter, WasmGC) | ✓ | ✗ | ✗ desktop | ✗ | ✗ | ◐ |
| Linked parts | ✓ API | ◐ part export and part view | ✓ (tags) | ✓ | via LilyPond | ◐ | ✗ |
| Scripting | Dart API | ✗ | ✓ Scheme | ✓ plugins | ✓ Python | ✓ Scheme | ✗ |
| Theory and analysis | ✓ (roman numerals, voice leading, set theory, key finding) | ✓ in games | ✗ | ◐ plugins | ✗ | ✗ | ✗ |
| Teaching (games, review, ear training) | ✗ (library) | ✓ | ✗ | ✗ | ✗ | ◐ | ✗ |

## Where crisp_notation stands

It is the only one of these that is a **library**: notation that an app lays
out, hit-tests and highlights, in pure Dart on every platform, with a wide
interchange surface (eight formats read and written: MusicXML, MEI, kern,
MIDI, MuseScore, Guitar Pro, ABC, LilyPond), OMR, and a theory layer the
others lack. The engravers above it — LilyPond, and
MuseScore Studio for interactive editing — are where its print quality has to
reach.

## What crisp_notation still lacks

Ordered by how much a reader of a real score sees it. The first block was
found by the side-by-side rendering; the fixed items are listed in
`packages/crisp_notation_core/CHANGELOG.md`.

1. **Horizontal spacing.** A Debussy song takes 12 lines where LilyPond
   needs about 10 (it took 14 before 2026-10-16, when lyrics reserved a flat
   0.62 em per character). The Flutter views now measure text with their own
   font (`LayoutSettings.textWidth`), PDF output with Times (the face it
   prints, `timesTextWidth`) or the text font it embeds, and SVG with a text
   font it embeds
   (`textWidthFromFont`, CLI `--text-font`); without one, SVG still estimates
   for the widest common font, since its viewer picks the face. Spacing is a duration curve with an ink floor
   and, since 2026-10-17, an optical correction for stem direction between
   notes, at the edges of beams and in the shared columns of systems;
   LilyPond's fuller optical spacing (note shapes, multi-voice columns on
   one staff) is not matched.
2. **Line breaking** — *done (2026-10-16):* breaks are chosen for the whole
   piece (minimal underfill, no lone last bar), in every wrapped layout. Pages
   fill greedily but never end on a lone system the page before could spare.
3. **Slurs and beams** — *done (2026-10-16):* a beam inside the staff sits
   on, straddles or hangs from a line, and a slur is the best-scoring of
   several hundred candidate shapes (clearance, closeness to the notes,
   flatness, slope with the notes), as LilyPond chooses it.
4. **Cross-staff chords** — *done (2026-10-17):* a chord on both staves of
   a piano part takes one stem through the gap (`CrossStaffChord`, read
   from MusicXML), in grand staves and in multi-part scores alike.
5. **Text styling from the source** — *done (2026-10-16):* italic and bold
   text keeps its style through MusicXML `<words>`, MEI `<rend>` and
   MuseScore `<i>`/`<b>` and the Expression style; tempo words print bold.
6. **Title block** — *done (2026-10-16):* title, subtitle, lyricist, composer,
   arranger and a copyright footer in SVG, read from and written to MusicXML.
   The Flutter views draw no title block of their own; apps compose one.
7. **Multi-voice conventions** — *done (2026-10-16):* shared rests, a
   notehead-width displacement, stem directions kept from the source, and
   same-direction voices moved apart. 237 notes in the corpus (from 28,249)
   are still crossed by another voice's stem, and one bar's staves do not
   close together.
8. **Vector PDF output** — *done (2026-10-16):* `pagedLayoutToPdf`,
   `multiPartPagesToPdf` and `scoreLayoutToPdf` write paged vector PDF in
   pure Dart, the SMuFL font embedded, with the title block and copyright on
   the first page; the CLI renders `.pdf`. Text is set in the standard Times
   faces, so characters outside Latin-1 print as `?` — unless a text font is
   given (`PdfTextFont`, CLI `--text-font`): it is embedded whole (no
   subsetting) with a ToUnicode map, so any script it covers prints and
   copies.
9. **House styles** — *done (2026-10-17):* `engraved` and `spacious`
   presets beside the default, and style sheets — JSON over a preset, read
   by `LayoutSettings.fromStyle` and the CLI's `--style`.
10. **Early notations** — *done (2026-10-17):* GABC engraves in square
    notation (`layoutChant`, CLI `--square`) as well as importing into
    modern notes, and MEI white mensural notation engraves with its own
    clefs, signs and note shapes (`layoutMensural`, CLI `--mensural`),
    ligatures and coloured notes included.
11. **Automated reference comparison** — *done (2026-10-16):* opt-in tests
    compare the first staff with Verovio for 1,745 MusicXML files: note
    onsets against its timing map (1,689 agree; it found whole-bar rests
    read as sixteen quarters in 9/8), and rests and accidentals per bar
    (1,681 agree; it found tied-over notes repeating their accidental). The
    rest are microtones, senza-misura bars, nested tuplets, multi-bar-rest
    numbering and Verovio's own editorial accidentals. A second oracle
    compares the LilyPond reader with LilyPond's own MIDI for 374 Mutopia
    files (152 agree).
12. **Beaming from the source** — *done (2026-10-17):* MusicXML `<beam>` is
    followed where a part states it (flagged vocal eighths, 3+3+2 groups,
    beams over a barline); parts without it are grouped by the meter.
13. **Vertical spacing** — *done (2026-10-17):* each pair of staves sits as
    close as its ink allows at each x, and pages pack systems tighter before
    justifying: 59 voice-and-piano songs went from 203 pages to 139.
14. **Repeat endings** — *done (2026-10-17):* one bracket per ending, labels
    for several passes and text, open last endings, continuation across
    system breaks, MuseScore 3 voltas.

By design and not gaps: audio synthesis (apps bring their own), note-entry UI
(apps build theirs on the interaction hooks).

## What CometBeat still lacks

CometBeat is a learning app, so the comparison that matters is with what a
pupil, a parent or a teacher would otherwise reach for — usually MuseScore
Studio, sometimes a LilyPond or ABC workflow for printed material.

1. **Printed output** — *done (2026-10-16):* PDF export is vector, from
   crisp_notation's PDF writer (the `pdf` package and the per-system PNGs
   are gone).
2. **Parts** — *done (2026-10-17, CometBeat #10, #13):* the export sheet
   offers each instrument's part on its own, its silent stretches as
   multi-bar rests (`Score.withMultiRests`), and the Workshop shows and
   edits a part alone while the whole score plays.
3. **Screen-reader access to scores** — *done (2026-10-17):* every
   crisp_notation score view (staff, grand staff, multi-system, multi-part,
   staff system, tablature, interactive) gives each note a screen-reader
   node in reading order, named with its instrument; the export sheet
   writes braille music (`.brf`).
4. **Teacher and classroom features.** No assignments, no class or progress
   view for a teacher, no sharing of a pupil's piece beyond files.
   This needs accounts and a server holding pupils' (children's) data — a
   product and privacy decision, deliberately not started.
5. **Typed entry for older pupils** — *done (2026-10-17, CometBeat #11):*
   the Workshop reads typed ABC, note names, LilyPond and scanner tokens.
6. **Fast keyboard entry** — *done (2026-10-17, CometBeat #12):* letters
   land in the nearest octave, Shift adds chord tones, Ctrl/⌘+arrows move an
   octave, 0 rests, T ties.
7. **Engraving quality** is crisp_notation's (above): spacing, breaking and
   text styling show in printed songs.
