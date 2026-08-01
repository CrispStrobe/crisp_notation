library;

import '../layout/multi_part.dart';
import '../layout/staff_system.dart';
import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/tempo.dart';
import '../theory/time_signature.dart';
import 'lilypond_ast.dart';
import 'lilypond_lexer.dart';
import 'lilypond_parser.dart';

/// Parses a LilyPond string into a [Score].
Score scoreFromLilyPond(String ly) {
  final lexer = LilyPondLexer(ly);
  final tokens = lexer.tokenize();
  final parser = LilyPondParser(tokens);
  final ast = parser.parse();

  final reader = _LilyPondReader(language: detectLyNoteLanguage(ly));
  return reader.buildScore(ast);
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
    case 'deutsch':
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
  _StaffContent(this.nodes, this.instrument);
  final List<LyNode> nodes;
  final String? instrument;
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
MultiPartScore multiPartFromLilyPond(String ly) {
  final language = detectLyNoteLanguage(ly);
  final tokens = LilyPondLexer(ly).tokenize();
  final ast = LilyPondParser(tokens).parse();

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

  if (staves.length < 2) {
    // One (or zero) staff → the existing single-part behaviour, unchanged.
    return MultiPartScore.fromStaffSystem(
      StaffSystem([scoreFromLilyPond(ly)]),
    );
  }

  final parts = <Score>[
    for (var i = 0; i < staves.length; i++)
      _LilyPondReader(language: language).buildScore(
        [...assignments, ...staves[i].nodes],
        metadata: ScoreMetadata(
          // Header fields are document-level → carried on the first part (which
          // is where multiPartToLilyPond reads them back from).
          title: i == 0 ? header.title : null,
          composer: i == 0 ? header.composer : null,
          lyricist: i == 0 ? header.lyricist : null,
          copyright: i == 0 ? header.copyright : null,
          instrument: staves[i].instrument,
        ),
      ),
  ];
  return MultiPartScore(parts);
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
/// the music absorbed into the current staff.
bool _isStaffBoundary(LyNode node) {
  final t = _contextType(node);
  return _staffLeafTypes.contains(t) || _staffContainerTypes.contains(t);
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

  void walk(List<LyNode> nodes) {
    var i = 0;
    while (i < nodes.length) {
      final node = nodes[i];
      final type = _contextType(node);

      if (node is LyScore) {
        walk(node.contents);
        i++;
      } else if (_staffContainerTypes.contains(type)) {
        walk((node as LyCommand).args.skip(1).toList()); // recurse into group
        i++;
      } else if (_staffLeafTypes.contains(type)) {
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
        while (i < nodes.length && !_isStaffBoundary(nodes[i])) {
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
        out.add(_StaffContent([...music, ...lyrics], instrument));
      } else if (node is LyBlock) {
        walk(node.children);
        i++;
      } else if (node is LySimultaneous) {
        walk(node.children);
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

class _LilyPondReader {
  _LilyPondReader({this.language = LyNoteLanguage.nederlands});

  /// Note-name language of the source being read.
  final LyNoteLanguage language;

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

  /// The note a `(` opened on, waiting for its `)`. LilyPond allows one slur at
  /// a time (a PHRASING slur is the separate `\(`…`\)`), so one slot is right;
  /// a stack would silently accept input LilyPond itself rejects.
  String? _openSlurStart;

  /// A `\time` seen after the first, waiting for the measure it starts.
  TimeSignature? _pendingTimeChange;

  /// The score's initial `\tempo`, and a later one awaiting its measure.
  Tempo? _tempo;
  Tempo? _pendingTempoChange;

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
  int _currentVerse = 1;

  Fraction _tupletRatio = Fraction(1, 1);
  Fraction _measureTime = Fraction.zero;
  int _elementId = 0;

  Score buildScore(List<LyNode> nodes,
      {ScoreMetadata metadata = const ScoreMetadata()}) {
    _processNodes(nodes);
    _closeMeasure(); // close any pending

    if (_measures.isEmpty) {
      _measures.add(Measure([RestElement(NoteDuration.whole, id: 'e0')]));
    }

    return Score(
      clef: _clef,
      keySignature: _key,
      timeSignature: _initialTime ?? _time,
      tempo: _tempo,
      measures: _measures,
      lyrics: _lyrics,
      slurs: _slurs,
      dynamics: _dynamics,
      hairpins: _hairpins,
      annotations: _annotations,
      chordSymbols: _buildChordSymbols(_measures),
      metadata: metadata,
    );
  }

  List<String> _extractLyricsSyllables(LyNode node) {
    if (node is LyWord) {
      if (RegExp(r'^[\d\.]+$').hasMatch(node.value)) return [];
      return [node.value];
    }
    if (node is LyString) return [node.value];
    if (node is LyNote) return [node.pitch];
    if (node is LyRest) return ['_'];
    if (node is LyBlock) {
      return node.children.expand(_extractLyricsSyllables).toList();
    }
    if (node is LySimultaneous) {
      return node.children.expand(_extractLyricsSyllables).toList();
    }
    if (node is LyCommand) {
      if (_variables.containsKey(node.name)) {
        return _extractLyricsSyllables(_variables[node.name]!);
      }
      return node.args.expand(_extractLyricsSyllables).toList();
    }
    return [];
  }

  /// LilyPond's shorthand articulation scripts, as the writer emits them.
  static const _scriptArtics = {
    '-.': Articulation.staccato,
    '--': Articulation.tenuto,
    '->': Articulation.accent,
    '-^': Articulation.marcato,
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
    'sfz': DynamicLevel.sf,
    'sff': DynamicLevel.ff,
    'fp': DynamicLevel.f,
    'rfz': DynamicLevel.sf,
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
        if (open != null && id != null && id != open.startId) {
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

  void _alignLyrics(List<String> syllables) {
    final noteIds = <String>[];
    for (final m in _measures) {
      for (final e in m.elements) {
        if (e is NoteElement && e.id != null) noteIds.add(e.id!);
      }
    }
    for (final e in _currentElements) {
      if (e is NoteElement && e.id != null) noteIds.add(e.id!);
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
          hyphenToNext: hyphen, extender: extender, verse: _currentVerse));

      noteIndex++;
      syllableIndex = lookahead;
    }
    _currentVerse++;
  }

  void _processNodes(List<LyNode> nodes) {
    for (var idx = 0; idx < nodes.length; idx++) {
      final node = nodes[idx];
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
        var alts = const <LyNode>[];
        if (idx + 1 < nodes.length) {
          final nxt = nodes[idx + 1];
          if (nxt is LyCommand &&
              nxt.name == 'alternative' &&
              nxt.args.isNotEmpty) {
            final arg = nxt.args.last;
            if (arg is LyBlock) {
              final inner = arg.children.whereType<LyBlock>().toList();
              alts = inner.isNotEmpty ? inner : [arg];
            }
            idx++; // consume the \alternative
          }
        }
        if (body != null) {
          if (type == 'unfold') {
            for (var pass = 0; pass < count; pass++) {
              _processNodes(
                  [body]); // written out N times; relative base continues
            }
          } else {
            _processNodes(
                [body]); // volta/percent/tremolo: sounded once in MIDI
          }
          for (final alt in alts) {
            _processNodes([alt]); // all alternatives, once, linearly
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
      } else if (node is LyRest) {
        _processRest(node);
      } else if (node is LyChord) {
        _processChord(node);
      } else if (node is LyWord) {
        if (node.value == '|') {
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
        // No `\\` — a plain simultaneous container (e.g. the body of
        // `\new Staff = "x" << … >>`), read sequentially as before.
        bool mainVoice = true;
        for (final child in node.children) {
          if (child is LyWord && child.value == '\\\\') {
            mainVoice = false;
          }
          if (mainVoice) {
            _processNodes([child]);
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
    // ⚠️ NOT derivable from `startPrefix`. `\partial` implements the anacrusis
    // by PRELOADING elapsed time (a 4/4 bar with `\partial 4` starts at 3/4),
    // so rewinding a branch to zero would hand it a full bar and the pickup
    // would swallow the next three beats of voice 2.
    final startTime = _measureTime;
    final startPending = {
      for (final e in _pendingVoices.entries)
        e.key: List<MusicElement>.from(e.value),
    };
    final startPendingTuplets = List<TupletSpan>.from(_pendingVoiceTuplets);
    final baseRelative = _relativeBase;
    final baseIsRelative = _isRelative;
    final baseDur = _currentDur;
    final before = List<Measure>.from(_measures);

    // Voice 1 runs normally and is deliberately NOT closed. Closing here is
    // what used to invent a barline: `<< … >> r4 << … >>` is ONE bar of 4/4,
    // and forcing a close after each group read it as three. Bars now end only
    // when they fill, via _checkMeasureBoundary.
    _processNodes(groups.first);

    final afterMeasures = List<Measure>.from(_measures);
    final afterElements = List<MusicElement>.from(_currentElements);
    final afterTuplets = List<TupletSpan>.from(_currentTuplets);
    final afterTime = _measureTime;
    // A voice split does NOT advance the relative reference: after `>>` the
    // music continues from where it stood BEFORE the `<<`. LilyPond wraps each
    // `\\` branch in its own Voice context, and that wrapper does not
    // propagate the octave reference outward the way plain sequential music
    // does — so a branch's last note is invisible to whatever follows.
    //
    // Taking it from the first branch instead makes the reference creep upward
    // on every split, and the error compounds: the Banister piano part climbed
    // to MIDI 171 over 48 bars, and the same file reads 50..101 — an actual
    // piano range — once the reference reverts. Three corpus files were left
    // with impossible pitches by this alone.
    final afterRelative = baseRelative;
    final afterIsRelative = _isRelative;
    final afterDur = _currentDur;

    // Read each remaining branch from the group's START state, collecting its
    // bars plus whatever it leaves open. Branches are read in isolation and
    // merged afterwards, so none can disturb another.
    final branches = <int, List<(List<MusicElement>, List<TupletSpan>)>>{};
    for (var g = 1; g < groups.length && g <= 3; g++) {
      _measures
        ..clear()
        ..addAll(before);
      _currentElements.clear();
      _currentTuplets.clear();
      _pendingVoices.clear();
      _pendingVoiceTuplets.clear();
      // Rewind to the group's bar position, preload included.
      _measureTime = startTime;
      // Occupy the bar up to the split so this branch's notes land at voice 1's
      // offsets. Whatever this voice already sang earlier in the bar comes
      // first; the rest is silence, which is what an inner voice renders there.
      // These are POSITIONS ONLY — `_measureTime` already accounts for them.
      final carried = startPending[g] ?? const <MusicElement>[];
      _currentElements.addAll(carried);
      var covered = carried.fold(
        Fraction.zero,
        (a, e) => a + e.duration.toFraction(),
      );
      final prefixTotal = startPrefix.fold(
        Fraction.zero,
        (a, e) => a + e.duration.toFraction(),
      );
      for (final e in startPrefix) {
        if (!(covered < prefixTotal)) break;
        _currentElements.add(RestElement(e.duration));
        covered = covered + e.duration.toFraction();
      }
      _relativeBase = baseRelative;
      _isRelative = baseIsRelative;
      _currentDur = baseDur;

      _processNodes(groups[g]);

      branches[g] = [
        for (var i = startMeasure; i < _measures.length; i++)
          (_measures[i].elements, _measures[i].tuplets),
        (
          List<MusicElement>.from(_currentElements),
          List<TupletSpan>.from(_currentTuplets)
        ),
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
    // Keep what earlier groups in this bar contributed. A branch that reaches
    // the open bar replaces its OWN slot — its output already carries that
    // earlier content, seeded above — and leaves the other voices alone.
    _pendingVoices
      ..clear()
      ..addAll(startPending);
    _pendingVoiceTuplets
      ..clear()
      ..addAll(startPendingTuplets);

    for (final entry in branches.entries) {
      final g = entry.key;
      for (var i = 0; i < entry.value.length; i++) {
        final (elements, tuplets) = entry.value[i];
        if (elements.isEmpty) continue;
        final target = startMeasure + i;
        // Tuplet spans address a voice by index, so they must travel WITH the
        // notes and be re-pointed at the voice they landed in. Dropping them
        // leaves tupleted notes counting at full value — the round-trip catches
        // it as a sounding-total drift, not as a missing note.
        final spans = [
          for (final t in tuplets)
            TupletSpan(t.startIndex, t.endIndex,
                actual: t.actual, normal: t.normal, voice: g),
        ];
        if (target < _measures.length) {
          final keep = _measures[target].tuplets;
          _measures[target] = switch (g) {
            1 => _measures[target]
                .copyWith(voice2: elements, tuplets: [...keep, ...spans]),
            2 => _measures[target]
                .copyWith(voice3: elements, tuplets: [...keep, ...spans]),
            _ => _measures[target]
                .copyWith(voice4: elements, tuplets: [...keep, ...spans]),
          };
        } else if (target == _measures.length) {
          // Lands in the bar still being filled — hold it until that closes.
          _pendingVoices[g] = List<MusicElement>.from(elements);
          _pendingVoiceTuplets.addAll(spans);
        } else {
          // This branch runs longer than voice 1 (voices need not fill the same
          // number of bars). Keep the overflow in ITS OWN voice — appending it
          // as `elements` would silently promote inner-voice notes to voice 1
          // and inflate the bar's sounding duration. It is QUEUED rather than
          // appended, because voice 1's bar is still open and would otherwise
          // close behind it.
          _pendingOverflow.add(switch (g) {
            1 => Measure(const [], voice2: elements, tuplets: spans),
            2 => Measure(const [], voice3: elements, tuplets: spans),
            _ => Measure(const [], voice4: elements, tuplets: spans),
          });
        }
      }
    }

    _relativeBase = afterRelative;
    _isRelative = afterIsRelative;
    _currentDur = afterDur;
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

        LyNode? block;
        if (cmd.args.isNotEmpty) {
          final first = cmd.args.first;
          if (first is LyWord) {
            _relativeBase = _parsePitch(first.value);
            if (cmd.args.length > 1) block = cmd.args[1];
          } else if (first is LyNote) {
            _relativeBase = _parsePitch(first.pitch);
            if (cmd.args.length > 1) block = cmd.args[1];
          } else if (first is LyBlock) {
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
        if (cmd.args.isNotEmpty && cmd.args.first is LyString) {
          final c = (cmd.args.first as LyString).value;
          if (c == 'bass') {
            _clef = Clef.bass;
          } else if (c == 'alto') {
            _clef = Clef.alto;
          } else if (c == 'tenor') {
            _clef = Clef.tenor;
          } else {
            _clef = Clef.treble;
          }
        } else if (cmd.args.isNotEmpty && cmd.args.first is LyWord) {
          final c = (cmd.args.first as LyWord).value;
          if (c == 'bass') {
            _clef = Clef.bass;
          } else if (c == 'alto') {
            _clef = Clef.alto;
          } else if (c == 'tenor') {
            _clef = Clef.tenor;
          } else {
            _clef = Clef.treble;
          }
        }
        break;
      case 'time':
        if (cmd.args.isNotEmpty && cmd.args.first is LyWord) {
          final parts = (cmd.args.first as LyWord).value.split('/');
          if (parts.length == 2) {
            final n = int.tryParse(parts[0]);
            final d = int.tryParse(parts[1]);
            if (n != null && d != null) {
              final parsed =
                  TimeSignature.tryParse(n, d) ?? TimeSignature.commonTime;
              if (_initialTime == null) {
                _initialTime = parsed;
                _time = parsed;
              } else if (parsed != _time) {
                _pendingTimeChange = parsed;
                // Notes already in this bar means the bar was written under the
                // OLD meter, so the change opens the next one — and the running
                // capacity must not move until then either.
                _timeChangeIsForNextMeasure = _currentElements.isNotEmpty;
                if (!_timeChangeIsForNextMeasure) _time = parsed;
              } else {
                _time = parsed;
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
          if (tonic != null) {
            final p = _parsePitch(tonic);
            _key = KeySignature(_fifthsFor(p.step, p.alter, major));
          }
        }
        break;
      case 'partial':
        // Anacrusis: preload elapsed time so the first auto-barline falls right
        // after the pickup (LilyPond emits no explicit '|' for it).
        if (cmd.args.isNotEmpty) {
          final a = cmd.args.first;
          final durStr = a is LyWord
              ? a.value
              : (a is LyNote ? (a.duration ?? a.pitch) : '');
          final partial = _parseDuration(durStr).toFraction();
          final cap = Fraction(_time.beats, _time.beatUnit);
          final remaining = cap - partial;
          _measureTime = remaining > Fraction.zero ? remaining : Fraction.zero;
        }
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
      case 'drummode':
        // Figured-bass / drum tracks are not melody notes either, and we have no
        // model for them yet — skip so they do not inflate the note stream.
        break;
      case 'addlyrics':
      case 'lyricsto':
      case 'lyricmode':
        final syllables = <String>[];
        for (final arg in cmd.args) {
          syllables.addAll(_extractLyricsSyllables(arg));
        }
        if (syllables.isNotEmpty) {
          _alignLyrics(syllables);
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
        if (cmd.args.length > 1) {
          block = cmd.args[1];
        }
        if (block != null) {
          final oldRatio = _tupletRatio;
          _tupletRatio = ratio;
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
      case 'transpose':
        // `\transpose <from> <to> { music }` — read the MUSIC.
        //
        // ⚠️ The pitches are NOT applied: DurationBase-style, there is no
        // transposition step here yet, so the notes read at WRITTEN pitch. That
        // is a known, bounded inaccuracy and it is strictly better than the
        // alternative, which was losing the music entirely — a Lotti motet
        // (157 notes) and a KWS song both read as empty.
        // TODO: apply the interval via Pitch.transposeBy once from/to are
        // resolved into an Interval incl. direction and compound cases.
        //
        // The body may be a command rather than a block — `\transpose f g
        // \relative c'' { … }` is the common spelling. The two pitch arguments
        // parse as notes, so forwarding commands as well cannot re-admit them.
        for (final arg in cmd.args) {
          if (arg is LyBlock || arg is LySimultaneous || arg is LyCommand) {
            _processNodes([arg]);
          }
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
        for (final arg in cmd.args) {
          if (arg is LyBlock || arg is LySimultaneous) _processNodes([arg]);
        }
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
    if (scripts.contains('(')) _openSlurStart ??= id;
    if (scripts.contains(')')) {
      final start = _openSlurStart;
      if (start != null && start != id) _slurs.add(Slur(start, id));
      _openSlurStart = null;
    }
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
    if (note.duration != null) {
      _currentDur = _parseDuration(note.duration!);
    }
    final pitch = _parsePitch(note.pitch);
    final p = _applyRelative(pitch);

    if (_expectGrace) {
      // This note IS the grace; it must not occupy time in the bar.
      _expectGrace = false;
      _pendingGraces.add(p);
      return;
    }

    _checkMeasureBoundary(_currentDur.toFraction() * _tupletRatio);
    final graces = List<Pitch>.from(_pendingGraces);
    final graceStyle = _pendingGraceStyle;
    _pendingGraces.clear();
    final id = 'e${_elementId++}';
    _currentElements.add(NoteElement(
      graceNotes: graces,
      graceStyle: graceStyle,
      pitches: [p],
      duration: _currentDur,
      articulations: _articsFrom(note.scripts),
      tieToNext: note.scripts.contains('~'),
      id: id,
    ));
    _applySlurScripts(note.scripts, id);
    _measureTime = _measureTime + (_currentDur.toFraction() * _tupletRatio);
  }

  void _processChord(LyChord chord) {
    if (chord.duration != null) {
      _currentDur = _parseDuration(chord.duration!);
    }
    // LilyPond relative rule for chords: each note is relative to the previous
    // note IN THE CHORD, but the reference carried to the NEXT event is the
    // chord's FIRST note — NOT its last. Applying the running base to every note
    // (as _applyRelative does) is right within the chord; afterwards we must
    // restore the base to the first note, or octaves drift upward on every
    // subsequent chord (e.g. `<d a'> <d a'> …` would climb without bound).
    final pitches =
        chord.pitches.map((pStr) => _applyRelative(_parsePitch(pStr))).toList();
    if (_isRelative && pitches.isNotEmpty) {
      _relativeBase = pitches.first;
    }
    if (pitches.isNotEmpty) {
      _checkMeasureBoundary(_currentDur.toFraction() * _tupletRatio);
      // A grace can precede a CHORD just as it can a single note; attaching it
      // only in _processNote silently dropped every grace on a chord.
      final graces = List<Pitch>.from(_pendingGraces);
      final graceStyle = _pendingGraceStyle;
      _pendingGraces.clear();
      final id = 'e${_elementId++}';
      _currentElements.add(NoteElement(
        graceNotes: graces,
        graceStyle: graceStyle,
        pitches: pitches,
        duration: _currentDur,
        articulations: _articsFrom(chord.scripts),
        tieToNext: chord.scripts.contains('~'),
        id: id,
      ));
      _applySlurScripts(chord.scripts, id);
      _measureTime = _measureTime + (_currentDur.toFraction() * _tupletRatio);
    }
  }

  void _processRest(LyRest rest) {
    if (rest.duration != null) {
      _currentDur = _parseDuration(rest.duration!);
    }
    _checkMeasureBoundary(_currentDur.toFraction() * _tupletRatio);
    _currentElements.add(RestElement(_currentDur, id: 'e${_elementId++}'));
    _measureTime = _measureTime + (_currentDur.toFraction() * _tupletRatio);
  }

  void _checkMeasureBoundary(Fraction nextDur) {
    final capacity = Fraction(_time.beats, _time.beatUnit);
    if (_measureTime + nextDur > capacity && _currentElements.isNotEmpty) {
      _closeMeasure();
    }
  }

  void _closeMeasure() {
    if (_currentElements.isEmpty && _pendingVoices.isEmpty) return;
    _measures.add(Measure(
      List.from(_currentElements),
      voice2: List.from(_pendingVoices[1] ?? const []),
      voice3: List.from(_pendingVoices[2] ?? const []),
      voice4: List.from(_pendingVoices[3] ?? const []),
      tuplets: [..._currentTuplets, ..._pendingVoiceTuplets],
      timeChange: _timeChangeIsForNextMeasure ? null : _pendingTimeChange,
      tempoChange: _pendingTempoChange,
    ));
    _pendingTempoChange = null;
    if (_timeChangeIsForNextMeasure) {
      // It lands on the bar that starts now; the capacity takes effect here too.
      _timeChangeIsForNextMeasure = false;
      if (_pendingTimeChange != null) _time = _pendingTimeChange!;
    } else {
      _pendingTimeChange = null;
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

  /// Chord-track entries, as (onset from the track's start, source text).
  final List<({Fraction onset, String text})> _chordTrack = [];

  /// Walks a `\chordmode` block recording each chord and where it falls.
  ///
  /// LilyPond writes a plain triad as a bare note (`f4`) and a qualified chord as
  /// one word (`c:7`, `bes:maj7`, `c:7/e`), so both node shapes appear here.
  /// Durations inherit from the previous chord exactly as they do for notes.
  void _collectChordTrack(List<LyNode> nodes) {
    var cursor = Fraction.zero;
    var dur = const NoteDuration(DurationBase.quarter);
    void walk(List<LyNode> ns) {
      for (final n in ns) {
        if (n is LyBlock) {
          walk(n.children);
        } else if (n is LyNote) {
          if (n.duration != null) dur = _parseDuration(n.duration!);
          // A SKIP holds the track's place and names no chord. Note names are
          // a-g, so `s` (and `r`) can only be a skip or a rest — reading one as
          // a chord root yields a phantom major triad on every unharmonised
          // beat, which is what a chord track is mostly made of.
          if (!_isChordSkip(n.pitch)) {
            _chordTrack.add((onset: cursor, text: n.pitch));
          }
          cursor += dur.toFraction();
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
          if (!_isChordSkip(m.group(1)!)) {
            _chordTrack
                .add((onset: cursor, text: '${m.group(1)}${m.group(4)}'));
          }
          cursor += _withMultiplier(dur.toFraction(), m.group(3));
        } else if (n is LyRest) {
          if (n.duration != null) dur = _parseDuration(n.duration!);
          cursor += dur.toFraction();
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
  /// elapsed time and each chord takes the first note sounding at or after it.
  /// A chord with nothing after it is dropped rather than anchored to a guess.
  List<ChordSymbol> _buildChordSymbols(List<Measure> measures) {
    if (_chordTrack.isEmpty) return const [];
    final noteAt = <({Fraction onset, String id})>[];
    var t = Fraction.zero;
    for (final m in measures) {
      for (final e in m.elements) {
        if (e is NoteElement && e.id != null) {
          noteAt.add((onset: t, id: e.id!));
        }
        if (e is NoteElement) t += e.duration.toFraction();
        if (e is RestElement) t += e.duration.toFraction();
      }
    }
    if (noteAt.isEmpty) return const [];

    final out = <ChordSymbol>[];
    final used = <String>{};
    for (final c in _chordTrack) {
      final parsed = _parseChordText(c.text);
      if (parsed == null) continue;
      // The first note at or after the chord, skipping any already carrying a
      // symbol. Advancing rather than dropping matters: a chord track is often
      // DENSER than the melody it sits over, and a first version that dropped
      // collisions silently lost 2 of 7 chords in a four-bar example — including
      // a real Gm7. A shifted chord is a small timing error; a missing one is a
      // hole in the chart.
      final hit = noteAt
          .where((n) => n.onset >= c.onset && !used.contains(n.id))
          .firstOrNull;
      if (hit == null) continue;
      used.add(hit.id);
      out.add(ChordSymbol(hit.id, parsed.root, parsed.kind, bass: parsed.bass));
    }
    return out;
  }

  /// `c:7/e` → root C, dominant seventh, bass E. Null when the root will not
  /// parse; an unknown QUALITY degrades to a major triad rather than dropping the
  /// chord, since the root is the part a player most needs.
  ({Pitch root, ChordSymbolKind kind, Pitch? bass})? _parseChordText(String s) {
    final slash = s.split('/');
    final head = slash.first;
    final colon = head.indexOf(':');
    final rootStr = colon < 0 ? head : head.substring(0, colon);
    final mods = colon < 0 ? '' : head.substring(colon + 1);
    Pitch root;
    try {
      root = _parsePitch(rootStr);
    } catch (_) {
      return null;
    }
    Pitch? bass;
    if (slash.length > 1) {
      try {
        bass = _parsePitch(slash[1]);
      } catch (_) {
        bass = null;
      }
    }
    return (root: root, kind: _chordKindOf(mods), bass: bass);
  }

  static ChordSymbolKind _chordKindOf(String mods) {
    final m = mods.toLowerCase().replaceAll('.', '');
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
      _ => ChordSymbolKind.major,
    };
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
  /// [_applyRelative] like any other; its DURATION does not affect the bar, so
  /// the running duration is restored afterwards.
  void _collectGraces(LyNode node) {
    if (node is LyNote) {
      final saved = _currentDur;
      if (node.duration != null) _currentDur = _parseDuration(node.duration!);
      _pendingGraces.add(_applyRelative(_parsePitch(node.pitch)));
      _currentDur = saved;
    } else if (node is LyBlock) {
      for (final c in node.children) {
        _collectGraces(c);
      }
    } else if (node is LyChord) {
      for (final pStr in node.pitches) {
        _pendingGraces.add(_applyRelative(_parsePitch(pStr)));
      }
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
          RegExp(r"^([a-h])(isis|eses|is|es|s)?([',]*)$"),
        LyNoteLanguage.english =>
          RegExp(r"^([a-g])(ss|ff|s|f|sharp|flat)?([',]*)$"),
        LyNoteLanguage.nederlands =>
          RegExp(r"^([a-g])(isis|eses|is|es)?([',]*)$"),
      };

  /// Dutch/German `-is`/`-es` accidentals.
  ///
  /// A BARE `s` is only the `es`/`as` contraction, which `_expand` has already
  /// turned into `ees`/`aes`; anything still carrying a lone `s` here (`fs`,
  /// `cs`) is not a Dutch note at all, so it must not be read as a flat.
  static int _isEsSuffix(String acc) => switch (acc) {
        'is' => 1,
        'isis' => 2,
        'es' => -1,
        'eses' => -2,
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
    'maxima': DurationBase.long, // no maxima in the model; longa is the longest
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
