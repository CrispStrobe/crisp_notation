/// Internal helpers — not exported from the package entrypoint.
library;

/// Compares two lists element-wise.
bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Compares two sets for equality.
bool setEquals<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) return true;
  return a.length == b.length && a.containsAll(b);
}

/// The lines of an instrument name as printed left of its staves. A name
/// can carry its own line breaks (a MusicXML `part-name` of "Singstimme",
/// newline, "Voice", as MuseScore writes it); set on one line the break
/// printed as a missing-glyph box. Blank lines and edge whitespace drop.
List<String> instrumentLabelLines(String label) => [
      for (final line in label.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
