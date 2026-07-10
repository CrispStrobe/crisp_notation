/// Access to the bundled Bravura font's SMuFL metadata.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:partitura_core/partitura_core.dart';

/// Loads and caches the metadata of the bundled Bravura font
/// (`assets/smufl/bravura_metadata.json`).
///
/// The first [StaffView] build triggers the load automatically and paints
/// once it completes. Call [load] up front (e.g. in `main()` or a test
/// `setUpAll`) to guarantee synchronous availability.
abstract final class Bravura {
  static SmuflMetadata? _metadata;
  static Future<SmuflMetadata>? _pending;

  /// The metadata, if already loaded.
  static SmuflMetadata? get metadataOrNull => _metadata;

  /// Loads the metadata from the asset bundle (once; later calls return
  /// the cached instance). If a load fails, the failure is not cached —
  /// the next call retries.
  static Future<SmuflMetadata> load() {
    if (_metadata != null) return Future.value(_metadata);
    return _pending ??= _loadFresh();
  }

  static Future<SmuflMetadata> _loadFresh() async {
    try {
      final source = await rootBundle
          .loadString('packages/partitura/assets/smufl/bravura_metadata.json');
      final metadata =
          SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>);
      _metadata = metadata;
      return metadata;
    } catch (_) {
      _pending = null; // allow a retry
      rethrow;
    }
  }

  /// Injects already-parsed [metadata] (for tests that load the JSON from
  /// the file system instead of an asset bundle).
  static void debugOverrideMetadata(SmuflMetadata metadata) {
    _metadata = metadata;
  }

  /// Clears the cache so the next [load] hits the asset bundle again
  /// (tests only).
  static void debugReset() {
    _metadata = null;
    _pending = null;
  }
}
