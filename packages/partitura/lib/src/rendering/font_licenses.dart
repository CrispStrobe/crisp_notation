// packages/partitura/lib/src/rendering/font_licenses.dart
//
// Registers the SIL Open Font License for the music fonts partitura bundles, so
// they appear on the consuming app's `showLicensePage()`.
//
// Flutter's license page auto-discovers the LICENSE file of each *pub package*
// (partitura's own MIT license shows that way), but a font shipped as an
// *asset* is invisible to it — the OFL must be registered explicitly via
// LicenseRegistry.addLicense. Doing it here means every app that renders
// notation with partitura gets the attribution for free: [MusicFonts.load]
// calls [registerBundledFontLicenses] on first font load. Apps that open the
// license page without rendering first (e.g. from a settings screen) can call
// it directly — it is idempotent.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

bool _registered = false;

/// Register the OFL for partitura's bundled fonts. Safe to call repeatedly.
///
/// Only **Bravura** is bundled by default (see `MusicFont`); the OFL text is
/// read lazily from partitura's own asset when the license page is shown, so
/// this call itself is cheap. If a consuming app bundles the optional faces
/// (Petaluma/Leland/Leipzig) it should register their licenses the same way.
void registerBundledFontLicenses() {
  if (_registered) return;
  _registered = true;

  LicenseRegistry.addLicense(() async* {
    final ofl =
        await rootBundle.loadString('packages/partitura/assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(
      const ['Bravura (SMuFL music font)'],
      'Bravura — SMuFL-compliant music notation font\n'
      'Copyright © Steinberg Media Technologies GmbH '
      '(designed by Daniel Spreadbury)\n'
      'Bundled by the partitura package.\n'
      'License: SIL Open Font License, Version 1.1\n\n'
      '------------------------------------------------------------\n\n'
      '$ofl',
    );
  });
}
