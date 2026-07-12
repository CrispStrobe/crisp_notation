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

Common:
  --from <musicxml|mxl|mei|kern|midi|abc|asciitab|mscx|mscz|gp|gpx|gp5|gp4|gp3|gpif>
                                       Force the input format (.mxl = zipped
                                       MusicXML; .mei = MEI; .krn = Humdrum
                                       kern; .abc = ABC; .tab/.crd/.txt are
                                       plain-text tab; .mscx/.mscz = MuseScore
                                       XML / zip; .gp = v7/8, .gpx = v6,
                                       .gp5/.gp4/.gp3 = binary tab)
  --to   <musicxml|mxl|mei|kern|ly|midi|abc|mscx|mscz|gp|gpif>
                                       (.ly = LilyPond, export only)
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

void main(List<String> argv) {
  exitCode = _run(argv);
}

int _run(List<String> argv) {
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
const _booleanFlags = {'tab', 'no-embed-font', 'no-expand', 'infer-rhythm'};

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

  final metadataFile = _findMetadata(options['metadata']);
  if (metadataFile == null) {
    throw _CliError('SMuFL metadata not found; pass --metadata <path>');
  }
  final metadata = SmuflMetadata.fromJson(
      jsonDecode(metadataFile.readAsStringSync()) as Map<String, Object?>);
  final settings = LayoutSettings(metadata: metadata);

  final ScoreLayout layout;
  if (options.containsKey('tab')) {
    layout = const TabLayoutEngine()
        .layout(score, _tuningOf(options['tuning']), settings);
  } else {
    layout = const LayoutEngine().layout(score, settings);
  }

  String? fontUri;
  if (!options.containsKey('no-embed-font')) {
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
int _renderPng(String inPath, String outPath, Map<String, String> options) {
  final pkg = _findPartituraDir();
  if (pkg == null) {
    throw _CliError('cannot locate the partitura Flutter package for PNG');
  }
  final env = {
    'PARTITURA_IN': File(inPath).absolute.path,
    'PARTITURA_OUT': File(outPath).absolute.path,
    'PARTITURA_TAB': options.containsKey('tab') ? '1' : '0',
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
