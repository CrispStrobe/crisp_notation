@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Live tests: they invoke the real `bin/crisp_notation.dart` as a subprocess and
/// assert on the files and output it produces.
///
/// The CLI is compiled to a native executable **once** in `setUpAll`, and every
/// case then execs that binary. Running `dart run bin/crisp_notation.dart` per
/// case instead re-JITs the whole workspace each time — ~30s a case, which blew
/// the default 30s timeout and made the suite unrunnable in CI.

/// Whether the Flutter SDK is available (PNG rendering delegates to it).
bool _hasFlutter() {
  try {
    return Process.runSync('flutter', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  late Directory tmp;
  late String samplePath;
  late String metadataPath;
  late String exe;

  // Resolve the SMuFL metadata (a sibling package asset) once, absolutely.
  metadataPath = File('../crisp_notation/assets/smufl/bravura_metadata.json')
      .absolute
      .path;

  Future<ProcessResult> run(List<String> args) => Process.run(
        exe,
        args,
        workingDirectory: Directory.current.path,
        // The compiled binary lives in a temp dir, so it cannot walk up to the
        // checkout to find the Flutter package the PNG path needs — point it
        // there explicitly.
        environment: {
          'CRISP_NOTATION_PACKAGE':
              File('../crisp_notation').absolute.path,
        },
      );

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('crisp_notation_cli_test');

    // Compile once; every case below execs this binary.
    exe = '${tmp.path}/crisp_notation${Platform.isWindows ? '.exe' : ''}';
    final built = Process.runSync(
      Platform.resolvedExecutable,
      ['compile', 'exe', 'bin/crisp_notation.dart', '-o', exe],
      workingDirectory: Directory.current.path,
    );
    if (built.exitCode != 0) {
      throw StateError('could not compile the CLI under test:\n'
          '${built.stdout}\n${built.stderr}');
    }

    samplePath = '${tmp.path}/sample.musicxml';
    File(samplePath).writeAsStringSync(scoreToMusicXml(Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4 | g4:h a4',
    )));
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('info summarizes the score', () async {
    final r = await run(['info', samplePath]);
    expect(r.exitCode, 0);
    expect(r.stdout, contains('meter:      4/4'));
    expect(r.stdout, contains('measures:   2'));
    expect(r.stdout, contains('elements:   6'));
  });

  test('timeline prints element onsets', () async {
    final r = await run(['timeline', samplePath]);
    expect(r.exitCode, 0);
    expect(r.stdout, contains('e0\t0/1\t1/4'));
    expect((r.stdout as String).trim().split('\n'), hasLength(7)); // header + 6
  });

  test('convert MusicXML → MIDI writes an SMF', () async {
    final out = '${tmp.path}/out.mid';
    final r = await run(['convert', samplePath, out]);
    expect(r.exitCode, 0);
    final bytes = File(out).readAsBytesSync();
    expect(bytes.sublist(0, 4), [0x4D, 0x54, 0x68, 0x64]); // "MThd"
  });

  test('MIDI round-trips back to a parseable MusicXML', () async {
    final mid = '${tmp.path}/rt.mid';
    final xml = '${tmp.path}/rt.musicxml';
    expect((await run(['convert', samplePath, mid])).exitCode, 0);
    expect((await run(['convert', mid, xml])).exitCode, 0);
    final score = scoreFromMusicXml(File(xml).readAsStringSync());
    final pitches = score.measures
        .expand((m) => m.elements)
        .whereType<NoteElement>()
        .expand((n) => n.pitches)
        .map((p) => p.toString());
    expect(pitches, containsAll(['C4', 'D4', 'E4', 'F4']));
  });

  test('convert MusicXML → .mscz writes a zip, and back preserves pitches',
      () async {
    final mscz = '${tmp.path}/out.mscz';
    final xml = '${tmp.path}/rt.musicxml';
    expect((await run(['convert', samplePath, mscz])).exitCode, 0);
    expect(File(mscz).readAsBytesSync().sublist(0, 2), [0x50, 0x4B]); // "PK"
    expect((await run(['convert', mscz, xml])).exitCode, 0);
    final pitches = scoreFromMusicXml(File(xml).readAsStringSync())
        .measures
        .expand((m) => m.elements)
        .whereType<NoteElement>()
        .expand((n) => n.pitches)
        .map((p) => p.toString());
    expect(pitches, containsAll(['C4', 'D4', 'E4', 'F4', 'G4', 'A4']));
  });

  test('convert MusicXML → .mxl (compressed) round-trips the pitches',
      () async {
    final mxl = '${tmp.path}/out.mxl';
    final xml = '${tmp.path}/rt2.musicxml';
    expect((await run(['convert', samplePath, mxl])).exitCode, 0);
    expect(File(mxl).readAsBytesSync().sublist(0, 2), [0x50, 0x4B]); // "PK"
    expect((await run(['convert', mxl, xml])).exitCode, 0);
    final pitches = scoreFromMusicXml(File(xml).readAsStringSync())
        .measures
        .expand((m) => m.elements)
        .whereType<NoteElement>()
        .expand((n) => n.pitches)
        .map((p) => p.toString());
    expect(pitches, containsAll(['C4', 'D4', 'E4', 'F4', 'G4', 'A4']));
  });

  test('convert MusicXML → .mei → MusicXML round-trips the pitches', () async {
    final mei = '${tmp.path}/out.mei';
    final xml = '${tmp.path}/rt3.musicxml';
    expect((await run(['convert', samplePath, mei])).exitCode, 0);
    expect(File(mei).readAsStringSync(), contains('<mei'));
    expect((await run(['convert', mei, xml])).exitCode, 0);
    final pitches = scoreFromMusicXml(File(xml).readAsStringSync())
        .measures
        .expand((m) => m.elements)
        .whereType<NoteElement>()
        .expand((n) => n.pitches)
        .map((p) => p.toString());
    expect(pitches, containsAll(['C4', 'D4', 'E4', 'F4', 'G4', 'A4']));
  });

  test('convert MusicXML → .krn → MusicXML round-trips the pitches', () async {
    final krn = '${tmp.path}/out.krn';
    final xml = '${tmp.path}/rt4.musicxml';
    expect((await run(['convert', samplePath, krn])).exitCode, 0);
    expect(File(krn).readAsStringSync(), startsWith('**kern'));
    expect((await run(['convert', krn, xml])).exitCode, 0);
    final pitches = scoreFromMusicXml(File(xml).readAsStringSync())
        .measures
        .expand((m) => m.elements)
        .whereType<NoteElement>()
        .expand((n) => n.pitches)
        .map((p) => p.toString());
    expect(pitches, containsAll(['C4', 'D4', 'E4', 'F4', 'G4', 'A4']));
  });

  test('convert MusicXML → .ly writes a LilyPond source (export only)',
      () async {
    final ly = '${tmp.path}/out.ly';
    expect((await run(['convert', samplePath, ly])).exitCode, 0);
    final text = File(ly).readAsStringSync();
    expect(text, contains('\\version'));
    expect(text, contains('\\new Staff'));
  });

  test('render writes an SVG with the clef glyph', () async {
    final out = '${tmp.path}/out.svg';
    final r =
        await run(['render', samplePath, out, '--metadata', metadataPath]);
    expect(r.exitCode, 0);
    final svg = File(out).readAsStringSync();
    expect(svg, contains('<svg'));
    expect(svg, contains(smuflCodepoints['gClef']!));
    expect(svg, contains('@font-face')); // font embedded by default
  });

  test('render lays out a multi-part MusicXML with every part', () async {
    // A two-part score-partwise document (treble + bass).
    final multiPath = '${tmp.path}/duet.musicxml';
    File(multiPath).writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"/><score-part id="P2"/></part-list>
  <part id="P1"><measure number="1">
    <attributes><divisions>2</divisions><key><fifths>0</fifths></key>
      <time><beats>4</beats><beat-type>4</beat-type></time>
      <clef><sign>G</sign><line>2</line></clef></attributes>
    <note><pitch><step>C</step><octave>5</octave></pitch><duration>8</duration><type>whole</type></note>
  </measure></part>
  <part id="P2"><measure number="1">
    <attributes><divisions>2</divisions><key><fifths>0</fifths></key>
      <time><beats>4</beats><beat-type>4</beat-type></time>
      <clef><sign>F</sign><line>4</line></clef></attributes>
    <note><pitch><step>C</step><octave>3</octave></pitch><duration>8</duration><type>whole</type></note>
  </measure></part>
</score-partwise>''');
    final out = '${tmp.path}/duet.svg';
    final r = await run(['render', multiPath, out, '--metadata', metadataPath]);
    expect(r.exitCode, 0);
    expect(r.stdout, contains('2 staves'));
    final svg = File(out).readAsStringSync();
    // Both clefs are present — proof it rendered both staves, not just the top.
    expect(svg, contains(smuflCodepoints['gClef']!));
    expect(svg, contains(smuflCodepoints['fClef']!));
    // Two staff groups stacked into one system.
    expect('<g transform'.allMatches(svg).length, greaterThanOrEqualTo(2));
  });

  test('render decodes a UTF-16 LE (BOM) MusicXML instead of crashing',
      () async {
    // Real MusicXML is often exported UTF-16; File.readAsStringSync assumes
    // UTF-8 and would throw. Encode the sample as UTF-16 LE with a BOM.
    final text = File(samplePath).readAsStringSync();
    final bytes = <int>[0xFF, 0xFE];
    for (final unit in text.codeUnits) {
      bytes.add(unit & 0xFF);
      bytes.add((unit >> 8) & 0xFF);
    }
    final u16Path = '${tmp.path}/utf16.musicxml';
    File(u16Path).writeAsBytesSync(bytes);
    final out = '${tmp.path}/utf16.svg';
    final r = await run(['render', u16Path, out, '--metadata', metadataPath]);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(File(out).readAsStringSync(), contains(smuflCodepoints['gClef']!));
  });

  test('render --tab writes a tab SVG', () async {
    final out = '${tmp.path}/tab.svg';
    final r = await run(
        ['render', samplePath, out, '--tab', '--metadata', metadataPath]);
    expect(r.exitCode, 0);
    final svg = File(out).readAsStringSync();
    expect(svg, contains(smuflCodepoints['6stringTabClef']!));
  });

  test('render to PNG via the Flutter SDK', () async {
    if (!_hasFlutter()) {
      markTestSkipped('flutter not on PATH');
      return;
    }
    final out = '${tmp.path}/out.png';
    final r = await run(['render', samplePath, out]);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    final bytes = File(out).readAsBytesSync();
    // PNG signature.
    expect(
        bytes.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('render to PNG lays out a multi-part input with every part', () async {
    if (!_hasFlutter()) {
      markTestSkipped('flutter not on PATH');
      return;
    }
    final multiPath = '${tmp.path}/duet_png.musicxml';
    File(multiPath).writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"/><score-part id="P2"/></part-list>
  <part id="P1"><measure number="1">
    <attributes><divisions>2</divisions><key><fifths>0</fifths></key>
      <time><beats>4</beats><beat-type>4</beat-type></time>
      <clef><sign>G</sign><line>2</line></clef></attributes>
    <note><pitch><step>C</step><octave>5</octave></pitch><duration>8</duration><type>whole</type></note>
  </measure></part>
  <part id="P2"><measure number="1">
    <attributes><divisions>2</divisions><key><fifths>0</fifths></key>
      <time><beats>4</beats><beat-type>4</beat-type></time>
      <clef><sign>F</sign><line>4</line></clef></attributes>
    <note><pitch><step>C</step><octave>3</octave></pitch><duration>8</duration><type>whole</type></note>
  </measure></part>
</score-partwise>''');
    final out = '${tmp.path}/duet.png';
    final r = await run(['render', multiPath, out]);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    final bytes = File(out).readAsBytesSync();
    expect(
        bytes.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    // The PNG IHDR height (bytes 20..24, big-endian) spans two stacked staves —
    // much taller than a single staff would be.
    final height =
        (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    expect(height, greaterThan(130));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('render --no-embed-font omits the font data', () async {
    final out = '${tmp.path}/light.svg';
    final r = await run([
      'render', samplePath, out, //
      '--no-embed-font', '--metadata', metadataPath,
    ]);
    expect(r.exitCode, 0);
    expect(File(out).readAsStringSync(), isNot(contains('@font-face')));
  });

  test('reads an ABC tune and converts it (and round-trips to ABC)', () async {
    final abc = '${tmp.path}/tune.abc';
    File(abc).writeAsStringSync(
        'X:1\nT:Test\nM:4/4\nL:1/8\nK:G\nGABc d2e2|f2 ^f2 g4|\n');
    final info = await run(['info', abc]);
    expect(info.exitCode, 0, reason: '${info.stdout}\n${info.stderr}');
    expect(info.stdout, contains('meter:      4/4'));

    // ABC -> MusicXML.
    final xml = '${tmp.path}/tune.musicxml';
    expect((await run(['convert', abc, xml])).exitCode, 0);
    expect(File(xml).readAsStringSync(), contains('<note>'));

    // ABC -> ABC keeps the pitches (via the score model).
    final out = '${tmp.path}/out.abc';
    expect((await run(['convert', abc, out])).exitCode, 0);
    final text = File(out).readAsStringSync();
    expect(text, contains('K:G'));
    expect(text, contains('G A B c'));
  });

  test('reads a plain-text (.tab) file and converts it', () async {
    final tab = '${tmp.path}/riff.tab';
    File(tab).writeAsStringSync('''
e|-------------|
B|-------------|
G|-0-2-2h4-----|
D|---------3-2-|
A|-------------|
E|-------------|
''');
    final info = await run(['info', tab]);
    expect(info.exitCode, 0, reason: '${info.stdout}\n${info.stderr}');
    expect(info.stdout, contains('meter:      unmetered'));
    // Convert the imported tab to MIDI.
    final mid = '${tmp.path}/riff.mid';
    final r = await run(['convert', tab, mid]);
    expect(r.exitCode, 0);
    expect(File(mid).readAsBytesSync().sublist(0, 4), [0x4D, 0x54, 0x68, 0x64]);
  });

  test('round-trips MusicXML -> .gp -> MusicXML with real files', () async {
    // A guitar-range melody so every note frets on standard tuning.
    final src = '${tmp.path}/song.musicxml';
    File(src).writeAsStringSync(scoreToMusicXml(Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'e3:q g3 b3 e4 | c4:q e4 g4 c5',
    )));
    final gp = '${tmp.path}/song.gp';
    final back = '${tmp.path}/from_gp.musicxml';
    expect((await run(['convert', src, gp])).exitCode, 0);
    // The .gp is a real ZIP archive.
    expect(File(gp).readAsBytesSync().sublist(0, 2), [0x50, 0x4B]); // "PK"
    expect((await run(['convert', gp, back])).exitCode, 0);

    List<String> pitches(String path) =>
        scoreFromMusicXml(File(path).readAsStringSync())
            .measures
            .expand((m) => m.elements)
            .whereType<NoteElement>()
            .expand((n) => n.pitches)
            .map((p) => p.toString())
            .toList();
    expect(pitches(back), pitches(src)); // transparent for pitches
  });

  test('reads a raw .gpif and reports it', () async {
    final gpif = '${tmp.path}/x.gpif';
    File(gpif).writeAsStringSync(scoreToGpif(Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'e3:q g3 b3 e4',
    )));
    final r = await run(['info', gpif]);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stdout, contains('elements:   4'));
  });

  test('a missing input file fails with a clear error', () async {
    final r = await run(['info', '${tmp.path}/nope.musicxml']);
    expect(r.exitCode, 1);
    expect(r.stderr, contains('no such file'));
  });

  test('an unknown command shows usage and exits 64', () async {
    final r = await run(['frobnicate']);
    expect(r.exitCode, 64);
    expect(r.stderr, contains('Usage:'));
  });

  test('no arguments prints usage', () async {
    final r = await run([]);
    expect(r.exitCode, 64);
    expect(r.stdout, contains('music notation CLI'));
  });
}
