import 'dart:convert';
import 'dart:typed_data';

import 'package:partitura_core/partitura_core.dart';

import 'embedded_metadata.dart';

/// The bundled Bravura SMuFL metadata JSON, decoded from the embedded
/// DEFLATE+base64 blob — the fallback that lets the standalone `partitura`
/// binary render without the repo checkout (or a `--metadata` path).
String embeddedBravuraMetadataJson() => utf8.decode(
    inflate(Uint8List.fromList(base64Decode(bravuraMetadataDeflatedBase64))));
