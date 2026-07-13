/// `partitura` command-line tool.
///
/// ```
/// info      <in>                     parse and summarize a score
/// timeline  <in> [--bpm N] [--no-expand]
/// convert   <in> <out>               MusicXML <-> MIDI (by extension)
/// render    <in> <out.svg> [--tab] [--tuning std|dropD|bass]
///                                    [--staff-space N] [--metadata P]
///                                    [--no-embed-font]
/// ```
///
/// Formats are inferred from file extensions (`.xml`/`.musicxml`, `.mid`/
/// `.midi`, `.svg`, `.png`) and can be overridden with `--from` / `--to`.
/// SVG rendering is pure Dart; PNG rendering delegates to the Flutter SDK
/// (`flutter test tool/render_png.dart` in the `partitura` package), which the
/// tool locates and runs automatically.
library;

import 'dart:convert';
import 'dart:io';

import 'package:partitura_cli/src/crispembed_omr.dart';
import 'package:partitura_cli/src/embedded_metadata_decoder.dart';
import 'package:partitura_core/partitura_core.dart';

const _usage = '''
partitura — music notation CLI

Usage: partitura <command> [arguments]

Commands:
  info      <in>                       Summarize a score (clef, meter, sizes)
  timeline  <in> [--bpm N] [--no-expand]
                                       Print the playback timeline
  convert   <in> <out>                 Convert between MusicXML and MIDI
  render    <in> <out.(svg|png)> [options]
                                       Render a score (SVG pure-Dart; PNG via
                                       the Flutter SDK)
  omr       <image> <out.(musicxml|mxl|krn|svg|png)> --model <gguf> [options]
                                       Recognize a staff image via CrispEmbed —
                                       Sheet Music Transformer (grand staff),
                                       Polyphonic-TrOMR (single staff) or Flova
                                       (handwritten), engine auto-detected
                                       (needs libcrispembed)

omr options:
  --model <gguf|name>                  OMR GGUF path, or a name that
                                       auto-downloads from Hugging Face
                                       (smt-grandstaff / tromr / flova); or set
                                       PARTITURA_OMR_MODEL
  --lib <path>                         libcrispembed shared library (or set
                                       CRISPEMBED_LIB)
  --threads <n>                        Inference threads (default: auto)
  --single                             Import the first spine only (single staff)
  --page                               Full-page scan: split into staff systems
                                       and recognize each, concatenated

Common:
  --from <musicxml|mxl|mei|kern|midi|abc|asciitab|mscx|mscz|gp|gpx|gp5|gp4|gp3|gpif>
                                       Force the input format (.mxl = zipped
                                       MusicXML; .mei = MEI; .krn = Humdrum
                                       kern; .abc = ABC; .tab/.crd/.txt are
                                       plain-text tab; .mscx/.mscz = MuseScore
                                       XML / zip; .gp = v7/8, .gpx = v6,
                                       .gp5/.gp4/.gp3 = binary tab)
  --to   <musicxml|mxl|mei|kern|ly|midi|abc|brl|mscx|mscz|gp|gpif>
                                       (.ly = LilyPond, .brl = braille music;
                                       export only)
                                       Force the convert output format

render options:
  --tab                                Render as guitar/bass tablature
  --tuning <std|dropD|bass>            Tab tuning (default std)
  --track <n>                          Which track to import from a .gp/.gpif
  --infer-rhythm                       Guess note durations from tab spacing
                                       (plain-text tab input)
  --staff-space <px>                   Pixels per staff space (default 12)
  --metadata <path>                    SMuFL font metadata JSON
  --no-embed-font                      Do not embed the engraving font

timeline options:
  --bpm <n>                            Quarter-note tempo for seconds (default 120)
  --no-expand                          Keep document order (no repeats/jumps)
''';

Future<void> main(List<String> argv) async {
  exitCode = await _run(argv);
}

Future<int> _run(List<String> argv) async {
  if (argv.isEmpty || argv.first == '-h' || argv.first == '--help') {
    stdout.writeln(_usage);
    return argv.isEmpty ? 64 : 0;
  }
  final command = argv.first;
  final rest = argv.sublist(1);
  try {
    switch (command) {
      case 'info':
        return _info(rest);
      case 'timeline':
        return _timeline(rest);
      case 'convert':
        return _convert(rest);
      case 'render':
        return _render(rest);
      case 'omr':
        return await _omr(rest);
      default:
        stderr.writeln('Unknown command: $command\n');
        stderr.writeln(_usage);
        return 64;
    }
  } on _CliError catch (e) {
    stderr.writeln('error: ${e.message}');
    return 1;
  } on FormatException catch (e) {
    stderr.writeln('error: ${e.message}');
    return 1;
  }
}

/// Flags that never take a value (so they don't swallow a following argument).
const _booleanFlags = {
  'tab',
  'no-embed-font',
  'no-expand',
  'infer-rhythm',
  'single',
  'page',
};

int _info(List<String> args) {
  final (positional, options) = _parse(args);
  if (positional.isEmpty) throw _CliError('info needs an input file');
  final score = _loadScore(positional.first, options);
  final timeline = playbackTimeline(score);
  final elements = score.measures.fold<int>(0, (n, m) => n + m.elements.length);
  stdout.writeln('file:       ${positional.first}');
  final format = options['from'] ?? _formatOf(positional.first);
  if (format == 'gp' || format == 'gpx' || format == 'gpif') {
    final gpif = switch (format) {
      'gp' => readGpifFromGp(File(positional.first).readAsBytesSync()),
      'gpx' => readGpifFromGpx(File(positional.first).readAsBytesSync()),
      _ => File(positional.first).readAsStringSync(),
    };
    final names = gpifTrackNames(gpif);
    stdout.writeln('tracks:     ${names.length} '
        '(${names.join(', ')})  [--track N to pick]');
  }
  stdout.writeln('clef:       ${score.clef.name}');
  stdout.writeln('key:        ${score.keySignature.fifths} fifths');
  stdout.writeln('meter:      ${score.timeSignature ?? 'unmetered'}');
  stdout.writeln('measures:   ${score.measures.length}');
  stdout.writeln('elements:   $elements');
  stdout.writeln('timeline:   ${timeline.length} events (repeats expanded)');
  return 0;
}

int _timeline(List<String> args) {
  final (positional, options) = _parse(args);
  if (positional.isEmpty) throw _CliError('timeline needs an input file');
  final score = _loadScore(positional.first, options);
  final bpm = double.tryParse(options['bpm'] ?? '120') ?? 120;
  final expand = !options.containsKey('no-expand');
  final timeline = playbackTimeline(score, expandRepeats: expand);
  stdout.writeln('# id\tstart\tdur\tseconds\tmeasure${' rest'}');
  for (final n in timeline) {
    final secs = secondsFor(n.start, quarterBpm: bpm).toStringAsFixed(3);
    stdout.writeln('${n.elementId}\t${n.start}\t${n.duration}\t$secs\t'
        'm${n.measureIndex}${n.isRest ? '\trest' : ''}');
  }
  return 0;
}

Future<int> _omr(List<String> args) async {
  final (positional, options) = _parse(args);
  if (positional.length < 2) throw _CliError('omr needs <image> <out>');
  final imagePath = positional[0];
  final outPath = positional[1];
  final model = options['model'] ?? Platform.environment['PARTITURA_OMR_MODEL'];
  if (model == null || model.isEmpty) {
    throw _CliError(
        'omr needs --model <gguf-or-name> (or PARTITURA_OMR_MODEL); '
        'a known name (${omrModelRegistry.keys.toSet().join('/')}) '
        'auto-downloads');
  }
  final outFormat = options['to'] ?? _formatOf(outPath);
  final threads = int.tryParse(options['threads'] ?? '') ?? 0;

  // Each recognized staff system's token string (one, unless `--page` splits a
  // full-page scan into per-system crops).
  final systems = <String>[];
  try {
    // A path is used as-is; a known name is fetched from Hugging Face + cached.
    final modelPath = await resolveOmrModel(model, onStatus: stderr.writeln);
    final engine = CrispEmbedOmrEngine.load(modelPath,
        libraryPath: options['lib'], threads: threads);
    try {
      if (options.containsKey('page')) {
        final crops = segmentStaffSystems(decodeImageFile(imagePath));
        stderr.writeln('omr: ${crops.length} staff system(s) detected');
        for (final crop in crops) {
          systems.add(engine.recognizeSync(omrImageOf(crop)));
        }
      } else {
        systems.add(engine.recognizeSync(decodeOmrImage(imagePath)));
      }
    } finally {
      engine.dispose();
    }
  } on OmrEngineException catch (e) {
    throw _CliError(e.message);
  }

  // The engine's output dialect is auto-detected (SMT → bekern grand staff,
  // TrOMR → semantic, Flova → LilyPond notes); per-system results concatenate.
  Score? score;
  GrandStaff? grand;
  String kern;
  String summary;
  final n = systems.length;
  final sys = n == 1 ? '' : ', $n systems';
  final dialect = omrDialectOf(systems.first);
  if (dialect == OmrDialect.lilyNotes) {
    score = _concatScores(systems.map(scoreFromLilyNotes));
    kern = scoreToKern(score);
    final notes = score.measures
        .expand((Measure m) => m.elements)
        .whereType<NoteElement>()
        .length;
    summary = 'Flova/handwritten$sys, $notes notes';
  } else if (dialect == OmrDialect.semantic) {
    score = _concatScores(systems.map(scoreFromSemantic));
    kern = scoreToKern(score);
    summary = 'TrOMR$sys, ${score.measures.length} measures';
  } else if (options.containsKey('single')) {
    score = _concatScores(systems.map(bekernToScore));
    kern = scoreToKern(score);
    summary = 'single staff$sys, ${score.measures.length} measures';
  } else {
    grand = _concatGrandStaffs(systems.map(bekernToGrandStaff));
    kern = systems.map(bekernToKern).join('\n');
    summary = 'grand staff$sys, upper ${grand.upper.measures.length} / '
        'lower ${grand.lower.measures.length} measures';
  }
  String musicXml() =>
      score != null ? scoreToMusicXml(score) : grandStaffToMusicXml(grand!);

  switch (outFormat) {
    case 'musicxml':
      File(outPath).writeAsStringSync(musicXml());
    case 'mxl':
      File(outPath).writeAsBytesSync(writeMusicXmlToMxl(musicXml()));
    case 'kern':
      File(outPath).writeAsStringSync(kern);
    case 'svg':
      File(outPath).writeAsStringSync(_omrSvg(score, grand, options));
    case 'png':
      // Rasterize via Flutter: write the recognized score to a temp MusicXML
      // and delegate to the PNG harness (a grand staff for SMT).
      final tmp = File('${Directory.systemTemp.createTempSync('omr').path}'
          '/score.musicxml')
        ..writeAsStringSync(musicXml());
      _renderPng(tmp.path, outPath, options, grand: score == null);
    default:
      throw _CliError(
          'omr can write musicxml, mxl, kern, svg or png (got "$outFormat")');
  }
  stderr.writeln('omr: $summary -> $outPath');
  return 0;
}

/// Concatenates per-system OMR [scores] into one — the first system's clef,
/// key and meter, then every system's measures in order. A single score is
/// returned unchanged (keeping its slurs/tempo/etc.).
Score _concatScores(Iterable<Score> scores) {
  final list = scores.toList();
  if (list.length == 1) return list.first;
  final first = list.first;
  return Score(
    clef: first.clef,
    keySignature: first.keySignature,
    timeSignature: first.timeSignature,
    measures: [for (final s in list) ...s.measures],
  );
}

/// Concatenates per-system grand [staves] into one (upper/lower measures
/// appended in order, keeping equal counts). A single grand staff is unchanged.
GrandStaff _concatGrandStaffs(Iterable<GrandStaff> staves) {
  final list = staves.toList();
  if (list.length == 1) return list.first;
  Score joined(Score first, List<Score> all) => Score(
        clef: first.clef,
        keySignature: first.keySignature,
        timeSignature: first.timeSignature,
        measures: [for (final s in all) ...s.measures],
      );
  return GrandStaff(
    upper: joined(list.first.upper, [for (final g in list) g.upper]),
    lower: joined(list.first.lower, [for (final g in list) g.lower]),
  );
}

/// Lays out and renders an OMR result to SVG — a [Score] (TrOMR / `--single`)
/// or a [GrandStaff] (SMT). If the recognized grand staff's staves disagree on
/// measure count (a recognition slip), falls back to rendering the upper staff.
String _omrSvg(Score? score, GrandStaff? grand, Map<String, String> options) {
  final staffSpace = double.tryParse(options['staff-space'] ?? '12') ?? 12;
  final (metadata, metadataFile) = _resolveMetadata(options);
  final settings = LayoutSettings(metadata: metadata);
  String? fontUri;
  if (metadataFile != null && !options.containsKey('no-embed-font')) {
    final font = _siblingFont(metadataFile);
    if (font != null) {
      fontUri = 'data:font/otf;base64,${base64Encode(font.readAsBytesSync())}';
    }
  }
  if (score != null) {
    final layout = const LayoutEngine().layout(score, settings);
    return scoreToSvg(layout, staffSpace: staffSpace, fontFaceDataUri: fontUri);
  }
  try {
    final layout = layoutGrandStaff(grand!, settings);
    return grandStaffToSvg(layout,
        staffSpace: staffSpace, fontFaceDataUri: fontUri);
  } on ArgumentError {
    stderr.writeln('omr: staves disagree on measure count; '
        'rendering the upper staff only');
    final layout = const LayoutEngine().layout(grand!.upper, settings);
    return scoreToSvg(layout, staffSpace: staffSpace, fontFaceDataUri: fontUri);
  }
}

int _convert(List<String> args) {
  final (positional, options) = _parse(args);
  if (positional.length < 2) {
    throw _CliError('convert needs <in> <out>');
  }
  final inPath = positional[0];
  final outPath = positional[1];
  final score = _loadScore(inPath, options);
  final outFormat = options['to'] ?? _formatOf(outPath);
  switch (outFormat) {
    case 'musicxml':
      File(outPath).writeAsStringSync(scoreToMusicXml(score));
    case 'mxl':
      File(outPath)
          .writeAsBytesSync(writeMusicXmlToMxl(scoreToMusicXml(score)));
    case 'mei':
      File(outPath).writeAsStringSync(scoreToMei(score));
    case 'kern':
      File(outPath).writeAsStringSync(scoreToKern(score));
    case 'ly':
      File(outPath).writeAsStringSync(scoreToLilyPond(score));
    case 'midi':
      File(outPath).writeAsBytesSync(scoreToMidi(score));
    case 'abc':
      File(outPath).writeAsStringSync(scoreToAbc(score));
    case 'brl':
      File(outPath).writeAsStringSync(scoreToBraille(score));
    case 'mscx':
      File(outPath).writeAsStringSync(scoreToMscx(score));
    case 'mscz':
      File(outPath).writeAsBytesSync(writeMsczFromMscx(scoreToMscx(score)));
    case 'gpif':
      File(outPath).writeAsStringSync(
          scoreToGpif(score, tuning: _tuningOf(options['tuning'])));
    case 'gp':
      File(outPath).writeAsBytesSync(writeGpFromGpif(
          scoreToGpif(score, tuning: _tuningOf(options['tuning']))));
    default:
      throw _CliError('cannot write format "$outFormat"');
  }
  stdout.writeln('wrote $outPath ($outFormat)');
  return 0;
}

int _render(List<String> args) {
  final (positional, options) = _parse(args);
  if (positional.length < 2) {
    throw _CliError('render needs <in> <out.(svg|png)>');
  }
  final outPath = positional[1];
  if (_formatOf(outPath) == 'png') {
    return _renderPng(positional[0], outPath, options);
  }
  final score = _loadScore(positional[0], options);
  final staffSpace = double.tryParse(options['staff-space'] ?? '12') ?? 12;

  final (metadata, metadataFile) = _resolveMetadata(options);
  final settings = LayoutSettings(metadata: metadata);

  final ScoreLayout layout;
  if (options.containsKey('tab')) {
    layout = const TabLayoutEngine()
        .layout(score, _tuningOf(options['tuning']), settings);
  } else {
    layout = const LayoutEngine().layout(score, settings);
  }

  String? fontUri;
  if (metadataFile != null && !options.containsKey('no-embed-font')) {
    final font = _siblingFont(metadataFile);
    if (font != null) {
      fontUri = 'data:font/otf;base64,${base64Encode(font.readAsBytesSync())}';
    }
  }

  final svg =
      scoreToSvg(layout, staffSpace: staffSpace, fontFaceDataUri: fontUri);
  File(outPath).writeAsStringSync(svg);
  stdout.writeln('wrote $outPath (${svg.length} bytes'
      '${fontUri == null ? '' : ', font embedded'})');
  return 0;
}

/// Loads a [Score] from [path], detecting the format from the extension or
/// the explicit `--from` override (`musicxml` / `midi` / `asciitab`).
/// ASCII tab uses `--tuning` (default standard guitar).
Score _loadScore(String path, Map<String, String> options) {
  final file = File(path);
  if (!file.existsSync()) throw _CliError('no such file: $path');
  switch (options['from'] ?? _formatOf(path)) {
    case 'musicxml':
      return scoreFromMusicXml(file.readAsStringSync());
    case 'mxl':
      return scoreFromMusicXml(readMusicXmlFromMxl(file.readAsBytesSync()));
    case 'mei':
      return scoreFromMei(file.readAsStringSync());
    case 'kern':
      return scoreFromKern(file.readAsStringSync());
    case 'midi':
      return scoreFromMidi(file.readAsBytesSync());
    case 'abc':
      return scoreFromAbc(file.readAsStringSync());
    case 'mscx':
      return scoreFromMscx(file.readAsStringSync());
    case 'mscz':
      return scoreFromMscx(readMscxFromMscz(file.readAsBytesSync()));
    case 'asciitab':
      return asciiTabToScore(
        file.readAsStringSync(),
        tuning: _tuningOf(options['tuning']),
        inferRhythm: options.containsKey('infer-rhythm'),
      );
    case 'gpif':
      return scoreFromGpif(file.readAsStringSync(),
          trackIndex: int.tryParse(options['track'] ?? '0') ?? 0);
    case 'gp':
      return scoreFromGpif(readGpifFromGp(file.readAsBytesSync()),
          trackIndex: int.tryParse(options['track'] ?? '0') ?? 0);
    case 'gpx':
      return scoreFromGpif(readGpifFromGpx(file.readAsBytesSync()),
          trackIndex: int.tryParse(options['track'] ?? '0') ?? 0);
    case 'gp5':
      return gp5ToScore(file.readAsBytesSync(),
          trackIndex: int.tryParse(options['track'] ?? '0') ?? 0);
    case 'gp4':
      return gp4ToScore(file.readAsBytesSync(),
          trackIndex: int.tryParse(options['track'] ?? '0') ?? 0);
    case 'gp3':
      return gp3ToScore(file.readAsBytesSync(),
          trackIndex: int.tryParse(options['track'] ?? '0') ?? 0);
    default:
      throw _CliError('unknown input format for $path (use --from)');
  }
}

Tuning _tuningOf(String? name) => switch (name) {
      'dropD' => Tuning.dropDGuitar,
      'bass' => Tuning.standardBass,
      _ => Tuning.standardGuitar,
    };

String _formatOf(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.mid') || lower.endsWith('.midi')) return 'midi';
  if (lower.endsWith('.mxl')) return 'mxl';
  if (lower.endsWith('.mei')) return 'mei';
  if (lower.endsWith('.krn') || lower.endsWith('.kern')) return 'kern';
  if (lower.endsWith('.ly')) return 'ly';
  if (lower.endsWith('.xml') || lower.endsWith('.musicxml')) return 'musicxml';
  if (lower.endsWith('.svg')) return 'svg';
  if (lower.endsWith('.png')) return 'png';
  if (lower.endsWith('.abc')) return 'abc';
  if (lower.endsWith('.brl')) return 'brl';
  if (lower.endsWith('.mscz')) return 'mscz';
  if (lower.endsWith('.mscx')) return 'mscx';
  if (lower.endsWith('.tab') ||
      lower.endsWith('.crd') ||
      lower.endsWith('.txt')) {
    return 'asciitab';
  }
  if (lower.endsWith('.gpif')) return 'gpif';
  if (lower.endsWith('.gpx')) return 'gpx';
  if (lower.endsWith('.gp5')) return 'gp5';
  if (lower.endsWith('.gp4')) return 'gp4';
  if (lower.endsWith('.gp3')) return 'gp3';
  if (lower.endsWith('.gp')) return 'gp';
  return 'unknown';
}

/// Renders to PNG by delegating to the Flutter engine: runs the
/// `render_png.dart` harness in the `partitura` package via `flutter test`
/// (the only way to reach `dart:ui` from the command line).
int _renderPng(String inPath, String outPath, Map<String, String> options,
    {bool grand = false}) {
  final pkg = _findPartituraDir();
  if (pkg == null) {
    throw _CliError('cannot locate the partitura Flutter package for PNG');
  }
  final env = {
    'PARTITURA_IN': File(inPath).absolute.path,
    'PARTITURA_OUT': File(outPath).absolute.path,
    'PARTITURA_TAB': options.containsKey('tab') ? '1' : '0',
    if (grand) 'PARTITURA_GRAND': '1',
    if (options['tuning'] != null) 'PARTITURA_TUNING': options['tuning']!,
    if (options['staff-space'] != null)
      'PARTITURA_STAFF_SPACE': options['staff-space']!,
  };
  final ProcessResult result;
  try {
    result = Process.runSync(
      'flutter',
      ['test', '--reporter', 'compact', 'tool/render_png.dart'],
      workingDirectory: pkg.path,
      environment: env,
    );
  } on ProcessException {
    throw _CliError(
        'PNG rendering needs the Flutter SDK (`flutter` not found)');
  }
  if (result.exitCode != 0) {
    throw _CliError('PNG render failed:\n${result.stdout}\n${result.stderr}');
  }
  stdout.writeln('wrote $outPath (png, via Flutter)');
  return 0;
}

/// Walks up from the running script to the repo's `packages/partitura`.
Directory? _findPartituraDir() {
  var dir = File.fromUri(Platform.script).parent;
  for (var i = 0; i < 8; i++) {
    final candidate = Directory('${dir.path}/packages/partitura/tool');
    if (File('${candidate.path}/render_png.dart').existsSync()) {
      return Directory('${dir.path}/packages/partitura');
    }
    dir = dir.parent;
  }
  return null;
}

/// Finds the SMuFL metadata JSON: the explicit [override], else by walking up
/// from the running script to the repo's `packages/partitura/assets`.
/// The SMuFL metadata for rendering, plus the sibling metadata file if one was
/// found (for `@font-face` embedding). Resolution order: `--metadata`, the repo
/// checkout, then the **embedded** Bravura metadata — so a standalone binary
/// renders offline. When it falls back to the embedded copy there is no file, so
/// the engraving font is referenced by name rather than inlined.
(SmuflMetadata, File?) _resolveMetadata(Map<String, String> options) {
  final file = _findMetadata(options['metadata']);
  final json =
      file != null ? file.readAsStringSync() : embeddedBravuraMetadataJson();
  final metadata =
      SmuflMetadata.fromJson(jsonDecode(json) as Map<String, Object?>);
  return (metadata, file);
}

File? _findMetadata(String? override) {
  if (override != null) {
    final f = File(override);
    return f.existsSync() ? f : throw _CliError('no metadata at $override');
  }
  var dir = File.fromUri(Platform.script).parent;
  for (var i = 0; i < 8; i++) {
    final candidate = File(
        '${dir.path}/packages/partitura/assets/smufl/bravura_metadata.json');
    if (candidate.existsSync()) return candidate;
    dir = dir.parent;
  }
  return null;
}

/// The Bravura font next to a metadata file, if present (for embedding).
File? _siblingFont(File metadata) {
  final root = metadata.parent.parent.parent; // assets/smufl -> package root
  final font = File('${root.path}/assets/fonts/Bravura.otf');
  return font.existsSync() ? font : null;
}

/// Splits [args] into positional values and `--key[ value]` options.
(List<String>, Map<String, String>) _parse(List<String> args) {
  final positional = <String>[];
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--')) {
      final key = arg.substring(2);
      if (!_booleanFlags.contains(key) &&
          i + 1 < args.length &&
          !args[i + 1].startsWith('--')) {
        options[key] = args[++i];
      } else {
        options[key] = '';
      }
    } else {
      positional.add(arg);
    }
  }
  return (positional, options);
}

/// A user-facing CLI error (printed without a stack trace).
class _CliError implements Exception {
  final String message;
  _CliError(this.message);
}
