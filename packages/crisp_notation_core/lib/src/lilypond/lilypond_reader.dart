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

  final reader = _LilyPondReader();
  return reader.buildScore(ast);
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
      _LilyPondReader().buildScore(
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
  Clef _clef = Clef.treble;
  KeySignature _key = const KeySignature(0);
  TimeSignature _time = TimeSignature.commonTime;

  NoteDuration _currentDur = NoteDuration.quarter;
  Pitch _relativeBase = const Pitch(Step.c, octave: 3); // c
  bool _isRelative = false;

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
      timeSignature: _time,
      measures: _measures,
      lyrics: _lyrics,
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
    final firstMeasure = _measures.length;
    final baseRelative = _relativeBase;
    final baseIsRelative = _isRelative;
    final baseDur = _currentDur;

    _processNodes(groups.first);
    _closeMeasure();
    // State to resume with once every branch has been read.
    final afterRelative = _relativeBase;
    final afterIsRelative = _isRelative;
    final afterDur = _currentDur;

    for (var g = 1; g < groups.length && g <= 3; g++) {
      final kept = List<Measure>.from(_measures);
      _measures.clear();
      _currentElements.clear();
      _currentTuplets.clear();
      _measureTime = Fraction.zero;
      _relativeBase = baseRelative;
      _isRelative = baseIsRelative;
      _currentDur = baseDur;

      _processNodes(groups[g]);
      _closeMeasure();
      final voiceMeasures = List<Measure>.from(_measures);

      _measures
        ..clear()
        ..addAll(kept);
      for (var i = 0; i < voiceMeasures.length; i++) {
        final target = firstMeasure + i;
        final elements = voiceMeasures[i].elements;
        if (elements.isEmpty) continue;
        // Tuplet spans address a voice by index, so they must travel WITH the
        // notes and be re-pointed at the voice they landed in. Dropping them
        // leaves tupleted notes counting at full value — the round-trip catches
        // it as a sounding-total drift, not as a missing note.
        final spans = [
          ..._measures.length > target
              ? _measures[target].tuplets
              : const <TupletSpan>[],
          for (final t in voiceMeasures[i].tuplets)
            TupletSpan(t.startIndex, t.endIndex,
                actual: t.actual, normal: t.normal, voice: g),
        ];
        if (target < _measures.length) {
          _measures[target] = switch (g) {
            1 => _measures[target].copyWith(voice2: elements, tuplets: spans),
            2 => _measures[target].copyWith(voice3: elements, tuplets: spans),
            _ => _measures[target].copyWith(voice4: elements, tuplets: spans),
          };
        } else {
          // This branch runs longer than voice 1 (voices need not fill the same
          // number of bars). Keep the overflow in ITS OWN voice — appending it
          // as `elements` would silently promote inner-voice notes to voice 1
          // and inflate the bar's sounding duration.
          _measures.add(switch (g) {
            1 => Measure(const [], voice2: elements),
            2 => Measure(const [], voice3: elements),
            _ => Measure(const [], voice4: elements),
          });
        }
      }
    }

    _relativeBase = afterRelative;
    _isRelative = afterIsRelative;
    _currentDur = afterDur;
  }

  void _processCommand(LyCommand cmd) {
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
              _time = TimeSignature.tryParse(n, d) ?? TimeSignature.commonTime;
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
      case 'figuremode':
      case 'drummode':
        // Chord-name / figured-bass / drum tracks are not melody notes — skip so
        // they do not inflate the note stream (e.g. Ebersberger `\new ChordNames`).
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
        for (final arg in cmd.args) {
          if (arg is LyBlock || arg is LySimultaneous) _processNodes([arg]);
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
          _processNodes([_variables[cmd.name]!]);
        }
        break;
    }
  }

  void _processNote(LyNote note) {
    if (note.duration != null) {
      _currentDur = _parseDuration(note.duration!);
    }
    final pitch = _parsePitch(note.pitch);
    final p = _applyRelative(pitch);

    _checkMeasureBoundary(_currentDur.toFraction() * _tupletRatio);
    _currentElements.add(NoteElement(
      pitches: [p],
      duration: _currentDur,
      id: 'e${_elementId++}',
    ));
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
      _currentElements.add(NoteElement(
        pitches: pitches,
        duration: _currentDur,
        id: 'e${_elementId++}',
      ));
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
    if (_currentElements.isEmpty) return;
    _measures.add(Measure(
      List.from(_currentElements),
      tuplets: List.from(_currentTuplets),
    ));
    _currentElements.clear();
    _currentTuplets.clear();
    _measureTime = Fraction.zero;
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

  Pitch _parsePitch(String pStr) {
    final noteRe = RegExp(r"^([a-g])(isis|eses|is|es)?([',]*)$");
    final m = noteRe.firstMatch(pStr);
    if (m == null) return const Pitch(Step.c);

    final stepStr = m[1]!.toLowerCase();
    final accStr = m[2] ?? '';
    final marks = m[3] ?? '';

    final step = Step.values.byName(stepStr);
    int alter = 0;
    if (accStr == 'is') alter = 1;
    if (accStr == 'isis') alter = 2;
    if (accStr == 'es') alter = -1;
    if (accStr == 'eses') alter = -2;

    final ups = "'".allMatches(marks).length;
    final downs = ','.allMatches(marks).length;

    return Pitch(step, alter: alter, octave: 3 + ups - downs);
  }

  NoteDuration _parseDuration(String durStr) {
    final baseRe = RegExp(r'^(\d+)(\.*)$');
    final m = baseRe.firstMatch(durStr);
    if (m == null) return NoteDuration.quarter;

    final val = m[1]!;
    final dots = (m[2] ?? '').length.clamp(0, 2);

    DurationBase base = DurationBase.quarter;
    switch (val) {
      case '1':
        base = DurationBase.whole;
        break;
      case '2':
        base = DurationBase.half;
        break;
      case '4':
        base = DurationBase.quarter;
        break;
      case '8':
        base = DurationBase.eighth;
        break;
      case '16':
        base = DurationBase.sixteenth;
        break;
      case '32':
        base = DurationBase.thirtySecond;
        break;
      case '64':
        base = DurationBase.sixtyFourth;
        break;
    }

    return NoteDuration(base, dots: dots);
  }
}
