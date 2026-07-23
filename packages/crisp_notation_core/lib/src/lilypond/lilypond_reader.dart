library;

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

class _LilyPondReader {
  Clef _clef = Clef.treble;
  KeySignature _key = const KeySignature(0);
  TimeSignature _time = TimeSignature.commonTime;

  NoteDuration _currentDur = NoteDuration.quarter;
  Pitch _relativeBase = const Pitch(Step.c, octave: 3); // c
  bool _isRelative = false;

  final List<Measure> _measures = [];
  List<MusicElement> _currentElements = [];
  List<TupletSpan> _currentTuplets = [];
  final List<Lyric> _lyrics = [];
  final Map<String, LyNode> _variables = {};
  int _currentVerse = 1;

  Fraction _tupletRatio = Fraction(1, 1);
  Fraction _measureTime = Fraction.zero;
  int _elementId = 0;

  Score buildScore(List<LyNode> nodes) {
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
    if (node is LyBlock)
      return node.children.expand(_extractLyricsSyllables).toList();
    if (node is LySimultaneous)
      return node.children.expand(_extractLyricsSyllables).toList();
    if (node is LyCommand) {
      if (_variables.containsKey(node.name))
        return _extractLyricsSyllables(_variables[node.name]!);
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

      String text = syl;
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
    for (final node in nodes) {
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
                  for (final arg in n.args)
                    syllables.addAll(_extractLyricsSyllables(arg));
                  if (syllables.isNotEmpty) _alignLyrics(syllables);
                } else if (n.name == 'new' || n.name == 'with') {
                  for (final arg in n.args) runLyricsCommands(arg);
                }
              } else if (n is LyBlock) {
                for (final c in n.children) runLyricsCommands(c);
              }
            }

            runLyricsCommands(child);
          }
        }
      }
    }
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
          if (c == 'bass')
            _clef = Clef.bass;
          else if (c == 'alto')
            _clef = Clef.alto;
          else if (c == 'tenor')
            _clef = Clef.tenor;
          else
            _clef = Clef.treble;
        } else if (cmd.args.isNotEmpty && cmd.args.first is LyWord) {
          final c = (cmd.args.first as LyWord).value;
          if (c == 'bass')
            _clef = Clef.bass;
          else if (c == 'alto')
            _clef = Clef.alto;
          else if (c == 'tenor')
            _clef = Clef.tenor;
          else
            _clef = Clef.treble;
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

          _processNodes([block]);

          final endIndex = _currentElements.length - 1;
          if (endIndex >= startIndex) {
            _currentTuplets.add(TupletSpan(startIndex, endIndex,
                actual: actual, normal: normal));
          }

          _tupletRatio = oldRatio;
        }
        break;
      case 'new':
      case 'with':
        // pass through inner blocks
        for (final arg in cmd.args) {
          if (arg is LyBlock) _processNodes([arg]);
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
    final pitches =
        chord.pitches.map((pStr) => _applyRelative(_parsePitch(pStr))).toList();
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
    final downs = ",".allMatches(marks).length;

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
