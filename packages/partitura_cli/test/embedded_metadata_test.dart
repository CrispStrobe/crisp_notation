import 'dart:convert';
import 'dart:io';

import 'package:partitura_cli/src/embedded_metadata_decoder.dart';
import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

void main() {
  test('embedded Bravura metadata decodes to usable, complete metadata', () {
    final json = embeddedBravuraMetadataJson();
    final meta =
        SmuflMetadata.fromJson(jsonDecode(json) as Map<String, Object?>);
    // A known glyph resolves to a real bounding box.
    expect(meta.bBoxOf(SmuflGlyph.noteheadBlack).width, greaterThan(0));
  });

  test('the embedded copy is byte-identical to the bundled asset', () {
    final file = File('../partitura/assets/smufl/bravura_metadata.json');
    expect(embeddedBravuraMetadataJson(), file.readAsStringSync(),
        reason:
            'regenerate with tool/embed_metadata.dart if the asset changed');
  });
}
