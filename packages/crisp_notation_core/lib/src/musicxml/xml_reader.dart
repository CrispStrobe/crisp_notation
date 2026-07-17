/// A minimal, dependency-free XML reader — just enough for the MusicXML
/// subset crisp_notation imports (elements, attributes, text; no namespaces,
/// no DTD processing).
library;

/// One XML element: name, attributes, child elements and direct text.
class XmlNode {
  /// Tag name.
  final String name;

  /// Attributes as written.
  final Map<String, String> attributes;

  /// Child elements in document order.
  final List<XmlNode> children;

  /// Concatenated direct text content, whitespace-trimmed.
  final String text;

  /// Creates a node.
  const XmlNode(this.name, this.attributes, this.children, this.text);

  /// The first child element named [childName], or null.
  XmlNode? child(String childName) {
    for (final node in children) {
      if (node.name == childName) return node;
    }
    return null;
  }

  /// All child elements named [childName].
  Iterable<XmlNode> childrenNamed(String childName) =>
      children.where((node) => node.name == childName);

  /// The trimmed text of the first child named [childName], or null.
  String? childText(String childName) => child(childName)?.text;

  @override
  String toString() => '<$name> (${children.length} children)';
}

/// Parses [source] and returns the document's root element.
///
/// Supports the constructs MusicXML files actually use: prolog,
/// DOCTYPE, comments, CDATA, self-closing tags and the five predefined
/// entities plus numeric character references. Throws [FormatException]
/// on malformed input.
XmlNode parseXml(String source) {
  final parser = _Parser(source);
  try {
    parser._skipProlog();
    return parser._element();
  } on RangeError {
    // The tokenizer indexes `s[i]` directly; truncated input runs it off the
    // end. That is malformed input, so honour the documented contract and
    // surface it as a FormatException rather than a raw RangeError.
    throw const FormatException('Malformed XML: unexpected end of input');
  }
}

class _Parser {
  final String s;
  int i = 0;
  _Parser(this.s);

  bool get _done => i >= s.length;

  void _skipWhitespaceAndMisc() {
    while (!_done) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        i++;
      } else if (s.startsWith('<!--', i)) {
        final end = s.indexOf('-->', i + 4);
        if (end < 0) throw const FormatException('Unterminated comment');
        i = end + 3;
      } else if (s.startsWith('<?', i)) {
        final end = s.indexOf('?>', i + 2);
        if (end < 0) throw const FormatException('Unterminated <? ?>');
        i = end + 2;
      } else {
        return;
      }
    }
  }

  void _skipProlog() {
    _skipWhitespaceAndMisc();
    // DOCTYPE (possibly with an internal subset in brackets).
    if (s.startsWith('<!DOCTYPE', i)) {
      var depth = 0;
      while (!_done) {
        final c = s[i];
        i++;
        if (c == '[') depth++;
        if (c == ']') depth--;
        if (c == '>' && depth <= 0) break;
      }
      _skipWhitespaceAndMisc();
    }
  }

  XmlNode _element() {
    if (_done || s[i] != '<') {
      throw FormatException('Expected "<" at offset $i');
    }
    i++;
    final name = _name();
    final attributes = <String, String>{};
    while (true) {
      _skipSpaces();
      if (_done) throw const FormatException('Unterminated tag');
      if (s[i] == '/') {
        if (!s.startsWith('/>', i)) {
          throw FormatException('Malformed tag end at offset $i');
        }
        i += 2;
        return XmlNode(name, attributes, const [], '');
      }
      if (s[i] == '>') {
        i++;
        break;
      }
      final attrName = _name();
      _skipSpaces();
      if (_done || s[i] != '=') {
        throw FormatException('Expected "=" in attribute at offset $i');
      }
      i++;
      _skipSpaces();
      final quote = s[i];
      if (quote != '"' && quote != "'") {
        throw FormatException('Expected quoted attribute at offset $i');
      }
      i++;
      final end = s.indexOf(quote, i);
      if (end < 0) throw const FormatException('Unterminated attribute');
      attributes[attrName] = _decode(s.substring(i, end));
      i = end + 1;
    }

    final children = <XmlNode>[];
    final textParts = <String>[];
    while (true) {
      if (_done) throw FormatException('Unterminated element <$name>');
      if (s[i] == '<') {
        if (s.startsWith('</', i)) {
          i += 2;
          final closing = _name();
          _skipSpaces();
          if (_done || s[i] != '>') {
            throw FormatException('Malformed closing tag </$closing');
          }
          i++;
          if (closing != name) {
            throw FormatException('Mismatched </$closing> for <$name>');
          }
          return XmlNode(name, attributes, children, textParts.join().trim());
        }
        if (s.startsWith('<!--', i)) {
          final end = s.indexOf('-->', i + 4);
          if (end < 0) throw const FormatException('Unterminated comment');
          i = end + 3;
          continue;
        }
        if (s.startsWith('<![CDATA[', i)) {
          final end = s.indexOf(']]>', i + 9);
          if (end < 0) throw const FormatException('Unterminated CDATA');
          textParts.add(s.substring(i + 9, end));
          i = end + 3;
          continue;
        }
        if (s.startsWith('<?', i)) {
          final end = s.indexOf('?>', i + 2);
          if (end < 0) throw const FormatException('Unterminated <? ?>');
          i = end + 2;
          continue;
        }
        children.add(_element());
      } else {
        final next = s.indexOf('<', i);
        if (next < 0) throw FormatException('Unterminated element <$name>');
        textParts.add(_decode(s.substring(i, next)));
        i = next;
      }
    }
  }

  void _skipSpaces() {
    while (!_done) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        i++;
      } else {
        return;
      }
    }
  }

  String _name() {
    final start = i;
    while (!_done) {
      final c = s[i];
      if (c == ' ' ||
          c == '\t' ||
          c == '\n' ||
          c == '\r' ||
          c == '>' ||
          c == '/' ||
          c == '=') {
        break;
      }
      i++;
    }
    if (i == start) throw FormatException('Expected a name at offset $start');
    return s.substring(start, i);
  }

  static String _decode(String text) {
    if (!text.contains('&')) return text;
    return text.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|\w+);'), (m) {
      final entity = m[1]!;
      switch (entity) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      if (entity.startsWith('#x') || entity.startsWith('#X')) {
        return String.fromCharCode(int.parse(entity.substring(2), radix: 16));
      }
      if (entity.startsWith('#')) {
        return String.fromCharCode(int.parse(entity.substring(1)));
      }
      return m[0]!; // unknown entity: keep literally
    });
  }
}
