library;

/// The kinds of token the [LilyPondLexer] emits.
enum TokenKind {
  /// A backslash command like `\key` (value is the name without the backslash).
  command,

  /// A bare word / identifier or a pitch/duration run.
  word,

  /// A double-quoted string literal (value already unquoted).
  string,

  /// A punctuation symbol such as `{`, `}`, `<<`, `>>`, `=`, `<`, `>`.
  symbol,

  /// End of input.
  eof,
}

/// One lexical token with its source position (1-based [line]/[column]).
class Token {
  /// What kind of token this is.
  final TokenKind kind;

  /// The token's text (unquoted for a [TokenKind.string]).
  final String value;

  /// The 1-based source line the token starts on.
  final int line;

  /// The 1-based source column the token starts on.
  final int column;

  /// Builds a token of [kind]/[value] at [line]:[column].
  const Token(this.kind, this.value, this.line, this.column);

  @override
  String toString() => '$kind($value) at $line:$column';
}

/// Turns LilyPond source text into a flat list of [Token]s (the parser then
/// builds the AST). Whitespace and `%`/`%{ … %}` comments are skipped.
class LilyPondLexer {
  /// The LilyPond source being tokenized.
  final String source;
  int _pos = 0;
  int _line = 1;
  int _col = 1;

  /// Creates a lexer over [source]; call [tokenize] to run it.
  LilyPondLexer(this.source);

  /// Scans [source] and returns its tokens, ending with a [TokenKind.eof].
  List<Token> tokenize() {
    final tokens = <Token>[];
    while (_pos < source.length) {
      _skipWhitespaceAndComments();
      if (_pos >= source.length) break;

      final startLine = _line;
      final startCol = _col;
      final char = source[_pos];

      if (char == '"') {
        tokens.add(Token(TokenKind.string, _readString(), startLine, startCol));
        continue;
      }

      if (char == '\\') {
        final peek = _peek();
        if (peek == '\\') {
          _advance(2);
          tokens.add(Token(TokenKind.symbol, '\\\\', startLine, startCol));
        } else if (_isAlpha(peek)) {
          tokens.add(
              Token(TokenKind.command, _readCommand(), startLine, startCol));
        } else if (peek != null && _escapedMarks.contains(peek)) {
          // Keep the escape TOGETHER as a two-character symbol. A lone `<` is
          // the chord-opener, so `c4\< d e\!` opened a chord that never closed
          // and swallowed the rest of the part.
          _advance(2);
          tokens.add(Token(TokenKind.symbol, '\\$peek', startLine, startCol));
        } else {
          _advance(1);
          tokens.add(Token(TokenKind.symbol, '\\', startLine, startCol));
        }
        continue;
      }

      if (_isSymbolPrefix(char)) {
        final sym = _readSymbol();
        tokens.add(Token(TokenKind.symbol, sym, startLine, startCol));
        continue;
      }

      final word = _readWord();
      if (word.isNotEmpty) {
        tokens.add(Token(TokenKind.word, word, startLine, startCol));
      } else {
        // Unknown character, just skip or treat as symbol
        _advance(1);
      }
    }
    tokens.add(Token(TokenKind.eof, '', _line, _col));
    return tokens;
  }

  void _skipWhitespaceAndComments() {
    while (_pos < source.length) {
      final char = source[_pos];
      if (char == ' ' || char == '\t' || char == '\r' || char == '\n') {
        if (char == '\n') {
          _line++;
          _col = 1;
        } else {
          _col++;
        }
        _pos++;
      } else if (char == '%') {
        final peek = _peek();
        if (peek == '{') {
          _advance(2);
          _skipBlockComment();
        } else {
          _skipLineComment();
        }
      } else {
        break;
      }
    }
  }

  void _skipLineComment() {
    while (_pos < source.length && source[_pos] != '\n') {
      _advance(1);
    }
  }

  void _skipBlockComment() {
    while (_pos < source.length) {
      if (source[_pos] == '%' && _peek() == '}') {
        _advance(2);
        break;
      }
      if (source[_pos] == '\n') {
        _line++;
        _col = 1;
      } else {
        _col++;
      }
      _pos++;
    }
  }

  /// Resolves `\\x` escapes in a quoted string's body.
  static String _unescape(String raw) {
    final out = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      if (raw[i] == '\\' && i + 1 < raw.length) {
        out.write(raw[i + 1]);
        i++;
        continue;
      }
      out.write(raw[i]);
    }
    return out.toString();
  }

  String _readString() {
    _advance(1); // skip "
    final start = _pos;
    while (_pos < source.length) {
      // A backslash escapes the NEXT character whatever it is. Honouring only
      // `\\"` meant a `\\\\` (an escaped backslash, which is how our own writer
      // emits a syllable ending in one) left the second backslash live, so it
      // ate the closing quote and the string ran on — swallowing whatever
      // followed into the lyric. LilyPond itself escapes both.
      if (source[_pos] == '\\' && _pos + 1 < source.length) {
        _advance(2);
        continue;
      }
      if (source[_pos] == '"') {
        final result = _unescape(source.substring(start, _pos));
        _advance(1);
        return result;
      }
      if (source[_pos] == '\n') {
        _line++;
        _col = 1;
      } else {
        _col++;
      }
      _pos++;
    }
    return source.substring(start);
  }

  String _readCommand() {
    _advance(1); // skip \
    final start = _pos;
    while (_pos < source.length && _isAlpha(source[_pos])) {
      _advance(1);
    }
    return source.substring(start, _pos);
  }

  bool _isSymbolPrefix(String char) {
    const symbols = '{ } < > ( ) [ ] ~ | = - ^ _';
    return symbols.contains(char) && char != ' ';
  }

  String _readSymbol() {
    final char = source[_pos];
    final peek = _peek();
    if (char == '<' && peek == '<') {
      _advance(2);
      return '<<';
    }
    if (char == '>' && peek == '>') {
      _advance(2);
      return '>>';
    }
    if (char == '-' &&
        (peek == '.' || peek == '>' || peek == '^' || peek == '-')) {
      _advance(2);
      return '$char$peek';
    }
    if (char == '_' && peek == '_') {
      _advance(2);
      return '__';
    }
    _advance(1);
    return char;
  }

  String _readWord() {
    final start = _pos;
    while (_pos < source.length) {
      final char = source[_pos];
      // ⚠️ A `-` or `+` GLUED to a chord token is part of the chord, not a
      // symbol: `c:m7.5-` is half-diminished and `c:5+` is an augmented fifth.
      // `-` is a symbol prefix (articulation shorthands, lyric hyphens), so it
      // ended the word and the alteration was dropped before the parser ever
      // saw it — silently turning every `c:m7.5-` into a plain minor seventh
      // and leaving the reader's own `m7.5-` case unreachable.
      //
      // The same applies inside a Scheme literal: `\ottava #-1` is a NEGATIVE
      // ONE, and splitting it left `#` on its own with the sign and the digit
      // as separate tokens — so the octave shift read as nothing at all.
      //
      // Gated on the word so far containing `:` (only a chord token does) or
      // starting with `#` (only a Scheme literal does), so `c4-.` and every
      // lyric hyphen are untouched.
      if ((char == '-' || char == '+') &&
          (source.substring(start, _pos).contains(':') ||
              source.startsWith('#', start))) {
        _advance(1);
        continue;
      }
      if (char == ' ' ||
          char == '\t' ||
          char == '\r' ||
          char == '\n' ||
          char == '%' ||
          char == '"' ||
          char == '\\' ||
          _isSymbolPrefix(char)) {
        break;
      }
      _advance(1);
    }
    return source.substring(start, _pos);
  }

  /// Hairpin escapes: `\<` crescendo, `\>` decrescendo, `\!` end.
  static const _escapedMarks = {'<', '>', '!'};

  String? _peek() => (_pos + 1 < source.length) ? source[_pos + 1] : null;

  void _advance(int count) {
    for (var i = 0; i < count; i++) {
      if (_pos < source.length) {
        if (source[_pos] == '\n') {
          _line++;
          _col = 1;
        } else {
          _col++;
        }
        _pos++;
      }
    }
  }

  bool _isAlpha(String? char) {
    if (char == null) return false;
    final code = char.codeUnitAt(0);
    return (code >= 97 && code <= 122) || (code >= 65 && code <= 90);
  }
}
