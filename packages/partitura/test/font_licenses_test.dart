// Verifies that partitura registers the SIL OFL for its bundled Bravura font,
// so it appears on a consuming app's showLicensePage().

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:partitura/partitura.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registerBundledFontLicenses adds the Bravura OFL', () async {
    registerBundledFontLicenses();

    final entries = await LicenseRegistry.licenses.toList();
    final bravura = entries.where(
      (e) => e.packages.contains('Bravura (SMuFL music font)'),
    );
    expect(bravura, isNotEmpty, reason: 'Bravura OFL should be registered');

    final text = bravura.first.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('SIL Open Font License'));
  });

  test('is idempotent — a second call adds no duplicate', () async {
    registerBundledFontLicenses();
    registerBundledFontLicenses();

    final entries = await LicenseRegistry.licenses.toList();
    final count = entries
        .where((e) => e.packages.contains('Bravura (SMuFL music font)'))
        .length;
    expect(count, 1);
  });
}
