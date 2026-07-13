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

## Gaps

| # | Severity | Area | Symptom | Repro | Status |
|---|---|---|---|---|---|
| G1 | medium | CLI packaging | `render` to SVG fails *"SMuFL metadata not found"* when the CLI binary runs outside the repo tree — so the **released standalone binary** can't render without `--metadata`. | `partitura render x.musicxml x.svg` from `/tmp` | open |
| G2 | high (fidelity) | reader / model | Multi-part scores (orchestra, string quartet, piano grand staff) collapse to a **single part** through the single-`Score` path (`scoreFromMusicXml` / CLI render): a Mozart quartet imports as one melodic line. | `partitura info Mozart_String_Quartet…` → 1 clef, 72 elements | open — tracked by **C6** multi-part model (other worktree) |
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
