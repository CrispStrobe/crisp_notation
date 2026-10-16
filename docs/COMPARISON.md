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
| Keyboard step entry | ✗ (app's job) | ◐ shortcuts | ✗ | ✓ | ✗ | ✓ | ✗ |
| MIDI keyboard entry | ✗ (app's job) | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ |
| Scan / photo (OMR) | ✓ | ✓ | ✗ | ✗ (separate service) | ✗ | ✗ | ✗ |
| Sung / played pitch | ✗ | ✓ mic pitch detection | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Engraving** | | | | | | | |
| Automatic layout quality | ◐ good for teaching material; gaps below | ◐ = crisp_notation | ✓ reference quality | ✓ | via LilyPond | via LilyPond | ◐ |
| Spacing, collisions | ◐ skyline collision avoidance, simple spacing | ◐ | ✓ optical spacing, scored slurs, beam quanting | ✓ | via LilyPond | via LilyPond | ◐ |
| Line / page breaking | ◐ greedy | ◐ | ✓ optimised | ✓ | via LilyPond | via LilyPond | ◐ |
| House styles | ◐ settings object | ✗ | ✓ | ✓ | via LilyPond | via LilyPond | ✓ `%%` directives |
| Early music (mensural, chant neumes) | ◐ chant imports to modern notes | ✗ | ✓ | ◐ | via LilyPond | via LilyPond | ✗ |
| Tablature | ✓ with techniques | ✓ | ✓ | ✓ | via LilyPond | via LilyPond | ✗ |
| **Output** | | | | | | | |
| Vector PDF | ✗ (SVG) | ◐ PDF of raster pages | ✓ | ✓ | via LilyPond | via LilyPond | ✓ via PostScript |
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
| Linked parts | ✓ API | ✗ UI | ✓ (tags) | ✓ | via LilyPond | ◐ | ✗ |
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
   font (`LayoutSettings.textWidth`); SVG and CLI output still estimate, for
   the widest common UI font. Spacing itself is a fixed duration curve with an ink
   floor, not optical spacing.
2. **Line breaking** — *done (2026-10-16):* breaks are chosen for the whole
   piece (minimal underfill, no lone last bar), in every wrapped layout. Page
   breaking (systems to pages) is still greedy.
3. **Slurs and beams** — *beams quanted (2026-10-16):* a beam inside the
   staff sits on, straddles or hangs from a line. Slurs still take one shape
   lifted over the ink they clear, where LilyPond scores candidate shapes.
4. **Cross-staff chords** (one stem, heads on both staves) cannot be
   represented: each staff now gets its half with its own stem (PLAN 2.2).
5. **Text styling from the source** — *done for MusicXML (2026-10-16):*
   italic and bold `<words>` keep their style, tempo words print bold. Other
   formats' text styles (MEI `rend`, MuseScore text styles) are not read yet.
6. **Title block** — *done (2026-10-16):* title, subtitle, lyricist, composer,
   arranger and a copyright footer in SVG, read from and written to MusicXML.
   The Flutter views draw no title block of their own; apps compose one.
7. **Multi-voice conventions** — *shared rests and a notehead-width
   displacement done (2026-10-16);* 2,398 notes in the corpus (from 28,249, mostly MEI and MuseScore
   files) are still crossed by another voice's stem — the model has no stem
   direction of its own, so the file's `<stem>` is not kept. In 111 bars a
   staff whose voices are pushed apart still ends its bar a little past the
   others.
8. **Vector PDF output.** SVG and PNG only; an app wanting print composes
   PDF itself (CometBeat rasterises pages).
9. **House styles** — *partly done (2026-10-16):* `LayoutSettings.engraved`
   and `.spacious` presets beside the default; no user-defined style sheets.
10. **Early notations.** Gregorian chant imports into modern notes; no
    neumes, no mensural notation.
11. **Automated reference comparison.** The live corpus checks engraving
    rules and round trips; it does not yet compare against a reference
    engraver. The defects in this round were found by doing that by hand.
    Next: note onsets against Verovio's timing map, and per-bar symbol counts
    (rests, accidentals, braces) against it.

By design and not gaps: audio synthesis (apps bring their own), note-entry UI
(apps build theirs on the interaction hooks).

## What CometBeat still lacks

CometBeat is a learning app, so the comparison that matters is with what a
pupil, a parent or a teacher would otherwise reach for — usually MuseScore
Studio, sometimes a LilyPond or ABC workflow for printed material.

1. **Printed output.** PDF export assembles raster page images; a vector PDF
   (from crisp_notation SVG) would print sharply and stay small.
2. **Parts.** No way to extract or view one instrument's part from an
   ensemble score, though crisp_notation has linked parts.
3. **Screen-reader access to scores.** Widgets carry semantics, but a score
   cannot be read note by note with a screen reader; crisp_notation's
   accessibility descriptions and braille export are not wired in.
4. **Teacher and classroom features.** No assignments, no class or progress
   view for a teacher, no sharing of a pupil's piece beyond files.
5. **Typed entry for older pupils.** No ABC or note-name text entry in the
   editor, though crisp_notation reads ABC and its own note DSL.
6. **Fast keyboard entry in the editor** as MuseScore Studio offers it
   (shortcuts exist; a full step-entry mode does not).
7. **Engraving quality** is crisp_notation's (above): spacing, breaking and
   text styling show in printed songs.
