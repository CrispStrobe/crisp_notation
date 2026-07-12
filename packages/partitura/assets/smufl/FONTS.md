# Music fonts (SMuFL)

partitura renders notation with a [SMuFL](https://www.smufl.org/) font. **Bravura**
(SIL OFL 1.1) is bundled and is the default (`MusicFont.bravura`). Because SMuFL
fixes every glyph's codepoint, any SMuFL font drops in without touching the glyph
tables — only the outlines and engraving metrics change.

## Licensing

Every mainstream SMuFL music font is **SIL Open Font License 1.1 (OFL)**, not MIT.
That is fine here: OFL is a *font* license (it governs the font file only, never
your code), it is more permissive than MIT for the things fonts need — embedding,
modification, redistribution, commercial use — and it bundles cleanly inside this
MIT-licensed project, exactly as Bravura already does. The only OFL conditions
(don't sell the bare font on its own; "reserved" names can't be reused for a
modified font) don't affect bundling a font in an app.

The one *more*-permissive option is **Gonville** (its generator is MIT and its
author disclaims copyright on the output font files — effectively public domain),
but Gonville is natively a LilyPond font; use the SMuFL-mapped variant
(MuseScore's **Gootville**) if you want a public-domain face.

| Font | Style | License | Source | Bundled? |
|---|---|---|---|---|
| Bravura | standard | SIL OFL 1.1 | steinbergmedia/bravura | ✅ default |
| Petaluma | jazz / handwritten | SIL OFL 1.1 | steinbergmedia/petaluma | drop-in (`MusicFont.petaluma`) |
| Leland | clean engraving | SIL OFL 1.1 | MuseScoreFonts/Leland | drop-in (`MusicFont.leland`) |
| Leipzig | Verovio/RISM | SIL OFL 1.1 | rism-digital/leipzig | drop-in (`MusicFont.leipzig`) |
| Gootville | Gonville-derived | public domain (font files) | musescore/MuseScore `fonts/` | manual |

## Adding a font (three steps)

Descriptors already exist for Petaluma / Leland / Leipzig (`MusicFont.petaluma`
etc.); the files just aren't vendored (they add ~1 MB each). To enable one — say
Petaluma — from its source repo:

1. **Drop the files** into `packages/partitura/assets/smufl/`:
   - `Petaluma.otf` (the font)
   - `petaluma_metadata.json` (glyph boxes + engraving defaults)
   - `OFL.txt` (its license — required by OFL)

2. **Declare it** in `packages/partitura/pubspec.yaml`:

   ```yaml
   flutter:
     assets:
       - assets/smufl/petaluma_metadata.json
     fonts:
       - family: Petaluma
         fonts:
           - asset: assets/smufl/Petaluma.otf
   ```

3. **Use it** via the theme (the descriptor is already defined):

   ```dart
   StaffView(
     score: score,
     theme: const PartituraTheme(musicFont: MusicFont.petaluma),
   );
   ```

That's it — every view (`StaffView`, `MultiSystemView`, `StaffSystemView`,
`ScorePageView`, `GrandStaffView`, `TabStaffView`, `renderLayoutToPng`) reads the
theme's font and relayouts with its metrics. For a font not listed here, define
your own `MusicFont(family: …, metadataAsset: …)` (with `package: null` when the
assets live in your own app) and pass it the same way.
