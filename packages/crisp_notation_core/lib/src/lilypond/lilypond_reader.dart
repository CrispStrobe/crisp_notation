library;

import '../internal/util.dart';
import '../internal/volta.dart';
import '../layout/multi_part.dart';
import '../layout/staff_system.dart';
import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../smufl/glyph_names.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/interval.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/tempo.dart';
import '../theory/time_signature.dart';
import '../theory/transposition.dart';
import 'lilypond_ast.dart';
import 'lilypond_lexer.dart';
import 'lilypond_parser.dart';

/// Drops MIDI-only `\score` blocks when the file also has one to print.
///
/// Mutopia files routinely carry a second `\score { … \midi { } }` for
/// playback (often with `\unfoldRepeats` or different music). Both were
/// read: the multi-part reader turned the playback score into extra parts,
/// and the single-staff reader appended its bars after the real ones.
/// `\parallelMusic #'(a b) { a1 | b1 | a2 | b2 | }` writes several voices
/// bar by bar, interleaved; it DEFINES the variables `a` and `b`. Unexpanded,
/// they were never defined and the staves that use them read as silence.
List<LyNode> _expandParallelMusic(List<LyNode> ast) {
  if (!ast.any((n) => n is LyCommand && n.name == 'parallelMusic')) return ast;
  final out = <LyNode>[];
  for (var i = 0; i < ast.length; i++) {
    final n = ast[i];
    if (n is LyCommand &&
        n.name == 'parallelMusic' &&
        i + 2 < ast.length &&
        ast[i + 1] is LyWord &&
        ast[i + 2] is LyBlock) {
      final names = RegExp(r'[A-Za-z][A-Za-z_-]*')
          .allMatches((ast[i + 1] as LyWord).value)
          .map((m) => m[0]!)
          .toList();
      if (names.isNotEmpty) {
        final bars = <List<LyNode>>[<LyNode>[]];
        for (final c in (ast[i + 2] as LyBlock).children) {
          if (c is LyWord && c.value == '|') {
            bars.add(<LyNode>[]);
          } else {
            bars.last.add(c);
          }
        }
        if (bars.last.isEmpty) bars.removeLast();
        for (var v = 0; v < names.length; v++) {
          out.add(LyAssignment(
              names[v],
              LyBlock([
                for (var b = v; b < bars.length; b += names.length) ...[
                  ...bars[b],
                  LyWord('|'),
                ]
              ])));
        }
        i += 2;
        continue;
      }
    }
    out.add(n);
  }
  return out;
}

/// The language a `\language "…"` / `\include "….ly"` directive names, or
/// null when it names none.
LyNoteLanguage? _languageNamed(String name) =>
    switch (name.toLowerCase().replaceAll(RegExp(r'\.ly$'), '')) {
      'italiano' ||
      'catalan' ||
      'francais' ||
      'espanol' ||
      'portugues' ||
      'vlaams' =>
        LyNoteLanguage.solfege,
      'deutsch' || 'svenska' || 'suomi' || 'norsk' => LyNoteLanguage.deutsch,
      'english' => LyNoteLanguage.english,
      'nederlands' => LyNoteLanguage.nederlands,
      _ => null,
    };

/// Spells every note of [ast] in Dutch when the source changes language
/// part-way, returning the tree and the language to read it in.
///
/// `\language` is a PARSER directive: it holds from where it is written on,
/// so notes before it keep the language they were written in. A piano duet
/// whose violin part says `\language "italiano"` inside its own variable has
/// its piano staves in Dutch above it, but the whole source was read in the
/// first language found anywhere, and every `c'`, `e'`, `g` of the piano was
/// no note at all in Italian: half the piece was silent. A source in one
/// language throughout is left exactly as it was.
(List<LyNode>, LyNoteLanguage) _unifyNoteLanguage(
    List<LyNode> ast, LyNoteLanguage detected) {
  // Contexts whose words are not notes.
  const skipCommands = {
    'header', 'paper', 'layout', 'midi', 'with', 'markup', 'markuplist', //
    'lyricmode', 'addlyrics', 'lyricsto', 'lyrics', 'drummode', 'drums',
    'figuremode', 'figures',
  };
  const pitchArgCommands = {'relative', 'transpose', 'key', 'transposition'};

  final readers = <LyNoteLanguage, _LilyPondReader>{};
  _LilyPondReader readerFor(LyNoteLanguage l) =>
      readers[l] ??= _LilyPondReader(language: l);
  var current = LyNoteLanguage.nederlands;
  final seen = <LyNoteLanguage>{};
  var rewrite = false;
  var anyNamed = false;

  String spell(String token) {
    seen.add(current);
    if (!rewrite || current == LyNoteLanguage.nederlands) return token;
    final r = readerFor(current);
    if (!r._pitchPattern.hasMatch(r._expand(token))) return token;
    final p = r._parsePitch(token);
    final acc = switch (p.alter) {
      1 => 'is',
      2 => 'isis',
      -1 => 'es',
      -2 => 'eses',
      _ => '',
    };
    final marks = p.octave >= 3 ? "'" * (p.octave - 3) : ',' * (3 - p.octave);
    return '${p.step.name}$acc$marks';
  }

  List<LyNode> walk(List<LyNode> nodes) {
    final out = <LyNode>[];
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      if (n case LyCommand(name: 'language' || 'include')
          when i + 1 < nodes.length && nodes[i + 1] is LyString) {
        final named = _languageNamed((nodes[i + 1] as LyString).value);
        if (named != null) {
          current = named;
          anyNamed = true;
        }
        out.add(n);
        continue;
      }
      out.add(switch (n) {
        LyNote() => LyNote(spell(n.pitch), n.duration, n.scripts),
        LyChord() =>
          LyChord([for (final p in n.pitches) spell(p)], n.duration, n.scripts),
        LyBlock() => LyBlock(walk(n.children)),
        LySimultaneous() => LySimultaneous(walk(n.children)),
        LyScore() => LyScore(walk(n.contents)),
        LyAssignment() => LyAssignment(n.key, walk([n.value]).single),
        LyCommand(:final name) when skipCommands.contains(name) => n,
        LyCommand(
          name: 'new' || 'context',
          args: [
            LyWord(
              value: 'Lyrics' || 'DrumStaff' || 'DrumVoice' || 'FiguredBass'
            ),
            ...
          ]
        ) =>
          n,
        LyCommand(:final name, :final args) => LyCommand(name, [
            for (final (k, a) in args.indexed)
              if (a is LyWord &&
                  pitchArgCommands.contains(name) &&
                  k < (name == 'transpose' ? 2 : 1))
                LyWord(spell(a.value))
              else
                ...walk([a]),
          ]),
        _ => n,
      });
    }
    return out;
  }

  walk(ast);
  if (!anyNamed) return (ast, detected);
  if (seen.length < 2 && (seen.isEmpty || seen.single == detected)) {
    return (ast, detected);
  }
  current = LyNoteLanguage.nederlands;
  rewrite = true;
  return (walk(ast), LyNoteLanguage.nederlands);
}

List<LyNode> _withoutPlaybackScores(List<LyNode> ast, {bool playback = false}) {
  bool has(LyScore score, String command) {
    bool scan(List<LyNode> nodes) => nodes.any((n) =>
        (n is LyCommand && n.name == command) ||
        (n is LyBlock && scan(n.children)));
    return scan(score.contents);
  }

  ast = _expandParallelMusic(ast);
  if (playback) {
    // `\book { \score { … } }` makes its own output file, and a book whose
    // scores have no `\midi` plays nothing. Its scores were hidden in the
    // book's block from the choice below, so an engraved-only book (a full
    // score, a part) was played beside the `\midi` score: every staff twice.
    // Lifted out, they are weighed like any other score.
    ast = [
      for (var i = 0; i < ast.length; i++)
        if (ast[i] case LyCommand(name: 'book' || 'bookpart')
            when i + 1 < ast.length && ast[i + 1] is LyBlock) ...[
          for (final c in (ast[++i] as LyBlock).children) c,
        ] else
          ast[i],
    ];
  }
  final scores = ast.whereType<LyScore>().toList();
  bool playbackOnly(LyScore s) => has(s, 'midi') && !has(s, 'layout');
  if (playback) {
    // What LilyPond PLAYS: a source that writes a separate `\midi` score
    // (unfolded repeats, a lead-in silence, other voicings) is heard from it.
    // Failing that, only the scores with a `\midi` block sound at all: a
    // second score that is only engraved (a coda printed apart) is silent.
    if (scores.length < 2) return ast;
    final heard =
        scores.any(playbackOnly) ? playbackOnly : (LyScore s) => has(s, 'midi');
    if (!scores.any(heard)) return ast;
    return [
      for (final n in ast)
        if (n is! LyScore || heard(n)) n
    ];
  }
  if (scores.length < 2 || scores.every(playbackOnly)) return ast;
  return [
    for (final n in ast)
      if (n is! LyScore || !playbackOnly(n)) n
  ];
}

/// Whether a `\score` in [ast] writes `\unfoldRepeats`: LilyPond then plays
/// (and prints) every repeat in it written out, alternatives in turn.
bool _scoresUnfoldRepeats(List<LyNode> ast) {
  bool scan(LyNode n) => switch (n) {
        LyCommand(:final name, :final args) =>
          name == 'unfoldRepeats' || args.any(scan),
        LyBlock(:final children) => children.any(scan),
        LySimultaneous(:final children) => children.any(scan),
        LyScore(:final contents) => contents.any(scan),
        _ => false,
      };
  return ast.whereType<LyScore>().any(scan);
}

/// Expands the music functions a file defines in plain LilyPond.
///
/// `Stff = #(define-music-function (parser location instr musexp)
/// (markup? ly:music?) #{ \new Staff \with { instrumentName = #instr }
/// { #musexp } #})` is a template: each call stands for its body with the
/// arguments put in for `#instr` and `#musexp`. Unexpanded, a call was read
/// as a variable holding Scheme, and a duet whose staves a function builds
/// came out as one staff, the second guitar after the first.
///
/// Only functions whose whole body is one `#{ … #}` and whose arguments are
/// all music or markup are expanded, and only at calls whose arguments are
/// each a variable, a string, a `\markup { … }` or a braced group: anything
/// else is left exactly as it was.
List<Token> _expandMusicFunctions(List<Token> tokens) {
  final fns = <String, (List<String>, List<Token>)>{};
  final def = RegExp(
    r'^[#$]\(define-music-function\s*\(([^()]*)\)\s*\(([^()]*)\)\s*'
    r'#\{(.*)#\}\s*\)$',
    dotAll: true,
  );
  for (var i = 0; i + 2 < tokens.length; i++) {
    if (tokens[i].kind != TokenKind.word ||
        tokens[i + 1].value != '=' ||
        tokens[i + 2].kind != TokenKind.word) {
      continue;
    }
    final m = def.firstMatch(tokens[i + 2].value);
    if (m == null) continue;
    var params = m[1]!.trim().split(RegExp(r'\s+'));
    final preds = m[2]!.trim().split(RegExp(r'\s+'));
    if (params.length == preds.length + 2 &&
        params[0] == 'parser' &&
        params[1] == 'location') {
      params = params.sublist(2);
    }
    if (preds.isEmpty ||
        params.length != preds.length ||
        !preds.every((p) => p == 'ly:music?' || p == 'markup?') ||
        m[3]!.contains('#{')) {
      continue;
    }
    final body = LilyPondLexer(m[3]!).tokenize()
      ..removeWhere((t) => t.kind == TokenKind.eof);
    fns[tokens[i].value] = (params, body);
  }
  if (fns.isEmpty) return tokens;

  /// The end (exclusive) of the call argument starting at [i], or null.
  int? argEnd(List<Token> ts, int i) {
    int? group(int at) {
      if (at >= ts.length || ts[at].kind != TokenKind.symbol) return null;
      final open = ts[at].value;
      final close = switch (open) { '{' => '}', '<<' => '>>', _ => null };
      if (close == null) return null;
      var depth = 0;
      for (var k = at; k < ts.length; k++) {
        if (ts[k].kind != TokenKind.symbol) continue;
        if (ts[k].value == open) depth++;
        if (ts[k].value == close && --depth == 0) return k + 1;
      }
      return null;
    }

    if (i >= ts.length) return null;
    final t = ts[i];
    if (t.kind == TokenKind.symbol) return group(i);
    if (t.kind == TokenKind.string) return i + 1;
    if (t.kind == TokenKind.command) {
      if (t.value == 'markup') return group(i + 1);
      if (fns.containsKey(t.value)) return null;
      return i + 1;
    }
    return null;
  }

  List<Token> expand(List<Token> ts, int depth) {
    final out = <Token>[];
    var i = 0;
    while (i < ts.length) {
      final t = ts[i];
      final fn = t.kind == TokenKind.command ? fns[t.value] : null;
      if (fn == null || depth > 8) {
        out.add(t);
        i++;
        continue;
      }
      final (params, body) = fn;
      final args = <String, List<Token>>{};
      var at = i + 1;
      for (final p in params) {
        final end = argEnd(ts, at);
        if (end == null) break;
        args[p] = ts.sublist(at, end);
        at = end;
      }
      if (args.length != params.length) {
        out.add(t);
        i++;
        continue;
      }
      final filled = <Token>[
        for (final b in body)
          if (b.kind == TokenKind.word &&
              b.value.length > 1 &&
              (b.value[0] == '#' || b.value[0] == r'$') &&
              args.containsKey(b.value.substring(1)))
            ...args[b.value.substring(1)]!
          else
            Token(b.kind, b.value, t.line, t.column),
      ];
      out.addAll(expand(filled, depth + 1));
      i = at;
    }
    return out;
  }

  return expand(tokens, 0);
}

/// Parses a LilyPond string into a [Score].
///
/// A source may write the music twice: a `\score` to engrave and a separate
/// `\midi`-only `\score` to play (repeats unfolded, a lead-in silence,
/// other voicings). By default the engraved one is read; with [playback] the
/// one LilyPond plays, which is what MIDI export or a comparison with
/// LilyPond's own MIDI wants.
Score scoreFromLilyPond(String ly, {bool playback = false}) {
  final tokens = _expandMusicFunctions(LilyPondLexer(ly).tokenize());
  final parser = LilyPondParser(tokens);
  final (parsed, language) =
      _unifyNoteLanguage(parser.parse(), detectLyNoteLanguage(ly));
  final ast = _withoutPlaybackScores(parsed, playback: playback);

  // A multi-staff source is its FIRST staff here. Read as one sequence,
  // every staff's bars were appended after the previous staff's: a vocal
  // line with a piano accompaniment came back three times as long.
  if (_collectStaves(ast).length >= 2) {
    return multiPartFromLilyPond(ly, playback: playback).parts.first;
  }

  final reader = _LilyPondReader(
    language: language,
    unfoldRepeats: _scoresUnfoldRepeats(ast),
    relativeFromMiddleC: _relativeFromMiddleC(ly),
  );
  // ⚠️ `\header` was read by `multiPartFromLilyPond` and NOT here, so the
  // single-staff path — which is what every round trip and most callers use —
  // dropped the title and composer the writer had just emitted. Another
  // write-only field, and systematic: every LilyPond export came back
  // untitled.
  //
  // A lone staff hears the score's `\midi { \transposition c }` too: a guitar
  // piece with no `\new Staff` (or one staff) read at written pitch, an
  // octave above what LilyPond plays.
  return reader.buildScore([...ast, ..._scoreTranspositions(ast)],
      metadata: _headerMetadata(ast));
}

/// Whether [ly] was written for LilyPond before 2.18 (its `\version`), when
/// a `\relative` with no start pitch started from middle C. Since 2.18 it
/// starts from the f below, so such a file read by today's rule sounds an
/// octave low; `convert-ly` writes the old default out as `\relative c'`.
bool _relativeFromMiddleC(String ly) {
  final m = RegExp(r'\\version\s*"(\d+)\.(\d+)').firstMatch(ly);
  if (m == null) return false;
  final major = int.parse(m[1]!), minor = int.parse(m[2]!);
  return major < 2 || (major == 2 && minor < 18);
}

/// The note-name language a source uses.
///
/// LilyPond's default is Dutch. Two others appear often enough in real corpora
/// to matter, and BOTH were silently mis-read before this existed, because
/// [_LilyPondReader._parsePitch] falls back to a plain `c` for any token its
/// regex rejects — so a wrong language turns into wrong *notes*, not an error.
enum LyNoteLanguage {
  /// LilyPond's default. `b` is B natural, accidentals are `-is`/`-es`.
  nederlands,

  /// `h` is B natural and a bare `b` is B FLAT — so reading German as Dutch
  /// both loses every `h` and raises every `b` by a semitone.
  deutsch,

  /// `b` is B natural as in Dutch, but accidentals are `-s`/`-f` (`cs`, `bf`),
  /// which the Dutch pattern rejects outright.
  english,

  /// Solfège names `do re mi fa sol la si`. `italiano` (and `catalan`) write
  /// sharps `-d` and flats `-b` (`sib`, `fad`); `francais` adds `ré` and `-x`
  /// for a double sharp; `espanol`/`portugues` write sharps `-s`; `vlaams`
  /// writes sharps `-k`. 44 Mutopia files use these, and all of them read as
  /// silence before, because the note names were not recognised at all.
  solfege,
}

/// Detects the note language from `\language "…"` or `\include "….ly"`.
///
/// Scanning the raw source is deliberate: the directive is a top-level
/// statement that may sit outside any music block, and `\include` carries the
/// same meaning without a `\language` line at all.
LyNoteLanguage detectLyNoteLanguage(String source) {
  final lang = RegExp(r'\\language\s+"([a-zA-Z]+)"').firstMatch(source)?[1] ??
      RegExp(r'\\include\s+"([a-zA-Z]+)\.ly"').firstMatch(source)?[1];
  switch (lang?.toLowerCase()) {
    case 'italiano' ||
          'catalan' ||
          'francais' ||
          'espanol' ||
          'portugues' ||
          'vlaams':
      return LyNoteLanguage.solfege;
    case 'deutsch' || 'svenska' || 'suomi' || 'norsk':
      // Swedish/Norwegian spell `-iss`/`-ess`; the German pattern takes both.
      return LyNoteLanguage.deutsch;
    case 'english':
      return LyNoteLanguage.english;
    case null:
      // Undeclared, so fall back on the notes themselves. `h` is a note name
      // in NO language but German, which makes it decisive evidence. Plenty of
      // real files (German Wikipedia's especially) use German names and simply
      // omit the declaration; read as Dutch they go badly wrong.
      //
      // Require an octave mark or a duration on at least one `h` — those never
      // occur in lyrics or prose, so a stray "h" in a title cannot trigger it.
      return _usesGermanH.hasMatch(_musicOnly(source))
          ? LyNoteLanguage.deutsch
          : LyNoteLanguage.nederlands;
    default:
      return LyNoteLanguage.nederlands;
  }
}

final _usesGermanH =
    RegExp(r"(?<![A-Za-z\\])h(?:isis|eses|is|es)?(?:[',]+\d*|\d+)");

/// [source] with everything that is TEXT rather than music removed.
///
/// The `h` guess must only ever see notes. Lyrics defeat it otherwise: an
/// Italian elision like `"h'in"` (for *ch'in*) is an `h` followed by an
/// apostrophe, which is indistinguishable from the note `h'`. That one syllable
/// in a madrigal flipped an entire C-major score to German and turned every
/// written `b` into B flat — caught by a cross-format round-trip, not by any
/// unit test.
String _musicOnly(String source) {
  var out = source.replaceAll(RegExp(r'"[^"]*"'), ' ');
  for (final keyword in const [
    'header',
    'addlyrics',
    'lyricmode',
    'lyricsto',
    'markup',
  ]) {
    out = _stripBlocks(out, keyword);
  }
  return out;
}

/// Removes `\<keyword> … { balanced }` regions, braces matched.
String _stripBlocks(String src, String keyword) {
  final buf = StringBuffer();
  var i = 0;
  final needle = '\\$keyword';
  while (i < src.length) {
    final at = src.indexOf(needle, i);
    if (at < 0) {
      buf.write(src.substring(i));
      break;
    }
    buf.write(src.substring(i, at));
    final open = src.indexOf('{', at);
    if (open < 0) {
      i = at + needle.length;
      continue;
    }
    var depth = 0;
    var j = open;
    for (; j < src.length; j++) {
      if (src[j] == '{') depth++;
      if (src[j] == '}') {
        depth--;
        if (depth == 0) break;
      }
    }
    i = j < src.length ? j + 1 : src.length;
  }
  return buf.toString();
}

/// LilyPond context types that hold ONE staff of music (each becomes a part).
const _staffLeafTypes = {
  'Staff',
  'DrumStaff',
  'RhythmicStaff',
  'TabStaff',
  'GregorianTranscriptionStaff',
};

/// LilyPond context types that GROUP staves (recurse into them for parts).
const _staffContainerTypes = {
  'StaffGroup',
  'ChoirStaff',
  'PianoStaff',
  'GrandStaff',
  'Score',
};

/// The music nodes of one staff plus the instrument name declared for it.
class _StaffContent {
  _StaffContent(this.nodes, this.instrument, {this.name});
  final List<LyNode> nodes;
  final String? instrument;

  /// The context name it was opened with (`\context Staff = "upper"`).
  final String? name;

  /// The music of `\new Dynamics` lines that belong to this staff (the one
  /// directly above them, as in a PianoStaff): spacer rests carrying
  /// dynamics and hairpins, applied to this staff BY ONSET.
  final List<LyNode> dynamics = [];
}

/// The name of a `\context Staff = "…"` (or any staff-leaf type), or null.
String? _staffName(LyCommand node) {
  if (node.args.isEmpty) return null;
  final first = node.args.first;
  if (first is! LyAssignment || !_staffLeafTypes.contains(first.key)) {
    return null;
  }
  final v = first.value;
  return v is LyString ? v.value : (v is LyWord ? v.value : null);
}

/// Score-level `\transposition` (e.g. guitar in `\midi { \transposition c }`)
/// lives in the Score's `\midi` block, not in any staff's music, so a staff's
/// reader never sees it: the parts then read at written pitch, an
/// octave above what LilyPond's MIDI plays. Only `\midi`/`\layout` blocks are
/// searched, so a `\transposition` in ONE staff's music cannot leak into the
/// others.
List<LyNode> _scoreTranspositions(List<LyNode> ast) {
  final out = <LyNode>[];
  void collectTranspositions(LyNode n) {
    if (n is LyCommand && n.name == 'transposition') {
      out.add(n);
    } else if (n is LyBlock) {
      n.children.forEach(collectTranspositions);
    } else if (n is LySimultaneous) {
      n.children.forEach(collectTranspositions);
    } else if (n is LyCommand) {
      n.args.forEach(collectTranspositions);
    } else if (n is LyScore) {
      n.contents.forEach(collectTranspositions);
    }
  }

  void findOutputBlocks(LyNode n) {
    if (n is LyCommand) {
      if (n.name == 'midi' || n.name == 'layout') {
        collectTranspositions(n);
        return;
      }
      n.args.forEach(findOutputBlocks);
    } else if (n is LyBlock) {
      n.children.forEach(findOutputBlocks);
    } else if (n is LySimultaneous) {
      n.children.forEach(findOutputBlocks);
    } else if (n is LyScore) {
      n.contents.forEach(findOutputBlocks);
    }
  }

  for (final n in ast) {
    findOutputBlocks(n);
  }
  return out;
}

/// Reads a LilyPond source into a [MultiPartScore] — one part per staff.
///
/// A `\score { \new StaffGroup << \new Staff … \new Staff … >> }` (what
/// [multiPartToLilyPond] writes), or any nesting of `Staff`/`StaffGroup`/
/// `PianoStaff`/`ChoirStaff`/`GrandStaff`, becomes one [Score] per staff.
/// Per-staff `\addlyrics` (a sibling inside the staff's `<< … >>`) is aligned to
/// that staff's notes; `\header` (title/composer/poet/copyright) lands on the
/// first part and each staff's `\with { instrumentName = … }` on its own part.
/// Variables assigned at the top level (`soprano = \relative { … }`) are visible
/// to any staff that references them (`\new Staff \soprano`).
///
/// A source with fewer than two staves degrades to a single-part document,
/// identical to wrapping [scoreFromLilyPond] — so this is a safe superset of the
/// single-staff reader for callers that always want a [MultiPartScore].
///
/// [playback] reads a separate `\midi`-only score instead of the engraved
/// one, as in [scoreFromLilyPond].
MultiPartScore multiPartFromLilyPond(String ly, {bool playback = false}) {
  final tokens = _expandMusicFunctions(LilyPondLexer(ly).tokenize());
  final (parsed, language) = _unifyNoteLanguage(
      LilyPondParser(tokens).parse(), detectLyNoteLanguage(ly));
  final ast = _withoutPlaybackScores(parsed, playback: playback);

  final unfoldRepeats = _scoresUnfoldRepeats(ast);

  // Top-level variable assignments must reach every staff that references them.
  final assignments = <LyAssignment>[];
  void gatherAssignments(List<LyNode> nodes) {
    for (final n in nodes) {
      if (n is LyAssignment) {
        assignments.add(n);
      } else if (n is LyBlock) {
        gatherAssignments(n.children);
      } else if (n is LySimultaneous) {
        gatherAssignments(n.children);
      } else if (n is LyScore) {
        gatherAssignments(n.contents);
      }
    }
  }

  gatherAssignments(ast);
  final header = _headerMetadata(ast);
  final staves = _collectStaves(ast);
  final scoreTranspositions = _scoreTranspositions(ast);

  // A ChordNames track beside the staves (`\context ChordNames { \accomp }`
  // in the score's `<< … >>`) belongs to no staff, so no staff's reader saw
  // it and its chords were lost. It goes to the top staff, which is where a
  // lead sheet prints them.
  final inStaves = Set<LyNode>.identity();
  void markStaff(LyNode n) {
    if (!inStaves.add(n)) return;
    if (n is LyBlock) n.children.forEach(markStaff);
    if (n is LySimultaneous) n.children.forEach(markStaff);
    if (n is LyCommand) n.args.forEach(markStaff);
  }

  for (final staff in staves) {
    staff.nodes.forEach(markStaff);
  }
  final chordTracks = <LyNode>[];
  // The `\transpose`s around a chord track, outermost first: a hymn written
  // `\transpose c' bes \context ChoirStaff << \context ChordNames … >>`
  // transposes its chords with its staves, and read bare the chords sounded a
  // tone above the voices.
  final transposes = <List<LyNode>>[];
  var searchingStaff = false;
  final variables = {for (final a in assignments) a.key: a.value};
  final expanding = <String>{};
  void findChordTracks(LyNode n) {
    if (inStaves.contains(n) && !searchingStaff) return;
    if (n is LyCommand &&
        (n.name == 'new' || n.name == 'context') &&
        _contextType(n) == 'ChordNames') {
      var track = n;
      for (final lead in transposes.reversed) {
        track = LyCommand('transpose', [
          ...lead,
          LyBlock([track])
        ]);
      }
      chordTracks.add(track);
      return;
    }
    if (n is LyBlock) n.children.forEach(findChordTracks);
    if (n is LySimultaneous) n.children.forEach(findChordTracks);
    if (n is LyCommand && n.name == 'transpose' && n.args.length > 2) {
      transposes.add(n.args.take(2).toList());
      n.args.skip(2).forEach(findChordTracks);
      transposes.removeLast();
    } else if (n is LyCommand &&
        n.args.isEmpty &&
        variables[n.name] is LyNode &&
        expanding.add(n.name)) {
      // A score that is a variable (`music = << \context ChordNames \harm
      // \upper \lower >>` … `\score { \music }`) holds its chord track
      // there; unexpanded, it was never found.
      findChordTracks(variables[n.name]!);
      expanding.remove(n.name);
    } else if (n is LyCommand) {
      n.args.forEach(findChordTracks);
    }
    if (n is LyScore) n.contents.forEach(findChordTracks);
  }

  for (final n in ast) {
    findChordTracks(n);
  }

  if (staves.length < 2) {
    // One (or zero) staff → the existing single-part behaviour, unchanged.
    return MultiPartScore.fromStaffSystem(
      StaffSystem([scoreFromLilyPond(ly, playback: playback)]),
    );
  }

  (Score, (TimeSignature, Fraction)?) readStaff(int i,
      {(TimeSignature, Fraction)? sharedPickup}) {
    final reader = _LilyPondReader(
        language: language,
        unfoldRepeats: unfoldRepeats,
        relativeFromMiddleC: _relativeFromMiddleC(ly));
    final score = reader.buildScore(
      [
        ...assignments,
        if (i == 0) ...chordTracks,
        ...staves[i].nodes,
        ...scoreTranspositions,
      ],
      metadata: ScoreMetadata(
        // Header fields are document-level → carried on the first part
        // (which is where multiPartToLilyPond reads them back from).
        title: i == 0 ? header.title : null,
        composer: i == 0 ? header.composer : null,
        lyricist: i == 0 ? header.lyricist : null,
        copyright: i == 0 ? header.copyright : null,
        instrument: staves[i].instrument,
      ),
      sharedPickup: sharedPickup,
    );
    return (score, reader._leadingPickup);
  }

  final read = [for (var i = 0; i < staves.length; i++) readStaff(i)];
  // A "staff" holding nothing but a chord track (`\context Staff = "b" <<
  // \context ChordNames \accomp >>`, a hymn's MIDI score) has no notes to
  // hang its chords on, and LilyPond makes the ChordNames a context of its
  // own anyway. Its chords go to the top staff, as a track beside the staves
  // does; read in their own staff, all of them were lost.
  final tracksBefore = chordTracks.length;
  for (var i = 0; i < staves.length; i++) {
    final noNotes = !read[i].$1.measures.any((m) => [
          for (var v = 0; v < 4; v++) ...m.voiceAt(v)
        ].any((e) => e is NoteElement));
    if (!noNotes) continue;
    searchingStaff = true;
    staves[i].nodes.forEach(findChordTracks);
    searchingStaff = false;
  }
  if (chordTracks.length > tracksBefore) read[0] = readStaff(0);
  final scores = [for (final (score, _) in read) score];
  final pickups = [for (final (_, pickup) in read) pickup];
  // `\partial` (and the `\time` it is measured in) belong to the Score's
  // Timing: written once in the soprano's music, they time the bass staff
  // too. A staff that never states a pickup is read again with the first
  // one another staff states; read alone, its every note came a bar's
  // remainder late against the others.
  final shared = pickups.nonNulls.firstOrNull;
  if (shared != null) {
    for (var i = 0; i < scores.length; i++) {
      if (pickups[i] == null) {
        scores[i] = readStaff(i, sharedPickup: shared).$1;
      }
    }
  }
  final parts = <Score>[
    for (var i = 0; i < staves.length; i++)
      _withDynamicsLine(
        scores[i],
        staves[i].dynamics.isEmpty
            ? null
            : _LilyPondReader(language: language)
                .buildScore([...assignments, ...staves[i].dynamics]),
      ),
  ];
  return MultiPartScore(parts);
}

/// Every element's onset as (bar, offset within the bar), by id.
Map<String, (int, Fraction)> _onsetsById(Score score) {
  final out = <String, (int, Fraction)>{};
  for (var b = 0; b < score.measures.length; b++) {
    final m = score.measures[b];
    for (var v = 0; v < 4; v++) {
      final els = m.voiceAt(v);
      var t = Fraction(0, 1);
      for (var i = 0; i < els.length; i++) {
        final id = els[i].id;
        if (id != null) out.putIfAbsent(id, () => (b, t));
        t = t + m.effectiveDurationAt(i, voice: v);
      }
    }
  }
  return out;
}

/// Applies a `\new Dynamics` line's marks to [staff] BY ONSET.
///
/// The line is read as its own score: spacer rests carrying `\p`, `\<` and
/// so on. Each mark moves to the staff's element (first voice) sounding at its
/// onset, or the last one that starts before it in that bar. Absorbed into
/// the staff's music instead, the line's bars were appended after the staff's
/// own, so its marks landed bars late or were lost.
Score _withDynamicsLine(Score staff, Score? line) {
  if (line == null) return staff;
  final onsets = _onsetsById(line);
  String? anchorAt((int, Fraction)? at) {
    if (at == null) return null;
    final (bar, offset) = at;
    if (bar >= staff.measures.length) return null;
    final m = staff.measures[bar];
    String? best;
    var t = Fraction(0, 1);
    for (var i = 0; i < m.elements.length; i++) {
      if (t.compareTo(offset) > 0) break;
      best = m.elements[i].id ?? best;
      t = t + m.effectiveDurationAt(i);
    }
    return best;
  }

  return staff.copyWith(
    dynamics: [
      ...staff.dynamics,
      for (final d in line.dynamics)
        if (anchorAt(onsets[d.elementId]) case final id?)
          DynamicMarking(id, d.level),
    ],
    hairpins: [
      ...staff.hairpins,
      for (final h in line.hairpins)
        if ((anchorAt(onsets[h.startId]), anchorAt(onsets[h.endId]))
            case (final a?, final b?))
          if (a != b) Hairpin(a, b, h.type, above: h.above),
    ],
  );
}

/// The context-type word of a `\new <Type> …` / `\context <Type> …`, or ''.
///
/// Handles BOTH spellings of the context name:
///   `\new Staff { … }`            → first arg is a word
///   `\new Staff = "vocalist" << … >>` → first arg is an ASSIGNMENT `Staff="…"`
///
/// The named form is what LilyPond requires whenever something must refer to
/// the context (`\lyricsto "vocalist"`), so it is everywhere in vocal scores.
/// Missing it meant no staves were collected at all, and the document fell back
/// to the single-staff path — which reads a `{ … }` body but returns NOTHING
/// for a `<< … >>` one. Every `\new Staff = "x" << … >>` score therefore read
/// as empty.
String _contextType(LyNode node) {
  if (node is! LyCommand) return '';
  if (node.name != 'new' && node.name != 'context') return '';
  if (node.args.isEmpty) return '';
  final first = node.args.first;
  if (first is LyWord) return first.value;
  if (first is LyAssignment) return first.key;
  return '';
}

/// Whether [node] begins a NEW staff or staff-group — i.e. a boundary that ends
/// the music absorbed into the current staff. A `\new Dynamics` line ends it
/// too: absorbed, its spacer rests were appended AFTER the staff's music.
bool _isStaffBoundary(LyNode node) {
  // A whole `\score` is never part of a staff: one stray top-level context
  // used to absorb every sibling after it, the score included.
  if (node is LyScore) return true;
  // `\relative a \new Staff { … }`, `\transpose c d \new Staff …`: a staff
  // behind a wrapper is still a new staff. Absorbed into the staff before
  // it, the second staff of a choir score ran on after the first.
  if (node is LyCommand &&
      (node.name == 'relative' || node.name == 'transpose') &&
      node.args.isNotEmpty) {
    return _isStaffBoundary(node.args.last);
  }
  final t = _contextType(node);
  return _staffLeafTypes.contains(t) ||
      _staffContainerTypes.contains(t) ||
      t == 'Dynamics';
}

/// Whether [node] is lyrics attached to a staff (`\addlyrics`, `\lyricsto`, or
/// `\new Lyrics …`).
bool _isLyricsNode(LyNode node) =>
    node is LyCommand &&
    (node.name == 'addlyrics' ||
        node.name == 'lyricsto' ||
        _contextType(node) == 'Lyrics');

/// The `instrumentName` string inside a `\with { … }` settings block, if any.
String? _instrumentInBlock(LyBlock block) {
  for (final c in block.children) {
    if (c is LyAssignment && c.key == 'instrumentName') {
      final v = c.value;
      if (v is LyString) return v.value;
      if (v is LyWord) return v.value;
    }
  }
  return null;
}

/// Walks the AST collecting one [_StaffContent] per staff, top to bottom.
///
/// LilyPond writes `\new Staff \with { … } { music }`, but the parser splits
/// that into a bare `\new Staff` followed by a sibling `\with` node that has
/// grabbed both the settings block AND the music block. So the walk is
/// SEQUENTIAL: a `\new <staff>` opens a part and every following sibling —
/// `\with` (settings + music), a bare `{ … }` / `<< … >>` / `\variable`, and
/// any `\addlyrics` — is absorbed into it until the next staff/group boundary.
/// Containers (`StaffGroup`/`PianoStaff`/…) and `\score`/blocks recurse.
List<_StaffContent> _collectStaves(List<LyNode> ast) {
  final out = <_StaffContent>[];

  // Top-level variables: a score commonly names its staves in variables
  // (`upper = \context Staff …` used as `\upper`), and those staves were
  // never found, so the whole score collapsed into one concatenated part.
  final variables = <String, LyNode>{};
  void gather(List<LyNode> nodes) {
    for (final n in nodes) {
      if (n is LyAssignment) variables[n.key] = n.value;
    }
  }

  gather(ast);
  final expanding = <String>{};

  // Top-level `\new Voice`s count as staves only beside real staves: a score
  // made of voices alone keeps the single-staff reading (LilyPond's implicit
  // staff rules there depend on context we do not model).
  bool hasStaff(List<LyNode> nodes) => nodes.any((n) =>
      _staffLeafTypes.contains(_contextType(n)) ||
      _staffContainerTypes.contains(_contextType(n)) &&
          _contextType(n) != 'Score' ||
      (n is LyBlock && hasStaff(n.children)) ||
      (n is LySimultaneous && hasStaff(n.children)) ||
      (n is LyScore && hasStaff(n.contents)) ||
      (n is LyCommand && hasStaff(n.args)));
  final impliedVoiceStaves = hasStaff(ast);

  /// Pulls settings (instrumentName) + music blocks out of one `\with` node.
  void absorbWith(
      LyCommand withCmd, List<LyNode> music, void Function(String) setName) {
    var settingsSeen = false;
    for (final a in withCmd.args) {
      if (!settingsSeen && a is LyBlock) {
        final name = _instrumentInBlock(a);
        if (name != null) setName(name);
        settingsSeen = true; // first block = \with settings
      } else {
        music.add(a); // anything after = this staff's music
      }
    }
  }

  // Enclosing `\transpose` and `\relative` wrappers, outermost first, each
  // with the arguments that come before its music.
  final wrappers = <(String, List<LyNode>)>[];
  List<LyNode> wrapped(List<LyNode> nodes) {
    var inner = nodes;
    for (final (name, lead) in wrappers.reversed) {
      inner = [
        LyCommand(name, [...lead, LyBlock(inner)])
      ];
    }
    return inner;
  }

  // Plain music — a block, a variable, a `\relative`/`\transpose` of one —
  // with notes in it and no staff inside.
  bool bareMusic(LyNode n, [int depth = 0]) {
    if (depth > 8) return false;
    bool notes(LyNode n, int depth) => switch (n) {
          LyNote() || LyChord() => true,
          LyBlock(:final children) ||
          LySimultaneous(:final children) =>
            children.any((c) => notes(c, depth)),
          LyCommand(name: 'relative' || 'transpose', :final args) =>
            args.any((c) => notes(c, depth)),
          LyCommand(:final name, args: []) when depth < 8 =>
            variables[name] is LyNode && notes(variables[name]!, depth + 1),
          _ => false,
        };
    bool staffInside(LyNode n, int depth) => switch (n) {
          LyBlock(:final children) ||
          LySimultaneous(:final children) =>
            children.any((c) => staffInside(c, depth)),
          LyCommand(args: []) when depth < 8 => variables[n.name] is LyNode &&
              staffInside(variables[n.name]!, depth + 1),
          LyCommand(:final args) =>
            _isStaffBoundary(n) || args.any((c) => staffInside(c, depth)),
          _ => false,
        };
    final music = switch (n) {
      LyBlock() => true,
      LyCommand(name: 'relative' || 'transpose', args: [_, ...]) => true,
      LyCommand(:final name, args: []) =>
        variables[name] is LyNode && bareMusic(variables[name]!, depth + 1),
      _ => false,
    };
    return music && notes(n, 0) && !staffInside(n, 0);
  }

  // A braced group with staves in it (`{ \new PianoStaff << … >> }`) is the
  // next staff along, not more music for the one before it: absorbed, the
  // piano's two staves ran on after a singer's line, three parts end to end.
  bool holdsStaff(LyNode n) => switch (n) {
        LyBlock(:final children) ||
        LySimultaneous(:final children) =>
          children.any((c) =>
              (_isStaffBoundary(c) &&
                  c is! LyScore &&
                  _contextType(c) != 'Dynamics') ||
              holdsStaff(c)),
        _ => false,
      };

  void walk(List<LyNode> nodes,
      {bool inScore = false, bool scoreTop = false, bool scoreVoices = false}) {
    // Plain music beside staves in a score's `<< … >>` gets a staff of its
    // own, as in LilyPond: `<< \melody \addlyrics \text \new PianoStaff … >>`.
    // Unread, the voice part was lost.
    final besideStaves =
        inScore && nodes.any((n) => _isStaffBoundary(n) && n is! LyScore);
    // Two or more voices side by side in the score's own `<< … >>` are a
    // staff each, as LilyPond makes them, staves or none beside them: a
    // hymn's `\context Voice = SA …` and `\context Voice = TB …` read as one
    // staff had all four parts fighting over its voice slots. (Voices met
    // later, after a staff in a sequence, may be going on in that staff.)
    final voiceStaves = inScore &&
        (impliedVoiceStaves ||
            scoreVoices &&
                nodes.where((n) => _contextType(n) == 'Voice').length >= 2);
    var i = 0;
    while (i < nodes.length) {
      final node = nodes[i];
      final type = _contextType(node);

      if (besideStaves && bareMusic(node)) {
        final lyrics = <LyNode>[];
        i++;
        while (i < nodes.length && _isLyricsNode(nodes[i])) {
          lyrics.add(nodes[i]);
          i++;
        }
        out.add(_StaffContent(wrapped([node, ...lyrics]), null));
        continue;
      }

      if (type == 'Dynamics') {
        // A Dynamics line belongs to the staff above it. Its music is the
        // node's own args after the type word, plus any following siblings
        // up to the next boundary (`\new Dynamics \dyn` parses either way).
        final music = <LyNode>[...(node as LyCommand).args.skip(1)];
        i++;
        while (i < nodes.length && !_isStaffBoundary(nodes[i])) {
          music.add(nodes[i]);
          i++;
        }
        if (out.isNotEmpty) out.last.dynamics.addAll(music);
        continue;
      }
      if (node is LyScore) {
        // `\score { … }` parses as one block: its children are the score's.
        final body = switch (node.contents) {
          [LyBlock(:final children)] => children,
          final contents => contents,
        };
        walk(body, inScore: true, scoreTop: true);
        i++;
      } else if (_staffContainerTypes.contains(type)) {
        walk((node as LyCommand).args.skip(1).toList(), inScore: inScore);
        i++;
      } else if (_staffLeafTypes.contains(type) ||
          (type == 'Voice' && voiceStaves)) {
        // (A `\new Voice` outside any staff is a staff of its own when the
        // score also has real staves: LilyPond creates one implicitly. A
        // vocal line written that way beside a PianoStaff was dropped.)
        // Open a staff and absorb its trailing music/settings/lyrics siblings.
        final music = <LyNode>[];
        final lyrics = <LyNode>[];
        String? instrument;
        void setName(String n) => instrument ??= n;

        // The `\new Staff` node's own args after the type word (the attached
        // `{ music }` when there is no separate `\with`).
        for (var k = 1; k < (node as LyCommand).args.length; k++) {
          final a = node.args[k];
          if (a is LyCommand && a.name == 'with') {
            absorbWith(a, music, setName);
          } else {
            music.add(a);
          }
        }
        i++;
        // A staff that a bare Voice implied ends at the next bare Voice:
        // `<< \new Voice = "cantus" … \new Lyrics … \new Voice = "altus" … >>`
        // is one staff per voice, not three voices run end to end.
        final impliedByVoice = type == 'Voice';
        while (i < nodes.length &&
            !_isStaffBoundary(nodes[i]) &&
            !holdsStaff(nodes[i]) &&
            !(impliedByVoice && _contextType(nodes[i]) == 'Voice')) {
          final sib = nodes[i];
          if (_isLyricsNode(sib)) {
            lyrics.add(sib);
          } else if (sib is LyCommand && sib.name == 'with') {
            absorbWith(sib, music, setName);
          } else {
            music.add(sib);
          }
          i++;
        }
        final content = wrapped([...music, ...lyrics]);
        // `\context Staff = "upper"` a second time (a hymn's last verse set
        // in a second `<< … >>` after the first) is the SAME staff going on,
        // not a new one: LilyPond re-enters the named context. Read as a
        // staff of its own, the ending sounded at the start of the piece,
        // on top of the verses.
        final name = node.name == 'context' ? _staffName(node) : null;
        final earlier =
            name == null ? -1 : out.indexWhere((s) => s.name == name);
        if (earlier >= 0) {
          final was = out[earlier];
          out[earlier] = _StaffContent(
              [...was.nodes, ...content], was.instrument ?? instrument,
              name: name)
            ..dynamics.addAll(was.dynamics);
        } else {
          out.add(_StaffContent(content, instrument,
              name: node.name == 'context' ? _staffName(node) : null));
        }
      } else if (node is LyBlock) {
        walk(node.children, inScore: inScore);
        i++;
      } else if (node is LySimultaneous) {
        walk(node.children, inScore: inScore, scoreVoices: scoreTop);
        i++;
      } else if (inScore &&
          node is LyCommand &&
          node.args.isEmpty &&
          variables[node.name] is LyNode &&
          !expanding.contains(node.name)) {
        // A variable holding (part of) the score's staff structure.
        expanding.add(node.name);
        walk([variables[node.name]!], inScore: inScore);
        expanding.remove(node.name);
        i++;
      } else if (inScore && node is LyCommand && node.args.isNotEmpty) {
        // A wrapper (`\transpose c' bes \context ChoirStaff << … >>`,
        // `\unfoldRepeats …`): the staves are inside its arguments. A
        // transposition must reach them too — each staff is read on its own,
        // outside the wrapper, so it would otherwise be lost.
        //
        // `\relative a' << \new Staff … >>` likewise: its octaves reach the
        // staves inside, which read as absolute pitches without it.
        if (node.name == 'transpose' && node.args.length > 2) {
          wrappers.add(('transpose', node.args.take(2).toList()));
          walk(node.args.skip(2).toList(), inScore: inScore);
          wrappers.removeLast();
        } else if (node.name == 'relative') {
          final lead = node.args.length > 1 && node.args.first is LyNote
              ? [node.args.first]
              : <LyNode>[];
          wrappers.add(('relative', lead));
          walk(node.args.skip(lead.length).toList(), inScore: inScore);
          wrappers.removeLast();
        } else {
          walk(node.args, inScore: inScore);
        }
        i++;
      } else {
        i++;
      }
    }
  }

  walk(ast);
  return out;
}

/// Extracts `\header { title/composer/poet/copyright = … }` into metadata.
/// Like staves, the parser splits `\header { … }` into a bare `\header` command
/// followed by a sibling `{ … }` block (or, defensively, keeps it as an arg).
ScoreMetadata _headerMetadata(List<LyNode> ast) {
  String? title, composer, lyricist, copyright;

  void applyBlock(LyBlock block) {
    for (final c in block.children) {
      if (c is! LyAssignment) continue;
      final v = c.value;
      final s = v is LyString ? v.value : (v is LyWord ? v.value : null);
      switch (c.key) {
        case 'title':
          title = s;
        case 'composer':
          composer = s;
        case 'poet':
        case 'lyricist':
          lyricist = s;
        case 'copyright':
          copyright = s;
      }
    }
  }

  void scan(List<LyNode> nodes) {
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      if (n is LyCommand && n.name == 'header') {
        LyBlock? block;
        for (final a in n.args) {
          if (a is LyBlock) block = a;
        }
        if (block == null && i + 1 < nodes.length && nodes[i + 1] is LyBlock) {
          block = nodes[i + 1] as LyBlock; // block is the following sibling
        }
        if (block != null) applyBlock(block);
      } else if (n is LyBlock) {
        scan(n.children);
      } else if (n is LySimultaneous) {
        scan(n.children);
      } else if (n is LyScore) {
        scan(n.contents);
      }
    }
  }

  scan(ast);
  return ScoreMetadata(
    title: title,
    composer: composer,
    lyricist: lyricist,
    copyright: copyright,
  );
}

/// An ending being read: the passes it is taken on, its printed label when
/// that says more than the numbers, and an open or closed end when the source
/// states one (`\once \override Score.VoltaBracket.edge-height`).
class _LyEnding {
  final List<int> passes;
  final String? text;
  final bool? openEnd;
  const _LyEnding(this.passes, {this.text, this.openEnd});
}

class _LilyPondReader {
  _LilyPondReader({
    this.language = LyNoteLanguage.nederlands,
    this.unfoldRepeats = false,
    this.relativeFromMiddleC = false,
  });

  /// Whether a `\relative` with no start pitch starts from middle C, as
  /// LilyPond read it before 2.18 (see [_relativeFromMiddleC]).
  final bool relativeFromMiddleC;

  /// The score says `\unfoldRepeats`, or the music being read sits inside
  /// one: every repeat is read written out.
  bool unfoldRepeats;

  /// Note-name language of the source being read.
  final LyNoteLanguage language;

  /// The partial a `\harmonicByFret` sounds, as (diatonic steps, semitones)
  /// above the written note; (0, 0) outside one.
  (int, int) _harmonicPartial = (0, 0);

  /// LilyPond's partial for each fret a harmonic is touched at
  /// (`fret-partials` and `partial-pitch` in its tablature.scm).
  static const _fretPartials = {
    '12': (7, 12), // the octave
    '7': (11, 19), '19': (11, 19), // an octave and a fifth
    '5': (14, 24), '24': (14, 24), // two octaves
    '4': (16, 28), '9': (16, 28), '16': (16, 28), // and a major third
    '3': (18, 31), // two octaves and a fifth
    '2.7': (20, 34), // two octaves and a minor seventh
    '2.3': (21, 36), // three octaves
    '2': (22, 38), // three octaves and a tone
  };

  /// [p] raised by the running `\harmonicByFret` partial.
  Pitch _harmonic(Pitch p) {
    final (steps, semis) = _harmonicPartial;
    if (steps == 0 && semis == 0) return p;
    return _spelledAbove(p, steps, semis);
  }

  /// Tags `\removeWithTag` leaves out of the music being read.
  Set<String> _removedTags = const {};

  /// Tags `\keepWithTag` keeps (with untagged music), or null for all.
  Set<String>? _keptTags;

  /// [nodes] with each `\tag #'x music` resolved: the music alone when the
  /// tag is kept, nothing when `\removeWithTag` or `\keepWithTag` leaves it
  /// out.
  ///
  /// `\removeWithTag #'x music` (and `\keepWithTag`), whose tag and music
  /// arrive as siblings, become one command holding both, so the music is
  /// never read apart from the filter: a `<< … >>` reads its children one by
  /// one.
  List<LyNode> _withTagsApplied(List<LyNode> nodes) {
    const tagCommands = {'tag', 'removeWithTag', 'keepWithTag'};
    if (!nodes.any((n) =>
        n is LyCommand && n.args.isEmpty && tagCommands.contains(n.name))) {
      return nodes;
    }
    final kept = _keptTags;
    final out = <LyNode>[];
    for (var k = 0; k < nodes.length; k++) {
      if (nodes[k] case LyCommand(:final name, args: [])
          when tagCommands.contains(name) && k + 2 < nodes.length) {
        if (_tagSymbols(nodes[k + 1]) case final tags?) {
          if (name != 'tag') {
            out.add(LyCommand(name, [nodes[k + 1], nodes[k + 2]]));
          } else if (!tags.any(_removedTags.contains) &&
              (kept == null || tags.any(kept.contains))) {
            out.add(nodes[k + 2]);
          }
          k += 2;
          continue;
        }
      }
      out.add(nodes[k]);
    }
    return out;
  }

  /// The symbols of a tag argument: `#'part`, `#'(part score)`, `part`.
  static Set<String>? _tagSymbols(LyNode n) {
    final text = switch (n) {
      LyWord(:final value) => value,
      LyString(:final value) => value,
      _ => null,
    };
    if (text == null) return null;
    final names = RegExp(r'[A-Za-z][\w-]*')
        .allMatches(text.replaceFirst(RegExp(r"^#'?"), ''))
        .map((m) => m[0]!)
        .toSet();
    return names.isEmpty ? null : names;
  }

  Clef _clef = Clef.treble;
  KeySignature _key = const KeySignature(0);
  TimeSignature _time = TimeSignature.commonTime;

  /// The FIRST `\time` in the score. `_time` is the RUNNING meter — it is what
  /// measures its capacity — so reading the score's signature off it takes
  /// whatever the last change happened to be. Brahms' Schicksalslied opens in
  /// 4/4 and moves to 3/4; the score came back declaring 3/4, and re-barring the
  /// whole piece at 3/4 turned 1,624 bars into 1,752 and lost 1,300 notes.
  TimeSignature? _initialTime;

  /// Dynamics (`\p`, `\f`, …) and hairpins (`\<`, `\>` closed by `\!`).
  ///
  /// `DynamicMarking` and `Hairpin` have always existed and every other codec
  /// carries them; the LilyPond reader had neither, so ~600 corpus files lost
  /// their dynamics on the way in.
  final List<DynamicMarking> _dynamics = [];
  final List<Hairpin> _hairpins = [];

  /// Text marks (`c4^"Eb"`). The writer has always been able to emit them and
  /// `Score.annotations` has always held them; the reader had nothing, so all
  /// 4,150 annotation-bearing files in the 10k ABC control lost them on the way
  /// through LilyPond.
  final List<Annotation> _annotations = [];

  /// Direction of a text mark whose string has not arrived yet
  /// (true = below, null = no mark pending).
  bool? _pendingAnnotationBelow;

  /// The note a `\<` or `\>` opened on, waiting for its `\!`.
  ({String startId, HairpinType type})? _openHairpin;

  /// Slurs, rebuilt from the `(` and `)` the parser collects into a note's
  /// scripts. The writer has always emitted them and `Score.slurs` has always
  /// held them; only the reader was missing, so every slur in every LilyPond
  /// file we read was lost — 73,412 of them across 3,286 corpus files, the
  /// single widest gap the expression audit found.
  final List<Slur> _slurs = [];

  /// The note each open slur started on, keyed by its LEVEL.
  ///
  /// ⚠️ The comment here used to say LilyPond allows only one slur at a time
  /// and that one slot was therefore right. It does not: `\=1(`/`\=2(` name
  /// concurrent slurs precisely so a nested pair can be written, and with one
  /// slot the inner close cleared the outer start, so `a-d` around `b-c` read
  /// back as the single slur `a-c`. Level 0 is the unnumbered `(`.
  final Map<int, String> _openSlurLevels = {};

  /// A `\time` seen after the first, waiting for the measure it starts.
  TimeSignature? _pendingTimeChange;

  /// The score's initial `\tempo`, and a later one awaiting its measure.
  Tempo? _tempo;
  Tempo? _pendingTempoChange;

  /// The note a `\glissando` departed from, awaiting the note it lands on.
  String? _openGlissFrom;
  final _glissandos = <Glissando>[];

  /// The note a `\sustainOn` opened on, awaiting its `\sustainOff`.
  String? _openPedalFrom;
  final _pedals = <Pedal>[];

  /// Whether `\numericTimeSignature` is in force. Sticky, like LilyPond's own
  /// property, until `\defaultTimeSignature` turns it off again.
  bool _numericTimeSig = false;

  /// A `\bar` awaiting the bar line it decorates.
  BarlineStyle? _pendingBarline;

  /// Repeat flags from a `\bar`: the end one closes the bar being written, the
  /// start one opens the NEXT.
  bool _pendingPickup = false;

  /// The latest `\partial`: how many it makes, the element id counter when it
  /// came, and the bar time it preloaded. [_processParallelVoices] uses it to
  /// hand a pickup set at the start of voice 1 to the other voices too.
  (int, int, Fraction) _lastPartial = (0, -1, Fraction.zero);

  /// A `\partial` met before the first bar holds anything, with the meter it
  /// was measured in. `\partial` and `\time` set the SCORE's timing, so
  /// [multiPartFromLilyPond] hands this to staves that never state it.
  (TimeSignature, Fraction)? _leadingPickup;
  bool _pendingEndRepeat = false;
  bool _pendingStartRepeat = false;
  bool _startRepeatHere = false;

  /// LilyPond's `\bar` string back to a style. Repeat bars (`:|.`, `.|:`) are
  /// carried by `startRepeat`/`endRepeat` already, so they map to nothing here
  /// rather than being flattened into a plain style.
  static BarlineStyle? _lyBarlineOf(String text) => switch (text) {
        '||' => BarlineStyle.doubleBar,
        '|.' => BarlineStyle.finalBar,
        '.' => BarlineStyle.heavy,
        '!' => BarlineStyle.dashed,
        ';' => BarlineStyle.dotted,
        "'" => BarlineStyle.tick,
        ',' => BarlineStyle.short,
        '.|' => BarlineStyle.reverseFinal,
        '' => BarlineStyle.none,
        '|' => BarlineStyle.normal,
        _ => null,
      };

  /// The note a `\startTrillSpan` opened on, awaiting its `\stopTrillSpan`.
  // 🛑 A mid-score `\clef` is still NOT recorded on the measure, and the
  // attempt is worth recording so it is not repeated blind.
  //
  // `scoreFromLilyPond` walks nodes across STAFF boundaries, so a multi-staff
  // file's other staves' `\clef` commands reach the same measure builder:
  // recording them produced 510 clef changes and 277 mid-bar ones across 250
  // choral files that have one clef each, and cost 477 corpus round trips.
  // Gating on "no music read yet" fixed only the first of them.
  //
  // Doing this properly needs the clef commands scoped to the staff being
  // read, which is a change to how the reader walks staves — not a patch here.
  // The WRITER does emit `Measure.clefChange` and `inlineClefs` correctly, so
  // a score that has them prints them; only the read side is missing.
  bool _arpeggioDown = false;

  /// A `\tweak NoteHead.style` awaiting the note it decorates.
  NoteheadShape _pendingHead = NoteheadShape.normal;

  /// A `\tweak font-size #-N` awaiting the note it shrinks.
  bool _pendingCue = false;

  /// The pending head, cleared as it is taken so it decorates ONE note.
  NoteheadShape _takeHead() {
    final h = _pendingHead;
    _pendingHead = NoteheadShape.normal;
    return h;
  }

  /// Records [id] as a cue note if a `\tweak font-size` is pending, and
  /// clears it so it shrinks ONE note — the same one-shot rule as the head.
  void _takeCue(String? id) {
    if (_pendingCue && id != null) _cueNoteIds.add(id);
    _pendingCue = false;
  }

  final List<String> _cueNoteIds = [];

  /// LilyPond's `#'style` value back to the model's shape.
  static NoteheadShape _lyHeadOf(String raw) =>
      switch (raw.replaceAll(RegExp(r"[#']"), '')) {
        'cross' => NoteheadShape.x,
        'diamond' => NoteheadShape.diamond,
        'triangle' => NoteheadShape.triangleUp,
        'slash' => NoteheadShape.slash,
        'xcircle' => NoteheadShape.circleX,
        _ => NoteheadShape.normal,
      };
  String? _openTrillFrom;
  final _trillExtensions = <TrillExtension>[];
  final _laissezVibrer = <LaissezVibrer>[];

  /// An `\ottava #N` waiting for the note it applies from, then the note it
  /// opened on while the bracket is running.
  bool _awaitingOttavaStart = false;
  bool _pendingOttavaDown = true;
  String? _openOttavaFrom;
  bool _openOttavaDown = true;
  final _ottavas = <Ottava>[];

  /// Whether [_pendingTimeChange] belongs to the measure AFTER the one being
  /// filled. A source may write `\time` either at the start of the bar it
  /// applies to (`| \time 3/4 notes |`) or at the end of the previous one
  /// (`notes \time 3/4 | notes`). Both mean the same bar; attaching the change
  /// to whichever measure happens to close next gets the second form wrong by
  /// one, which then re-bars everything after it.
  bool _timeChangeIsForNextMeasure = false;

  NoteDuration _currentDur = NoteDuration.quarter;
  Pitch _relativeBase = const Pitch(Step.c, octave: 3); // c
  bool _isRelative = false;

  /// Inner-voice content for the bar still being filled, keyed by voice index
  /// (1 = voice 2). A `<< A \\ B >>` that ends mid-bar leaves voice-2 material
  /// with nowhere to live until that bar finally closes.
  final Map<int, List<MusicElement>> _pendingVoices = {};

  /// Tuplet spans belonging to those pending inner voices.
  final List<TupletSpan> _pendingVoiceTuplets = [];

  /// Bars an inner voice runs on for AFTER the one still being filled. They
  /// cannot be appended yet: the open bar has to close first or they would land
  /// in front of it.
  final List<Measure> _pendingOverflow = [];

  /// Grace notes read but not yet attached — they belong to the NEXT note.
  final List<Pitch> _pendingGraces = [];

  /// Which of [_pendingGraces] carry a tie (`~`), by index.
  final Set<int> _pendingGraceTies = {};

  /// Where in [_pendingGraces] the last grace event (a note or a chord)
  /// begins: only that one's ties reach the note after it, unless
  /// [_tieWaitForNote] lets an earlier tie wait for its pitch.
  int _lastGraceEventStart = 0;

  /// `\set tieWaitForNote = ##t`: a tie whose next note lacks its pitch waits
  /// for a later note that has it, instead of being dropped.
  bool _tieWaitForNote = false;

  /// The graces in [graces] that tie into a note sounding [main], and the
  /// pending ties cleared.
  ///
  /// `\grace { d''16[ g'' ~ d''] ~ } <g' d'' g''>4.` under `tieWaitForNote`
  /// ties both g'' and the second d'' into the chord, and LilyPond strikes
  /// neither again; only g' sounds anew. A tie on an earlier grace lands on
  /// the main note only while it waits for its pitch, and a later grace of the
  /// same pitch takes it first.
  Set<int> _takeGraceTies(List<Pitch> graces, List<Pitch> main) {
    final out = <int>{};
    for (final i in _pendingGraceTies) {
      if (i >= graces.length) continue;
      final key = graces[i].midiNumber;
      if (!main.any((p) => p.midiNumber == key)) continue;
      if (i < _lastGraceEventStart && !_tieWaitForNote) continue;
      if (graces.skip(i + 1).any((g) => g.midiNumber == key)) continue;
      out.add(i);
    }
    _pendingGraceTies.clear();
    _lastGraceEventStart = 0;
    return out;
  }

  /// True between a bare `\acciaccatura`/`\grace` and its operand, which the
  /// parser leaves as a following sibling rather than an argument.
  bool _expectGrace = false;
  GraceStyle _pendingGraceStyle = GraceStyle.acciaccatura;

  /// Set when a `\relative` took effect without owning its body (the parser
  /// split it off as a sibling); consumed at the end of the assignment.
  (bool, Pitch)? _pendingRelativeRestore;

  final List<Measure> _measures = [];
  final List<MusicElement> _currentElements = [];
  final List<TupletSpan> _currentTuplets = [];
  final List<Lyric> _lyrics = [];
  final Map<String, LyNode> _variables = {};

  /// The next verse number, PER VOICE.
  ///
  /// ⚠️ A single counter numbered lyric blocks in the order they appear, so
  /// once a staff carried lyrics for two voices the second voice's first verse
  /// continued the first voice's numbering — six verses where the score has
  /// two. Verses belong to a voice, not to the file.
  final Map<int, int> _verseOf = {};

  Fraction _tupletRatio = Fraction(1, 1);
  Fraction _measureTime = Fraction.zero;

  /// The pitches of the last chord, for `q` chord repetition. LilyPond's
  /// `q` repeats the last CHORD: single notes in between don't count.
  List<Pitch> _lastPitches = [];

  /// A `q` chord repeat with an optional duration (`q`, `q4`, `q8.`, `q2*3`).
  static final _chordRepeat = RegExp(r'^q(\d+\.*(?:\*\d+(?:/\d+)?)?)?$');

  /// How many staff LEAVES have been entered.
  ///
  /// ⚠️ `scoreFromLilyPond` walks every node in the file, staves included, so
  /// a SATB score's four `\clef` commands all reach this one measure builder.
  /// Honouring them all made the score clef whatever the LAST staff used and
  /// produced 510 phantom clef changes across 250 one-clef choral files. A
  /// clef belongs to ITS staff, so only the first staff's are read.
  int _staffLeavesSeen = 0;
  Clef? _pendingClefChange;

  /// The ending of the bar in progress alone: one that closes mid-bar.
  _LyEnding? _pendingVolta;

  /// The ending opened by `\set Score.repeatCommands = #'((volta "…"))`,
  /// over every bar until `(volta #f)` closes it.
  _LyEnding? _commandVolta;

  /// An end stated by `\once \override Score.VoltaBracket.edge-height` for the
  /// next ending opened: open when its right height is 0.
  bool? _pendingVoltaOpenEnd;

  /// Ends stated in the source, by the index of a bar of that ending; every
  /// other ending's end follows LilyPond's own rule ([voltaHookedByBarline]).
  final Map<int, bool> _voltaOpenEndAt = {};
  NavigationMark? _pendingNavigation;
  KeySignature? _pendingKeyChange;

  /// The clef and key the score OPENS with.
  ///
  /// ⚠️ `_clef`/`_key` are the RUNNING values, so once mid-score changes are
  /// recorded they end up holding whatever the LAST change set — and the score
  /// would report its final key as its opening one. `_initialTime` already
  /// existed for exactly this reason; these are its two missing siblings.
  Clef? _initialClef;
  KeySignature? _initialKey;
  final List<InlineClefChange> _pendingInlineClefs = [];
  int _elementId = 0;

  Score buildScore(List<LyNode> nodes,
      {ScoreMetadata metadata = const ScoreMetadata(),
      (TimeSignature, Fraction)? sharedPickup}) {
    if (sharedPickup case (final time, final partial)) {
      // Another staff's `\time … \partial …`: the Score's timing, which this
      // staff shares although its own music never says so.
      _initialTime = _time = time;
      final remaining = Fraction(time.beats, time.beatUnit) - partial;
      _measureTime = remaining > Fraction.zero ? remaining : Fraction.zero;
      _pendingPickup = true;
    }
    _processNodes(nodes);
    _closeMeasure(); // close any pending

    if (_measures.isEmpty) {
      _measures.add(Measure([RestElement(NoteDuration.whole, id: 'e0')]));
    }
    _settleVoltaEnds();

    final score = Score(
      clef: _initialClef ?? _clef,
      keySignature: _initialKey ?? _key,
      timeSignature: _initialTime ?? _time,
      tempo: _tempo,
      measures: _measures,
      lyrics: _lyrics,
      slurs: _slurs,
      dynamics: _dynamics,
      hairpins: _hairpins,
      annotations: _annotations,
      glissandos: _glissandos,
      pedals: _pedals,
      ottavas: _ottavas,
      trillExtensions: _trillExtensions,
      laissezVibrer: _laissezVibrer,
      cueNoteIds: _cueNoteIds,
      chordSymbols: _buildChordSymbols(_measures),
      figuredBass: _buildFiguredBass(_measures),
      transposition: _instrumentTransposition,
      metadata: metadata,
    );
    if (_dynamicsLines.isEmpty) return score;
    // Each `\new Dynamics` line, read on its own and laid on the staff by
    // onset, as the multi-staff reader does.
    final line = _LilyPondReader(language: language).buildScore([
      for (final e in _variables.entries) LyAssignment(e.key, e.value),
      ..._dynamicsLines,
    ]);
    return _withDynamicsLine(score, line);
  }

  /// The music of the `\new Dynamics` lines met while reading: marks for
  /// this staff, not notes of it.
  final List<LyNode> _dynamicsLines = [];

  /// A `\transposition <pitch>`: the written part sounds as if `c'` were
  /// [pitch] (`\transposition bes` is a B♭ clarinet, `c` a guitar).
  Transposition? _instrumentTransposition;

  static Transposition? _transpositionFor(Pitch sounding) {
    const written = Pitch(Step.c, octave: 4);
    final steps = sounding.diatonicIndex - written.diatonicIndex;
    final semis = sounding.midiNumber - written.midiNumber;
    if (steps == 0 && semis == 0) return null;
    final down = steps < 0 || (steps == 0 && semis < 0);
    final octaves = steps.abs() ~/ 7;
    final rest = steps.abs() % 7;
    final restSemis = semis.abs() - 12 * octaves;
    final step = Step.values[rest];
    final alter = restSemis - step.semitonesFromC;
    if (alter < -2 || alter > 2) return null;
    try {
      final interval = Interval.between(
          written, Pitch(step, alter: alter, octave: written.octave));
      return Transposition(interval, down: down, octaves: octaves);
    } on ArgumentError {
      return null;
    }
  }

  List<String> _extractLyricsSyllables(LyNode node) {
    if (node is LyWord) {
      if (RegExp(r'^[\d\.]+$').hasMatch(node.value)) return [];
      return [node.value];
    }
    if (node is LyString) return [node.value];
    if (node is LyNote) return [node.pitch];
    if (node is LyRest) return ['_'];
    if (node is LyBlock) return _extractLyricsList(node.children);
    if (node is LySimultaneous) return _extractLyricsList(node.children);
    if (node is LyCommand) {
      if (_lyricSettings.contains(node.name)) return const [];
      // `\skip 4` in lyrics holds a note without a syllable, like `_`.
      if (node.name == 'skip') return const ['_'];
      if (_variables.containsKey(node.name)) {
        return _extractLyricsSyllables(_variables[node.name]!);
      }
      // A nested `\lyricsto` drops its voice-name argument for the same
      // reason as the top-level one below.
      final args = node.name == 'lyricsto' && node.args.isNotEmpty
          ? node.args.sublist(1)
          : node.args;
      return _extractLyricsList(args);
    }
    return [];
  }

  /// Commands that CONFIGURE a lyric context rather than contribute to it.
  static const _lyricSettings = {
    'set',
    'unset',
    'override',
    'revert',
    'once',
  };

  /// Walks a sibling list, skipping context settings.
  ///
  /// ⚠️ `\set stanza = #"1. "` does not arrive as one node: the parser leaves
  /// `\set` with NO arguments, the `stanza = #` assignment as its sibling and
  /// the Scheme string as a sibling of that. Walking the list blindly sang the
  /// verse number `1. ` as a syllable and shifted the whole verse by one note.
  List<String> _extractLyricsList(List<LyNode> nodes) {
    final out = <String>[];
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node is LyCommand && _lyricSettings.contains(node.name)) {
        if (i + 1 < nodes.length && nodes[i + 1] is LyAssignment) {
          final value = (nodes[i + 1] as LyAssignment).value;
          i++;
          // A bare `#` means the literal itself is the NEXT sibling.
          if (value is LyWord && value.value == '#') i++;
        }
        continue;
      }
      if (node is LyAssignment) continue;
      out.addAll(_extractLyricsSyllables(node));
    }
    return out;
  }

  /// LilyPond's shorthand articulation scripts, as the writer emits them.
  static const _scriptArtics = {
    '-.': Articulation.staccato,
    '--': Articulation.tenuto,
    '->': Articulation.accent,
    '-^': Articulation.marcato,
    '-|': Articulation.staccatissimo,
    '^|': Articulation.staccatissimo,
    '_|': Articulation.staccatissimo,
  };

  /// Post-note commands: `\trill` and friends attach to the note BEFORE them,
  /// arriving as a sibling rather than as one of that note's scripts.
  static const _commandOrnaments = {
    'trill': Ornament.trill,
    'prall': Ornament.shortTrill,
    'mordent': Ornament.mordent,
    'turn': Ornament.turn,
    'reverseturn': Ornament.invertedTurn,
  };

  /// LilyPond's dynamic marks, which are commands rather than scripts.
  static const _commandDynamics = {
    'ppppp': DynamicLevel.pppp,
    'pppp': DynamicLevel.pppp,
    'ppp': DynamicLevel.ppp,
    'pp': DynamicLevel.pp,
    'p': DynamicLevel.p,
    'mp': DynamicLevel.mp,
    'mf': DynamicLevel.mf,
    'f': DynamicLevel.f,
    'ff': DynamicLevel.ff,
    'fff': DynamicLevel.fff,
    'ffff': DynamicLevel.ffff,
    'fffff': DynamicLevel.ffff,
    'sf': DynamicLevel.sf,
    // ⚠️ These five used to collapse onto sf/f/ff, so a score's accents came
    // back weaker and less specific than they went in — a silent LOSS that no
    // round trip could see, because the writer emitted `\${level.name}` and
    // the reader mapped that one name to the wrong level.
    'sfz': DynamicLevel.sfz,
    'fp': DynamicLevel.fp,
    'rfz': DynamicLevel.rf,
    'rf': DynamicLevel.rf,
    'fz': DynamicLevel.fz,
    'sffz': DynamicLevel.sffz,
    // No model value; the nearest is the honest reading.
    'sff': DynamicLevel.ff,
    'sp': DynamicLevel.p,
    'spp': DynamicLevel.pp,
  };

  /// The id of the most recent element, for a mark that attaches backwards.
  String? _lastElementId() {
    if (_currentElements.isEmpty) return null;
    return _currentElements.last.id;
  }

  /// `\<` / `\>` open a hairpin, `\!` closes it on the note it follows.
  void _hairpinMark(String mark) {
    switch (mark) {
      case r'\<':
        final id = _lastElementId();
        if (id != null) {
          _openHairpin = (startId: id, type: HairpinType.crescendo);
        }
      case r'\>':
        final id = _lastElementId();
        if (id != null) {
          _openHairpin = (startId: id, type: HairpinType.diminuendo);
        }
      case r'\!':
        final open = _openHairpin;
        final id = _lastElementId();
        // An unmatched `\!` is ignored rather than guessed at, for the same
        // reason an unmatched `)` is: real files carry them across branches.
        //
        // ⚠️ A hairpin that starts and ends on the SAME note used to be
        // rejected here. It is legitimate — MusicXML, MEI and MuseScore all
        // carry one, and a real corpus file has one — and it is unambiguous
        // because the writer orders that case `\>\!` rather than `\!\>`.
        // The ordering is what distinguishes it from the ordinary chain, where
        // the `\!` belongs to a span that opened on an EARLIER note.
        if (open != null && id != null) {
          _hairpins.add(Hairpin(open.startId, id, open.type));
        }
        _openHairpin = null;
    }
  }

  static const _commandArtics = {
    'fermata': Articulation.fermata,
    'staccatissimo': Articulation.staccatissimo,
    'breathe': Articulation.breath,
    'upbow': Articulation.upBow,
    'downbow': Articulation.downBow,
    'staccato': Articulation.staccato,
    'tenuto': Articulation.tenuto,
    'accent': Articulation.accent,
    'marcato': Articulation.marcato,
  };

  /// Attaches a post-note command to the note it follows. Returns whether the
  /// command was one of ours, so the caller can leave anything else alone.
  bool _attachToPrevious(String name) {
    if (name == 'arpeggioArrowUp' || name == 'arpeggioArrowDown') {
      // A CONTEXT property, sticky until changed — not attached to the note it
      // precedes.
      _arpeggioDown = name == 'arpeggioArrowDown';
      return true;
    }
    if (name == 'arpeggio') {
      final id = _lastElementId();
      if (id != null) {
        final i =
            _currentElements.indexWhere((e) => e is NoteElement && e.id == id);
        if (i >= 0) {
          _currentElements[i] = (_currentElements[i] as NoteElement)
              .copyWith(arpeggio: _arpeggioDown ? Arpeggio.down : Arpeggio.up);
        }
      }
      return true;
    }
    if (name == 'laissezVibrer') {
      final id = _lastElementId();
      if (id != null) _laissezVibrer.add(LaissezVibrer(id));
      return true;
    }
    if (name == 'startTrillSpan' || name == 'stopTrillSpan') {
      final id = _lastElementId();
      if (id != null) {
        if (name == 'startTrillSpan') {
          _openTrillFrom = id;
        } else if (_openTrillFrom case final from?) {
          _trillExtensions.add(TrillExtension(from, id));
          _openTrillFrom = null;
        }
      }
      return true;
    }
    if (name == 'sustainOn' || name == 'sustainOff') {
      final id = _lastElementId();
      if (id != null) {
        if (name == 'sustainOn') {
          _openPedalFrom = id;
        } else if (_openPedalFrom case final from?) {
          _pedals.add(Pedal(from, id));
          _openPedalFrom = null;
        }
      }
      return true;
    }
    if (name == 'glissando') {
      // LilyPond marks only the DEPARTURE note; the line runs to whatever note
      // comes next, which may not exist yet, so the span is closed later.
      final id = _lastElementId();
      if (id != null) _openGlissFrom = id;
      return true;
    }
    final level = _commandDynamics[name];
    if (level != null) {
      final id = _lastElementId();
      if (id != null) _dynamics.add(DynamicMarking(id, level));
      return true;
    }
    final ornament = _commandOrnaments[name];
    final artic = _commandArtics[name];
    if (ornament == null && artic == null) return false;
    if (_currentElements.isEmpty) return true;
    final last = _currentElements.last;
    if (last is! NoteElement) return true;
    _currentElements[_currentElements.length - 1] = last.copyWith(
      ornament: ornament ?? last.ornament,
      articulations:
          artic == null ? last.articulations : {...last.articulations, artic},
    );
    return true;
  }

  /// The context name of a `\new Voice = "…"` node, if it has one.
  static String? _contextName(LyNode node) {
    if (node is! LyCommand) return null;
    if (node.name != 'new' && node.name != 'context') return null;
    if (node.args.isEmpty) return null;
    final first = node.args.first;
    if (first is! LyAssignment || first.key != 'Voice') return null;
    final v = first.value;
    if (v is LyString) return v.value;
    if (v is LyWord) return v.value;
    return null;
  }

  /// Voice CONTEXT NAME to voice index, from `\new Voice = "…"`.
  final Map<String, int> _voiceNames = {};

  void _alignLyrics(List<String> syllables, {int voice = 0}) {
    final noteIds = <String>[];
    List<MusicElement> pick(Measure m) => switch (voice) {
          0 => m.elements,
          1 => m.voice2,
          2 => m.voice3,
          _ => m.voice4,
        };
    void take(MusicElement e) {
      if (e is NoteElement &&
          e.id != null &&
          !_barContinuations.contains(e.id)) {
        noteIds.add(e.id!);
      }
    }

    for (final m in _measures) {
      pick(m).forEach(take);
    }
    if (voice == 0) {
      _currentElements.forEach(take);
    } else {
      (_pendingVoices[voice] ?? const <MusicElement>[]).forEach(take);
    }

    int noteIndex = 0;
    int syllableIndex = 0;

    while (syllableIndex < syllables.length && noteIndex < noteIds.length) {
      final syl = syllables[syllableIndex];
      if (['|', '{', '}', '<<', '>>', '\\\\'].contains(syl)) {
        syllableIndex++;
        continue;
      }
      if (syl == '--' || syl == '__') {
        syllableIndex++;
        continue;
      }
      if (syl == '_') {
        noteIndex++;
        syllableIndex++;
        continue;
      }

      final String text = syl;
      bool hyphen = false;
      bool extender = false;

      int lookahead = syllableIndex + 1;
      while (lookahead < syllables.length) {
        final nextSyl = syllables[lookahead];
        if (nextSyl == '--') {
          hyphen = true;
          lookahead++;
        } else if (nextSyl == '__') {
          extender = true;
          lookahead++;
        } else if (['|', '{', '}'].contains(nextSyl)) {
          lookahead++;
        } else {
          break;
        }
      }

      _lyrics.add(Lyric(noteIds[noteIndex], text,
          hyphenToNext: hyphen,
          extender: extender,
          verse: _verseOf[voice] ?? 1));

      noteIndex++;
      syllableIndex = lookahead;
    }
    _verseOf[voice] = (_verseOf[voice] ?? 1) + 1;
  }

  void _processNodes(List<LyNode> nodes) {
    // `b4\rest` is a REST drawn at the pitch b (to place it in a voice), not
    // a note: read as one, every such rest in a guitar or piano part sounded.
    if (nodes
        .any((n) => n is LyCommand && n.name == 'rest' && n.args.isEmpty)) {
      nodes = [
        for (var k = 0; k < nodes.length; k++)
          if (nodes[k] case LyNote(:final pitch, :final duration)
              when k + 1 < nodes.length &&
                  nodes[k + 1] is LyCommand &&
                  (nodes[k + 1] as LyCommand).name == 'rest' &&
                  (nodes[k + 1] as LyCommand).args.isEmpty)
            _LyPitchedRest(pitch, duration)
          else if (!(nodes[k] is LyCommand &&
              (nodes[k] as LyCommand).name == 'rest' &&
              (nodes[k] as LyCommand).args.isEmpty &&
              k > 0 &&
              nodes[k - 1] is LyNote))
            nodes[k],
      ];
    }
    nodes = _withTagsApplied(nodes);
    for (var idx = 0; idx < nodes.length; idx++) {
      var node = nodes[idx];
      // `\incipit \cantusIncipit` — the argument is engraved as the staff's
      // NAME (an instrument-name stencil), not played. Read as music it put
      // the incipit's notes in front of the piece, and since each voice's
      // incipit has its own length, the parts of a Renaissance partbook came
      // back with different bar counts.
      if (_isIncipitCall(node)) {
        idx++;
        continue;
      }
      // `\unfoldRepeats music`, also inside a variable the playback score
      // uses (`midiPiano = { \unfoldRepeats \piano }`): every repeat in its
      // music sounds written out.
      if (node is LyCommand && node.name == 'unfoldRepeats') {
        final music = node.args.isNotEmpty
            ? node.args
            : [if (idx + 1 < nodes.length) nodes[++idx]];
        final outer = unfoldRepeats;
        unfoldRepeats = true;
        _processNodes(music);
        unfoldRepeats = outer;
        continue;
      }
      // `\harmonicByFret #12 { d,,4 a d, }`: harmonics touched at a fret
      // sound the partial that fret gives, and LilyPond writes them so — it
      // moves each written note up by that partial (an octave at the 12th
      // fret, an octave and a fifth at the 7th) before `\relative` reads it.
      // Read as written, they sounded two octaves low.
      if (node case LyCommand(name: 'harmonicByFret', args: [])
          when idx + 2 < nodes.length) {
        final fret = switch (nodes[idx + 1]) {
          LyWord(:final value) => value.replaceFirst('#', ''),
          _ => null,
        };
        if (fret != null) {
          final outer = _harmonicPartial;
          _harmonicPartial = _fretPartials[fret] ?? (0, 0);
          _processNodes([nodes[idx + 2]]);
          _harmonicPartial = outer;
          idx += 2;
          continue;
        }
      }
      // `\tag #'part music` marks music for one edition; `\removeWithTag
      // #'part \violin` leaves it out and `\keepWithTag #'score \violin`
      // keeps only it (and what is untagged). Unread, a cue voice tagged for
      // the printed part sounded in the score's MIDI as a second violin.
      if (node
          case LyCommand(
            name: 'removeWithTag' || 'keepWithTag',
            args: [final tagArg, final music],
          )) {
        if (_tagSymbols(tagArg) case final tags?) {
          final (removed, kept) = (_removedTags, _keptTags);
          if (node.name == 'removeWithTag') {
            _removedTags = {...removed, ...tags};
          } else {
            _keptTags = tags;
          }
          _processNodes([music]);
          _removedTags = removed;
          _keptTags = kept;
          continue;
        }
      }
      // \repeat <type> <count> { body }  (+ optional \alternative { {..}{..} }).
      // Match LilyPond's DEFAULT MIDI (no \unfoldRepeats): `\repeat unfold N`
      // sounds N times, but `\repeat volta` (and percent/tremolo) sound the
      // written material just ONCE — body then every alternative, linearly.
      // A score reader mirrors that: unfold -> N copies; everything else -> once.
      // `\tempo 4 = 96` — the writer has always emitted this and the reader
      // never read it, so every LilyPond file in the corpus lost its tempo on
      // import. A write-only feature is invisible to a round trip of our own
      // output only if nothing compares the field; nothing did.
      //
      // ⚠️ TWO shapes, because of the parser's sibling split: bare, the
      // `4 = 96` arrives as an ARG (an LyAssignment, since `=` is a symbol);
      // with a text label (`\tempo "Allegro" 4 = 96`) the label takes the arg
      // slot and the assignment lands as the NEXT SIBLING.
      // `\ottava #N` — the `#N` is a sibling word, and the bracket applies
      // from the note that FOLLOWS, so the start is bound when that note
      // arrives. `#0` closes it on the note just written.
      // `\bar "||"` — the string may be an argument or, after the parser's
      // sibling split, the next node.
      // `\set Score.repeatCommands = #'((volta "1"))` — LilyPond's explicit
      // volta bracket, and the only spelling that does not require wrapping the
      // music in `\repeat volta { … } \alternative { … }`. The corpus uses
      // both: 442 files write `\repeat volta` (which the unfolding path above
      // handles) and 4 write this, with exactly these shapes — `(volta "1")`,
      // `(volta "1.2.3.")` and `(volta #f)` to close.
      //
      // ⚠️ The parser does NOT keep the Scheme list together: `#'`, `(`, `(`,
      // `volta`, the string and the closing parens all arrive as SIBLINGS of
      // the assignment. So the value is read by scanning forward, exactly as
      // `\bar` and `\ottava` read theirs.
      // `\set Timing.measureLength = #(ly:make-moment 3/2)` — an explicit bar
      // length. Like `repeatCommands`, the Scheme arrives as SIBLINGS of the
      // assignment, so the value is scanned forward.
      if (node is LyAssignment && node.key == 'Timing.measureLength') {
        // The value is the assignment's own (one Scheme token), or — from an
        // older lexer split — its following siblings.
        for (var j = idx; j < nodes.length && j <= idx + 8; j++) {
          final n = j == idx ? node.value : nodes[j];
          if (n is LyNote || n is LyRest) break;
          final text = n is LyWord ? n.value : (n is LyString ? n.value : '');
          // The lexer delivers a Scheme list whole: `#(ly:make-moment 3/2)`,
          // and the older two-number `#(ly:make-moment 3 2)`.
          final m = RegExp(r'^(\d+)/(\d+)$').firstMatch(text) ??
              RegExp(r'make-moment\s+(\d+)\s*[/ ]\s*(\d+)').firstMatch(text);
          if (m != null) {
            final num = int.tryParse(m[1]!);
            final den = int.tryParse(m[2]!);
            if (num != null && den != null && den > 0) {
              _measureLengthOverride = Fraction(num, den);
            }
            break;
          }
        }
        continue;
      }
      // `\set tieWaitForNote = ##t` (in any context): a tie waits for its
      // pitch. It decides which grace notes tie into the note after them.
      if (node is LyAssignment &&
          (node.key == 'tieWaitForNote' ||
              node.key.endsWith('.tieWaitForNote'))) {
        for (var j = idx; j < nodes.length && j <= idx + 2; j++) {
          final n = j == idx ? node.value : nodes[j];
          final text = n is LyWord ? n.value : '';
          if (text.endsWith('t') || text.endsWith('f')) {
            _tieWaitForNote = text.endsWith('t');
            break;
          }
        }
        continue;
      }
      if (node is LyAssignment && node.key == 'Score.repeatCommands') {
        // ⚠️ The directives apply IN ORDER: closing one bracket and opening
        // the next in the same bar reads `#'((volta #f) (volta "2"))`, and
        // stopping at the first left the second ending unmarked.
        //
        // The bracket covers every bar until `(volta #f)` — it used to mark
        // only the bar it opened on. The label is printed as written and
        // names the passes ("1.2.3.", "1.-3."); one naming none ("Fine") is
        // taken on the pass after the endings before it.
        final directives = <String?>[]; // a label, or null for `#f`
        var endRepeat = false;
        var startRepeat = false;
        for (var j = idx; j < nodes.length && j <= idx + 12; j++) {
          final n = j == idx ? node.value : nodes[j];
          if (n is LyNote || n is LyRest || n is LyCommand) break;
          if (n is LyWord && n.value.startsWith("#'(")) {
            // The whole list as one Scheme token.
            for (final m in RegExp(r'volta\s+(#f|"[^"]*")|(end|start)-repeat')
                .allMatches(n.value)) {
              if (m[2] == 'end') {
                endRepeat = true;
              } else if (m[2] == 'start') {
                startRepeat = true;
              } else {
                final v = m[1]!;
                directives.add(v == '#f' ? null : v.substring(1, v.length - 1));
              }
            }
            break;
          }
          if (n is LyWord && n.value == 'volta' && j + 1 < nodes.length) {
            final v = nodes[j + 1];
            // `#f` closes the bracket; a string opens one.
            directives.add(v is LyString ? v.value : null);
          }
        }
        void apply() {
          final atBarStart = _currentElements.isEmpty;
          if (endRepeat) {
            if (atBarStart && _measures.isNotEmpty) {
              _measures.last = _measures.last.copyWith(endRepeat: true);
            } else {
              _pendingEndRepeat = true;
            }
          }
          if (startRepeat) {
            if (atBarStart) {
              _startRepeatHere = true;
            } else {
              _pendingStartRepeat = true;
            }
          }
          for (final label in directives) {
            if (label == null) {
              // An ending closing mid-bar still owns the bar it closes in.
              if (!atBarStart) _pendingVolta ??= _commandVolta;
              _commandVolta = null;
            } else {
              _commandVolta = _endingFromLabel(label);
            }
          }
        }

        // A directive after a full bar that no note has closed yet belongs
        // to the NEXT bar, so it waits for that close. Closing here instead
        // would strand a `\bar "|."` written after it.
        if (_isFull()) {
          _afterClose.add(apply);
        } else {
          apply();
        }
        continue;
      }
      // `\once \override Score.VoltaBracket.edge-height = #'(2 . 0)`: a right
      // height of 0 leaves the next ending open, any other closes it. The
      // lexer splits the property at its hyphen, so the value arrives as an
      // assignment to `height` after a `….VoltaBracket.edge` word.
      if (node is LyWord &&
          node.value.contains('VoltaBracket') &&
          node.value.contains('edge')) {
        for (var j = idx + 1; j < nodes.length && j <= idx + 3; j++) {
          final n = nodes[j];
          final text = n is LyAssignment && n.value is LyWord
              ? (n.value as LyWord).value
              : n is LyWord
                  ? n.value
                  : '';
          final m =
              RegExp(r'\(\s*-?[\d.]+\s+\.\s+(-?[\d.]+)\s*\)').firstMatch(text);
          if (m != null) {
            _pendingVoltaOpenEnd = (double.tryParse(m[1]!) ?? 1) == 0;
            idx = j;
            break;
          }
        }
        continue;
      }
      // `\mark` — a rehearsal/navigation mark. The TARGETS arrive as a markup
      // containing `\musicglyph "scripts.segno"`; the instructions as a plain
      // string carrying the conventional label. Both are matched against
      // [SmuflGlyph.navigationLabel] rather than guessed, so a third-party
      // `\mark "D.S. al Coda"` is read as well as our own.
      if (node is LyCommand && node.name == 'mark') {
        final words = <String>[];
        void collect(LyNode n) {
          if (n is LyString) words.add(n.value);
          if (n is LyWord) words.add(n.value);
          if (n is LyBlock) n.children.forEach(collect);
          if (n is LyCommand) n.args.forEach(collect);
        }

        node.args.forEach(collect);
        for (var j = idx + 1;
            j < nodes.length && j <= idx + 6 && words.isEmpty;
            j++) {
          final n = nodes[j];
          if (n is LyNote || n is LyRest) break;
          collect(n);
        }
        final text = words.join(' ');
        if (text.contains('scripts.segno')) {
          _pendingNavigation = NavigationMark.segno;
        } else if (text.contains('scripts.coda')) {
          _pendingNavigation = NavigationMark.coda;
        } else {
          for (final mark in NavigationMark.values) {
            final label = SmuflGlyph.navigationLabel(mark);
            if (label != null && words.contains(label)) {
              _pendingNavigation = mark;
              break;
            }
          }
        }
      }
      if (node is LyCommand && node.name == 'bar') {
        var text = node.args.whereType<LyString>().firstOrNull?.value;
        if (text == null &&
            idx + 1 < nodes.length &&
            nodes[idx + 1] is LyString) {
          text = (nodes[idx + 1] as LyString).value;
          idx++;
        }
        if (text != null) {
          // A repeat bar sets the flags rather than a style — they share the
          // `\bar` slot, and `.|:` belongs to the bar that FOLLOWS it.
          if (text.contains(':|')) _pendingEndRepeat = true;
          if (text.contains('|:')) {
            // `.|:` opens the bar that FOLLOWS it — but with no notes yet
            // accumulated that bar is the one being built, not the next one.
            // Staging it unconditionally put a leading repeat on bar 2.
            if (_currentElements.isEmpty && _measures.isEmpty) {
              _startRepeatHere = true;
            } else {
              _pendingStartRepeat = true;
            }
          }
          final style = _lyBarlineOf(text);
          if (style != null) _pendingBarline = style;
        }
        continue;
      }
      // `\tweak NoteHead.style #'cross` — a PREFIX on the note that follows,
      // and its two operands arrive as siblings after the parser's split.
      if (node is LyCommand && node.name == 'tweak') {
        final words = <String>[
          for (final a in node.args)
            if (a is LyWord) a.value,
        ];
        var k = idx + 1;
        // ⚠️ A hyphenated property does NOT arrive whole: `-` is the script
        // marker, so the lexer splits `font-size` into `font`, `-`, `size`.
        // `NoteHead.style` survived only because it has no hyphen. The name is
        // therefore everything up to the first `#`-prefixed operand, joined.
        while (k < nodes.length && nodes[k] is LyWord) {
          final w = (nodes[k] as LyWord).value;
          words.add(w);
          k++;
          if (w.startsWith('#')) break;
        }
        final valueAt = words.indexWhere((w) => w.startsWith('#'));
        final property = valueAt <= 0 ? '' : words.take(valueAt).join();
        final value = valueAt < 0 ? '' : words[valueAt];
        if (property == 'font-size') {
          // A cue note is one drawn SMALL, which is exactly what a negative
          // font-size says. Any reduction counts — real files pick different
          // magnitudes — so the test is the SIGN, not our own `-3`.
          final size = num.tryParse(value.replaceFirst('#', ''));
          if (size != null && size < 0) _pendingCue = true;
          idx = k - 1;
          continue;
        }
        if (words.length >= 2 && words[0] == 'NoteHead.style') {
          _pendingHead = _lyHeadOf(words[1]);
          idx = k - 1;
        }
        continue;
      }
      if (node is LyCommand && node.name == 'ottava') {
        var arg = node.args.whereType<LyWord>().firstOrNull?.value;
        if (arg == null && idx + 1 < nodes.length && nodes[idx + 1] is LyWord) {
          arg = (nodes[idx + 1] as LyWord).value;
          idx++;
        }
        final n = int.tryParse((arg ?? '').replaceFirst('#', ''));
        if (n != null) {
          if (n == 0) {
            final id = _lastElementId();
            if (_openOttavaFrom case final from? when id != null) {
              _ottavas.add(Ottava(from, id, down: _openOttavaDown));
              _openOttavaFrom = null;
            }
          } else {
            _pendingOttavaDown = n > 0;
            _awaitingOttavaStart = true;
          }
        }
        continue;
      }
      if (node is LyCommand && node.name == 'tempo') {
        var mark = node.args.whereType<LyAssignment>().firstOrNull;
        if (mark == null &&
            idx + 1 < nodes.length &&
            nodes[idx + 1] is LyAssignment) {
          mark = nodes[idx + 1] as LyAssignment;
          idx++;
        }
        final parsed = mark == null ? null : _tempoFrom(mark);
        if (parsed != null) {
          if (_tempo == null && _currentElements.isEmpty && _measures.isEmpty) {
            _tempo = parsed;
          } else {
            _pendingTempoChange = parsed;
          }
        }
        continue;
      }
      if (node is LyCommand && node.name == 'repeat') {
        var type = 'volta';
        var count = 2;
        LyNode? body;
        for (final a in node.args) {
          if (a is LyWord && int.tryParse(a.value) != null) {
            count = int.parse(a.value);
          } else if (a is LyWord) {
            type = a.value;
          } else if (a is LyBlock) {
            body = a;
          }
        }
        // The body is any music expression, not only a braced one:
        // `\repeat tremolo 8 c32` repeats the one note after it.
        if (body == null && idx + 1 < nodes.length) {
          final nxt = nodes[idx + 1];
          if (nxt is LyNote ||
              nxt is LyChord ||
              nxt is LyRest ||
              nxt is LySimultaneous ||
              (nxt is LyCommand &&
                  nxt.args.isEmpty &&
                  _variables.containsKey(nxt.name))) {
            body = nxt;
            idx++;
          }
        }
        var alts = const <LyNode>[];
        // Passes an alternative states with `\volta 1,2 { … }`, by index.
        final statedPasses = <List<int>?>[];
        if (idx + 1 < nodes.length) {
          final nxt = nodes[idx + 1];
          if (nxt is LyCommand &&
              nxt.name == 'alternative' &&
              nxt.args.isNotEmpty) {
            final arg = nxt.args.last;
            if (arg is LyBlock) {
              final inner = <LyBlock>[];
              List<int>? stated;
              for (var c = 0; c < arg.children.length; c++) {
                final child = arg.children[c];
                if (child is LyCommand && child.name == 'volta') {
                  final word =
                      c + 1 < arg.children.length ? arg.children[c + 1] : null;
                  if (word is LyWord) {
                    final ns = voltaNumbersIn(word.value);
                    if (ns.isNotEmpty) stated = ns;
                    c++;
                  }
                } else if (child is LyBlock) {
                  inner.add(child);
                  statedPasses.add(stated);
                  stated = null;
                }
              }
              alts = inner.isNotEmpty ? inner : [arg];
              if (inner.isEmpty) statedPasses.add(null);
            }
            idx++; // consume the \alternative
          }
        }
        // A tremolo LilyPond can write as one value per note (`c32` eight
        // times is `c4:32`); one it cannot is written out instead.
        final tremolo = body != null && type == 'tremolo' && !unfoldRepeats
            ? _tremoloOf(body, count)
            : null;
        if (body != null) {
          // `\repeat unfold` is written out the same way, always.
          if (type == 'unfold' ||
              type == 'tremolo' && !unfoldRepeats && tremolo == null ||
              unfoldRepeats &&
                  (type == 'volta' ||
                      type == 'segno' ||
                      type == 'percent' ||
                      type == 'tremolo')) {
            // Under `\unfoldRepeats` LilyPond plays the body [count] times,
            // each pass followed by its alternative; with fewer alternatives
            // than passes the first one serves the extra passes. Read as a
            // repeat sign instead, a repeat that starts on a pickup or ends
            // mid-bar could not be unfolded bar by bar.
            //
            // `\relative` and the running duration are resolved on the text
            // as WRITTEN, before unfolding: every pass starts where the body
            // starts in the source, and each alternative where the item
            // written before it ends. Chained from the previous pass instead,
            // a body that climbs came back an octave higher each time.
            (Pitch, NoteDuration) at() => (_relativeBase, _currentDur);
            void go((Pitch, NoteDuration) st) {
              _relativeBase = st.$1;
              _currentDur = st.$2;
            }

            final bodyStart = at();
            (Pitch, NoteDuration)? bodyEnd;
            final altEnds = <int, (Pitch, NoteDuration)>{};
            for (var pass = 0; pass < count; pass++) {
              go(bodyStart);
              _processNodes([body]);
              bodyEnd ??= at();
              if (alts.isNotEmpty) {
                final extra = count - alts.length;
                final k = (pass <= extra ? 0 : pass - extra)
                    .clamp(0, alts.length - 1);
                go(k == 0 ? bodyEnd : altEnds[k - 1] ?? bodyEnd);
                _processNodes([alts[k]]);
                altEnds[k] ??= at();
              }
            }
            final last = alts.isEmpty ? bodyEnd : altEnds[alts.length - 1];
            if (last != null) go(last);
            continue;
          }
          if (type == 'unfold') {
            for (var pass = 0; pass < count; pass++) {
              _processNodes(
                  [body]); // written out N times; relative base continues
            }
          } else if (type == 'volta') {
            // Written once, as LilyPond prints it — but with its repeat
            // barlines and volta brackets, so playback can unfold it. They
            // were dropped: a binary dance played each half once, and
            // nothing downstream could even draw the repeat signs.
            _closeIfFull();
            if (_currentElements.isEmpty) {
              _startRepeatHere = true;
            } else {
              _pendingStartRepeat = true; // mid-bar: the nearest barline
            }
            _processNodes([body]);
            if (alts.isEmpty) _pendingEndRepeat = true;
            final endings = _alternativeEndings(count, alts, statedPasses);
            for (var k = 0; k < alts.length; k++) {
              _closeIfFull();
              final outer = _activeVolta;
              _activeVolta = endings[k];
              // An ending that begins mid-bar still owns the bar it ends in.
              _processNodes([alts[k]]);
              if (k < alts.length - 1) _pendingEndRepeat = true;
              if (_currentElements.isNotEmpty && !_closeIfFull()) {
                _pendingVolta ??= endings[k];
              }
              _activeVolta = outer;
            }
            continue;
          } else if (tremolo != null) {
            // `\repeat tremolo 8 c32` lasts eight 32nds and sounds as one
            // c4 (LilyPond's MIDI holds it); read once at the written value
            // it took an eighth of its time and every later note came early.
            _tremoloTimes = count;
            _tremoloSlashes = tremolo.slashes;
            _processNodes([body]);
            _tremoloTimes = 1;
            _tremoloSlashes = null;
          } else if (type == 'percent') {
            _readPercent(body, count);
          } else {
            _processNodes([body]);
          }
          for (final alt in alts) {
            _processNodes([alt]);
          }
        }
        continue;
      }
      if (node is LyScore) {
        _processNodes(node.contents);
      } else if (node is LyBlock) {
        if (_expectGrace) {
          // `\grace { b8 c8 }` — the WHOLE block is the grace group, so it is
          // collected in one go. Recursing would let only the first note be
          // diverted and turn the rest into real notes.
          _expectGrace = false;
          _collectGraces(node);
          continue;
        }
        _processNodes(node.children);
      } else if (node is LyCommand) {
        _processCommand(node);
      } else if (node is LyNote) {
        _processNote(node);
      } else if ((node is LyRest || node is LyChord) && _expectGrace) {
        // `\grace s8` (a grace spacer, which only makes room) and
        // `\grace <c e>8` take no time either. Read as a real spacer, the
        // `s8` pushed every later note of the voice an eighth late.
        _expectGrace = false;
        _collectGraces(node);
      } else if (node is LyRest) {
        _processRest(node);
      } else if (node is LyChord) {
        _processChord(node);
      } else if (node is LyWord) {
        // `q` repeats the previous chord's pitches with a new duration.
        // LilyPond writes a chord then `q4 q q8` to repeat it; we stored the
        // last pitches in `_lastPitches`. The duration may be explicit (`q4`,
        // `q4.`) or inherited, and a following sibling may carry it.
        final qMatch = _chordRepeat.firstMatch(node.value);
        if (qMatch != null && _lastPitches.isNotEmpty) {
          final durStr = qMatch.group(1);
          var qDur = _currentDur;
          if (durStr != null && durStr.isNotEmpty) {
            qDur = _runningDuration(durStr);
            _currentDur = qDur;
          } else if (idx + 1 < nodes.length && nodes[idx + 1] is LyWord) {
            final nxt = (nodes[idx + 1] as LyWord).value;
            if (RegExp(r'^\d+\.*(?:\*\d+(?:/\d+)?)?$').hasMatch(nxt)) {
              qDur = _runningDuration(nxt);
              _currentDur = qDur;
              idx++; // consume the duration sibling
            }
          }
          final id = 'e${_elementId++}';
          if (_awaitingOttavaStart) {
            _openOttavaFrom = id;
            _openOttavaDown = _pendingOttavaDown;
            _awaitingOttavaStart = false;
          }
          if (_openGlissFrom case final from? when from != id) {
            _glissandos.add(Glissando(from, id));
            _openGlissFrom = null;
          }
          _addAtRunning(
            qDur,
            id,
            (d, pieceId, _, last) => NoteElement(
              pitches: List.from(_lastPitches),
              duration: d,
              tieToNext: !last,
              id: pieceId,
            ),
          );
          _takeCue(id);
        } else if (node.value == '|') {
          _closeMeasure();
        } else if (node.value == r'\<' ||
            node.value == r'\>' ||
            node.value == r'\!') {
          _hairpinMark(node.value);
        } else if (node.value == '^' || node.value == '_') {
          // A text mark: `c4^"Eb"` above, `c4_"text"` below. The direction
          // arrives as its own word and the text as the NEXT node, so the
          // direction is remembered until that string shows up.
          _pendingAnnotationBelow = node.value == '_';
        }
      } else if (node is LyString) {
        final below = _pendingAnnotationBelow;
        _pendingAnnotationBelow = null;
        final id = _lastElementId();
        if (below != null && id != null && node.value.isNotEmpty) {
          _annotations.add(Annotation(
            id,
            node.value,
            placement:
                below ? AnnotationPlacement.below : AnnotationPlacement.above,
          ));
        }
      } else if (node is LyAssignment) {
        _variables[node.key] = node.value;
      } else if (node is LySimultaneous) {
        // `<< A \\ B >>` is PARALLEL VOICES. Split on the `\\` separators and
        // read each branch, so B lands in Measure.voice2 rather than being
        // discarded — the model has voice2..voice4 and MusicXML/kern/MuseScore
        // all preserve them.
        node = LySimultaneous(_withTagsApplied(node.children));
        final groups = <List<LyNode>>[<LyNode>[]];
        for (final child in node.children) {
          if (child is LyWord && child.value == '\\\\') {
            groups.add(<LyNode>[]);
          } else {
            groups.last.add(child);
          }
        }
        if (groups.length > 1) {
          _processParallelVoices(groups);
          continue;
        }
        // `<< \new Voice { … } \new Voice { … } >>` — explicit voices are
        // parallel too, exactly like `\\`. Read in sequence, the second voice
        // was appended after the first: a piano or guitar staff, or an SATB
        // hymn's soprano/alto, came back twice as long. Anything before the
        // first voice (`\global`, `\clef`, `\set`) goes with the first one.
        bool isVoice(LyNode n) {
          final t = _contextType(n);
          return t == 'Voice' || t == 'CueVoice' || t == 'TabVoice';
        }

        if (node.children.where(isVoice).length >= 2) {
          final voiceGroups = <List<LyNode>>[<LyNode>[]];
          var seenVoice = false;
          for (final child in node.children) {
            if (isVoice(child)) {
              if (seenVoice) voiceGroups.add(<LyNode>[]);
              seenVoice = true;
            }
            voiceGroups.last.add(seenVoice ? child : _settingsOnly(child));
          }
          // `\new Voice \global` — a "voice" of spacer rests carrying the
          // meter and bar lines — is settings, not a part: as voice 1 it put
          // invisible rests in the main voice and pushed the melody to voice 2.
          final musical = <List<LyNode>>[];
          var carried = <LyNode>[];
          for (final g in voiceGroups) {
            if (!g.any(_carriesNotes)) {
              carried.addAll(g.map(_settingsOnly));
            } else {
              musical.add([...carried, ...g]);
              carried = [];
            }
          }
          if (musical.isNotEmpty) musical.last.addAll(carried);
          if (musical.length < 2) {
            _processNodes(musical.isEmpty ? carried : musical.single);
            continue;
          }
          voiceGroups
            ..clear()
            ..addAll(musical);
          _processParallelVoices(voiceGroups);
          continue;
        }
        // `<< \transpose c' c \Treble \transpose c' c \Bass >>`, `<< { … }
        // { … } >>` — several plain expressions that each carry notes sound
        // TOGETHER as well. Sequential reading made a lute piece three times
        // its length. Note-less items (`\global`, `\clef`, lyrics) travel with
        // the next part, exactly as before the first explicit voice.
        // An expression right after a user-defined music function
        // (`\incipit \cantusIncipit`) is that function's ARGUMENT, not a part.
        // A staff among them (an ossia, `<< { cs4. } \new Staff { … } >>`)
        // sounds with the rest too; read after them, it made the voice late.
        final kids = node.children;
        bool startsPart(int k) =>
            _carriesNotes(kids[k]) &&
            !(k > 0 && _isSchemeFunctionCall(kids[k - 1]));
        final notey = [for (var k = 0; k < kids.length; k++) startsPart(k)]
            .where((b) => b);
        if (notey.length >= 2) {
          final parts = <List<LyNode>>[<LyNode>[]];
          var seen = false;
          for (var k = 0; k < kids.length; k++) {
            if (startsPart(k)) {
              if (seen) parts.add(<LyNode>[]);
              seen = true;
            }
            parts.last.add(seen ? kids[k] : _settingsOnly(kids[k]));
          }
          _processParallelVoices(parts);
          continue;
        }
        // No `\\` — a plain simultaneous container (e.g. the body of
        // `\new Staff = "x" << … >>`), read sequentially as before.
        // With one part carrying notes, the rest run alongside it: a
        // `<< \clef treble \global \upper >>` whose `global` is spacer rests
        // must not push `upper` back by the length of the piece.
        final oneMusical = node.children.any(_carriesNotes);
        bool mainVoice = true;
        for (var k = 0; k < node.children.length; k++) {
          final child = node.children[k];
          // Read one child at a time, an incipit's argument would lose the
          // call that consumes it (see [_isIncipitCall]).
          if (k > 0 && _isIncipitCall(node.children[k - 1])) continue;
          if (child is LyWord && child.value == '\\\\') {
            mainVoice = false;
          }
          if (mainVoice) {
            _processNodes([
              oneMusical && !_carriesNotes(child) ? _settingsOnly(child) : child
            ]);
          } else {
            void runLyricsCommands(LyNode n) {
              if (n is LyCommand) {
                if (['addlyrics', 'lyricsto', 'lyricmode'].contains(n.name)) {
                  final syllables = <String>[];
                  for (final arg in n.args) {
                    syllables.addAll(_extractLyricsSyllables(arg));
                  }
                  if (syllables.isNotEmpty) _alignLyrics(syllables);
                } else if (n.name == 'new' || n.name == 'with') {
                  for (final arg in n.args) {
                    runLyricsCommands(arg);
                  }
                }
              } else if (n is LyBlock) {
                for (final c in n.children) {
                  runLyricsCommands(c);
                }
              }
            }

            runLyricsCommands(child);
          }
        }
      }
    }
  }

  /// A note-less shared prefix (`\global`) placed before parallel voices,
  /// keeping its settings (`\key`, `\time`, `\partial`, `\clef`) but not its
  /// spacer rests or bar lines. Read in front of the first voice, a `global`
  /// of `s4 | \skip 2.*3 | …` pushed the whole melody back by the length of
  /// the piece: every such hymn came back twice as long.
  LyNode _settingsOnly(LyNode node, [int depth = 0]) {
    if (_carriesNotes(node) || depth > 12) return node;
    LyNode? strip(LyNode n) {
      // A figure, chord-name or lyric track keeps its spacers: they are what
      // places each figure under its note.
      if (_isTextTrack(n)) return n;
      if (n is LyRest) return null;
      if (n is LyCommand &&
          (n.name == 'skip' || n.name == 'bar' || n.name == 'mark')) {
        return null;
      }
      if (n is LyBlock) return LyBlock([...n.children.map(strip).nonNulls]);
      if (n is LySimultaneous) {
        return LySimultaneous([...n.children.map(strip).nonNulls]);
      }
      if (n is LyCommand && n.args.isEmpty && !_isSchemeFunctionCall(n)) {
        final v = _variables[n.name];
        if (v != null) return _settingsOnly(v, depth + 1);
      }
      if (n is LyCommand && n.args.isNotEmpty) {
        return LyCommand(n.name, [...n.args.map(strip).nonNulls]);
      }
      return n;
    }

    return strip(node) ?? const LyBlock([]);
  }

  /// Whether [node] calls a music function the file defines itself
  /// (`incipit = #(define-music-function …)`).
  bool _isSchemeFunctionCall(LyNode node) {
    if (node is! LyCommand || node.args.isNotEmpty) return false;
    final v = _variables[node.name];
    return v is LyWord && v.value.contains('-function');
  }

  /// Whether [node] calls the Mutopia/LSR `incipit` music function, which
  /// typesets its music argument as the staff's instrument name. Other user
  /// functions may return their argument as real music, so only this idiom
  /// (by name, or by a body that builds an `InstrumentName` stencil) has its
  /// argument dropped.
  bool _isIncipitCall(LyNode node) {
    if (!_isSchemeFunctionCall(node)) return false;
    final name = (node as LyCommand).name.toLowerCase();
    final body = (_variables[node.name] as LyWord).value;
    return name.contains('incipit') || body.contains('InstrumentName');
  }

  /// A lyric, chord-name, figured-bass or drum track — music-shaped, but not
  /// notes of this staff.
  static bool _isTextTrack(LyNode node) {
    if (node is! LyCommand) return false;
    const modes = {
      'addlyrics', 'lyricsto', 'lyricmode', 'lyrics', 'chordmode', //
      'chords', 'figuremode', 'figures', 'drummode',
    };
    const contexts = {
      'Lyrics', 'ChordNames', 'FiguredBass', 'Dynamics', 'NoteNames', //
      'DrumStaff', 'DrumVoice',
    };
    return modes.contains(node.name) ||
        ((node.name == 'new' || node.name == 'context') &&
            contexts.contains(_contextType(node)));
  }

  /// Whether [node] holds a `\chordmode` / `\chords` block, looking through
  /// blocks, commands and variables.
  bool _holdsChordMode(LyNode node, [int depth = 0]) {
    if (depth > 12) return false;
    return switch (node) {
      LyCommand(name: 'chordmode' || 'chords') => true,
      LyCommand(:final name, args: []) when _variables[name] != null =>
        _holdsChordMode(_variables[name]!, depth + 1),
      LyCommand(:final args) => args.any((a) => _holdsChordMode(a, depth + 1)),
      LyBlock(:final children) ||
      LySimultaneous(:final children) =>
        children.any((c) => _holdsChordMode(c, depth + 1)),
      _ => false,
    };
  }

  /// Whether [node] holds notes of its own (not lyrics, chord names or
  /// figures), looking through variables and wrapper commands.
  bool _carriesNotes(LyNode node, [int depth = 0]) {
    if (depth > 12) return false;
    if (node is LyNote || node is LyChord) return true;
    if (node is LyWord && _chordRepeat.hasMatch(node.value)) return true;
    if (node is LyBlock) {
      return node.children.any((c) => _carriesNotes(c, depth + 1));
    }
    if (node is LySimultaneous) {
      return node.children.any((c) => _carriesNotes(c, depth + 1));
    }
    if (node is LyCommand) {
      const notNotes = {
        'addlyrics', 'lyricsto', 'lyricmode', 'lyrics', 'chordmode', //
        'chords', 'figuremode', 'figures', 'drummode', 'markup', //
        'key', 'set', 'override', 'tempo', 'mark', 'clef', 'time',
        // `\transposition c` names the instrument's pitch; it plays nothing.
        'transposition',
      };
      if (notNotes.contains(node.name) || _isTextTrack(node)) return false;
      // The pitch arguments of `\transpose`/`\relative` are not music.
      final skip = switch (node.name) {
        'transpose' => 2,
        'relative' => node.args.isNotEmpty && node.args.first is LyNote ? 1 : 0,
        _ => 0,
      };
      if (node.args.skip(skip).any((c) => _carriesNotes(c, depth + 1))) {
        return true;
      }
      final v = node.args.isEmpty ? _variables[node.name] : null;
      return v != null && _carriesNotes(v, depth + 1);
    }
    return false;
  }

  /// Reads `<< A \\ B \\ C >>` — each group becomes one voice of the measures
  /// it spans.
  ///
  /// Every branch starts from the SAME musical state (relative reference,
  /// current duration), because in LilyPond the voices run concurrently from
  /// the context as it stood at the `<<`. After the construct, state continues
  /// from the FIRST voice, which is the one whose notes occupy `elements`.
  ///
  /// Extra voices are read into a scratch accumulator and then merged into the
  /// measures voice 1 produced. A branch longer than voice 1 keeps its overflow
  /// as new measures rather than dropping it — losing music silently is exactly
  /// the failure this replaces.
  void _processParallelVoices(List<List<LyNode>> groups) {
    // Where the group begins. A split can start MID-BAR, so the bar in
    // progress, how much of it is already filled, and what earlier splits put
    // in its inner voices are all part of that position.
    final startMeasure = _measures.length;
    final startPrefix = List<MusicElement>.from(_currentElements);
    // How long that is, tuplets counted: a triplet's notes take two thirds
    // of their written values.
    final prefixProbe = Measure(startPrefix, tuplets: [
      for (final t in _currentTuplets)
        if (t.voice == 0 && t.endIndex < startPrefix.length) t,
    ]);
    final prefixTime = [
      for (var i = 0; i < startPrefix.length; i++)
        prefixProbe.effectiveDurationAt(i),
    ].fold(Fraction.zero, (a, b) => a + b);
    // ⚠️ NOT derivable from `startPrefix`. `\partial` implements the anacrusis
    // by PRELOADING elapsed time (a 4/4 bar with `\partial 4` starts at 3/4),
    // so rewinding a branch to zero would hand it a full bar and the pickup
    // would swallow the next three beats of voice 2.
    final startTime = _measureTime;
    final startMeter = (_time, _pendingTimeChange, _timeChangeIsForNextMeasure);
    final initialBefore = _initialTime;
    final startPending = {
      for (final e in _pendingVoices.entries)
        e.key: List<MusicElement>.from(e.value),
    };
    final startPendingTuplets = List<TupletSpan>.from(_pendingVoiceTuplets);
    final baseIsRelative = _isRelative;
    final before = List<Measure>.from(_measures);
    final partialsBefore = _lastPartial.$1;
    final elementsBefore = _elementId;

    // Voice 1 runs normally and is deliberately NOT closed. Closing here is
    // what used to invent a barline: `<< … >> r4 << … >>` is ONE bar of 4/4,
    // and forcing a close after each group read it as three. Bars now end only
    // when they fill, via _checkMeasureBoundary.
    _parallelDepth++;
    _processNodes(groups.first);

    final afterMeasures = List<Measure>.from(_measures);
    final afterElements = List<MusicElement>.from(_currentElements);
    final afterTuplets = List<TupletSpan>.from(_currentTuplets);
    final afterTime = _measureTime;
    final afterMeter = (_time, _pendingTimeChange, _timeChangeIsForNextMeasure);
    // `\time` sets the Score's timing, as `\partial` does: a meter change
    // voice 1 makes takes effect in every voice at that bar. Read alone, the
    // other voices kept the old meter — or started in voice 1's LAST one —
    // and barred their music to it.
    final outerShared = _sharedMeters;
    final shared = <int, TimeSignature>{
      ...outerShared,
      if (startPrefix.isEmpty && afterMeasures.length > startMeasure)
        if (afterMeasures[startMeasure].timeChange case final t?)
          startMeasure: t,
      for (var i = startMeasure + 1; i < afterMeasures.length; i++)
        if (afterMeasures[i].timeChange case final t?) i: t,
      if (afterMeasures.length > startMeasure) afterMeasures.length: _time,
      if (_timeChangeIsForNextMeasure && _pendingTimeChange != null)
        afterMeasures.length + 1: _pendingTimeChange!,
    };
    // Voice 1's own inner voices in the bar still open (a `<< … \\ … >>`
    // inside it) — dropping these lost the lower notes of every such split.
    final afterPending = {
      for (final e in _pendingVoices.entries)
        e.key: List<MusicElement>.from(e.value),
    };
    final afterPendingTuplets = List<TupletSpan>.from(_pendingVoiceTuplets);
    // `\partial` sets the Score's timing, not one voice's: a pickup voice 1
    // declares before its first note (often via a shared `\global`, or the
    // soprano of a `\partcombine`) times every voice. Rewinding the others
    // to a full bar put each later note of theirs a bar's remainder late.
    var branchStart = startTime;
    final (partials, partialAt, preload) = _lastPartial;
    if (partials != partialsBefore &&
        partialAt == elementsBefore &&
        startPrefix.isEmpty) {
      branchStart = preload;
    }
    // `\relative` runs through `<< … >>` in plain TEXT order (checked against
    // LilyPond 2.24): each branch starts from where the previous one ENDED,
    // and the music after `>>` continues from the LAST branch. The default
    // duration is lexical too, so it chains the same way.
    //
    // Two wrong rules were tried before. Continuing from the FIRST branch made
    // the reference creep upward on every split (the Banister piano part
    // climbed to MIDI 171); restarting every branch from the `<<` state put
    // inner voices and the following bar an octave off whenever a branch
    // moved far — Horetzky's guitar studies read a whole octave high.
    var chainRelative = _relativeBase;
    var chainDur = _currentDur;
    final afterIsRelative = _isRelative;

    // Read each remaining branch from the group's START position, collecting its
    // bars plus whatever it leaves open. Branches are read in isolation and
    // merged afterwards, so none can disturb another.
    // Per bar, each voice the branch produced: its main line first, then any
    // inner voices of its own (with the tuplet spans addressing each).
    final branches =
        <int, List<List<(List<MusicElement>, List<TupletSpan>)>>>{};
    for (var g = 1; g < groups.length && g <= 3; g++) {
      _measures
        ..clear()
        ..addAll(before);
      _currentElements.clear();
      _currentTuplets.clear();
      _pendingVoices.clear();
      _pendingVoiceTuplets.clear();
      // Rewind to the group's bar position, preload included, and its meter.
      _measureTime = branchStart;
      _restoreMeter(startMeter);
      _sharedMeters = shared;
      // The piece's opening meter, stated in voice 1 (a shared `\global`).
      if (initialBefore == null && _initialTime != null) _time = _initialTime!;
      if (shared[startMeasure] case final t? when startPrefix.isEmpty) {
        _time = t;
      }
      // Occupy the bar up to the split so this branch's notes land at voice 1's
      // offsets. Whatever this voice already sang earlier in the bar comes
      // first; the rest is silence, which is what an inner voice renders there.
      // These are POSITIONS ONLY — `_measureTime` already accounts for them.
      final carried = startPending[g] ?? const <MusicElement>[];
      _currentElements.addAll(carried);
      // Its tuplets come too: carried without them, an earlier split's
      // triplets in this bar went back to full value when this branch
      // replaced the voice (`<< e2 \\ \times 2/3 { … } >>` twice in a bar).
      final carriedTuplets = [
        for (final t in startPendingTuplets)
          if (t.voice == g)
            TupletSpan(t.startIndex, t.endIndex,
                actual: t.actual, normal: t.normal, hidden: t.hidden),
      ];
      _currentTuplets.addAll(carriedTuplets);
      final carriedProbe = Measure(carried, tuplets: carriedTuplets);
      var covered = [
        for (var i = 0; i < carried.length; i++)
          carriedProbe.effectiveDurationAt(i),
      ].fold(Fraction.zero, (a, b) => a + b);
      // ⚠️ These spacer rests align an inner voice to where its `\\` split
      // began, and they were the ONLY elements this reader left without an
      // id — 33 of 181 in one corpus file. That is not cosmetic: a span
      // cannot attach to an id-less element, every index-based comparison
      // shifts from that point on, and `scoreToMidi` silently DROPS notes
      // with a null id, so inner voices read from `.ly` never reached MIDI.
      //
      // They fill exactly the time voice 1 has taken. One rest per element
      // of voice 1 instead ran long after a triplet (each rest at the
      // triplet note's written value) and overshot what this voice carried
      // in from earlier in the bar.
      final gap = prefixTime - covered;
      final asWritten = covered == Fraction.zero &&
          startPrefix.fold(Fraction.zero,
                  (Fraction a, e) => a + e.duration.toFraction()) ==
              prefixTime;
      final spelled =
          gap > Fraction.zero && !asWritten ? _spaceDurations(gap) : null;
      if (spelled != null) {
        for (final d in spelled) {
          _currentElements
              .add(RestElement(d, id: 'e${_elementId++}', hidden: true));
        }
      } else {
        // One rest per element of voice 1, as written, when that is exact
        // (or when no run of note values spells the gap).
        for (final e in startPrefix) {
          if (!(covered < prefixTime)) break;
          _currentElements.add(
              RestElement(e.duration, id: 'e${_elementId++}', hidden: true));
          covered = covered + e.duration.toFraction();
        }
      }
      _relativeBase = chainRelative;
      _isRelative = baseIsRelative;
      _currentDur = chainDur;

      // A branch written `\new Voice = "v1" { … }` names itself; record it so
      // a later `\lyricsto "v1"` can find which voice it became.
      for (final n in groups[g]) {
        final name = _contextName(n);
        if (name != null) _voiceNames[name] = g;
      }
      _processNodes(groups[g]);
      chainRelative = _relativeBase;
      chainDur = _currentDur;

      List<TupletSpan> spansOf(List<TupletSpan> all, int v) => [
            for (final t in all)
              if (t.voice == v) t
          ];
      branches[g] = [
        for (var i = startMeasure; i < _measures.length; i++)
          [
            for (var v = 0; v < 4; v++)
              (_measures[i].voiceAt(v), spansOf(_measures[i].tuplets, v)),
          ],
        [
          (
            List<MusicElement>.from(_currentElements),
            List<TupletSpan>.from(_currentTuplets)
          ),
          for (final MapEntry(key: v, value: els) in _pendingVoices.entries)
            (List<MusicElement>.from(els), spansOf(_pendingVoiceTuplets, v)),
        ],
      ];
    }

    // Restore voice 1, then fold each branch in as an inner voice.
    _measures
      ..clear()
      ..addAll(afterMeasures);
    _currentElements
      ..clear()
      ..addAll(afterElements);
    _currentTuplets
      ..clear()
      ..addAll(afterTuplets);
    _measureTime = afterTime;
    _restoreMeter(afterMeter);
    _sharedMeters = outerShared;
    // Keep what earlier groups in this bar contributed, and what voice 1's
    // own inner voices put in it. A branch that reaches the open bar replaces
    // its OWN slot — its output already carries that earlier content, seeded
    // above — and leaves the other voices alone.
    _pendingVoices
      ..clear()
      ..addAll(afterPending);
    _pendingVoiceTuplets
      ..clear()
      ..addAll(afterPendingTuplets);
    // Slots voice 1 filled itself in the open bar (beyond what it inherited).
    final openTaken = <int>{
      for (final MapEntry(key: v, value: els) in afterPending.entries)
        if (els.isNotEmpty && els.length != (startPending[v]?.length ?? 0)) v,
    };
    final overflowAt = <int, Measure>{};

    for (final entry in branches.entries) {
      final g = entry.key;
      for (var i = 0; i < entry.value.length; i++) {
        final target = startMeasure + i;
        final Set<int> taken;
        if (target < _measures.length) {
          taken = {
            for (var v = 1; v < 4; v++)
              if (_measures[target].voiceAt(v).isNotEmpty) v,
          };
        } else if (target == _measures.length) {
          taken = openTaken;
        } else {
          final m = overflowAt[target];
          taken = {
            if (m != null)
              for (var v = 1; v < 4; v++)
                if (m.voiceAt(v).isNotEmpty) v,
          };
        }
        final sources = entry.value[i];
        for (var k = 0; k < sources.length; k++) {
          final (elements, tuplets) = sources[k];
          if (elements.isEmpty) continue;
          // The branch's main line goes to its own voice; its inner voices,
          // or a main line whose voice is already used — voice 1 can have
          // inner voices of its own — to the first voice still free.
          // Overwriting one silently dropped those notes.
          // Its own voice holding only what the branch itself carried in from
          // earlier in the bar (seeded above) is not taken: the branch's
          // output is that content and more.
          final existing = target < _measures.length
              ? _measures[target].voiceAt(g)
              : (target == _measures.length
                  ? _pendingVoices[g] ?? const <MusicElement>[]
                  : const <MusicElement>[]);
          final ids = {for (final e in elements) e.id};
          final own = existing.every((e) => ids.contains(e.id));
          int? slot = k == 0 && (own || !taken.contains(g)) ? g : null;
          for (var v = 1; slot == null && v < 4; v++) {
            if (!taken.contains(v)) slot = v;
          }
          if (slot == null) {
            if (k != 0) continue;
            // Every slot is in use. A line of nothing but spacers (a voice
            // resting through this bar) has nothing to keep; written over
            // a slot, it erased the notes of an inner voice already there.
            if (elements.every((e) => e is RestElement && e.hidden)) continue;
            slot = g;
          }
          final v = slot;
          taken.add(v);
          // Tuplet spans address a voice by index, so they must travel WITH the
          // notes and be re-pointed at the voice they landed in. Dropping them
          // leaves tupleted notes counting at full value — the round-trip
          // catches it as a sounding-total drift, not as a missing note.
          final spans = [
            for (final t in tuplets)
              TupletSpan(t.startIndex, t.endIndex,
                  actual: t.actual,
                  normal: t.normal,
                  voice: v,
                  hidden: t.hidden),
          ];
          Measure withVoice(Measure m) => switch (v) {
                1 => m.copyWith(voice2: elements),
                2 => m.copyWith(voice3: elements),
                _ => m.copyWith(voice4: elements),
              }
                  .copyWith(tuplets: [
                for (final t in m.tuplets)
                  if (t.voice != v) t,
                ...spans,
              ]);
          if (target < _measures.length) {
            _measures[target] = withVoice(_measures[target]);
          } else if (target == _measures.length) {
            // Lands in the bar still being filled — hold it until that closes.
            _pendingVoices[v] = List<MusicElement>.from(elements);
            _pendingVoiceTuplets
              ..removeWhere((t) => t.voice == v)
              ..addAll(spans);
          } else {
            // This branch runs longer than voice 1 (voices need not fill the
            // same number of bars). Keep the overflow in ITS OWN voice —
            // appending it as `elements` would silently promote inner-voice
            // notes to voice 1 and inflate the bar's sounding duration. It is
            // QUEUED rather than appended, because voice 1's bar is still open
            // and would otherwise close behind it.
            overflowAt[target] =
                withVoice(overflowAt[target] ?? Measure(const []));
          }
        }
      }
    }
    final overflowKeys = overflowAt.keys.toList()..sort();
    _pendingOverflow.addAll([for (final k in overflowKeys) overflowAt[k]!]);

    _relativeBase = chainRelative;
    _isRelative = afterIsRelative;
    _currentDur = chainDur;
    _parallelDepth--;
  }

  void _processCommand(LyCommand cmd) {
    // `\trill`, `\fermata`, `\upbow` … belong to the note BEFORE them and
    // arrive as a sibling, not as one of that note's scripts. Handled first so
    // the switch below stays about structure.
    if (cmd.args.isEmpty && _attachToPrevious(cmd.name)) return;
    switch (cmd.name) {
      case 'relative':
        final oldRelative = _isRelative;
        final oldBase = _relativeBase;
        _isRelative = true;
        // With no start pitch, LilyPond reckons the first note from f (the f
        // below middle C), so its octave marks read as absolute ones:
        // `\relative { a' … }` starts on A4. Keeping whatever base came
        // before (c, by default) put such a voice an octave low.
        _relativeBase = relativeFromMiddleC
            ? const Pitch(Step.c, octave: 4)
            : const Pitch(Step.f, octave: 3);

        LyNode? block;
        if (cmd.args.isNotEmpty) {
          final first = cmd.args.first;
          if (first is LyWord) {
            _relativeBase = _parsePitch(first.value);
            if (cmd.args.length > 1) block = cmd.args[1];
          } else if (first is LyNote) {
            _relativeBase = _parsePitch(first.pitch);
            if (cmd.args.length > 1) block = cmd.args[1];
          } else {
            // `\relative { … }`, and any other music expression with no
            // start pitch: `\relative \new Staff { … }` read as nothing.
            block = first;
          }
        }

        if (block != null) {
          _processNodes([block]);
          _isRelative = oldRelative;
          _relativeBase = oldBase;
        } else {
          // No body in the args means the parser split it off as a SIBLING, so
          // relative mode must stay live for the nodes that follow. Record that
          // the state is owed a restore at the end of this assignment —
          // otherwise it leaks into the NEXT variable, and a four-voice score
          // reads its first voice correctly and drifts on the rest.
          _pendingRelativeRestore = (oldRelative, oldBase);
        }
        break;
      // Grace notes PREFIX their principal, so they are collected and attached
      // when the next note arrives. The writer has always emitted these; the
      // reader did not know them, so it read each grace as a full note —
      // inflating the note count and shifting every pitch after it. That
      // asymmetry is invisible to a self round-trip and showed up only when
      // real files were driven through the writer/reader pair.
      case 'acciaccatura':
      case 'appoggiatura':
      case 'slashedGrace':
      case 'grace':
        _pendingGraceStyle = cmd.name == 'appoggiatura'
            ? GraceStyle.appoggiatura
            : GraceStyle.acciaccatura;
        if (cmd.args.isEmpty) {
          // The parser splits a command's operand off as a SIBLING (the same
          // shape as `\relative`), so there is nothing to read here — mark the
          // next note as the grace instead.
          _expectGrace = true;
        } else {
          for (final arg in cmd.args) {
            _collectGraces(arg);
          }
        }
        break;
      case 'clef':
        String? name;
        if (cmd.args.isNotEmpty && cmd.args.first is LyString) {
          name = (cmd.args.first as LyString).value;
        } else if (cmd.args.isNotEmpty && cmd.args.first is LyWord) {
          name = (cmd.args.first as LyWord).value;
        }
        // Only the first staff's clefs are this score's — see [_staffLeavesSeen].
        if (name != null && _staffLeavesSeen <= 1) {
          final clef = switch (name) {
            'bass' => Clef.bass,
            'alto' => Clef.alto,
            'tenor' => Clef.tenor,
            _ => Clef.treble,
          };
          if (_measures.isEmpty && _currentElements.isEmpty) {
            _clef = clef; // still before any music: this IS the score clef
          } else if (clef != _clef) {
            // POSITION decides: at a barline it is a measure-level change, and
            // anywhere else a mid-bar one at its own onset.
            _initialClef ??= _clef;
            if (_currentElements.isEmpty) {
              _pendingClefChange = clef;
            } else {
              _pendingInlineClefs.add(InlineClefChange(_measureTime, clef));
            }
            _clef = clef;
          }
        }
        break;
      case 'numericTimeSignature':
        _numericTimeSig = true;
        break;
      case 'defaultTimeSignature':
        _numericTimeSig = false;
        break;
      case 'time':
        // ⚠️ `\time` RESETS the bar length in LilyPond, so a
        // `Timing.measureLength` set for an earlier irregular bar must not
        // outlive it — otherwise every bar after a meter change keeps the old
        // override and the piece re-bars from there.
        _measureLengthOverride = null;
        if (cmd.args.isNotEmpty && cmd.args.first is LyWord) {
          final parts = (cmd.args.first as LyWord).value.split('/');
          if (parts.length == 2) {
            final n = int.tryParse(parts[0]);
            final d = int.tryParse(parts[1]);
            if (n != null && d != null) {
              // ⚠️ LilyPond draws 4/4 as C and 2/2 as cut-C BY DEFAULT; the
              // numerals only appear after `\numericTimeSignature`, which is
              // sticky until `\defaultTimeSignature`. The reader ignored both,
              // so every common-time score — most 4/4 music there is — came
              // back as a numeric 4/4 and lost its glyph.
              final symbol = _numericTimeSig
                  ? TimeSymbol.numeric
                  : (n == 4 && d == 4
                      ? TimeSymbol.common
                      : (n == 2 && d == 2
                          ? TimeSymbol.cut
                          : TimeSymbol.numeric));
              final parsed = TimeSignature.tryParse(n, d, symbol: symbol) ??
                  TimeSignature.commonTime;
              if (_initialTime == null) {
                _initialTime = parsed;
                _time = parsed;
              } else {
                // ⚠️ A RESTATED meter is recorded, not suppressed — see the
                // note in the kern reader. `layout_engine` guards
                // `timeChange != _time` before DRAWING one, so a redundant
                // restatement cannot print a spurious meter.
                _pendingTimeChange = parsed;
                // Notes already in this bar means the bar was written under the
                // OLD meter, so the change opens the next one — and the running
                // capacity must not move until then either.
                _timeChangeIsForNextMeasure = _currentElements.isNotEmpty;
                if (!_timeChangeIsForNextMeasure) _time = parsed;
              }
            }
          }
        }
        break;
      case 'key':
        // \key f \major  ->  KeySignature. tonic = args[0], mode = args[1].
        if (cmd.args.isNotEmpty) {
          final t = cmd.args.first;
          final tonic = t is LyWord ? t.value : (t is LyNote ? t.pitch : null);
          var major = true;
          if (cmd.args.length > 1) {
            final m = cmd.args[1];
            final mode = m is LyCommand ? m.name : (m is LyWord ? m.value : '');
            major = !(mode == 'minor' ||
                mode == 'moll' ||
                mode == 'aeolian' ||
                mode == 'dorian' ||
                mode == 'phrygian');
          }
          if (tonic != null && _staffLeavesSeen <= 1) {
            final p = _transposed(_parsePitch(tonic));
            final key = KeySignature(_fifthsFor(p.step, p.alter, major));
            // POSITION decides, and the staff scope applies for the same
            // reason as clefs: every staff carries its own `\key`, so reading
            // them all turns a transposing part into a phantom key change.
            if (_measures.isEmpty && _currentElements.isEmpty) {
              _key = key; // still before any music: this IS the score key
            } else if (key != _key) {
              _initialKey ??= _key;
              _pendingKeyChange = key;
              _key = key;
            }
          }
        }
        break;
      case 'partial':
        // Anacrusis: preload elapsed time so the first auto-barline falls right
        // after the pickup (LilyPond emits no explicit '|' for it).
        if (cmd.args.isNotEmpty) {
          // A mid-piece `\partial` opens a new bar: one already full closes
          // first, or the preload rewound it and the two bars merged.
          _closeIfFull();
          final a = cmd.args.first;
          final durStr = a is LyWord
              ? a.value
              : (a is LyNote ? (a.duration ?? a.pitch) : '');
          final partial = _parseDuration(durStr).toFraction();
          // Mid-piece (`\partial 8*3` before a short last bar), it starts a
          // bar: the one before it ends here. Left open, the short bar's
          // notes were packed into the full bar before it.
          if (_currentElements.isNotEmpty) _closeMeasure();
          final cap = Fraction(_time.beats, _time.beatUnit);
          final remaining = cap - partial;
          _measureTime = remaining > Fraction.zero ? remaining : Fraction.zero;
          _lastPartial = (_lastPartial.$1 + 1, _elementId, _measureTime);
          if (_measures.isEmpty && _currentElements.isEmpty) {
            _leadingPickup ??= (_time, partial);
          }
          // The bar it opens IS a pickup. Preloading the time alone made the
          // anacrusis fall in the right place and then lose the flag saying it
          // was one, so the writer could not mark it again.
          _pendingPickup = true;
        }
        break;
      case 'chordmode' when _chordNamesDepth == 0:
        // `\chordmode` in a staff's own music, outside any ChordNames, is
        // CHORDS ON THE STAFF: LilyPond engraves and plays their notes (an
        // accompaniment written as `c:6^5 r c:6^5`). Read as chord names,
        // they were lost and the piece ended early.
        _processChordModeNotes(cmd.args);
        break;
      case 'chordmode':
      case 'chords':
        // 🔴 A chord track is NOT melody, and must never reach the note stream —
        // that is why this block is consumed rather than walked. But it carries
        // exactly what a lead sheet wants, and we were throwing it away: 285
        // corpus `.ly` files (all 238 Ebersberger songs among them) name their
        // chords here. Collect them as SYMBOLS, anchored later by elapsed time,
        // and still add no notes.
        _collectChordTrack(cmd.args);
        break;
      case 'figuremode':
      case 'figures':
        // A figured-bass track is not melody, so the block is CONSUMED rather
        // than walked — but it carries exactly what continuo needs, and the
        // model has held `Score.figuredBass` all along.
        for (final a in cmd.args) {
          if (a is LyBlock) _collectFigureTrack(a.children);
        }
        break;
      case 'drummode':
        // A drum track is not melody either, and there is no model for it yet
        // — skip so it does not inflate the note stream.
        break;
      case 'addlyrics':
      case 'lyricsto':
      case 'lyricmode':
        // ⚠️ `\lyricsto "Melodie" \Text` names the VOICE in its first
        // argument. Reading it as a syllable put the voice name at the head of
        // the lyric line and pushed every real syllable onto the NEXT note — a
        // silent misalignment of the whole verse, not a stray word.
        // ⚠️ `\lyricsto "v1"` names WHICH voice the lyrics belong to.
        // Ignoring it aligned every lyric stream to voice 1, so a staff
        // carrying two sung parts kept only the first one's words.
        var voice = 0;
        final args = cmd.name == 'lyricsto' && cmd.args.isNotEmpty
            ? cmd.args.sublist(1)
            : cmd.args;
        if (cmd.name == 'lyricsto' && cmd.args.isNotEmpty) {
          final target = cmd.args.first;
          final name = target is LyString
              ? target.value
              : (target is LyWord ? target.value : '');
          voice = _voiceNames[name] ?? 0;
        }
        final syllables = _extractLyricsList(args);
        if (syllables.isNotEmpty) {
          _alignLyrics(syllables, voice: voice);
        }
        break;
      case 'tuplet':
      case 'times':
        Fraction ratio = Fraction(1, 1);
        int actual = 3;
        int normal = 2;
        if (cmd.args.isNotEmpty && cmd.args.first is LyWord) {
          final parts = (cmd.args.first as LyWord).value.split('/');
          if (parts.length == 2) {
            final n = int.tryParse(parts[0]);
            final d = int.tryParse(parts[1]);
            if (n != null && d != null) {
              if (cmd.name == 'tuplet') {
                ratio = Fraction(d, n);
                actual = n;
                normal = d;
              } else {
                ratio = Fraction(n, d);
                actual = d;
                normal = n;
              }
            }
          }
        }

        LyNode? block;
        if (cmd.args.length > 1 && cmd.args.last is! LyWord) {
          block = cmd.args.last; // after an optional span duration
        }
        if (block != null) {
          final oldRatio = _tupletRatio;
          // A tuplet inside a tuplet sounds both ratios: its notes' spans nest,
          // and the clock runs at the product.
          _tupletRatio = oldRatio * ratio;
          final startIndex = _currentElements.length;
          final startMeasure = _measures.length;

          _processNodes([block]);

          final endIndex = _currentElements.length - 1;
          if (_measures.length == startMeasure) {
            // The whole group stayed inside one bar — the common case.
            if (endIndex >= startIndex) {
              _currentTuplets.add(TupletSpan(startIndex, endIndex,
                  actual: actual, normal: normal));
            }
          } else {
            // The bar filled mid-group, so the notes were split across
            // measures. A tuplet may legitimately straddle a barline; emit ONE
            // SPAN PER MEASURE it touches.
            //
            // Previously the single span was built from a startIndex belonging
            // to the old measure and an endIndex belonging to the new one, so
            // `endIndex >= startIndex` failed and the span was dropped whole —
            // leaving every note in the group counting at FULL value. That is a
            // sounding-duration error, not a missing note, so it is invisible
            // to a note-count check.
            final head = _measures[startMeasure];
            if (head.elements.length - 1 >= startIndex) {
              _measures[startMeasure] = head.copyWith(tuplets: [
                ...head.tuplets,
                TupletSpan(startIndex, head.elements.length - 1,
                    actual: actual, normal: normal),
              ]);
            }
            for (var mi = startMeasure + 1; mi < _measures.length; mi++) {
              final mid = _measures[mi];
              if (mid.elements.isEmpty) continue;
              _measures[mi] = mid.copyWith(tuplets: [
                ...mid.tuplets,
                TupletSpan(0, mid.elements.length - 1,
                    actual: actual, normal: normal),
              ]);
            }
            if (endIndex >= 0) {
              _currentTuplets
                  .add(TupletSpan(0, endIndex, actual: actual, normal: normal));
            }
          }

          _tupletRatio = oldRatio;
        }
        break;
      case 'scaleDurations':
      case 'compressMusic':
        // `\scaleDurations 3/2 { … }` (`\compressMusic #'(3 . 2)` before 2.12)
        // multiplies every duration inside by the fraction and prints nothing:
        // the classic way to set a 2/4 line against a 6/8 accompaniment.
        // Each note gets a HIDDEN span of the ratio (see [_addAtRunning]), so
        // a `\times` inside it nests in that span and sounds both ratios.
        //
        // ⚠️ Unknown, the command was skipped and its music read at the written
        // values: a song's whole vocal line ended two thirds of the way
        // through its accompaniment.
        final factor = cmd.args.isEmpty ? null : _scaleFactor(cmd.args.first);
        final body = cmd.args.length > 1 ? cmd.args.last : null;
        if (body == null) break;
        final oldScale = _durationScale;
        if (factor != null) _durationScale = oldScale * factor;
        _processNodes([body]);
        _durationScale = oldScale;
        break;
      case 'transpose':
        // `\transpose <from> <to> { music }` — read the music, moved by the
        // interval from→to (octave marks included: `\transpose c c'` is an
        // octave up). Nested transpositions add up.
        //
        // ⚠️ It used to read at WRITTEN pitch, which put every hymn written
        // `\transpose g f { … }` a tone sharp and, with an octave in the pair,
        // a whole octave off — invisible to a note count, glaring to the ear.
        //
        // The body may be a command rather than a block — `\transpose f g
        // \relative c'' { … }` is the common spelling. The two pitch arguments
        // parse as notes, so forwarding commands as well cannot re-admit them.
        //
        // A pitch may be a variable (`target = a,` … `\transpose c \target`):
        // read as music, its pitch sounded as a note and the music went
        // untransposed.
        final outerTranspose = _transposition;
        LyNode pitchArg(LyNode a) => switch (a) {
              LyCommand(:final name, args: [])
                  when _variables[name] is LyNote =>
                _variables[name]!,
              _ => a,
            };
        final pitchArgs = [
          for (final a in cmd.args.take(2).map(pitchArg))
            if (a is LyNote) a.pitch else if (a is LyWord) a.value
        ];
        if (pitchArgs.length == 2) {
          final from = _parsePitch(pitchArgs[0]);
          final to = _parsePitch(pitchArgs[1]);
          _transposition = (
            outerTranspose.$1 + to.diatonicIndex - from.diatonicIndex,
            outerTranspose.$2 + to.midiNumber - from.midiNumber,
          );
        }
        for (final (i, arg) in cmd.args.indexed) {
          if (i < 2 && pitchArg(arg) is LyNote) continue;
          if (arg is LyBlock || arg is LySimultaneous || arg is LyCommand) {
            _processNodes([arg]);
          }
        }
        _transposition = outerTranspose;
        break;
      case 'transposition':
        // Written pitch stays as written; the tag records how it sounds.
        final arg = cmd.args.firstOrNull;
        final name =
            arg is LyNote ? arg.pitch : (arg is LyWord ? arg.value : null);
        if (name != null && _instrumentTransposition == null) {
          _instrumentTransposition = _transpositionFor(_parsePitch(name));
        }
        break;
      case 'skip':
        // `\skip <dur>` is a spacer rest, `\skip 1*8` eight bars of it. Its
        // duration is a function argument: unlike `s4` it does not become the
        // duration of the notes after it.
        final arg = cmd.args.firstOrNull;
        final durStr = arg is LyWord
            ? arg.value
            : (arg is LyNote ? (arg.duration ?? arg.pitch) : null);
        if (durStr != null && RegExp(r'^\d').hasMatch(durStr)) {
          final running = _currentDur;
          _processRest(LyRest(durStr, spacer: true));
          _currentDur = running;
        }
        break;
      case 'partcombine':
      case 'partCombine':
        // Two parts on one staff, sounding together: the same as
        // `<< { upper } \\ { lower } >>`.
        if (cmd.args.length == 2) {
          _processParallelVoices([
            [cmd.args[0]],
            [cmd.args[1]],
          ]);
        } else {
          _processNodes(cmd.args);
        }
        break;
      case 'new':
      case 'context':
      case 'with':
        // Pass through the inner music of a context, whether it is written
        // `{ … }` or `<< … >>`.
        //
        // Only `LyBlock` used to be forwarded, and `\context` was not handled
        // at all, so two extremely common vocal-score spellings read as silence:
        //   \new Staff = "vocalist" << \new Voice { … } >>   (simultaneous body)
        //   \context Voice = "PartPOneVoiceOne" { … }        (\context form)
        // Both are what LilyPond requires as soon as anything needs to refer to
        // the context by name, e.g. `\lyricsto "vocalist"`.
        // A `\new Dynamics` line beside the staff carries its marks (and
        // often a spacer or a cue note per bar). Read as the staff's own
        // music, its bars were added to the staff's: a guitar piece whose
        // tempo marks ran in a Dynamics line above it came back twice as
        // long.
        if (cmd.name != 'with' && _contextType(cmd) == 'Dynamics') {
          _dynamicsLines.addAll(cmd.args.skip(1));
          break;
        }
        final isStaffLeaf = _staffLeafTypes.contains(_contextType(cmd));
        if (isStaffLeaf) _staffLeavesSeen++;
        final chordNames = _contextType(cmd) == 'ChordNames';
        if (chordNames) _chordNamesDepth++;
        // The body may also be a command: `\new Staff \relative c' { … }`,
        // `\context Staff \new Voice { … }`, `\new Voice \melody`. (The first
        // arg of `\new`/`\context` is the type word, never music.)
        for (var k = 0; k < cmd.args.length; k++) {
          var arg = cmd.args[k];
          // `\context ChordNames << \global \guitar >>`: beside the chords,
          // the skips that carry the bar lines and repeats. They are not the
          // staff's music — read as it, a hymn's bars came twice, a silent
          // copy before the real one.
          if (chordNames && arg is LySimultaneous) {
            arg = LySimultaneous([
              for (final c in arg.children)
                if (_holdsChordMode(c)) c
            ]);
          }
          if (arg is LyBlock ||
              arg is LySimultaneous ||
              (arg is LyCommand && (cmd.name == 'with' || k > 0))) {
            _processNodes([arg]);
          }
        }
        if (chordNames) _chordNamesDepth--;
        break;
      default:
        if (cmd.args.isEmpty && _variables.containsKey(cmd.name)) {
          // A variable is a self-contained musical expression. If expanding it
          // turned on relative mode without owning its body, that state must
          // NOT survive into the next variable — otherwise a four-voice score
          // reads its first voice correctly and every later one drifts, which
          // is how `Gevaert LaVacheEgaree.ly` reached MIDI -65.
          final outer = _pendingRelativeRestore;
          _pendingRelativeRestore = null;
          _processNodes([_variables[cmd.name]!]);
          final owed = _pendingRelativeRestore;
          if (owed != null) {
            _isRelative = owed.$1;
            _relativeBase = owed.$2;
          }
          _pendingRelativeRestore = outer;
        }
        break;
    }
  }

  /// Opens or closes a slur from an element's scripts.
  ///
  /// `)` without a matching `(` is ignored rather than guessed at: real corpus
  /// files carry unbalanced marks (a slur opened in one `\\` branch and closed
  /// in another), and inventing a span across them would be worse than dropping
  /// one.
  void _applySlurScripts(List<String> scripts, String id) {
    if (_silentPass) return;
    // ⚠️ CLOSE BEFORE OPEN — the mirror of the writer's rule. On `e)(`, taking
    // the open first is a no-op (`??=` sees a slur already running) and the
    // close then clears it, so the NEW slur was silently dropped and only the
    // first of a chained pair survived.
    // A NUMBERED slur (`\=2(`) is its own concurrent slur; plain `(` is
    // level 0. Without levels a nested pair merged into one, since the inner
    // close cleared the outer start.
    for (final script in scripts) {
      final m = RegExp(r'^(?:\\=(\d+))?\)$').firstMatch(script);
      if (m == null) continue;
      final level = int.tryParse(m[1] ?? '0') ?? 0;
      final start = _openSlurLevels.remove(level);
      if (start != null && start != id) _slurs.add(Slur(start, id));
    }
    for (final script in scripts) {
      final m = RegExp(r'^(?:\\=(\d+))?\($').firstMatch(script);
      if (m == null) continue;
      _openSlurLevels[int.tryParse(m[1] ?? '0') ?? 0] ??= id;
    }
  }

  /// Inside `\repeat tremolo N`: how many times each note's written value
  /// it lasts, and the slashes a one-note tremolo draws.
  int _tremoloTimes = 1;
  int? _tremoloSlashes;

  /// The value a note or chord read now is written with.
  NoteDuration get _writtenDur =>
      _tremoloTimes == 1 ? _currentDur : _scaled(_currentDur, _tremoloTimes, 1);

  /// Whether `\repeat tremolo [count] [body]` can be read as notes of
  /// [count] times their written value (each value scales to a note value),
  /// with the slashes a one-note body draws; null when it cannot.
  ({int? slashes})? _tremoloOf(LyNode body, int count) {
    final notes = <LyNode>[];
    void walk(LyNode n) {
      if (n is LyBlock) {
        n.children.forEach(walk);
      } else if (n is LyNote ||
          n is LyChord ||
          n is LyRest ||
          n is LySimultaneous) {
        notes.add(n);
      }
    }

    walk(body);
    // Rests and inner voices: written out rather than guessed at.
    if (notes.isEmpty || notes.any((n) => n is! LyNote && n is! LyChord)) {
      return null;
    }
    var running = _currentDur;
    for (final n in notes) {
      final written = n is LyNote ? n.duration : (n as LyChord).duration;
      if (written != null) running = _parseDuration(written);
      final scaled = _scaled(running, count, 1);
      if (scaled.toFraction() != running.toFraction() * Fraction(count, 1)) {
        return null;
      }
    }
    if (notes.length != 1) return (slashes: null);
    final v = running.toFraction();
    var slashes = 0;
    for (var d = v; d < Fraction(1, 4); d = d * Fraction(2, 1)) {
      slashes++;
    }
    return (slashes: slashes == 0 ? null : slashes);
  }

  /// The tremolo slash count from a `:N` duration suffix. LilyPond states the
  /// SUBDIVISION (`:32`), the model the number of slashes, and 32 = 4 << 3.
  static int? _tremoloFrom(List<String> scripts) {
    for (final s in scripts) {
      if (s.startsWith(':')) {
        final n = int.tryParse(s.substring(1));
        if (n != null && n >= 8) {
          var slashes = 0;
          var v = n;
          while (v > 4) {
            v >>= 1;
            slashes++;
          }
          return slashes;
        }
      }
    }
    return null;
  }

  /// Finger numbers from a note's attached scripts (`c4-1`).
  static List<int> _fingeringsFrom(List<String> scripts) {
    final out = <int>[];
    for (final s in scripts) {
      if (s.length == 2 && s[0] == '-') {
        final n = int.tryParse(s[1]);
        if (n != null) out.add(n);
      }
    }
    return out;
  }

  /// Articulations from a note's attached scripts.
  ///
  /// The parser has always collected these into `LyNote.scripts` and the writer
  /// has always emitted them; the reader simply dropped them on the floor, so
  /// every tie, staccato, accent, tenuto and marcato was lost on the way back
  /// in. Invisible until the sweep started comparing more than pitch and
  /// rhythm.
  static Set<Articulation> _articsFrom(List<String> scripts) => {
        for (final s in scripts)
          if (_scriptArtics[s] case final a?) a,
      };

  void _processNote(LyNote note) {
    // The parser admits every language's note names; one that is not a note
    // in THIS file's language (a solfège `la` in a Dutch file) is not a note
    // at all. Read as one, it became a spurious C.
    if (!_pitchPattern.hasMatch(_expand(note.pitch))) return;
    if (note.duration != null) {
      _currentDur = _runningDuration(note.duration!);
    }
    final pitch = _harmonic(_parsePitch(note.pitch));
    final p = _transposed(_applyRelative(pitch));

    if (_expectGrace) {
      // This note IS the grace; it must not occupy time in the bar.
      _expectGrace = false;
      _lastGraceEventStart = _pendingGraces.length;
      if (note.scripts.contains('~')) {
        _pendingGraceTies.add(_pendingGraces.length);
      }
      _pendingGraces.add(p);
      return;
    }

    final graces = List<Pitch>.from(_pendingGraces);
    final graceStyle = _pendingGraceStyle;
    final graceTies = _takeGraceTies(graces, [p]);
    _pendingGraces.clear();
    final id = 'e${_elementId++}';
    if (_awaitingOttavaStart) {
      _openOttavaFrom = id;
      _openOttavaDown = _pendingOttavaDown;
      _awaitingOttavaStart = false;
    }
    // A pending `\glissando` lands on this note. ⚠️ Closed at BOTH note-append
    // sites — a glissando into a chord is ordinary, and closing it at only the
    // single-note one would drop it there.
    if (_openGlissFrom case final from? when from != id) {
      _glissandos.add(Glissando(from, id));
      _openGlissFrom = null;
    }
    final head = _takeHead();
    final tied = note.scripts.contains('~');
    _addAtRunning(
      _writtenDur,
      id,
      (d, pieceId, first, last) => NoteElement(
        graceNotes: first ? graces : const [],
        graceStyle: graceStyle,
        graceTiesToMain: first ? graceTies : const {},
        pitches: [p],
        duration: d,
        articulations: first ? _articsFrom(note.scripts) : const {},
        fingerings: first ? _fingeringsFrom(note.scripts) : const [],
        tremolo: _tremoloSlashes ?? _tremoloFrom(note.scripts),
        notehead: head,
        tieToNext: last ? tied : true,
        // `!` forces the accidental, `?` prints it in parentheses as a
        // reminder. The model holds one flag, so both mean "print it".
        showAccidental:
            first && (note.scripts.contains('!') || note.scripts.contains('?'))
                ? true
                : null,
        id: pieceId,
      ),
    );
    _takeCue(id);
    _applySlurScripts(note.scripts, id);
  }

  /// [absolute] gives the chord's pitches outright (a `\chordmode` chord),
  /// leaving `\relative` untouched.
  void _processChord(LyChord chord, {List<Pitch>? absolute}) {
    if (chord.duration != null) {
      _currentDur = _runningDuration(chord.duration!);
    }
    // LilyPond relative rule for chords: each note is relative to the previous
    // note IN THE CHORD, but the reference carried to the NEXT event is the
    // chord's FIRST note — NOT its last. Applying the running base to every note
    // (as _applyRelative does) is right within the chord; afterwards we must
    // restore the base to the first note, or octaves drift upward on every
    // subsequent chord (e.g. `<d a'> <d a'> …` would climb without bound).
    final written = absolute ??
        chord.pitches
            .map((pStr) => _applyRelative(_harmonic(_parsePitch(pStr))))
            .toList();
    if (absolute == null && _isRelative && written.isNotEmpty) {
      _relativeBase = written.first;
    }
    final pitches = written.map(_transposed).toList();
    if (pitches.isNotEmpty) {
      // A grace can precede a CHORD just as it can a single note; attaching it
      // only in _processNote silently dropped every grace on a chord.
      final graces = List<Pitch>.from(_pendingGraces);
      final graceStyle = _pendingGraceStyle;
      final graceTies = _takeGraceTies(graces, pitches);
      _pendingGraces.clear();
      final id = 'e${_elementId++}';
      if (_awaitingOttavaStart) {
        _openOttavaFrom = id;
        _openOttavaDown = _pendingOttavaDown;
        _awaitingOttavaStart = false;
      }
      // A pending `\glissando` lands on this note. ⚠️ Closed at BOTH note-append
      // sites — a glissando into a chord is ordinary, and closing it at only the
      // single-note one would drop it there.
      if (_openGlissFrom case final from? when from != id) {
        _glissandos.add(Glissando(from, id));
        _openGlissFrom = null;
      }
      final head = _takeHead();
      final tied = chord.scripts.contains('~');
      _addAtRunning(
        _writtenDur,
        id,
        (d, pieceId, first, last) => NoteElement(
          graceNotes: first ? graces : const [],
          graceStyle: graceStyle,
          graceTiesToMain: first ? graceTies : const {},
          pitches: pitches,
          duration: d,
          articulations: first ? _articsFrom(chord.scripts) : const {},
          fingerings: first ? _fingeringsFrom(chord.scripts) : const [],
          tremolo: _tremoloSlashes ?? _tremoloFrom(chord.scripts),
          notehead: head,
          tieToNext: last ? tied : true,
          showAccidental: first &&
                  (chord.scripts.contains('!') || chord.scripts.contains('?'))
              ? true
              : null,
          id: pieceId,
        ),
      );
      _takeCue(id);
      _applySlurScripts(chord.scripts, id);
      _lastPitches = List.from(pitches);
    }
  }

  void _processRest(LyRest rest) {
    // A pitched rest still takes part in `\relative`: the next note is
    // reckoned from it, as from a note.
    if (rest is _LyPitchedRest) _applyRelative(_parsePitch(rest.pitch));
    // `s1*0` lasts no time at all: it is how a source hangs a `^\markup` or a
    // `\mark` on the start of a bar. Read as the bare `s1`, it put a whole
    // bar of silence in front of the music after it.
    if (rest.duration != null &&
        RegExp(r'\*0+(?:/\d+)?$').hasMatch(rest.duration!)) {
      return;
    }
    // `R1*4` is four bars of rest, and `s4*3` three beats: an integer
    // multiplier REPEATS the rest. Scaled into one element instead, four bars
    // became a single 4-whole-note rest crammed into one bar, and every bar
    // after it shifted.
    final repeat = rest.duration == null
        ? null
        : RegExp(r'^((?:\d+|\\?[A-Za-z]+)\.*)\*(\d+)(?:/1)?$')
            .firstMatch(rest.duration!);
    if (repeat != null && int.parse(repeat[2]!) > 1) {
      for (var k = 0; k < int.parse(repeat[2]!); k++) {
        _processRest(LyRest(repeat[1], spacer: rest.spacer));
      }
      return;
    }
    if (rest.duration != null) {
      _currentDur = _runningDuration(rest.duration!);
    }
    // A whole rest opening a bar rests the whole bar, whatever the meter.
    final barRest = !rest.spacer &&
        _durationScale == Fraction(1, 1) &&
        (_measureTime == Fraction.zero ||
            (_measureTime >= _capacity && _currentElements.isNotEmpty)) &&
        _currentDur == const NoteDuration(DurationBase.whole);
    if (barRest) {
      _checkMeasureBoundary(_currentDur.toFraction() * _tupletRatio);
      _currentElements.add(RestElement(_currentDur, id: 'e${_elementId++}'));
      _measureTime = _measureTime + (_currentDur.toFraction() * _tupletRatio);
      return;
    }
    _addAtRunning(
      _currentDur,
      'e${_elementId++}',
      (d, id, _, __) => RestElement(d, id: id, hidden: rest.spacer),
    );
  }

  /// An explicit `\set Timing.measureLength`, overriding the meter's capacity.
  ///
  /// ⚠️ LilyPond derives barlines from durations plus the meter, so it has no
  /// way to hold a bar that EXCEEDS its meter — and real early music is full
  /// of them (a 3/2 bar written under 3/4). Without this the reader re-bars
  /// such a piece and every bar after it shifts: one 135-bar motet came back
  /// with 152. `\set Timing.measureLength` is how LilyPond itself states an
  /// irregular measure, so the writer emits it and this honours it.
  Fraction? _measureLengthOverride;

  /// The ending of the `\alternative` being read, or null.
  _LyEnding? _activeVolta;

  /// Each ending's end, open or closed. LilyPond states none: it draws the
  /// closing hook only where the ending stops at a repeat sign or the final
  /// barline, so a last ending running on into the music is left open — read
  /// as closed, every last ending gained a hook it was printed without. A
  /// `VoltaBracket.edge-height` override stated in the file wins.
  void _settleVoltaEnds() {
    final settled = withVoltaOpenEnds(_measures, (last) {
      for (var i = last; i >= 0; i--) {
        if (_voltaOpenEndAt[i] case final open?) return open;
        if (voltaStartsAt(_measures, i)) break;
      }
      return !voltaHookedByBarline(_measures, last);
    });
    _measures
      ..clear()
      ..addAll(settled);
  }

  /// The ending a `repeatCommands` label opens: the passes it names, or for
  /// a label naming none ("Fine") the pass after the endings before it.
  _LyEnding _endingFromLabel(String label) {
    var passes = voltaNumbersIn(label);
    if (passes.isEmpty) passes = [nextVoltaPass(_measures)];
    final open = _pendingVoltaOpenEnd;
    _pendingVoltaOpenEnd = null;
    return _LyEnding(passes, text: voltaTextOf(label, passes), openEnd: open);
  }

  /// The endings of a `\repeat volta [count]` with [alts], in LilyPond's
  /// reading: with fewer alternatives than passes the FIRST is taken for the
  /// spare ones (`\repeat volta 3` with two alternatives prints "1., 2." and
  /// "3."), and `\volta 1,2 { … }` states an alternative's passes outright.
  static List<_LyEnding> _alternativeEndings(
      int count, List<LyNode> alts, List<List<int>?> stated) {
    final k = alts.length;
    final passes = count < k ? k : count;
    final spare = passes - k;
    return [
      for (var j = 0; j < k; j++)
        _LyEnding(stated[j] ??
            (j == 0
                ? [for (var p = 1; p <= spare + 1; p++) p]
                : [spare + 1 + j])),
    ];
  }

  /// Work waiting for the bar in progress to close, run just after it does.
  final List<void Function()> _afterClose = [];

  /// Whether the bar in progress is full, though no note has closed it yet.
  bool _isFull() {
    final capacity =
        _measureLengthOverride ?? Fraction(_time.beats, _time.beatUnit);
    return _currentElements.isNotEmpty && _measureTime >= capacity;
  }

  /// Closes the bar in progress when it is already full, so whatever follows
  /// (a repeat sign, an ending) starts the next one. Returns whether it closed.
  bool _closeIfFull() {
    final capacity =
        _measureLengthOverride ?? Fraction(_time.beats, _time.beatUnit);
    if (_currentElements.isNotEmpty && _measureTime >= capacity) {
      _closeMeasure();
      return true;
    }
    return false;
  }

  /// The bar's capacity, and the next bar's once this one closes.
  Fraction get _capacity =>
      _measureLengthOverride ?? Fraction(_time.beats, _time.beatUnit);
  Fraction get _nextCapacity {
    if (_measureLengthOverride case final o?) return o;
    final next = _sharedMeters[_measures.length + 1] ??
        (_timeChangeIsForNextMeasure ? _pendingTimeChange : null);
    return next == null ? _capacity : Fraction(next.beats, next.beatUnit);
  }

  /// [total] cut at every barline it crosses, as the written values each
  /// bar's share is spelled with, or null when it fits in the bar (or cannot
  /// be cut: inside a tuplet, or at a length no note value spells).
  ///
  /// LilyPond's bars come from the clock, not from the notes: a note that
  /// starts late in a bar and runs past its end simply sounds over the
  /// barline. Closing the bar early instead put the note whole into the next
  /// bar, so the bar came out short — harmless alone, but a second voice
  /// read beside it kept its full bars, and from there on every bar of the
  /// two voices was paired with the wrong one: the voices drifted apart.
  List<List<NoteDuration>>? _piecesAcrossBars(Fraction total) {
    if (_tupletRatio != Fraction(1, 1)) return null;
    bool dyadic(Fraction f) => f.denominator & (f.denominator - 1) == 0;
    var time = _measureTime;
    var cap = _capacity;
    if (time >= cap && _currentElements.isNotEmpty) {
      time = Fraction.zero;
      cap = _nextCapacity;
    }
    if (!(time + total > cap)) return null;
    final out = <List<NoteDuration>>[];
    var left = total;
    while (left > Fraction.zero) {
      final room = cap - time;
      if (room <= Fraction.zero) return null;
      final chunk = left > room ? room : left;
      if (!dyadic(chunk)) return null;
      final spelled = _spaceDurations(chunk);
      if (spelled == null) return null;
      out.add(spelled);
      left = left - chunk;
      time = Fraction.zero;
      cap = _nextCapacity;
    }
    return out;
  }

  /// [gap] spelled largest value first, or null when no run of note values
  /// sums to it exactly.
  static List<NoteDuration>? _spaceDurations(Fraction gap) {
    var left = gap;
    final out = <NoteDuration>[];
    while (left > Fraction.zero) {
      NoteDuration? pick;
      for (final base in DurationBase.values) {
        for (final dots in const [1, 0]) {
          final d = NoteDuration(base, dots: dots);
          if (d.toFraction() <= left &&
              (pick == null || d.toFraction() > pick.toFraction())) {
            pick = d;
          }
        }
      }
      if (pick == null) return null;
      out.add(pick);
      left = left - pick.toFraction();
    }
    return out;
  }

  /// Adds an event of [total] length made by [make], cut into tied pieces at
  /// each barline it crosses (see [_piecesAcrossBars]). [make] receives each
  /// piece's value, its id (the first piece keeps [id]) and whether it is the
  /// first and the last piece.
  void _addAcrossBars(
    NoteDuration written,
    String id,
    MusicElement Function(NoteDuration d, String id, bool first, bool last)
        make,
  ) {
    if (_silentPass) {
      make = (d, id, _, __) {
        if (_silentBars) _silentBarIds.add(id);
        return RestElement(d, id: id, hidden: true);
      };
    }
    final total = written.toFraction() * _tupletRatio;
    final pieces = _piecesAcrossBars(total);
    if (pieces == null) {
      _checkMeasureBoundary(total);
      _currentElements.add(make(written, id, true, true));
      _measureTime = _measureTime + total;
      return;
    }
    final flat = [for (final bar in pieces) ...bar];
    for (var k = 0; k < flat.length; k++) {
      final d = flat[k];
      _checkMeasureBoundary(d.toFraction());
      final pieceId = k == 0 ? id : 'e${_elementId++}';
      if (k > 0) _barContinuations.add(pieceId);
      _currentElements.add(make(d, pieceId, k == 0, k == flat.length - 1));
      _measureTime = _measureTime + d.toFraction();
    }
  }

  /// While the repeats of a `\repeat percent` are read: they take their
  /// time but sound nothing, so every event reads as a hidden rest.
  bool _silentPass = false;

  /// Whether those repeats are of a body one whole bar long, so a bar made
  /// of them alone is drawn as a measure-repeat sign.
  bool _silentBars = false;

  /// The hidden rests such whole-bar repeats were read as.
  final Set<String> _silentBarIds = {};

  /// How many `<< … >>` voice groups are being read, inside one another.
  int _parallelDepth = 0;

  /// `\repeat percent [count] [body]`: the body once, then its repeats.
  ///
  /// LilyPond prints the repeats as percent signs and its MIDI plays the
  /// body ONCE, the repeats taking their time in silence (checked against
  /// its MIDI). Read as the body once, the repeats' time was lost and every
  /// later note came early. A repeat of a whole bar becomes a measure-repeat
  /// bar; anything else, hidden rests. `\relative` and the running duration
  /// go on from the body as written.
  void _readPercent(LyNode body, int count) {
    final startBase = _relativeBase;
    final startDur = _currentDur;
    final barsBefore = _measures.length;
    final closesFirst =
        _currentElements.isNotEmpty && _measureTime >= _capacity;
    final atBarStart = _measureTime == Fraction.zero || closesFirst;
    _processNodes([body]);
    final endBase = _relativeBase;
    final endDur = _currentDur;
    final wholeBar = atBarStart &&
        _measureTime == _capacity &&
        _measures.length == barsBefore + (closesFirst ? 1 : 0);
    final outer = (_silentPass, _silentBars);
    _silentPass = true;
    _silentBars = wholeBar && _parallelDepth == 0;
    for (var pass = 1; pass < count; pass++) {
      _relativeBase = startBase;
      _currentDur = startDur;
      _processNodes([body]);
    }
    _silentPass = outer.$1;
    _silentBars = outer.$2;
    _relativeBase = endBase;
    _currentDur = endDur;
  }

  /// Ids of the pieces after the first of a note cut at a barline: they carry
  /// no syllable of their own (LilyPond's `completionBusy`).
  final Set<String> _barContinuations = {};

  /// While a voice beside voice 1 is read: the meter voice 1 set at each bar
  /// (by bar index), which every voice keeps.
  Map<int, TimeSignature> _sharedMeters = const {};

  void _restoreMeter((TimeSignature, TimeSignature?, bool) meter) {
    _time = meter.$1;
    _pendingTimeChange = meter.$2;
    _timeChangeIsForNextMeasure = meter.$3;
  }

  void _checkMeasureBoundary(Fraction nextDur) {
    final capacity =
        _measureLengthOverride ?? Fraction(_time.beats, _time.beatUnit);
    if (_measureTime + nextDur > capacity && _currentElements.isNotEmpty) {
      _closeMeasure();
    }
  }

  void _closeMeasure() {
    if (_currentElements.isEmpty && _pendingVoices.isEmpty) return;
    // A bar holding nothing but a whole-bar percent repeat is that sign.
    final repeatsBar = _currentElements.isNotEmpty &&
        _pendingVoices.isEmpty &&
        _measureTime == _capacity &&
        _currentElements.every((e) => _silentBarIds.contains(e.id));
    final ending = _pendingVolta ?? _activeVolta ?? _commandVolta;
    if (ending?.openEnd case final open?) {
      _voltaOpenEndAt[_measures.length] = open;
    }
    _measures.add(Measure(
      repeatsBar ? const [] : List.from(_currentElements),
      measureRepeat: repeatsBar ? 1 : null,
      voice2: List.from(_pendingVoices[1] ?? const []),
      voice3: List.from(_pendingVoices[2] ?? const []),
      voice4: List.from(_pendingVoices[3] ?? const []),
      tuplets: [..._currentTuplets, ..._pendingVoiceTuplets],
      timeChange: _timeChangeIsForNextMeasure ? null : _pendingTimeChange,
      tempoChange: _pendingTempoChange,
      volta: ending?.passes.first,
      voltaNumbers:
          ending == null || ending.passes.length < 2 ? const [] : ending.passes,
      voltaText: ending?.text,
      navigation: _pendingNavigation,
      clefChange: _pendingClefChange,
      keyChange: _pendingKeyChange,
      inlineClefs: List.from(_pendingInlineClefs),
      barline: _pendingBarline ?? BarlineStyle.normal,
      endRepeat: _pendingEndRepeat,
      startRepeat: _startRepeatHere,
      pickup: _pendingPickup,
    ));
    _pendingTempoChange = null;
    _pendingClefChange = null;
    _pendingKeyChange = null;
    _pendingVolta = null;
    _pendingNavigation = null;
    _pendingInlineClefs.clear();
    _pendingBarline = null;
    _pendingEndRepeat = false;
    _pendingPickup = false;
    _startRepeatHere = _pendingStartRepeat;
    _pendingStartRepeat = false;
    if (_timeChangeIsForNextMeasure) {
      // It lands on the bar that starts now; the capacity takes effect here too.
      _timeChangeIsForNextMeasure = false;
      if (_pendingTimeChange != null) _time = _pendingTimeChange!;
    } else {
      _pendingTimeChange = null;
    }
    if (_sharedMeters[_measures.length] case final t?) {
      _time = t;
      _pendingTimeChange = null;
      _timeChangeIsForNextMeasure = false;
    }
    _currentElements.clear();
    _currentTuplets.clear();
    _pendingVoices.clear();
    _pendingVoiceTuplets.clear();
    _measureTime = Fraction.zero;
    if (_pendingOverflow.isNotEmpty) {
      _measures.addAll(_pendingOverflow);
      _pendingOverflow.clear();
    }
    if (_afterClose.isNotEmpty) {
      final waiting = List.of(_afterClose);
      _afterClose.clear();
      for (final work in waiting) {
        work();
      }
    }
  }

  /// Whether a chord-track root is really a skip/rest placeholder rather than
  /// a chord. Octave marks are allowed on it (`s,`), duration is already split.
  static bool _isChordSkip(String root) {
    final r = root.replaceAll(RegExp(r"[,']"), '');
    return r == 's' || r == 'r' || r == 'R';
  }

  /// A `\tempo` mark's `unit = bpm` assignment as a [Tempo], or null when the
  /// unit or the count will not parse. The unit is a LilyPond duration, so its
  /// dots ride along with it (`4.` is a dotted quarter, not a quarter).
  Tempo? _tempoFrom(LyAssignment mark) {
    final value = mark.value;
    final bpm = value is LyWord ? double.tryParse(value.value) : null;
    if (bpm == null || bpm <= 0) return null;
    final unit = _parseDuration(mark.key);
    return Tempo(bpm, beatUnit: unit.base, dots: unit.dots);
  }

  /// Figure-track entries, as (onset from the track's start, figures).
  final List<({Fraction onset, List<String> figures})> _figureTrack = [];

  /// Walks a `\figuremode` block recording each stack and where it falls.
  /// `<6 4>` is a chord of FIGURES, not pitches; `s` is a skip holding place.
  void _collectFigureTrack(List<LyNode> nodes) {
    var cursor = Fraction.zero;
    var dur = const NoteDuration(DurationBase.quarter);
    void walk(List<LyNode> ns) {
      for (final n in ns) {
        if (n is LyBlock) {
          walk(n.children);
        } else if (n is LyChord) {
          if (n.duration != null) dur = _parseDuration(n.duration!);
          _figureTrack.add((onset: cursor, figures: List.of(n.pitches)));
          cursor += dur.toFraction();
        } else if (n is LyNote) {
          if (n.duration != null) dur = _parseDuration(n.duration!);
          if (!_isChordSkip(n.pitch)) {
            _figureTrack.add((onset: cursor, figures: [n.pitch]));
          }
          cursor += dur.toFraction();
        } else if (n is LyRest) {
          if (n.duration != null) dur = _parseDuration(n.duration!);
          cursor += dur.toFraction();
        } else if (n is LyWord) {
          // ⚠️ A skip can arrive as a WORD (`s4`), not an LyNote — the chord
          // track's walker has the same branch for the same reason. Without it
          // the cursor never advances past a skip and every later stack
          // anchors one note early.
          final m =
              RegExp(r"^([a-zA-Z]+[,']*)([0-9]+\.*)?").firstMatch(n.value);
          if (m == null) continue;
          if (m.group(2) != null) dur = _parseDuration(m.group(2)!);
          if (!_isChordSkip(m.group(1)!)) {
            _figureTrack.add((onset: cursor, figures: [n.value]));
          }
          cursor += dur.toFraction();
        }
      }
    }

    walk(nodes);
  }

  /// Anchors the figure track to real notes, exactly as the chord track is.
  List<FiguredBass> _buildFiguredBass(List<Measure> measures) {
    if (_figureTrack.isEmpty) return const [];
    final noteAt = <({Fraction onset, String id})>[];
    var t = Fraction.zero;
    for (final m in measures) {
      for (final e in m.elements) {
        if (e is NoteElement && e.id != null) {
          noteAt.add((onset: t, id: e.id!));
        }
        t += e.duration.toFraction();
      }
    }
    final out = <FiguredBass>[];
    final used = <String>{};
    for (final f in _figureTrack) {
      final hit = noteAt
          .where((n) => n.onset >= f.onset && !used.contains(n.id))
          .firstOrNull;
      if (hit == null) continue;
      used.add(hit.id);
      out.add(FiguredBass(hit.id, f.figures));
    }
    return out;
  }

  /// Inside a `\new ChordNames`, where `\chordmode` names chords rather than
  /// writing notes.
  int _chordNamesDepth = 0;

  /// A `\chordmode` chord: root (with duration and multiplier), modifiers,
  /// and an inversion (`/e`) or added bass (`/+d`).
  static final _chordModeWord = RegExp(
      r"^([a-zé]+[',]*)(\d+\.*)?(\*\d+(?:/\d+)?)?(?::([^/]*))?(?:/(\+)?([a-zé]+[',]*))?$");

  /// Reads `\chordmode` music on a staff as the chords LilyPond plays.
  ///
  /// Chord mode is absolute (a bare `c` is middle C) and leaves the
  /// `\relative` reference where it was; dynamics and other commands between
  /// the chords are read as usual.
  void _processChordModeNotes(List<LyNode> nodes) {
    final wasRelative = _isRelative;
    _isRelative = false;
    void chord(String root, String? duration, String mods, String? bassText,
        bool added, List<String> scripts) {
      if (!_pitchPattern.hasMatch(_expand(root))) return;
      final r = _parsePitch(root);
      final pitches = _chordModePitches(
          Pitch(r.step, alter: r.alter, octave: r.octave + 1), mods);
      if (bassText != null && _pitchPattern.hasMatch(_expand(bassText))) {
        final b = _parsePitch(bassText);
        final rootMidi = pitches.first.midiNumber;
        final same = pitches.indexWhere(
            (p) => (p.midiNumber - b.midiNumber) % 12 == 0 && !added);
        if (same >= 0) {
          // `c/e`: the inversion note and all above it go down an octave.
          final at = pitches[same].midiNumber;
          for (var i = 0; i < pitches.length; i++) {
            final p = pitches[i];
            if (p.midiNumber >= at) {
              pitches[i] = Pitch(p.step, alter: p.alter, octave: p.octave - 1);
            }
          }
        } else {
          // `c/+d`, or `c/f` with no F in the chord: a bass below the root.
          var bass = Pitch(b.step, alter: b.alter, octave: r.octave + 1);
          while (bass.midiNumber >= rootMidi) {
            bass = Pitch(bass.step, alter: bass.alter, octave: bass.octave - 1);
          }
          pitches.add(bass);
        }
        pitches.sort((a, b) => a.midiNumber - b.midiNumber);
      }
      _processChord(LyChord(const [], duration, scripts), absolute: pitches);
    }

    void walk(List<LyNode> ns) {
      for (var i = 0; i < ns.length; i++) {
        final n = ns[i];
        switch (n) {
          case LyBlock(:final children):
            walk(children);
          case LyNote(:final pitch, :final duration, :final scripts):
            chord(pitch, duration, '', null, false, scripts);
          case LyWord(:final value) when _chordModeWord.hasMatch(value):
            // `c:6^5` lexes as `c:6`, `^`, `5`: the removals rejoin it.
            var text = value;
            if (i + 2 < ns.length &&
                ns[i + 1] is LyWord &&
                (ns[i + 1] as LyWord).value == '^' &&
                ns[i + 2] is LyWord &&
                RegExp(r'^[\d.]+').hasMatch((ns[i + 2] as LyWord).value)) {
              text = '$value^${(ns[i + 2] as LyWord).value}';
              i += 2;
            }
            final m = _chordModeWord.firstMatch(text) ??
                _chordModeWord.firstMatch(value)!;
            final dur = m[2] == null ? null : '${m[2]}${m[3] ?? ''}';
            chord(m[1]!, dur, m[4] ?? '', m[6], m[5] != null, const []);
          default:
            _processNodes([n]);
        }
      }
    }

    walk(nodes);
    _isRelative = wasRelative;
  }

  /// The pitches of a `\chordmode` chord on [root], from its modifiers
  /// (`m7`, `7.9-`, `maj9`, `dim7`, `sus4`, `6^5`), as LilyPond builds it.
  static List<Pitch> _chordModePitches(Pitch root, String mods) {
    final parts = mods.split('^');
    // Step -> semitones above the root.
    final steps = <int, int>{1: 0, 3: 4, 5: 7};
    const natural = {
      1: 0, 2: 2, 3: 4, 4: 5, 5: 7, 6: 9, 7: 10, //
      8: 12, 9: 14, 10: 16, 11: 17, 12: 19, 13: 21,
    };
    var minor = false, maj = false, dim = false, aug = false;
    int? sus;
    var first = true;
    final altered = <int, int>{};
    for (final m in RegExp(r'(m(?:aj|in)?|dim|aug|sus)|(\d+)([+-]*)')
        .allMatches(parts.first)) {
      if (m[1] case final word?) {
        switch (word) {
          case 'm' || 'min':
            minor = true;
          case 'maj':
            maj = true;
          case 'dim':
            dim = true;
          case 'aug':
            aug = true;
          case 'sus':
            sus = 4;
        }
        continue;
      }
      final n = int.parse(m[2]!);
      final shift = '+'.allMatches(m[3]!).length - '-'.allMatches(m[3]!).length;
      if (sus == 4 &&
          first &&
          (n == 2 || n == 4) &&
          m.start > 0 &&
          parts.first.substring(0, m.start).endsWith('sus')) {
        sus = n;
        continue;
      }
      if (n > 13) continue;
      if (first) {
        // The first number is how far the chord reaches: thirds stacked up
        // to it (a thirteenth leaves out the eleventh); 6 adds a sixth to
        // the triad, 5 is root and fifth, 1 the root alone.
        first = false;
        if (n == 1) {
          steps.remove(3);
          steps.remove(5);
        } else if (n == 5) {
          steps.remove(3);
        } else if (n >= 7) {
          for (var s = 7; s <= n; s += 2) {
            if (!(n == 13 && s == 11)) steps[s] = natural[s]!;
          }
        } else {
          steps[n] = natural[n]!;
        }
      } else {
        steps[n] = natural[n]!;
      }
      if (shift != 0) altered[n] = shift;
    }
    // A bare `maj` is a major seventh chord, a bare `dim7` diminished.
    if (maj) steps[7] = 11;
    if (minor && steps.containsKey(3)) steps[3] = 3;
    if (dim) {
      if (steps.containsKey(3)) steps[3] = 3;
      steps[5] = 6;
      if (steps.containsKey(7)) steps[7] = 9;
    }
    if (aug) steps[5] = 8;
    if (sus != null) {
      steps.remove(3);
      steps[sus] = natural[sus]!;
    }
    altered.forEach((s, shift) {
      if (steps.containsKey(s)) steps[s] = natural[s]! + shift;
    });
    if (parts.length > 1) {
      for (final m in RegExp(r'\d+').allMatches(parts[1])) {
        steps.remove(int.parse(m[0]!));
      }
    }
    final ordered = steps.keys.toList()..sort();
    return [
      for (final s in ordered) _spelledAbove(root, s - 1, steps[s]!),
    ];
  }

  /// The pitch [steps] diatonic steps and [semis] semitones above [root].
  static Pitch _spelledAbove(Pitch root, int steps, int semis) {
    final target = root.diatonicIndex + steps;
    final step = Step.values[target % 7];
    final octave = (target - target % 7) ~/ 7;
    final alter =
        root.midiNumber + semis - ((octave + 1) * 12 + step.semitonesFromC);
    if (alter < -2 || alter > 2) return Pitch.fromMidi(root.midiNumber + semis);
    return Pitch(step, alter: alter, octave: octave);
  }

  /// Chord-track entries: onset from the track's start, how long the chord
  /// is written, and the chord with its voicing octave.
  ///
  /// The chord is parsed as it is met, not when the symbols are built: a
  /// `\transpose` around the track (`\transpose g c \chordmode { … }`) has
  /// ended by then, and the chords came out in the key they were written in,
  /// a fourth or a tone away from the staves they stand over.
  final List<
      ({
        Fraction onset,
        Fraction length,
        ({Pitch root, ChordSymbolKind kind, Pitch? bass, bool added}) chord,
        int? octave,
      })> _chordTrack = [];

  void _addChord(Fraction onset, Fraction length, String text) {
    final parsed = _parseChordText(text);
    if (parsed == null) return;
    // LilyPond voices a chord-mode root where it is written: a bare `c` is
    // middle C (one octave above the note `c`), `c,` the octave below. The
    // model's default voicing is the bare one — from middle C up — so only
    // a root outside it states an octave.
    final root = parsed.root;
    final octave = root.octave + 1;
    final midi = Pitch(root.step, alter: root.alter, octave: octave).midiNumber;
    _chordTrack.add((
      onset: onset,
      length: length,
      chord: parsed,
      octave: midi >= 60 && midi <= 71 ? null : octave,
    ));
  }

  /// Walks a `\chordmode` block recording each chord and where it falls.
  ///
  /// LilyPond writes a plain triad as a bare note (`f4`) and a qualified chord as
  /// one word (`c:7`, `bes:maj7`, `c:7/e`), so both node shapes appear here.
  /// Durations inherit from the previous chord exactly as they do for notes;
  /// a duration multiplier (`f1*3/4`) is exact and does not carry on.
  void _collectChordTrack(List<LyNode> nodes) {
    var cursor = Fraction.zero;
    var dur = const NoteDuration(DurationBase.quarter);
    // `1*3/4` → the base duration (which carries on) and the exact length.
    Fraction lengthOf(String? written) {
      if (written == null) return dur.toFraction();
      final m = RegExp(r'^(.*?)(\*\d+(?:/\d+)?)?$').firstMatch(written.trim())!;
      dur = _parseDuration(m[1]!);
      return _withMultiplier(dur.toFraction(), m[2]);
    }

    void walk(List<LyNode> ns) {
      for (final n in ns) {
        if (n is LyBlock) {
          walk(n.children);
        } else if (n is LyNote) {
          final length = lengthOf(n.duration);
          // A SKIP holds the track's place and names no chord. Note names are
          // a-g, so `s` (and `r`) can only be a skip or a rest — reading one as
          // a chord root yields a phantom major triad on every unharmonised
          // beat, which is what a chord track is mostly made of.
          if (!_isChordSkip(n.pitch)) {
            _addChord(cursor, length, n.pitch);
          }
          cursor += length;
        } else if (n is LyWord) {
          // `f1*3/4` — the duration MULTIPLIER has to be split off before the
          // quality, or it is read as part of the chord: the trailing group
          // caught `*3/4`, which `_parseChordText` then split on the `/` into a
          // slash chord, turning F into `C/C`. Unlike a melody note the cursor
          // here is an exact Fraction, so the scaling is applied exactly and
          // does NOT stick to the following chord (`f1*3/4 f` → the second `f`
          // is a whole note).
          // The `[,']*` is the octave mark, and it has to be part of the ROOT:
          // chord tracks are conventionally written low (`f,2/c`), and without
          // it the duration no longer sat where the digit group could see it,
          // so `2` was left stuck to the root — `f,2` does not parse as a pitch,
          // and `f,2/c` came out as `C/C`.
          final m =
              RegExp(r"^([a-zA-Z]+[,']*)([0-9]+\.*)?(\*\d+(?:/\d+)?)?(.*)$")
                  .firstMatch(n.value);
          if (m == null) continue;
          if (m.group(2) != null) dur = _parseDuration(m.group(2)!);
          final length = _withMultiplier(dur.toFraction(), m.group(3));
          if (!_isChordSkip(m.group(1)!)) {
            _addChord(cursor, length, '${m.group(1)}${m.group(4)}');
          }
          cursor += length;
        } else if (n is LyRest) {
          cursor += lengthOf(n.duration);
        }
      }
    }

    walk(nodes);
  }

  /// [f] scaled by a `*N` / `*N/M` multiplier suffix, or [f] when there is none.
  static Fraction _withMultiplier(Fraction f, String? mult) {
    if (mult == null) return f;
    final m = RegExp(r'^\*(\d+)(?:/(\d+))?$').firstMatch(mult);
    if (m == null) return f;
    final num = int.parse(m[1]!);
    final den = int.parse(m[2] ?? '1');
    if (num <= 0 || den <= 0) return f;
    return f * Fraction(num, den);
  }

  /// Turns the collected chord track into [ChordSymbol]s anchored to real notes.
  ///
  /// `ChordSymbol` binds to a NOTE ELEMENT ID, but a chord track has its own
  /// rhythm and knows nothing about melody ids — so both streams are walked by
  /// elapsed time. Each chord stands over the note sounding when it starts, at
  /// an [ChordSymbol.offset] from that note's onset, so it keeps its own time:
  /// a chord between two melody notes, or several over one long note.
  ///
  /// A first version took the first note at or after each chord that had no
  /// symbol yet: a chord track denser than its melody pushed chords onto later
  /// notes, and LilyPond's MIDI — which plays the track at its own onsets —
  /// disagreed with ours on every such file.
  ///
  /// The anchor is a top-voice note in the chord's bar where there is one
  /// (the note sounding then, else the bar's first after it, at a negative
  /// offset); a bar the top voice rests through takes another voice's note,
  /// and a bar with no note at all the last note before it.
  ///
  /// A chord that stops before the next one starts — a rest or skip in the
  /// track after it, or a last chord ending before the music — keeps its
  /// written length as [ChordSymbol.duration]; LilyPond's MIDI is silent
  /// there.
  List<ChordSymbol> _buildChordSymbols(List<Measure> measures) {
    if (_chordTrack.isEmpty) return const [];
    // Each bar's start and its notes as (voice, onset, id).
    final barStart = <Fraction>[];
    final barNotes = <List<({int voice, Fraction onset, String id})>>[];
    var t = Fraction.zero;
    for (final m in measures) {
      barStart.add(t);
      final notes = <({int voice, Fraction onset, String id})>[];
      var end = t;
      for (var v = 0; v < 4; v++) {
        final voice = m.voiceAt(v);
        var at = t;
        for (var i = 0; i < voice.length; i++) {
          final e = voice[i];
          if (e is NoteElement && e.id != null) {
            notes.add((voice: v, onset: at, id: e.id!));
          }
          at += m.effectiveDurationAt(i, voice: v);
        }
        if (at > end) end = at;
      }
      barNotes.add(notes);
      t = end;
    }
    final musicEnd = t;
    if (barNotes.every((n) => n.isEmpty)) return const [];

    ({Fraction onset, String id})? anchorFor(Fraction at) {
      var bar = 0;
      while (bar + 1 < barStart.length && barStart[bar + 1] <= at) {
        bar++;
      }
      final notes = barNotes[bar];
      ({Fraction onset, String id})? latest(
          Iterable<({int voice, Fraction onset, String id})> ns) {
        ({int voice, Fraction onset, String id})? best;
        for (final n in ns) {
          if (n.onset <= at && (best == null || n.onset > best.onset)) best = n;
        }
        return best == null ? null : (onset: best.onset, id: best.id);
      }

      final top = notes.where((n) => n.voice == 0);
      if (latest(top) case final hit?) return hit;
      if (top.isNotEmpty) {
        final first = top.reduce((a, b) => b.onset < a.onset ? b : a);
        return (onset: first.onset, id: first.id);
      }
      if (latest(notes) case final hit?) return hit;
      if (notes.isNotEmpty) {
        final first = notes.reduce((a, b) => b.onset < a.onset ? b : a);
        return (onset: first.onset, id: first.id);
      }
      // A bar without notes: the last note before it, else the first after.
      for (var b = bar - 1; b >= 0; b--) {
        if (barNotes[b].isNotEmpty) {
          final n = barNotes[b].reduce((a, c) => c.onset > a.onset ? c : a);
          return (onset: n.onset, id: n.id);
        }
      }
      for (var b = bar + 1; b < barNotes.length; b++) {
        if (barNotes[b].isNotEmpty) {
          final n = barNotes[b].reduce((a, c) => c.onset < a.onset ? c : a);
          return (onset: n.onset, id: n.id);
        }
      }
      return null;
    }

    final out = <ChordSymbol>[];
    for (var k = 0; k < _chordTrack.length; k++) {
      final c = _chordTrack[k];
      final hit = anchorFor(c.onset);
      if (hit == null) continue;
      final ends = c.onset + c.length;
      final next =
          k + 1 < _chordTrack.length ? _chordTrack[k + 1].onset : musicEnd;
      out.add(ChordSymbol(
        hit.id,
        c.chord.root,
        c.chord.kind,
        bass: c.chord.bass,
        addedBass: c.chord.added,
        offset: c.onset - hit.onset,
        duration: ends == next ? null : c.length,
        voicingOctave: c.octave,
      ));
    }
    return out;
  }

  /// `c:7/e` → root C, dominant seventh, bass E. Null when the root will not
  /// parse; an unknown QUALITY degrades to a major triad rather than dropping the
  /// chord, since the root is the part a player most needs.
  ({Pitch root, ChordSymbolKind kind, Pitch? bass, bool added})?
      _parseChordText(String s) {
    final slash = s.split('/');
    final head = slash.first;
    final colon = head.indexOf(':');
    final rootStr = colon < 0 ? head : head.substring(0, colon);
    final mods = colon < 0 ? '' : head.substring(colon + 1);
    Pitch root;
    try {
      root = _transposed(_parsePitch(rootStr));
    } catch (_) {
      return null;
    }
    Pitch? bass;
    if (slash.length > 1) {
      try {
        // `/+e` ADDS a bass below the chord (where `/e` inverts it): the bass
        // is the pitch after the `+`. Read whole, `+e` parsed as no pitch,
        // which is C — every added bass was a C.
        final b = slash[1].startsWith('+') ? slash[1].substring(1) : slash[1];
        bass = _transposed(_parsePitch(b));
      } catch (_) {
        bass = null;
      }
    }
    return (
      root: root,
      kind: _chordKindOf(mods),
      bass: bass,
      added: bass != null && slash[1].startsWith('+'),
    );
  }

  static ChordSymbolKind _chordKindOf(String mods) {
    // `^7` REMOVES degrees (`d:6^7`, a sixth chord with no seventh): what is
    // left is named by what comes before it.
    final m = mods.toLowerCase().split('^').first.replaceAll('.', '');
    if (m.isEmpty) return ChordSymbolKind.major;
    return switch (m) {
      'm' || 'min' => ChordSymbolKind.minor,
      'm7' || 'min7' => ChordSymbolKind.minorSeventh,
      '7' => ChordSymbolKind.dominantSeventh,
      'maj7' || 'maj' => ChordSymbolKind.majorSeventh,
      '6' => ChordSymbolKind.sixth,
      'm6' || 'min6' => ChordSymbolKind.minorSixth,
      '9' => ChordSymbolKind.dominantNinth,
      'dim' => ChordSymbolKind.diminished,
      'dim7' => ChordSymbolKind.diminishedSeventh,
      'aug' => ChordSymbolKind.augmented,
      'sus4' || 'sus' => ChordSymbolKind.suspendedFourth,
      'sus2' => ChordSymbolKind.suspendedSecond,
      'm7-5' || 'm75-' => ChordSymbolKind.halfDiminishedSeventh,
      // `7+` is LilyPond's RAISED seventh, so `m7+` is the minor triad with a
      // major seventh. Without this the model's own spelling read back major.
      'm7+' => ChordSymbolKind.minorMajorSeventh,
      // ...and `7+` alone the major seventh chord.
      '7+' => ChordSymbolKind.majorSeventh,
      // A six-nine has no kind of its own; the sixth is the nearer.
      '69' => ChordSymbolKind.sixth,
      _ => ChordSymbolKind.major,
    };
  }

  /// The running `\transpose` interval as (diatonic steps, semitones).
  (int, int) _transposition = (0, 0);

  /// [p] moved by the running `\transpose` interval, spelled diatonically.
  /// A spelling that would need more than a double accidental (F𝄪 up an
  /// augmented second) falls back to the enharmonic MIDI spelling.
  Pitch _transposed(Pitch p) {
    final (steps, semis) = _transposition;
    if (steps == 0 && semis == 0) return p;
    final target = p.diatonicIndex + steps;
    final step = Step.values[target % 7];
    final octave = (target - target % 7) ~/ 7;
    final alter =
        p.midiNumber + semis - ((octave + 1) * 12 + step.semitonesFromC);
    if (alter < -2 || alter > 2 || p.microtone != null) {
      return Pitch.fromMidi(p.midiNumber + semis);
    }
    return Pitch(step, alter: alter, octave: octave);
  }

  Pitch _applyRelative(Pitch p) {
    if (!_isRelative) return p;
    // LilyPond relative pitch rules:
    // Distance from _relativeBase ignoring octaves
    final stepsBase = _relativeBase.step.index;
    final stepsP = p.step.index;

    // Find shortest distance
    int diff = stepsP - stepsBase;
    if (diff > 3) diff -= 7;
    if (diff < -3) diff += 7;

    // Apply octave shift based on shortest distance + explicit marks
    int octave = _relativeBase.octave;
    if (stepsP - stepsBase > 3) octave -= 1;
    if (stepsP - stepsBase < -3) octave += 1;

    // Add explicit octave marks from p (where p is initially parsed as if absolute around C3)
    // Actually, _parsePitch returns octave = 3 + ups - downs.
    // So p.octave - 3 is the explicit shift.
    octave += (p.octave - 3);

    final result = Pitch(p.step, alter: p.alter, octave: octave);
    _relativeBase = result; // update for next note
    return result;
  }

  /// Circle-of-fifths signature for a `\key <tonic> \major|\minor`. Natural
  /// tonics sit at F=-1..B=5; each sharp adds 7, each flat subtracts 7; a minor
  /// key is its relative major minus 3 fifths.
  int _fifthsFor(Step step, int alter, bool major) {
    const base = {
      Step.f: -1,
      Step.c: 0,
      Step.g: 1,
      Step.d: 2,
      Step.a: 3,
      Step.e: 4,
      Step.b: 5,
    };
    var f = (base[step] ?? 0) + 7 * alter;
    if (!major) f -= 3;
    // A transposed key can pass seven accidentals (F-flat major); the model
    // holds -7..7, so it wraps to the enharmonic key, as `transposedBy` does.
    while (f > 7) {
      f -= 12;
    }
    while (f < -7) {
      f += 12;
    }
    return f;
  }

  /// Dutch and German both contract `ees`→`es` and `aes`→`as` (and their
  /// double-flats). Those contractions are the NORMAL spelling in real scores,
  /// and they matched none of the accidental alternatives — so every `es` and
  /// `as` fell through to the silent `c` fallback, dragging the relative base
  /// with it. Expanding them first keeps one pattern per language.
  static const _contractions = {
    'es': 'ees',
    'as': 'aes',
    'eses': 'eeses',
    'ases': 'aeses',
    'asas': 'aeses',
    'hes': 'bes',
    'heses': 'beses',
    // Swedish (`svenska`) writes E flat and A flat `ess` and `ass`.
    'ess': 'eess',
    'ass': 'aess',
    'essess': 'eessess',
    'assess': 'aessess',
  };

  /// Contractions are a Dutch/German spelling. English uses `-s`/`-f`, where
  /// `es` means E SHARP — expanding it to `ees` there would flip an accidental.
  String _expand(String token) {
    if (language == LyNoteLanguage.english) return token;
    final m = RegExp(r"^([a-z]+)([',]*)$").firstMatch(token);
    if (m == null) return token;
    final body = _contractions[m[1]!.toLowerCase()];
    if (body == null) return token;
    // `hes`/`heses` are German-only spellings of B flat.
    if (body.startsWith('b') && language != LyNoteLanguage.deutsch) {
      return token;
    }
    return '$body${m[2]}';
  }

  /// Gathers the pitches of a `\grace`/`\acciaccatura` argument.
  ///
  /// A grace note still advances the relative reference, so it goes through
  /// [_applyRelative] like any other; it takes no time in the bar, but its
  /// duration becomes the running one, as any written duration does.
  void _collectGraces(LyNode node) {
    // A grace's duration is the running duration from then on, as any
    // note's is: LilyPond's default duration is lexical, so in
    // `\acciaccatura { g8 } f f d4` both f are eighths. Restored after the
    // grace, they read as quarters and ran the bar a beat long.
    if (node is LyNote) {
      if (node.duration != null) {
        _currentDur = _runningDuration(node.duration!);
      }
      _lastGraceEventStart = _pendingGraces.length;
      if (node.scripts.contains('~')) {
        _pendingGraceTies.add(_pendingGraces.length);
      }
      _pendingGraces.add(_transposed(_applyRelative(_parsePitch(node.pitch))));
    } else if (node is LyBlock) {
      for (final c in node.children) {
        _collectGraces(c);
      }
    } else if (node is LyChord) {
      if (node.duration != null) {
        _currentDur = _runningDuration(node.duration!);
      }
      final written = [
        for (final pStr in node.pitches) _applyRelative(_parsePitch(pStr)),
      ];
      // As after any chord, `\relative` goes on from its FIRST note.
      if (_isRelative && written.isNotEmpty) _relativeBase = written.first;
      _lastGraceEventStart = _pendingGraces.length;
      if (node.scripts.contains('~')) {
        for (var k = 0; k < written.length; k++) {
          _pendingGraceTies.add(_pendingGraces.length + k);
        }
      }
      _pendingGraces.addAll(written.map(_transposed));
    } else if (node is LyRest) {
      // A grace rest or spacer sounds nothing; only its duration carries on.
      if (node is _LyPitchedRest) _applyRelative(_parsePitch(node.pitch));
      if (node.duration case final d?) _currentDur = _runningDuration(d);
    }
  }

  Pitch _parsePitch(String pStr) {
    final m = _pitchPattern.firstMatch(_expand(pStr));
    if (m == null) return const Pitch(Step.c);

    var stepStr = m[1]!.toLowerCase();
    final accStr = (m[2] ?? '').toLowerCase();
    final marks = m[3] ?? '';

    var alter = 0;
    switch (language) {
      case LyNoteLanguage.deutsch:
        // `h` is B natural; a BARE `b` is B flat (German never writes `bes`
        // for it, though `hes`/`heses` also mean B flat / B double-flat).
        if (stepStr == 'h') {
          stepStr = 'b';
        } else if (stepStr == 'b' && accStr.isEmpty) {
          alter = -1;
        }
        alter += _isEsSuffix(accStr);
      case LyNoteLanguage.english:
        alter = _englishSuffix(accStr);
      case LyNoteLanguage.nederlands:
        alter = _isEsSuffix(accStr);
      case LyNoteLanguage.solfege:
        stepStr = _solfegeSteps[stepStr]!;
        alter = _solfegeSuffix(accStr);
    }

    // `h` only exists as a step in German; if one reaches here under another
    // language the source is mislabelled, so read it as the B it means rather
    // than throwing on an unknown enum name.
    final step = Step.values.byName(stepStr == 'h' ? 'b' : stepStr);
    final ups = "'".allMatches(marks).length;
    final downs = ','.allMatches(marks).length;

    return Pitch(step, alter: alter, octave: 3 + ups - downs);
  }

  /// The accidental pattern differs per language, so the note pattern does too.
  RegExp get _pitchPattern => switch (language) {
        LyNoteLanguage.deutsch =>
          RegExp(r"^([a-h])(ississ|essess|isis|eses|iss|ess|is|es|s)?([',]*)$"),
        LyNoteLanguage.english =>
          RegExp(r"^([a-g])(ss|ff|s|f|sharp|flat)?([',]*)$"),
        LyNoteLanguage.nederlands =>
          RegExp(r"^([a-g])(isis|eses|is|es)?([',]*)$"),
        LyNoteLanguage.solfege => RegExp(
            r"^(do|ré|re|mi|fa|sol|la|si)(dd|bb|ss|kk|x|d|b|s|k)?([',]*)$"),
      };

  static const _solfegeSteps = {
    'do': 'c',
    're': 'd',
    'ré': 'd',
    'mi': 'e',
    'fa': 'f',
    'sol': 'g',
    'la': 'a',
    'si': 'b',
  };

  /// `-d` (italiano/francais) / `-s` (espanol/portugues) / `-k` (vlaams)
  /// sharp, `-b` flat, doubled for double; `-x` is the French double sharp.
  static int _solfegeSuffix(String acc) => switch (acc) {
        'd' || 's' || 'k' => 1,
        'dd' || 'ss' || 'kk' || 'x' => 2,
        'b' => -1,
        'bb' => -2,
        _ => 0,
      };

  /// Dutch/German `-is`/`-es` accidentals.
  ///
  /// A BARE `s` is only the `es`/`as` contraction, which `_expand` has already
  /// turned into `ees`/`aes`; anything still carrying a lone `s` here (`fs`,
  /// `cs`) is not a Dutch note at all, so it must not be read as a flat.
  static int _isEsSuffix(String acc) => switch (acc) {
        'is' || 'iss' => 1,
        'isis' || 'ississ' => 2,
        'es' || 'ess' => -1,
        'eses' || 'essess' => -2,
        _ => 0,
      };

  static int _englishSuffix(String acc) => switch (acc) {
        's' || 'sharp' => 1,
        'ss' => 2,
        'f' || 'flat' => -1,
        'ff' => -2,
        _ => 0,
      };

  /// LilyPond duration → [NoteDuration].
  ///
  /// The numeric series only covers whole and shorter; anything LONGER is a
  /// word (`\breve`, `\longa`, `\maxima`). The pattern used to accept digits
  /// only, so `\breve` matched nothing and silently became a QUARTER — a
  /// four-to-one error that survives as a plausible-looking note, which is why
  /// it went unnoticed until real mensural and chorale sources were driven
  /// through the writer/reader pair.
  static const _durationWords = {
    'maxima': DurationBase.maxima,
    'longa': DurationBase.long,
    'breve': DurationBase.breve,
    'brevis': DurationBase.breve,
  };

  static const _durationNumbers = {
    '1': DurationBase.whole,
    '2': DurationBase.half,
    '4': DurationBase.quarter,
    '8': DurationBase.eighth,
    '16': DurationBase.sixteenth,
    '32': DurationBase.thirtySecond,
    '64': DurationBase.sixtyFourth,
    '128': DurationBase.oneHundredTwentyEighth,
    '256': DurationBase.twoHundredFiftySixth,
    '512': DurationBase.fiveHundredTwelfth,
    '1024': DurationBase.oneThousandTwentyFourth,
  };

  /// What a written duration's multiplier leaves over when no note value
  /// spells the product (`8*2/3`), as part of the running duration.
  Fraction _currentScale = Fraction(1, 1);

  /// Parses [durStr] as the new running duration: its note value, with the
  /// part of a multiplier no note value spells kept in [_currentScale].
  /// LilyPond's default duration carries the multiplier on: `c8*2/3 d e`
  /// is three notes of a triplet's length.
  NoteDuration _runningDuration(String durStr) {
    final d = _parseDuration(durStr);
    _currentScale = Fraction(1, 1);
    final m = RegExp(r'^[^*]*\*(\d+)(?:/(\d+))?$').firstMatch(durStr.trim());
    if (m != null) {
      final plain = _parseDuration(durStr.substring(0, durStr.indexOf('*')));
      final want = plain.toFraction() *
          Fraction(int.parse(m[1]!), int.parse(m[2] ?? '1'));
      if (d.toFraction() != want && want > Fraction.zero) {
        _currentScale = want *
            Fraction(d.toFraction().denominator, d.toFraction().numerator);
      }
    }
    return d;
  }

  /// [_addAcrossBars] for a note, chord or rest at the running duration: a
  /// multiplier no note value spells makes it a tuplet note, so `c8*2/3`
  /// lasts a twelfth (read at its written value, every note it led ran a
  /// third long and the voice fell behind).
  void _addAtRunning(
    NoteDuration written,
    String id,
    MusicElement Function(NoteDuration d, String id, bool first, bool last)
        make,
  ) {
    final scale = _currentScale;
    // A multiplier inside a tuplet stays unread, as it always has; a
    // `\scaleDurations` around it applies everywhere.
    final multiplied =
        scale != Fraction(1, 1) && _tupletRatio == Fraction(1, 1);
    final stretched = _durationScale != Fraction(1, 1);
    if (!multiplied && !stretched) {
      _addAcrossBars(written, id, make);
      return;
    }
    final saved = _tupletRatio;
    _tupletRatio =
        saved * (multiplied ? scale : Fraction(1, 1)) * _durationScale;
    _addAcrossBars(written, id, make);
    _tupletRatio = saved;
    final i = _currentElements.length - 1;
    if (multiplied) {
      _scaleSpan = _extendOrOpenSpan(_scaleSpan, i, scale, hidden: false);
    }
    if (stretched) {
      _stretchSpan =
          _extendOrOpenSpan(_stretchSpan, i, _durationScale, hidden: true);
    }
    _spanBar = _measures.length;
  }

  /// The span for the element at [i] sounding [scale] of its written value:
  /// [open] grown to take it when [open] ended on the element before in this
  /// bar's list at the same ratio — consecutive notes at one scale share one
  /// span — or else a new one.
  TupletSpan _extendOrOpenSpan(TupletSpan? open, int i, Fraction scale,
      {required bool hidden}) {
    // A span's ratio is actual:normal with actual >= 2: a doubling is 2:4.
    var actual = scale.denominator;
    var normal = scale.numerator;
    if (actual < 2) {
      actual *= 2;
      normal *= 2;
    }
    final at = open == null || _spanBar != _measures.length
        ? -1
        : _currentTuplets.indexWhere((t) => identical(t, open));
    if (open != null &&
        at >= 0 &&
        open.endIndex == i - 1 &&
        open.actual == actual &&
        open.normal == normal) {
      return _currentTuplets[at] = TupletSpan(open.startIndex, i,
          actual: actual, normal: normal, hidden: hidden);
    }
    final span =
        TupletSpan(i, i, actual: actual, normal: normal, hidden: hidden);
    _currentTuplets.add(span);
    return span;
  }

  /// The product of the `\scaleDurations` factors around the music being
  /// read: every duration sounds this multiple of its written value.
  Fraction _durationScale = Fraction(1, 1);

  /// The open hidden span of a `\scaleDurations`, as [_scaleSpan] is a
  /// multiplier's.
  TupletSpan? _stretchSpan;

  /// The `\scaleDurations` factor [node] spells: `3/2`, the older Scheme
  /// pair `#'(3 . 2)`, or a moment `#(ly:make-moment 3/2)`; null if none.
  static Fraction? _scaleFactor(LyNode node) {
    final text = node is LyWord ? node.value : '';
    final m = RegExp(r'(\d+)\s*[./]?\s*(\d+)').firstMatch(text);
    if (m == null) return null;
    final n = int.parse(m[1]!), d = int.parse(m[2]!);
    if (n == 0 || d == 0) return null;
    return Fraction(n, d);
  }

  TupletSpan? _scaleSpan;

  /// The bar in which [_scaleSpan] and [_stretchSpan] were last extended.
  int _spanBar = -1;

  NoteDuration _parseDuration(String durStr) {
    final m = RegExp(r'^\\?([A-Za-z]+|\d+)(\.*)(?:\*(\d+)(?:/(\d+))?)?$')
        .firstMatch(durStr.trim());
    if (m == null) return NoteDuration.quarter;
    final val = m[1]!;
    final dots = (m[2] ?? '').length.clamp(0, 2);
    final base = _durationNumbers[val] ??
        _durationWords[val.toLowerCase()] ??
        DurationBase.quarter;
    final plain = NoteDuration(base, dots: dots);
    if (m[3] == null) return plain;
    return _scaled(plain, int.parse(m[3]!), int.parse(m[4] ?? '1'));
  }

  /// [d] scaled by `num/den` — LilyPond's duration multiplier (`c1*3/4`).
  ///
  /// `NoteDuration` is base-plus-dots, so it cannot represent an arbitrary
  /// scaling: `c4*2/3` has no symbolic spelling. When the scaled value lands on
  /// a real note value this returns it; otherwise it returns [d] unchanged,
  /// because a slightly wrong length beats the alternative this replaced —
  /// the whole note being dropped from the score.
  static NoteDuration _scaled(NoteDuration d, int num, int den) {
    if (num <= 0 || den <= 0) return d;
    final (bn, bd) = d.fraction;
    final target = Fraction(bn * num, bd * den);
    for (final b in DurationBase.values) {
      for (var dots = 0; dots <= 2; dots++) {
        final cand = NoteDuration(b, dots: dots);
        final (cn, cd) = cand.fraction;
        if (Fraction(cn, cd) == target) return cand;
      }
    }
    return d;
  }
}

/// `b4\rest`: a rest drawn at a pitch, which `\relative` reckons from.
class _LyPitchedRest extends LyRest {
  const _LyPitchedRest(this.pitch, super.duration);

  /// The written pitch, octave marks included.
  final String pitch;
}
