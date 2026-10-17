part of 'gabc_reader.dart';

/// A GABC piece engraved in square (Gregorian) notation on one line: the
/// four-line staff, do- and fa-clefs, puncta, inclinata, virgae, quilismas,
/// oriscus, strophicus and liquescents, pes and clivis joined as printed,
/// flats, mora dots, episemata, the division bars and the sung syllables.
///
/// GABC letters are staff positions (`d` on the bottom line, `j` on the top
/// one), so the notes sit where the source puts them whatever the clef.
/// Each note carries an element id (`n0`, `n1`, … in reading order) and a
/// hit region, so a player can highlight what is being sung.
ScoreLayout layoutChant(String gabc, LayoutSettings settings) =>
    _ChantBuilder(settings).build(_chantItems(gabc));

/// [layoutChant] broken into lines no wider than [maxWidth] staff spaces at
/// syllable and bar boundaries, each line opening with the clef in force.
/// Note ids run on across the lines.
List<ScoreLayout> layoutChantLines(
  String gabc,
  LayoutSettings settings, {
  required double maxWidth,
}) {
  final items = _chantItems(gabc);
  final lines = <ScoreLayout>[];
  var clef = const _ChantClef(true, 4, false);
  var start = 0;
  var firstId = 0;
  while (start < items.length) {
    final head = items[start] is _ChantClef ? <_ChantItem>[] : [clef];
    var end = start + 1;
    while (end < items.length) {
      final trial = _ChantBuilder(settings)
          .build([...head, ...items.sublist(start, end + 1)]);
      if (trial.width > maxWidth) break;
      end++;
    }
    final builder = _ChantBuilder(settings, firstId: firstId);
    lines.add(builder.build([...head, ...items.sublist(start, end)]));
    firstId = builder.nextId;
    for (final item in items.sublist(start, end)) {
      if (item is _ChantClef) clef = item;
    }
    start = end;
  }
  return lines;
}

sealed class _ChantItem {
  const _ChantItem();
}

final class _ChantClef extends _ChantItem {
  final bool doClef;
  final int line;
  final bool flat;
  const _ChantClef(this.doClef, this.line, this.flat);
}

final class _ChantBar extends _ChantItem {
  final String kind; // `,` `;` `:` `::` or a backtick
  const _ChantBar(this.kind);
}

final class _ChantSyllable extends _ChantItem {
  final String text;
  final bool wordStart;

  /// The neumes, each a run of notes drawn joined; [gaps] is the space
  /// before each neume after the first.
  final List<List<_ChantNote>> neumes;
  final List<double> gaps;
  const _ChantSyllable(this.text, this.wordStart, this.neumes, this.gaps);
}

/// One note: [position] in half-spaces above the bottom line (GABC `d` =
/// 0), its [shape] (`punctum`, `inclinatum`, `virga`, `quilisma`,
/// `oriscus`, `strophicus`, `liquescent`, `cavum`, or `flat`/`natural`/
/// `sharp` for an accidental sign at that position).
final class _ChantNote {
  final int position;
  final String shape;
  final bool mora;
  final bool episema;
  const _ChantNote(this.position, this.shape,
      {this.mora = false, this.episema = false});

  _ChantNote copyWith({String? shape, bool? mora, bool? episema}) =>
      _ChantNote(position, shape ?? this.shape,
          mora: mora ?? this.mora, episema: episema ?? this.episema);

  bool get isSign => shape == 'flat' || shape == 'natural' || shape == 'sharp';
}

/// The body of [gabc] as clefs, bars and syllables with their neumes.
List<_ChantItem> _chantItems(String gabc) {
  final separator = gabc.indexOf('%%');
  if (separator < 0) {
    throw const FormatException('GABC: missing "%%" header separator');
  }
  final body = gabc.substring(separator + 2);
  final items = <_ChantItem>[];
  var first = true;
  final buffer = StringBuffer();
  var i = 0;
  while (i < body.length) {
    if (body[i] != '(') {
      buffer.write(body[i]);
      i++;
      continue;
    }
    final raw = buffer.toString();
    buffer.clear();
    var j = i + 1;
    while (j < body.length && body[j] != ')') {
      j++;
    }
    final group = body.substring(i + 1, j).trim();
    i = j < body.length ? j + 1 : j;
    final text = _stripLyric(raw);
    final wordStart = first || _startsWithSpace(raw);
    if (text.isNotEmpty) first = false;
    final clef = _clefPattern.firstMatch(group);
    if (clef != null) {
      items
          .add(_ChantClef(clef[1] == 'c', int.parse(clef[3]!), clef[2] == 'b'));
      continue;
    }
    // A bar may close a group of notes: `(f.,)`.
    final bar = RegExp(r'(::|[,;:`])[0-9]?$').firstMatch(group);
    final notes = bar == null ? group : group.substring(0, bar.start);
    final (neumes, gaps) = _neumesOf(notes);
    if (neumes.isNotEmpty || text.isNotEmpty) {
      items.add(_ChantSyllable(text, wordStart, neumes, gaps));
    }
    if (bar != null) items.add(_ChantBar(bar[1]!));
  }
  return items;
}

(List<List<_ChantNote>>, List<double>) _neumesOf(String group) {
  final neumes = <List<_ChantNote>>[];
  final gaps = <double>[];
  var current = <_ChantNote>[];
  var gap = 0.0;
  void push(List<_ChantNote> neume) {
    if (neumes.isNotEmpty) gaps.add(gap);
    neumes.add(neume);
    gap = 0;
  }

  void close(double next) {
    if (current.isNotEmpty) {
      push(current);
      current = <_ChantNote>[];
    }
    gap = max(gap, next);
  }

  var k = 0;
  while (k < group.length) {
    final ch = group[k];
    final code = ch.toLowerCase().codeUnitAt(0);
    if (code >= _aCode && code <= _mCode) {
      final position = code - _aCode - 3;
      final next = k + 1 < group.length ? group[k + 1] : '';
      if (next == 'x' || next == 'y' || next == '#') {
        close(0);
        push([
          _ChantNote(position,
              next == 'x' ? 'flat' : (next == 'y' ? 'natural' : 'sharp')),
        ]);
        gap = 0.3;
        k += 2;
        continue;
      }
      current.add(_ChantNote(
          position, ch == ch.toUpperCase() ? 'inclinatum' : 'punctum'));
      k++;
      continue;
    }
    if (current.isNotEmpty) {
      final last = current.last;
      void shape(String s) => current[current.length - 1] = last.copyWith(
            shape: s,
          );
      switch (ch) {
        case 'v' || 'V':
          shape('virga');
        case 'w':
          shape('quilisma');
        case 'o' || 'O':
          shape('oriscus');
        case 's':
          // `gs` is a strophicus; each further `s` repeats it.
          if (last.shape == 'strophicus') {
            current.add(_ChantNote(last.position, 'strophicus'));
          } else {
            shape('strophicus');
          }
        case '~' || '<' || '>':
          shape('liquescent');
        case 'r':
          shape('cavum');
        case '.':
          current[current.length - 1] = last.copyWith(mora: true);
        case '_':
          current[current.length - 1] = last.copyWith(episema: true);
      }
    }
    switch (ch) {
      case '/':
        close(0.5);
      case ' ':
        close(0.9);
      case '!':
        close(0.15);
      case '[':
        // Bracketed attachments (`[ll:1]`, `[alt:…]`) carry no notes.
        final end = group.indexOf(']', k);
        if (end > k) k = end;
    }
    k++;
  }
  close(0);
  return (neumes, gaps);
}

class _ChantBuilder {
  final LayoutSettings s;
  int nextId;
  _ChantBuilder(this.s, {int firstId = 0}) : nextId = firstId;

  final _primitives = <LayoutPrimitive>[];
  final _regions = <ElementRegion>[];
  var _x = 0.5;
  var _textRight = double.negativeInfinity;
  var _minY = 0.0, _maxY = 3.0;
  final _syllables = <(double left, double right, bool wordStart)>[];

  static double _y(int position) => 3 - position / 2;

  double _width(String glyph) => s.metadata.bBoxOf(glyph).width;

  void _glyph(String name, double x, double y, {String? id}) {
    _primitives.add(GlyphPrimitive(name, Point(x, y), elementId: id));
    final box = s.metadata.bBoxOf(name);
    _minY = min(_minY, y - box.neY);
    _maxY = max(_maxY, y - box.swY);
  }

  void _line(double x1, double y1, double x2, double y2, double thickness) {
    _primitives
        .add(LinePrimitive(Point(x1, y1), Point(x2, y2), thickness: thickness));
    _minY = min(_minY, min(y1, y2));
    _maxY = max(_maxY, max(y1, y2));
  }

  ScoreLayout build(List<_ChantItem> items) {
    for (final item in items) {
      switch (item) {
        case _ChantClef():
          _clef(item);
        case _ChantBar():
          _bar(item.kind);
        case _ChantSyllable():
          _syllable(item);
      }
    }
    _hyphens();
    final width = _x + 0.5;
    final staff = [
      for (var line = 0; line < 4; line++)
        LinePrimitive(Point(0, line.toDouble()), Point(width, line.toDouble()),
            thickness: s.staffLineThickness),
    ];
    final top = min(-1.0, _minY - 0.5);
    final textBottom = _syllables.isEmpty ? _maxY : 5.0 + s.lyricSize * 0.4;
    return ScoreLayout(
      width: width,
      height: max(_maxY, textBottom) + 0.5 - top,
      top: top,
      primitives: [...staff, ..._primitives],
      regions: _regions,
      measureRegions: [MeasureRegion(0, startX: 0, endX: width)],
    );
  }

  void _clef(_ChantClef clef) {
    final y = 4.0 - clef.line;
    final glyph = clef.doClef ? 'chantCclef' : 'chantFclef';
    _glyph(glyph, _x, y);
    _x += _width(glyph) + 0.4;
    if (clef.flat) {
      // The b-flat signature sits on si, a step below a do-clef's line or
      // three steps below a fa-clef's.
      final position = 2 * (clef.line - 1) - (clef.doClef ? 1 : 3);
      _glyph('accidentalFlat', _x, _y(position));
      _x += _width('accidentalFlat') + 0.3;
    }
    _x += 0.6;
  }

  void _bar(String kind) {
    _x += 0.4;
    final t = s.staffLineThickness * 1.3;
    switch (kind) {
      case ',':
        _line(_x, -0.5, _x, 0.5, t);
      case '`':
        _line(_x, -0.9, _x, -0.3, t);
      case ';':
        _line(_x, 0.5, _x, 2.5, t);
      case ':':
        _line(_x, 0, _x, 3, t);
      default: // '::' finalis
        _line(_x, 0, _x, 3, t);
        _x += 0.4;
        _line(_x, 0, _x, 3, t * 2.2);
    }
    _x += 1.0;
  }

  void _syllable(_ChantSyllable syllable) {
    if (syllable.wordStart && _syllables.isNotEmpty) _x += 0.5;
    final half = syllable.text.isEmpty
        ? 0.0
        : (s.textWidth?.call(syllable.text, s.lyricSize) ??
                2 * estimateTextHalfWidth(syllable.text, s.lyricSize)) /
            2;
    // The syllable centres under its first note; it may not touch the text
    // before it, so the notes move right when it would.
    final firstNote = syllable.neumes.isEmpty
        ? null
        : syllable.neumes.first.firstWhere((n) => !n.isSign,
            orElse: () => syllable.neumes.first.first);
    final signs = syllable.neumes.isEmpty
        ? 0.0
        : syllable.neumes
            .takeWhile((n) => n.length == 1 && n.first.isSign)
            .fold(0.0, (w, _) => w + 1.1);
    final noteHalf = _width('chantPunctum') / 2;
    if (half > 0) {
      final minCentre = _textRight + 0.35 + half;
      final centre = _x + signs + noteHalf;
      if (centre < minCentre) _x += minCentre - centre;
    }
    final textCentre = _x + signs + noteHalf;
    for (var n = 0; n < syllable.neumes.length; n++) {
      if (n > 0) _x += syllable.gaps[n - 1];
      _neume(syllable.neumes[n]);
    }
    if (syllable.text.isNotEmpty) {
      _primitives.add(TextPrimitive(syllable.text, Point(textCentre, 5.0),
          size: s.lyricSize));
      _textRight = textCentre + half;
      _syllables
          .add((textCentre - half, textCentre + half, syllable.wordStart));
    }
    _x += firstNote == null ? half * 2 : 0.7;
  }

  void _neume(List<_ChantNote> notes) {
    var i = 0;
    double? prevRight;
    int? prevPosition;
    while (i < notes.length) {
      final note = notes[i];
      final next = i + 1 < notes.length ? notes[i + 1] : null;
      if (note.isSign) {
        final glyph = switch (note.shape) {
          'flat' => 'accidentalFlat',
          'natural' => 'accidentalNatural',
          _ => 'accidentalSharp',
        };
        _glyph(glyph, _x, _y(note.position));
        _x += _width(glyph) + 0.3;
        i++;
        continue;
      }
      // Pes: a lower note with a higher one stacked on it, joined on the
      // right.
      if (next != null &&
          note.shape == 'punctum' &&
          next.position > note.position &&
          (next.shape == 'punctum' || next.shape == 'virga')) {
        final w = _width('chantPunctum');
        _note(note, _x, 'chantPunctum');
        _note(next, _x, 'chantPunctum');
        _line(_x + w - 0.04, _y(note.position), _x + w - 0.04,
            _y(next.position), 0.12);
        prevRight = _x + w;
        prevPosition = next.position;
        _x += w;
        i += 2;
        continue;
      }
      if (note.shape == 'inclinatum') {
        // Inclinata descend in a diagonal of diamonds, unjoined.
        if (prevRight != null) _x = prevRight + 0.05;
        _note(note, _x, 'chantPunctumInclinatum');
        prevRight = _x + _width('chantPunctumInclinatum') * 0.75;
        prevPosition = null;
        _x = prevRight;
        i++;
        if (next == null || next.shape != 'inclinatum') _x += 0.25;
        continue;
      }
      final glyph = switch (note.shape) {
        'virga' => 'chantPunctumVirga',
        'quilisma' => 'chantQuilisma',
        'oriscus' => 'chantOriscusAscending',
        'strophicus' => 'chantStrophicus',
        'liquescent' => 'chantPunctumDeminutum',
        'cavum' => 'chantPunctumCavum',
        _ => 'chantPunctum',
      };
      // Clivis: a falling first note takes a stem down on its left.
      if (i == 0 && next != null && next.position < note.position) {
        _line(_x + 0.04, _y(note.position), _x + 0.04, _y(next.position) + 0.55,
            0.12);
      }
      // Notes side by side in one neume are joined by a line between them.
      if (prevRight != null &&
          prevPosition != null &&
          prevPosition != note.position &&
          note.shape != 'strophicus') {
        _line(_x, _y(prevPosition), _x, _y(note.position), 0.12);
      }
      _note(note, _x, glyph);
      prevRight = _x + _width(glyph);
      prevPosition = note.position;
      _x = prevRight + (note.shape == 'strophicus' ? 0.25 : 0);
      i++;
    }
  }

  void _note(_ChantNote note, double x, String glyph) {
    final id = 'n${nextId++}';
    final y = _y(note.position);
    final width = _width(glyph);
    _glyph(glyph, x, y, id: id);
    _regions.add(ElementRegion(id, Rectangle(x, y - 0.45, width, 0.9)));
    // Ledger lines beyond the four lines.
    for (var p = 8; p <= note.position; p += 2) {
      _line(x - 0.25, _y(p), x + width + 0.25, _y(p), s.staffLineThickness);
    }
    for (var p = -2; p >= note.position; p -= 2) {
      _line(x - 0.25, _y(p), x + width + 0.25, _y(p), s.staffLineThickness);
    }
    if (note.mora) {
      final dotY = note.position.isEven ? y - 0.5 : y;
      _glyph('augmentationDot', x + width + 0.2, dotY);
      _x = max(_x, x + width + 0.6);
    }
    if (note.episema) {
      _line(x, y - 0.75, x + width, y - 0.75, 0.12);
    }
  }

  /// A hyphen between the syllables of one word, where there is room.
  void _hyphens() {
    for (var k = 1; k < _syllables.length; k++) {
      final (_, prevRight, _) = _syllables[k - 1];
      final (left, _, wordStart) = _syllables[k];
      if (wordStart || left - prevRight < 0.7) continue;
      _primitives.add(TextPrimitive('-', Point((prevRight + left) / 2, 5.0),
          size: s.lyricSize));
    }
  }
}
