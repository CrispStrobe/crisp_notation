library;

import 'lilypond_ast.dart';
import 'lilypond_lexer.dart';

/// Duration values LilyPond spells as commands rather than numbers
/// (`c\\breve`, `c\\longa`) — they never matched the numeric duration test.
const _longDurations = {'breve', 'brevis', 'longa', 'maxima'};

/// Builds a LilyPond AST ([LyNode]s) from the [Token]s a [LilyPondLexer]
/// produced. Unknown tokens are skipped, so a partially-understood file still
/// yields the structure the importer can read.
class LilyPondParser {
  /// The token stream being parsed (must end with a [TokenKind.eof]).
  final List<Token> tokens;
  int _pos = 0;

  /// Creates a parser over [tokens]; call [parse] to run it.
  LilyPondParser(this.tokens);

  /// Parses [tokens] into the top-level list of AST nodes.
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
        case 'repeat':
          argsCount = 2;
          break; // \repeat <type> <count> { ... }
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
        case 'transpose':
          // \transpose <from> <to> { music } — TWO pitch arguments, then the
          // body. Without this the command took no args at all, so the pitches
          // and the music block were left as SIBLINGS and the music became
          // unreachable once the reader started collecting staves properly.
          // Cost: a whole Lotti motet and a KWS song read as empty.
          argsCount = 2;
          break;
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
        'drummode',
        'repeat',
        'alternative',
        'transpose',
      ].contains(token.value)) {
        final next = _peek();
        if (next.kind == TokenKind.symbol &&
            (next.value == '{' || next.value == '<<')) {
          final body = _parseNode();
          if (body != null) args.add(body);
        } else if (['addlyrics', 'lyricsto', 'lyricmode', 'transpose']
                .contains(token.value) &&
            next.kind == TokenKind.command) {
          // `\transpose f g \relative c'' { … }` and `\transpose f g \melody`
          // are as ordinary as the braced form: the body of a music function is
          // any music expression, not just a block. Accepting only `{`/`<<` left
          // the body a SIBLING of the command. In a single-staff document that
          // was invisible — the sibling still got read — but a variable
          // assignment stops at one expression, so `top = \transpose f g
          // \relative …` bound `top` to a transpose with no music and stranded
          // the notes outside every staff. Two-staff scores read as silence.
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
    // ⚠️ A forced/cautionary accidental sits on the PITCH inside the chord —
    // `<f'! d'! g!>` — and the pitch texts are stored verbatim, so `_parsePitch`
    // saw `f'!`, failed, and the whole chord collapsed to middle C. Strip the
    // mark and carry it as a chord-level script, the way a single note carries
    // its own.
    for (var i = 0; i < pitches.length; i++) {
      final v = pitches[i];
      if (v.endsWith('!') || v.endsWith('?')) {
        pitches[i] = v.substring(0, v.length - 1);
        scripts.add(v[v.length - 1]);
      }
    }
    _parseDurationAndScripts((dur) {
      duration = dur;
    }, scripts);

    return LyChord(pitches, duration, scripts);
  }

  LyNode _parseWord(String word) {
    // Is it a rest? r, r4, r4.
    final restRe = RegExp(r'^r(\d+)?(\.*)(\*\d+(?:/\d+)?)?$');
    if (restRe.hasMatch(word)) {
      final m = restRe.firstMatch(word)!;
      final durStr = (m[1] ?? '') + (m[2] ?? '') + (m[3] ?? '');
      String? duration = durStr.isEmpty ? null : durStr;
      final scripts = <String>[];
      _parseDurationAndScripts((dur) {
        duration ??= dur;
      }, scripts);
      return LyRest(duration);
    }

    // Is it a note?
    //
    // This gate decides what is a NOTE at all, so anything it rejects is
    // dropped silently rather than mis-read. It therefore has to admit every
    // note-name language the reader can be asked to interpret, and let the
    // reader (which knows the `\language`) decide what each token MEANS:
    //   * `h` — B natural in German.
    //   * `es`/`as` and `eses`/`ases`/`asas` — the Dutch/German contractions of
    //     `ees`/`aes`/`eeses`/`aeses`, and the NORMAL spelling in real scores.
    //   * `-s`/`-f`/`-ss`/`-ff`/`-sharp`/`-flat` — English accidentals.
    // Longest alternatives first, or `es` would swallow the `e` of `eses`.
    //
    // The trailing `*N` / `*N/M` is LilyPond's duration MULTIPLIER (`c1*3/4`,
    // `s1*4`). `*` and `/` are not symbol prefixes, so the lexer hands the whole
    // thing over as ONE word — and because this regex is `$`-anchored, rejecting
    // it did not mis-read the note, it made the note vanish: `c1*3/4 d1` read as
    // a single note. Admit the multiplier here and let the reader scale it.
    //
    // `!` (forced) and `?` (cautionary) sit between the octave marks and the
    // duration, and rejecting them cost the whole note for the same reason the
    // multiplier did: `c'4 d'!4 e'!4 f'?4` read as ONE note, not four. Both are
    // ordinary in engraved music, so this was silent loss across the corpus.
    final noteRe = RegExp(
      r"^([a-h])(isis|eses|sharp|flat|ses|sas|is|es|ss|ff|s|f)?([',]*)"
      r'([!?]?)(\d+)?(\.*)(\*\d+(?:/\d+)?)?$',
    );
    if (noteRe.hasMatch(word)) {
      final m = noteRe.firstMatch(word)!;
      final pitch = '${m[1]}${m[2] ?? ''}${m[3] ?? ''}';
      // A multiplier only travels with an explicit base (`c1*3/4`). Bare
      // `c*3/4` scales the INHERITED duration, which this string cannot carry —
      // so the note keeps the inherited value rather than being dropped.
      final durStr =
          (m[5] ?? '') + (m[6] ?? '') + (m[5] == null ? '' : (m[7] ?? ''));
      String? duration = durStr.isEmpty ? null : durStr;

      final scripts = <String>[];
      // Carried as a script so it rides with the note the way `~` does.
      if ((m[4] ?? '').isNotEmpty) scripts.add(m[4]!);
      _parseDurationAndScripts((dur) {
        duration ??= dur;
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
      } else if (t.kind == TokenKind.command &&
          _longDurations.contains(t.value)) {
        // A word duration can still be dotted (`c\breve.`), and the dots lex
        // as their own token — dropping them shortened a dotted breve by a
        // third.
        var value = t.value;
        _advance();
        while (
            _pos < tokens.length && RegExp(r'^\.+$').hasMatch(_peek().value)) {
          value += _peek().value;
          _advance();
        }
        setDuration(value);
        continue;
      } else if (t.kind == TokenKind.symbol) {
        if (['(', ')', '~', '[', ']', '-.', '->', '--', '-^']
                .contains(t.value) ||
            RegExp(r'^-[0-9]$').hasMatch(t.value)) {
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
