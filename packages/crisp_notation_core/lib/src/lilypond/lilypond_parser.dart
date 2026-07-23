library;

import 'lilypond_lexer.dart';
import 'lilypond_ast.dart';

class LilyPondParser {
  final List<Token> tokens;
  int _pos = 0;

  LilyPondParser(this.tokens);

  List<LyNode> parse() {
    final nodes = <LyNode>[];
    while (_pos < tokens.length) {
      if (_peek().kind == TokenKind.eof) break;
      final node = _parseNode();
      if (node != null) {
        nodes.add(node);
      } else {
        _advance(); // skip unknown
      }
    }
    return nodes;
  }

  LyNode? _parseNode() {
    final token = _peek();

    if (token.kind == TokenKind.command) {
      _advance();
      if (token.value == 'score') {
        final block = _parseNextExpression();
        return LyScore([block].whereType<LyNode>().toList());
      }

      // Known commands and their arg counts
      int argsCount = 0;
      switch (token.value) {
        case 'new':
          argsCount = 1;
          break; // e.g. \new Staff
        case 'with':
          argsCount = 1;
          break;
        case 'relative':
          argsCount = 1;
          break; // e.g. \relative c'
        case 'time':
          argsCount = 1;
          break; // e.g. \time 4/4
        case 'clef':
          argsCount = 1;
          break; // e.g. \clef treble
        case 'key':
          argsCount = 2;
          break; // e.g. \key c \major
        case 'partial':
          argsCount = 1;
          break;
        case 'tempo':
          argsCount = 1;
          break; // \tempo 4 = 120 (simplified)
        case 'tuplet':
          argsCount = 1;
          break; // \tuplet 3/2 { ... }
        case 'times':
          argsCount = 1;
          break; // \times 2/3 { ... }
        case 'lyricsto':
          argsCount = 1;
          break; // \lyricsto "voice" { ... }
        case 'addlyrics':
          argsCount = 0;
          break; // \addlyrics { ... }
        case 'lyricmode':
          argsCount = 0;
          break; // \lyricmode { ... }
        // Many commands like \major, \minor take 0 args.
      }

      final args = <LyNode>[];
      for (int i = 0; i < argsCount; i++) {
        final arg = _parseNextExpression();
        if (arg != null) args.add(arg);
      }

      // If the command is naturally followed by a block (like \new Staff { ... }),
      // we don't automatically consume it unless we hardcode it, but in AST,
      // it's fine if the block is a sibling, OR we can peek if there is a { next.
      // For a generalized AST, we can let `{` be an expression of its own,
      // but Lilypond evaluates commands like functions. Let's just consume one more if it's `{` or `<<`
      // for specific commands that act as wrappers: `\new`, `\relative`, `\score`, `\tuplet`, `\times`, `\with`, `\addlyrics`, `\lyricsto`, `\lyricmode`.
      if ([
        'new',
        'with',
        'relative',
        'tuplet',
        'times',
        'addlyrics',
        'lyricsto',
        'lyricmode',
        'chordmode',
        'chords',
        'figuremode',
        'drummode'
      ].contains(token.value)) {
        final next = _peek();
        if (next.kind == TokenKind.symbol &&
            (next.value == '{' || next.value == '<<')) {
          final body = _parseNode();
          if (body != null) args.add(body);
        } else if (['addlyrics', 'lyricsto', 'lyricmode']
                .contains(token.value) &&
            next.kind == TokenKind.command) {
          final body = _parseNode();
          if (body != null) args.add(body);
        }
      }
      return LyCommand(token.value, args);
    }

    if (token.kind == TokenKind.symbol) {
      if (token.value == '{') {
        _advance();
        return LyBlock(_parseListUntil('}'));
      }
      if (token.value == '<<') {
        _advance();
        return LySimultaneous(_parseListUntil('>>'));
      }
      if (token.value == '<') {
        _advance();
        return _parseChord();
      }

      // standalone scripts like ( ) ~ [ ]
      if (['(', ')', '~', '[', ']', '|'].contains(token.value)) {
        _advance();
        return LyWord(token.value);
      }

      // -., ->, etc are parsed as words or attached to previous note?
      // The lexer yields them as standalone symbols if they follow space.
      // But if attached, they're separate tokens anyway.
      // For now, return as LyWord.
      _advance();
      return LyWord(token.value);
    }

    if (token.kind == TokenKind.word) {
      // Check for assignment: word = value
      final next = _peek(1);
      if (next.kind == TokenKind.symbol && next.value == '=') {
        _advance(2);
        final val = _parseNextExpression();
        return LyAssignment(token.value, val ?? LyWord(''));
      }

      _advance();
      // Parse as note, rest, or word
      return _parseWord(token.value);
    }

    if (token.kind == TokenKind.string) {
      _advance();
      return LyString(token.value);
    }

    _advance();
    return null;
  }

  List<LyNode> _parseListUntil(String endSymbol) {
    final list = <LyNode>[];
    while (_pos < tokens.length) {
      final t = _peek();
      if (t.kind == TokenKind.eof) break;
      if (t.kind == TokenKind.symbol && t.value == endSymbol) {
        _advance();
        break;
      }
      // LilyPond has `\\` to separate voices in `<< { } \\ { } >>`
      if (t.kind == TokenKind.symbol && t.value == '\\\\') {
        _advance();
        list.add(LyWord('\\\\'));
        continue;
      }
      final node = _parseNode();
      if (node != null) list.add(node);
    }
    return list;
  }

  LyNode? _parseNextExpression() {
    return _parseNode();
  }

  LyNode _parseChord() {
    final pitches = <String>[];
    while (_pos < tokens.length) {
      final t = _peek();
      if (t.kind == TokenKind.eof) break;
      if (t.kind == TokenKind.symbol && t.value == '>') {
        _advance();
        break;
      }
      if (t.kind == TokenKind.word) {
        pitches.add(t.value);
      }
      _advance();
    }

    // Duration and scripts follow the `>`
    String? duration;
    final scripts = <String>[];
    _parseDurationAndScripts((dur) {
      duration = dur;
    }, scripts);

    return LyChord(pitches, duration, scripts);
  }

  LyNode _parseWord(String word) {
    // Is it a rest? r, r4, r4.
    final restRe = RegExp(r'^r(\d+)?(\.*)$');
    if (restRe.hasMatch(word)) {
      final m = restRe.firstMatch(word)!;
      final durStr = (m[1] ?? '') + (m[2] ?? '');
      String? duration = durStr.isEmpty ? null : durStr;
      final scripts = <String>[];
      _parseDurationAndScripts((dur) {
        if (duration == null) duration = dur;
      }, scripts);
      return LyRest(duration);
    }

    // Is it a note?
    final noteRe = RegExp(r"^([a-g])(isis|eses|is|es)?([',]*)(\d+)?(\.*)$");
    if (noteRe.hasMatch(word)) {
      final m = noteRe.firstMatch(word)!;
      final pitch = '${m[1]}${m[2] ?? ''}${m[3] ?? ''}';
      final durStr = (m[4] ?? '') + (m[5] ?? '');
      String? duration = durStr.isEmpty ? null : durStr;

      final scripts = <String>[];
      _parseDurationAndScripts((dur) {
        if (duration == null) duration = dur;
      }, scripts);

      return LyNote(pitch, duration, scripts);
    }

    return LyWord(word);
  }

  void _parseDurationAndScripts(
      void Function(String) setDuration, List<String> scripts) {
    // Look ahead for standalone duration or scripts
    while (_pos < tokens.length) {
      final t = _peek();
      if (t.kind == TokenKind.word) {
        // Is it purely a duration?
        if (RegExp(r'^\d+\.*$').hasMatch(t.value)) {
          setDuration(t.value);
          _advance();
          continue;
        }
      } else if (t.kind == TokenKind.symbol) {
        if (['(', ')', '~', '[', ']', '-.', '->', '--', '-^']
            .contains(t.value)) {
          scripts.add(t.value);
          _advance();
          continue;
        }
      }
      break;
    }
  }

  Token _peek([int offset = 0]) {
    if (_pos + offset < tokens.length) {
      return tokens[_pos + offset];
    }
    return Token(TokenKind.eof, '', 0, 0);
  }

  void _advance([int count = 1]) {
    _pos += count;
  }
}
