# Contributing

## Every change

- `dart format`, and `flutter analyze` at the repo root with zero issues.
- All tests green: `dart test` in `packages/crisp_notation_core` and
  `packages/crisp_notation_cli`, `CI=true flutter test` in
  `packages/crisp_notation`.
- A `CHANGELOG.md` entry under `## Unreleased` in each package you touched.

## Writing tests: assert the engraving, not the output

A test that counts what the code draws agrees with the code, bugs included.
Before #19 was fixed, a test asserted three thick barlines for a piece ending
on a repeat — "start repeat + end repeat + final barline" — and so protected
the doubled closing barline it was meant to catch.

State what a reader of the printed page would check instead:

- **Good:** "a piece that ends on a repeat ends with exactly one closing
  barline, the repeat's", "no notehead overlaps the time signature".
- **Weak:** "the layout has 3 thick lines" — fine as a supporting detail, not
  as the claim. If you write a count, say in the comment *why* that number is
  correct engraving, and check it against a reference (Gould, *Behind Bars*;
  LilyPond's or MuseScore's output of the same music).

Three tools do this for you:

- **`test/support/layout_lint.dart`** (core) — `lintLayout` checks a finished
  `ScoreLayout` against engraving rules: barline groups engravers draw, the
  staff ending on its closing barline, repeat dots beside a repeat barline,
  no notehead on the clef/key/time signature or a barline, no element drawn
  twice. `barlineMismatches` compares the drawn barlines with what the score's
  measures ask for. Run new layout features through both.
- **`test/barline_grid_test.dart`** — every barline style and repeat at the
  first, middle and last bar, on and off a line break, through every layout
  entry point (single line, wrapped, grand staff, staff systems, notation +
  tab). A new barline kind or layout entry point belongs in this grid.
- **`test/live_corpus_test.dart`** — the same rules over ~4,700 real scores
  in six formats, plus the LilyPond MusicXML test suite and the W3C examples
  (opt-in, see the file's header; the corpus is not in the repo). Its ceilings only go down: a
  change that raises one is a regression, a change that lowers one should
  lower the ceiling in the same commit.

## Reference renderings

`packages/crisp_notation/test/goldens_svg/` holds an SVG per golden scene and
gates in CI. Update with `CI=true UPDATE_SVG_GOLDENS=1 flutter test
test/golden_test.dart`, then **look at** every changed file (render it, e.g.
`cairosvg x.svg -o x.png`) before committing — an updated golden is a claim
that the new picture is right. The PNG goldens are macOS-only and are
regenerated there (see issue #5).
