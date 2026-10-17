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
  const _MNote(this.diatonic, this.dur, {this.dotted = false, this.accid});
}

final class _MCustos extends _MItem {
  final int diatonic;
  const _MCustos(this.diatonic);
}

const _steps = {'c': 0, 'd': 1, 'e': 2, 'f': 3, 'g': 4, 'a': 5, 'b': 6};

List<_MItem> _mensuralItems(String mei, int staffN) {
  final root = parseXml(mei);
  final items = <_MItem>[];
  int? diatonicOf(XmlNode n) {
    final step = _steps[n.attributes['pname']?.toLowerCase()];
    final oct = int.tryParse(n.attributes['oct'] ?? '');
    return step == null || oct == null ? null : oct * 7 + step;
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
        final d = diatonicOf(e);
        if (d == null) return;
        final accid = e.attributes['accid'] ??
            e.descendants
                .where((c) => c.name == 'accid')
                .map((c) => c.attributes['accid'])
                .firstOrNull;
        items.add(_MNote(d, e.attributes['dur'] ?? 'semibrevis',
            dotted: e.attributes['dots'] == '1', accid: accid));
      case 'rest':
        items.add(_MNote(null, e.attributes['dur'] ?? 'semibrevis'));
      case 'dot':
        // A dot of addition or division follows its note.
        final last = items.isEmpty ? null : items.last;
        if (last is _MNote && last.diatonic != null) {
          items[items.length - 1] =
              _MNote(last.diatonic, last.dur, dotted: true, accid: last.accid);
        }
      case 'custos':
        final d = diatonicOf(e);
        if (d != null) items.add(_MCustos(d));
      case 'ligature' || 'beam' || 'tuplet' || 'choice' || 'sic' || 'orig':
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
    final glyph = switch (note.dur) {
      'maxima' => 'mensuralWhiteMaxima',
      'longa' => 'mensuralWhiteLonga',
      'brevis' => 'mensuralWhiteBrevis',
      'minima' => 'mensuralWhiteMinima',
      'semiminima' => 'mensuralWhiteSemiminima',
      'fusa' || 'semifusa' => 'mensuralWhiteFusa',
      _ => 'mensuralWhiteSemibrevis',
    };
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
}
