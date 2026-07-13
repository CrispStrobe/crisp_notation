# Hardening — real-input gap log

Systematic robustness pass: feed partitura complicated real-world scores from
many sources (Guitar Pro, MusicXML, MIDI, …), parse + render them, and record
every gap found so they can be closed one at a time.

The guiding principle: **the renderer must never crash on real input** — an
unrecognized or malformed element should be skipped (ideally logged), not throw.

## Corpus swept so far

| Source | Files | Result |
|---|---|---|
| Guitar Pro (`.gp3/4/5/.gp/.gpx`, in-repo) | 25 | all parse + render (notation & tab) ✅ |
| MusicXML real scores (OSMD corpus: Bach, Beethoven, Mozart quartet/quintet, Brahms, Debussy, Clementi, 1.2 MB orchestral, `.mxl`) | 12 | 9 render ✅, 1 parse-fail, 2 render-crash |
| MIDI (round-trip of the above) | 3 | all parse + render ✅ |
| MEI real scores (Aguado guitar, Altenburg concerto 431 KB, Bach **Brandenburg** 1.2 MB, fughette) | 4 | all parse + render ✅ (single-part path) |
| Humdrum `**kern` (Bach chorales) | 2 | all parse + render ✅ |
| **C6 multi-part probe** (via `staffSystemFromMusicXml`) | 10 | Mozart quartet → 4 staves, Beethoven/Debussy → 3, Bach/Clementi → 2, **ActorPrelude orchestral → 23 staves / 2377 elements** ✅ (all after G6/G7) |
| **Round 4** — 10 more each: MusicXML (Gounod 7-staff, Haydn, Mozart songs), MEI (Brandenburg II/III/IV, Chopin, chorales), `**kern` (10 Bach chorales → 4-part SATB) | 30 | all parse + render ✅; multi-part probe 19/20 (1 `.mxl` = probe artifact) |
| **Round 4** — MIDI + ABC round-trips of the real XMLs | 10 + 10 | MIDI all ✅; **3 ABC (vocal) rendered a crash → G8** |

## Gaps

| # | Severity | Area | Symptom | Repro | Status |
|---|---|---|---|---|---|
| G1 | medium | CLI packaging | `render` to SVG failed *"SMuFL metadata not found"* when the CLI binary ran outside the repo tree — so the **released standalone binary** couldn't render without `--metadata`. | `partitura render x.musicxml x.svg` from `/tmp` | **fixed** — Bravura metadata embedded (deflate+base64, ~136 KB) as an offline fallback |
| G2 | high (fidelity) | reader / model | Multi-part scores collapsed to a **single part** through the single-`Score` path. | `partitura info Mozart_String_Quartet…` → 1 clef | **mostly fixed by C6**: `staffSystemFromMusicXml` + `layoutMultiPartPages` import & paginate all parts (Mozart quartet → 4 staves, Beethoven/Debussy → 3, Bach/Clementi → 2). *Follow-up:* the **CLI `render`** still uses the single-`Score` path — wire it to the multi-part layout. |
| G6 | high | musicxml reader | The orchestral **ActorPrelude** threw `Cannot map duration 85/1024` — a `<duration>` with no `<type>` that doesn't reduce to a standard value aborted the import. | multi-part import of `ActorPreludeSample.xml` | **fixed** — snaps to the nearest note value |
| G7 | high | musicxml reader | A percussion `<unpitched>` note (no `<pitch>`, no `<rest>`) threw `<note> without <pitch> or <rest>`, aborting the import (orchestral scores). | same file, after G6 | **fixed** — `<unpitched>` maps to its display staff line (proper percussion staff is a tracked follow-up) |
| G8 | high (crash) | **abc reader** | A vocal ABC round-trip threw `RangeError` in `_layoutLyrics`. **Root cause** (not the layout): the reader added *rest* ids to `noteOrder`, so `w:` syllables aligned onto rests — shifting every syllable and attaching some past the last note. | round-trip render of Mozart AnChloe / DasVeilchen / Land der Berge | **fixed at the source** — `noteOrder` now holds note ids only, so syllables align to notes and skip rests (per the ABC spec). Regression test pins it. |
| G3 | high | musicxml reader | A slur `start`/`stop` imbalance (a `type="continue"` reusing a number, or a lost `stop`) left a slur open → parse aborted *"Unclosed `<slur>`"*. | `partitura info Debussy_Mandoline.xml` | **fixed** — dangling slur dropped, parse continues |
| G4 | high (crash) | layout engine | A degenerate `Hairpin(eN → eN)` (start == end) threw `must run forward in reading order` — uncaught. | `partitura render Dichterliebe01.xml …` | **fixed** (a2… ) |
| G5 | high (crash) | layout engine | A `Pedal(e0 → e29)` whose end id is not in the imported score threw `references an unknown note element id` — uncaught. | `partitura render OSMD_Function_Test_Pedals.musicxml …` | **fixed** |

### G4 + G5 — fixed, and generalized
Root cause: **every** span/annotation layout pass threw on a degenerate span
(start == end / reversed) or a dangling note id. Any span whose other end is in a
dropped part (very common — see G2) crashed the whole render. Fix: **all** of the
~20 span passes (dynamics, hairpins, pedals, slurs, glissandos, portamentos,
laissez-vibrer, ottavas, trills, vibratos, lyrics, figured bass, breath marks,
jazz marks, chord diagrams) now **skip** a degenerate/dangling span and render
everything else — a renderer must never crash on real input. The
"fails-loudly" tests were updated to assert the new leniency. Verified: the two
crashers now render, core + Flutter suites green.

## Closing order (highest value first)
1. **G4 + G5** — never crash on a bad span (skip degenerate / dangling spans).
2. **G3** — handle `<slur type="continue">` in the MusicXML reader.
3. **G1** — embed the SMuFL metadata in the CLI so the released binary renders.
4. **G2** — folds into the C6 multi-part effort (other worktree).
