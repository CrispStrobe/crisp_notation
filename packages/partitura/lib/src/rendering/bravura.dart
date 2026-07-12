/// Access to the bundled Bravura font's SMuFL metadata.
///
/// Thin convenience wrapper over [MusicFonts] for the default font. New code
/// that wants a specific or pluggable font should use [MusicFonts] with a
/// [MusicFont] directly (e.g. via `PartituraTheme.musicFont`).
library;

import 'package:partitura_core/partitura_core.dart';

import 'music_font.dart';

/// Loads and caches the metadata of the bundled Bravura font
/// (`assets/smufl/bravura_metadata.json`).
///
/// The first view build triggers the load automatically and paints once it
/// completes. Call [load] up front (e.g. in `main()` or a test `setUpAll`) to
/// guarantee synchronous availability.
abstract final class Bravura {
  /// The metadata, if already loaded.
  static SmuflMetadata? get metadataOrNull =>
      MusicFonts.metadataOrNull(MusicFont.bravura);

  /// Loads the metadata from the asset bundle (once; later calls return the
  /// cached instance).
  static Future<SmuflMetadata> load() => MusicFonts.load(MusicFont.bravura);

  /// Injects already-parsed [metadata] (for tests that load the JSON from the
  /// file system instead of an asset bundle).
  static void debugOverrideMetadata(SmuflMetadata metadata) =>
      MusicFonts.debugRegister(MusicFont.bravura, metadata);

  /// Clears the cache so the next [load] hits the asset bundle again
  /// (tests only).
  static void debugReset() => MusicFonts.debugReset();
}
