/// White mensural notation (c. 1450–1600) from MEI, engraved as printed in
/// its time: no barlines, the old clefs, the mensuration sign, and the note
/// shapes from maxima to fusa — SMuFL's mensural glyphs on five lines.
library;

import 'dart:math';

import '../layout/layout_settings.dart';
import '../layout/score_layout.dart';
import '../musicxml/xml_reader.dart';

/// The mensural voice on staff [staff] of [mei] (`notationtype="mensural"`
/// or any MEI whose durations are mensural: `maxima`, `longa`, `brevis`,
/// `semibrevis`, `minima`, `semiminima`, `fusa`) on one line: clefs
/// (`<clef>` or the staff definition's `clef.shape`/`clef.line`),
/// mensuration signs (`<mensur sign="O|C" dot slash>`), notes with their
/// dots and accidentals, rests and custodes. Each note and rest carries an
/// element id (`m0`, `m1`, … in reading order) and a hit region.
ScoreLayout layoutMensural(String mei, LayoutSettings settings,
        {int staff = 1}) =>
    _MensuralBuilder(settings).build(_mensuralItems(mei, staff));

/// [layoutMensural] broken into lines no wider than [maxWidth] staff
/// spaces, each opening with the clef in force; ids run on across lines.
List<ScoreLayout> layoutMensuralLines(
  String mei,
  LayoutSettings settings, {
  required double maxWidth,
  int staff = 1,
}) {
  final items = _mensuralItems(mei, staff);
  final lines = <ScoreLayout>[];
  _MClef? clef;
  var start = 0;
  var firstId = 0;
  while (start < items.length) {
    final head = clef == null || items[start] is _MClef ? <_MItem>[] : [clef];
    var end = start + 1;
    while (end < items.length &&
        _MensuralBuilder(settings)
                .build([...head, ...items.sublist(start, end + 1)]).width <=
            maxWidth) {
      end++;
    }
    final builder = _MensuralBuilder(settings, firstId: firstId);
    lines.add(builder.build([...head, ...items.sublist(start, end)]));
    firstId = builder.nextId;
    for (final item in items.sublist(start, end)) {
      if (item is _MClef) clef = item;
    }
    start = end;
  }
  return lines;
}

sealed class _MItem {
  const _MItem();
}

final class _MClef extends _MItem {
  final String shape; // C, F or G
  final int line; // 1 = bottom
  const _MClef(this.shape, this.line);
}

final class _MMensur extends _MItem {
  final String sign; // O or C
  final bool dot, slash;
  const _MMensur(this.sign, {this.dot = false, this.slash = false});
}

final class _MNote extends _MItem {
  /// Diatonic index (C4 = 28), or null for a rest.
  final int? diatonic;
  final String dur;
  final bool dotted;
  final String? accid; // f, s, n
  final bool colored;
  const _MNote(this.diatonic, this.dur,
      {this.dotted = false, this.accid, this.colored = false});
}

final class _MLigature extends _MItem {
  final List<_MNote> notes;
  final String form; // '' or 'obliqua'
  const _MLigature(this.notes, {this.form = ''});
}

final class _MCustos extends _MItem {
  final int diatonic;
  const _MCustos(this.diatonic);
}

const _steps = {'c': 0, 'd': 1, 'e': 2, 'f': 3, 'g': 4, 'a': 5, 'b': 6};

List<_MItem> _mensuralItems(String mei, int staffN) {
  final root = parseXml(mei);
  final items = <_MItem>[];
  bool blackStaff = false;
  int? diatonicOf(XmlNode n) {
    final step = _steps[n.attributes['pname']?.toLowerCase()];
    final oct = int.tryParse(n.attributes['oct'] ?? '');
    return step == null || oct == null ? null : oct * 7 + step;
  }

  // Helper to create _MNote from a <note> XmlNode, respecting blackStaff and colored.
  _MNote? noteFrom(XmlNode e) {
    final d = diatonicOf(e);
    if (d == null) return null;
    final accid = e.attributes['accid'] ??
        e.descendants
            .where((c) => c.name == 'accid')
            .map((c) => c.attributes['accid'])
            .firstOrNull;
    final colored = e.attributes['colored'] == 'true' || blackStaff;
    return _MNote(d, e.attributes['dur'] ?? 'semibrevis',
        dotted: e.attributes['dots'] == '1', accid: accid, colored: colored);
  }

  void visitEvent(XmlNode e) {
    switch (e.name) {
      case 'clef':
        final line = int.tryParse(e.attributes['line'] ?? '');
        if (line != null) items.add(_MClef(e.attributes['shape'] ?? 'C', line));
      case 'mensur':
        items.add(_MMensur(e.attributes['sign'] ?? 'C',
            dot: e.attributes['dot'] == 'true',
            slash: (e.attributes['slash'] ?? '0') != '0'));
      case 'note':
        final n = noteFrom(e);
        if (n != null) items.add(n);
      case 'rest':
        items.add(_MNote(null, e.attributes['dur'] ?? 'semibrevis'));
      case 'dot':
        // A dot of addition or division follows its note.
        final last = items.isEmpty ? null : items.last;
        if (last is _MNote && last.diatonic != null) {
          items[items.length - 1] = _MNote(last.diatonic, last.dur,
              dotted: true, accid: last.accid, colored: last.colored);
        } else if (last is _MLigature && last.notes.isNotEmpty) {
          // Dot after a ligature: apply to its last note.
          final notes = List<_MNote>.from(last.notes);
          final lastNote = notes.last;
          notes[notes.length - 1] = _MNote(lastNote.diatonic, lastNote.dur,
              dotted: true, accid: lastNote.accid, colored: lastNote.colored);
          items[items.length - 1] = _MLigature(notes, form: last.form);
        }
      case 'custos':
        final d = diatonicOf(e);
        if (d != null) items.add(_MCustos(d));
      case 'ligature':
        final form = e.attributes['form'] ?? '';
        final notes = <_MNote>[];
        var hasObliqua = form == 'obliqua';
        for (final child in e.children) {
          if (child.name == 'note') {
            final n = noteFrom(child);
            if (n != null) {
              notes.add(n);
              if (child.attributes['lig'] == 'obliqua') hasObliqua = true;
            }
          } else if (child.name == 'dot') {
            if (notes.isNotEmpty) {
              final last = notes.last;
              notes[notes.length - 1] = _MNote(last.diatonic, last.dur,
                  dotted: true, accid: last.accid, colored: last.colored);
            }
          } else {
            // Recurse for other wrappers inside ligature.
            visitEvent(child);
          }
        }
        if (notes.isNotEmpty) {
          // If any note inside was marked obliqua or the ligature itself is obliqua, mark whole as obliqua.
          // For a 2-note obliqua, we keep them as one ligature so the builder can draw a single oblique glyph.
          final ligForm = hasObliqua ? 'obliqua' : form;
          items.add(_MLigature(notes, form: ligForm));
        }
        return;
      case 'beam' || 'tuplet' || 'choice' || 'sic' || 'orig':
        for (final child in e.children) {
          visitEvent(child);
        }
    }
  }

  void staffDef(XmlNode def) {
    final shape = def.attributes['clef.shape'];
    final line = int.tryParse(def.attributes['clef.line'] ?? '');
    if (shape != null && line != null) items.add(_MClef(shape, line));
    final sign = def.attributes['mensur.sign'];
    if (sign != null) {
      items.add(_MMensur(sign,
          dot: def.attributes['mensur.dot'] == 'true',
          slash: (def.attributes['mensur.slash'] ?? '0') != '0'));
    }
    // Black notation on the staff: notationtype="mensural.black" (MENSURAL BLACK)
    final notationtype = def.attributes['notationtype'] ?? '';
    if (notationtype.contains('black')) blackStaff = true;
    for (final child in def.children) {
      visitEvent(child);
    }
  }

  void walk(XmlNode node) {
    switch (node.name) {
      case 'staffDef':
        if (node.attributes['n'] == '$staffN') staffDef(node);
        return;
      case 'staff':
        if (node.attributes['n'] != '$staffN') return;
        for (final layer in node.children.where((c) => c.name == 'layer')) {
          for (final event in layer.children) {
            visitEvent(event);
          }
          break; // the first layer: one voice per staff
        }
        return;
    }
    for (final child in node.children) {
      walk(child);
    }
  }

  walk(root);
  return items;
}

class _MensuralBuilder {
  final LayoutSettings s;
  int nextId;
  _MensuralBuilder(this.s, {int firstId = 0}) : nextId = firstId;

  final _primitives = <LayoutPrimitive>[];
  final _regions = <ElementRegion>[];
  var _x = 0.6;
  var _minY = 0.0, _maxY = 4.0;
  var _clef = const _MClef('C', 3);

  /// Staff position (0 = bottom line, 8 = top line) of a diatonic index.
  int _position(int diatonic) {
    final reference = switch (_clef.shape) {
      'F' => 3 * 7 + 3, // F3
      'G' => 4 * 7 + 4, // G4
      _ => 4 * 7, // C4
    };
    return diatonic - reference + 2 * (_clef.line - 1);
  }

  static double _y(int position) => 4 - position / 2;

  double _width(String glyph) => s.metadata.bBoxOf(glyph).width;

  void _glyph(String name, double x, double y, {String? id}) {
    _primitives.add(GlyphPrimitive(name, Point(x, y), elementId: id));
    final box = s.metadata.bBoxOf(name);
    _minY = min(_minY, y - box.neY);
    _maxY = max(_maxY, y - box.swY);
  }

  void _line(double x1, double y1, double x2, double y2, double t) {
    _primitives.add(LinePrimitive(Point(x1, y1), Point(x2, y2), thickness: t));
  }

  ScoreLayout build(List<_MItem> items) {
    for (final item in items) {
      switch (item) {
        case _MClef():
          _clef = item;
          final glyph = switch (item.shape) {
            'F' => 'mensuralFclef',
            'G' => 'mensuralGclef',
            _ => 'mensuralCclef',
          };
          _glyph(glyph, _x, 4.0 - (item.line - 1));
          _x += _width(glyph) + 1.0;
        case _MMensur():
          // SMuFL's prolation signs: O with a dot (1), O (2), O with a
          // stroke (3), with both (4); the same for C from 5 to 8.
          final number = (item.sign == 'O' ? 1 : 5) +
              switch ((item.slash, item.dot)) {
                (false, true) => 0,
                (false, false) => 1,
                (true, false) => 2,
                (true, true) => 3,
              };
          final glyph = 'mensuralProlation$number';
          _glyph(glyph, _x, 2);
          _x += _width(glyph) + 1.2;
        case _MNote():
          _note(item);
        case _MLigature():
          _ligature(item);
        case _MCustos():
          _glyph('mensuralCustosUp', _x, _y(_position(item.diatonic)));
          _x += _width('mensuralCustosUp') + 0.8;
      }
    }
    final width = _x + 0.4;
    return ScoreLayout(
      width: width,
      height: _maxY - min(-1, _minY - 0.5) + 0.5,
      top: min(-1, _minY - 0.5),
      primitives: [
        for (var line = 0; line < 5; line++)
          LinePrimitive(
              Point(0, line.toDouble()), Point(width, line.toDouble()),
              thickness: s.staffLineThickness),
        ..._primitives,
      ],
      regions: _regions,
      measureRegions: [MeasureRegion(0, startX: 0, endX: width)],
    );
  }

  /// How far a value advances: the longer, the wider, on a gentle curve.
  static const _advance = {
    'maxima': 5.0,
    'longa': 4.2,
    'brevis': 3.4,
    'semibrevis': 2.8,
    'minima': 2.3,
    'semiminima': 1.9,
    'fusa': 1.7,
    'semifusa': 1.6,
  };

  /// Glyph for a mensural note, honouring `colored` (black notation).
  String _glyphFor(_MNote note) {
    if (note.colored) {
      // Black notation: use black glyphs where they exist, otherwise fall back to white.
      return switch (note.dur) {
        'maxima' => 'mensuralBlackMaxima',
        'longa' => 'mensuralBlackLonga',
        'brevis' => 'mensuralBlackBrevis',
        'semibrevis' => 'mensuralBlackSemibrevis',
        'minima' => 'mensuralBlackMinima',
        'semiminima' => 'mensuralBlackSemiminima',
        'semibrevisOblique' => 'mensuralBlackSemibrevisOblique',
        _ => 'mensuralBlackSemibrevis',
      };
    }
    return switch (note.dur) {
      'maxima' => 'mensuralWhiteMaxima',
      'longa' => 'mensuralWhiteLonga',
      'brevis' => 'mensuralWhiteBrevis',
      'minima' => 'mensuralWhiteMinima',
      'semiminima' => 'mensuralWhiteSemiminima',
      'fusa' || 'semifusa' => 'mensuralWhiteFusa',
      _ => 'mensuralWhiteSemibrevis',
    };
  }

  void _note(_MNote note) {
    final id = 'm${nextId++}';
    final advance = _advance[note.dur] ?? 2.8;
    if (note.diatonic == null) {
      final glyph = switch (note.dur) {
        'maxima' => 'mensuralRestMaxima',
        'longa' => 'mensuralRestLongaImperfecta',
        'brevis' => 'mensuralRestBrevis',
        'minima' => 'mensuralRestMinima',
        'semiminima' => 'mensuralRestSemiminima',
        'fusa' => 'mensuralRestFusa',
        'semifusa' => 'mensuralRestSemifusa',
        _ => 'mensuralRestSemibrevis',
      };
      _glyph(glyph, _x, 2, id: id);
      final box = s.metadata.bBoxOf(glyph);
      _regions.add(ElementRegion(
          id, Rectangle(_x, 2 - box.neY, max(box.width, 0.4), box.height)));
      _x += max(advance * 0.8, box.width + 0.8);
      return;
    }
    final position = _position(note.diatonic!);
    final y = _y(position);
    if (note.accid != null) {
      final glyph = switch (note.accid) {
        'f' => 'accidentalFlat',
        's' => 'accidentalSharp',
        _ => 'accidentalNatural',
      };
      _glyph(glyph, _x, y);
      _x += _width(glyph) + 0.25;
    }
    final glyph = _glyphFor(note);
    _glyph(glyph, _x, y, id: id);
    final width = _width(glyph);
    _regions.add(ElementRegion(id, Rectangle(_x, y - 0.75, width, 1.5)));
    for (var p = 10; p <= position; p += 2) {
      _line(_x - 0.3, _y(p), _x + width + 0.3, _y(p), s.staffLineThickness);
    }
    for (var p = -2; p >= position; p -= 2) {
      _line(_x - 0.3, _y(p), _x + width + 0.3, _y(p), s.staffLineThickness);
    }
    if (note.dotted) {
      _glyph(
          'augmentationDot', _x + width + 0.3, position.isEven ? y - 0.5 : y);
    }
    _x += max(advance, width + 0.9) + (note.dotted ? 0.5 : 0);
  }

  /// Draw a ligature: square heads edge-to-edge with vertical connectors,
  /// or a single oblique glyph for a 2-note obliqua pair.
  void _ligature(_MLigature lig) {
    if (lig.notes.isEmpty) return;
    // Check for oblique: 2-note ligature with form obliqua.
    if (lig.form == 'obliqua' && lig.notes.length == 2) {
      _oblique(lig.notes);
      return;
    }
    // Square ligature: each note as a square head, edge-to-edge, with
    // vertical connecting lines between different pitches.
    final ids = <String>[];
    final positions = <int>[];
    final ys = <double>[];
    // Pre-allocate ids in order m0, m1, ...
    for (final n in lig.notes) {
      ids.add('m${nextId++}');
      final pos = _position(n.diatonic!);
      positions.add(pos);
      ys.add(_y(pos));
    }
    // Advance for the whole ligature: sum of head widths plus small gaps.
    var startX = _x;
    String headGlyph(String dur, bool colored) {
      if (colored) {
        // Black square heads: use black longa/maxima noteheads where available.
        return dur == 'maxima'
            ? 'mensuralNoteheadMaximaBlack'
            : 'mensuralNoteheadLongaBlack';
      }
      return dur == 'maxima'
          ? 'mensuralNoteheadMaximaWhite'
          : 'mensuralNoteheadLongaWhite';
    }

    // First, handle accidentals for the first note (if any) before the ligature.
    // For simplicity, draw accidental at startX before first head.
    if (lig.notes.first.accid != null) {
      final accGlyph = switch (lig.notes.first.accid) {
        'f' => 'accidentalFlat',
        's' => 'accidentalSharp',
        _ => 'accidentalNatural',
      };
      _glyph(accGlyph, startX, ys.first);
      startX += _width(accGlyph) + 0.25;
      _x = startX;
    }
    // Draw each head edge-to-edge.
    var x = startX;
    for (var i = 0; i < lig.notes.length; i++) {
      final note = lig.notes[i];
      final id = ids[i];
      final glyph = headGlyph(note.dur, note.colored);
      _glyph(glyph, x, ys[i], id: id);
      final w = _width(glyph);
      // Hit region per note: its head's bounds.
      _regions.add(ElementRegion(id, Rectangle(x, ys[i] - 0.75, w, 1.5)));
      // Leger lines for each note (like _note does).
      final pos = positions[i];
      for (var p = 10; p <= pos; p += 2) {
        _line(x - 0.2, _y(p), x + w + 0.2, _y(p), s.staffLineThickness);
      }
      for (var p = -2; p >= pos; p -= 2) {
        _line(x - 0.2, _y(p), x + w + 0.2, _y(p), s.staffLineThickness);
      }
      // Vertical connector to next note if pitches differ.
      if (i + 1 < lig.notes.length && positions[i] != positions[i + 1]) {
        final nextY = ys[i + 1];
        final top = min(ys[i], nextY);
        final bottom = max(ys[i], nextY);
        // At the shared edge: x + w
        final connX = x + w;
        _line(connX, top, connX, bottom, s.stemThickness);
      }
      x += w;
      if (note.dotted) {
        _glyph('augmentationDot', x + 0.2,
            positions[i].isEven ? ys[i] - 0.5 : ys[i]);
        x += 0.5;
      }
    }
    // Advance _x to after the ligature.
    final totalAdvance =
        lig.notes.map((n) => _advance[n.dur] ?? 2.8).reduce((a, b) => a + b) /
            lig.notes.length;
    _x = max(x + 0.6, startX + totalAdvance);
  }

  /// Draw a 2-note oblique ligature as a single oblique glyph spanning both pitches.
  void _oblique(List<_MNote> notes) {
    assert(notes.length == 2);
    final n0 = notes[0];
    final n1 = notes[1];
    final id0 = 'm${nextId++}';
    final id1 = 'm${nextId++}';
    final pos0 = _position(n0.diatonic!);
    final pos1 = _position(n1.diatonic!);
    final y0 = _y(pos0);
    final y1 = _y(pos1);
    final asc = pos1 > pos0;
    final interval = (pos1 - pos0).abs() ~/ 1; // diatonic steps difference
    // Interval in seconds: 1 step = 2nd, 2 = 3rd, etc.
    final second = interval + 1;
    final glyph = _obliqueGlyph(second, asc, n0.colored || n1.colored);
    // The oblique glyph is drawn at the lower pitch's y (or midpoint) – use y0 for now.
    // Its width encodes the diagonal; we place it at _x, y0.
    // For asc, the glyph goes up; for desc, down. Use y0 as baseline.
    final x = _x;
    // Handle accidental for first note before oblique.
    var xOff = 0.0;
    if (n0.accid != null) {
      final accGlyph = switch (n0.accid) {
        'f' => 'accidentalFlat',
        's' => 'accidentalSharp',
        _ => 'accidentalNatural',
      };
      _glyph(accGlyph, x, y0);
      xOff = _width(accGlyph) + 0.25;
    }
    final drawX = x + xOff;
    // Draw the oblique glyph; tag with first id (second will share region but different id)
    _glyph(glyph, drawX, y0, id: id0);
    final w = _width(glyph);
    // Create hit regions for both notes: both cover the oblique glyph's area but with different ids,
    // offset vertically to their pitches so ids remain distinct.
    // Use the glyph's bounds but shift y to each note's pitch.
    _regions.add(ElementRegion(id0, Rectangle(drawX, y0 - 0.75, w, 1.5)));
    _regions.add(ElementRegion(id1, Rectangle(drawX, y1 - 0.75, w, 1.5)));
    // Ledger lines for each pitch.
    for (final pos in [pos0, pos1]) {
      for (var p = 10; p <= pos; p += 2) {
        _line(drawX - 0.2, _y(p), drawX + w + 0.2, _y(p), s.staffLineThickness);
      }
      for (var p = -2; p >= pos; p -= 2) {
        _line(drawX - 0.2, _y(p), drawX + w + 0.2, _y(p), s.staffLineThickness);
      }
    }
    // Advance.
    _x = drawX + max(w + 0.8, (_advance[n0.dur] ?? 2.8) * 0.8);
  }

  /// Pick an oblique glyph for the given interval, direction and colour, falling back to square.
  String _obliqueGlyph(int second, bool asc, bool black) {
    if (second < 2) second = 2;
    if (second > 5) second = 5;
    final dir = asc ? 'Asc' : 'Desc';
    final colour = black ? 'Black' : 'White';
    final suffix = switch (second) {
      2 => '2nd',
      3 => '3rd',
      4 => '4th',
      5 => '5th',
      _ => '${second}th',
    };
    final name = 'mensuralOblique$dir$suffix$colour';
    // Check if glyph exists in the font metadata (bBox width > 0 or present).
    // We can test via s.metadata.bBoxOf – if missing, width is 0 and name may not be in smuflCodepoints.
    // Fall back to square notehead if not found.
    final box = s.metadata.bBoxOf(name);
    if (box.width == 0 && box.height == 0) {
      return black
          ? 'mensuralNoteheadLongaBlack'
          : 'mensuralNoteheadLongaWhite';
    }
    return name;
  }
}
