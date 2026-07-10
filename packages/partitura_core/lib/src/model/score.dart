/// The score document model and the `Score.simple` string DSL.
library;

import '../internal/util.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/time_signature.dart';
import 'element.dart';
import 'measure.dart';

/// A single-staff score: clef, signatures and measures.
class Score {
  /// The staff's clef.
  final Clef clef;

  /// The key signature (default: no sharps or flats).
  final KeySignature keySignature;

  /// The time signature; null renders an unmetered snippet (no time
  /// signature drawn, measure lengths unchecked).
  final TimeSignature? timeSignature;

  /// The measures in order.
  final List<Measure> measures;

  /// Slurs between note elements, referenced by element ids.
  final List<Slur> slurs;

  /// Dynamic markings attached to note elements (model-only; the DSL has
  /// no shorthand for them).
  final List<DynamicMarking> dynamics;

  /// Crescendo/diminuendo wedges between note elements (model-only).
  final List<Hairpin> hairpins;

  /// Creates a score (treat the lists as immutable).
  const Score({
    required this.clef,
    this.keySignature = const KeySignature(0),
    this.timeSignature,
    required this.measures,
    this.slurs = const [],
    this.dynamics = const [],
    this.hairpins = const [],
  });

  /// Builds a score from a terse note string, for tests and games.
  ///
  /// Grammar (whitespace-separated tokens, measures separated by `|`):
  ///
  /// ```text
  /// notes    := measure ('|' measure)*
  /// token    := rest | chord
  /// rest     := 'r' (':' duration)?
  /// chord    := pitch ('+' pitch)* (':' duration)?
  /// pitch    := stepLetter accidental? octaveDigit(s)     // see Pitch.parse
  /// duration := ('w'|'h'|'q'|'e'|'s'|'t'|'x'|'b') ('.' | '..')?
  /// ```
  ///
  /// - Durations are sticky: a token without `:duration` reuses the previous
  ///   token's duration (initially quarter). `w h q e s t x` are whole
  ///   down to sixty-fourth and `b` is a breve; dots follow the letter
  ///   (`q.` = dotted quarter).
  /// - A trailing `~` ties the note/chord to the next note element
  ///   (`c4:q~ c4:q`), also across a barline.
  /// - A trailing `(` opens a slur on this note and a trailing `)` closes
  ///   it (`c4:q( d4 e4)`); slurs may cross barlines but not nest.
  /// - A `{pitch,pitch}` prefix attaches grace notes (acciaccatura),
  ///   e.g. `{g4}a4:q` or `{f4,g4}a4:q`.
  /// - Articulation markers at the end of a note token: `'` staccato,
  ///   `_` tenuto, `>` accent, `^` marcato, `@` fermata (combinable, e.g.
  ///   `c4:q>'`).
  /// - Measure directives (tokens starting with `!`, conventionally first
  ///   in the measure): `!clef=bass`, `!key=-2`, `!time=3/4`, `!repeat`
  ///   (start repeat), `!endrepeat`, `!volta=1`.
  /// - `3[c4:e d4 e4]` groups a tuplet: `actual[`…`]` or `actual:normal[`
  ///   (default `normal` = the largest power of two below `actual`, and 3
  ///   for duplets). Tuplets cannot cross barlines or nest.
  /// - The accidental `n` parses as an explicit natural and forces the
  ///   accidental to be drawn (`showAccidental: true`).
  /// - Every element is auto-assigned the id `e0`, `e1`, … in reading order,
  ///   so games can address them immediately.
  ///
  /// Examples: `Score.simple(notes: 'c4:q d4 e4:h')`,
  /// `Score.simple(notes: 'c4+e4+g4:h r:h | g4:w')`.
  ///
  /// Throws a [FormatException] on malformed input.
  factory Score.simple({
    Clef clef = Clef.treble,
    KeySignature keySignature = const KeySignature(0),
    TimeSignature? timeSignature,
    required String notes,
  }) {
    var duration = NoteDuration.quarter;
    var nextId = 0;
    final measures = <Measure>[];
    final slurs = <Slur>[];
    String? openSlurStart;
    for (final measureSource in notes.split('|')) {
      final elements = <MusicElement>[];
      final tuplets = <TupletSpan>[];
      (int start, int actual, int normal)? openTuplet;
      Clef? clefChange;
      KeySignature? keyChange;
      TimeSignature? timeChange;
      var startRepeat = false;
      var endRepeat = false;
      int? volta;
      for (var token in measureSource.trim().split(RegExp(r'\s+'))) {
        if (token.isEmpty) continue;
        if (token.startsWith('!')) {
          final directive = token.substring(1);
          if (directive == 'repeat') {
            startRepeat = true;
          } else if (directive == 'endrepeat') {
            endRepeat = true;
          } else if (directive.startsWith('clef=')) {
            final name = directive.substring(5);
            clefChange = Clef.values.asNameMap()[name];
            if (clefChange == null) {
              throw FormatException('Unknown clef: "$token"');
            }
          } else if (directive.startsWith('key=')) {
            final fifths = int.tryParse(directive.substring(4));
            if (fifths == null || fifths < -7 || fifths > 7) {
              throw FormatException('Invalid key directive: "$token"');
            }
            keyChange = KeySignature(fifths);
          } else if (directive.startsWith('time=')) {
            final match =
                RegExp(r'^(\d+)/(\d+)$').firstMatch(directive.substring(5));
            if (match == null) {
              throw FormatException('Invalid time directive: "$token"');
            }
            timeChange = TimeSignature(
              int.parse(match[1]!),
              int.parse(match[2]!),
            );
          } else if (directive.startsWith('volta=')) {
            volta = int.tryParse(directive.substring(6));
            if (volta == null || volta < 1) {
              throw FormatException('Invalid volta directive: "$token"');
            }
          } else {
            throw FormatException('Unknown directive: "$token"');
          }
          continue;
        }
        final tupletMatch = RegExp(r'^(\d+)(?::(\d+))?\[').firstMatch(token);
        if (tupletMatch != null) {
          if (openTuplet != null) {
            throw const FormatException('Tuplets cannot nest');
          }
          final actual = int.parse(tupletMatch[1]!);
          if (actual < 2) {
            throw FormatException('Invalid tuplet ratio: "$token"');
          }
          var normal = tupletMatch[2] == null ? 0 : int.parse(tupletMatch[2]!);
          if (normal == 0) {
            if (actual == 2) {
              normal = 3; // duplet convention
            } else {
              normal = 1;
              while (normal * 2 < actual) {
                normal *= 2;
              }
            }
          }
          openTuplet = (elements.length, actual, normal);
          token = token.substring(tupletMatch[0]!.length);
        }
        var tied = false;
        var opensSlur = false;
        var closesSlur = false;
        var closesTuplet = false;
        final articulations = <Articulation>{};
        var stripping = true;
        while (stripping && token.isNotEmpty) {
          switch (token[token.length - 1]) {
            case '~':
              tied = true;
              token = token.substring(0, token.length - 1);
            case '(':
              opensSlur = true;
              token = token.substring(0, token.length - 1);
            case ')':
              closesSlur = true;
              token = token.substring(0, token.length - 1);
            case ']':
              closesTuplet = true;
              token = token.substring(0, token.length - 1);
            case "'":
              articulations.add(Articulation.staccato);
              token = token.substring(0, token.length - 1);
            case '_':
              articulations.add(Articulation.tenuto);
              token = token.substring(0, token.length - 1);
            case '>':
              articulations.add(Articulation.accent);
              token = token.substring(0, token.length - 1);
            case '^':
              articulations.add(Articulation.marcato);
              token = token.substring(0, token.length - 1);
            case '@':
              articulations.add(Articulation.fermata);
              token = token.substring(0, token.length - 1);
            default:
              stripping = false;
          }
        }
        var graceNotes = const <Pitch>[];
        final graceMatch = RegExp(r'^\{([^}]*)\}').firstMatch(token);
        if (graceMatch != null) {
          final inner = graceMatch[1]!.trim();
          if (inner.isEmpty) {
            throw FormatException('Empty grace group: "$token"');
          }
          graceNotes = [
            for (final source in inner.split(',')) Pitch.parse(source.trim()),
          ];
          token = token.substring(graceMatch[0]!.length);
        }
        final parts = token.split(':');
        if (parts.length > 2) {
          throw FormatException('Invalid token: "$token"');
        }
        if (parts.length == 2) {
          duration = _parseDuration(parts[1], token);
        }
        final id = 'e${nextId++}';
        if (parts[0] == 'r') {
          if (tied) {
            throw FormatException('A rest cannot be tied: "$token~"');
          }
          if (opensSlur || closesSlur) {
            throw FormatException('A rest cannot carry a slur: "$token"');
          }
          if (articulations.isNotEmpty) {
            throw FormatException(
                'A rest cannot carry articulations: "$token"');
          }
          if (graceNotes.isNotEmpty) {
            throw FormatException('A rest cannot carry grace notes: "$token"');
          }
          elements.add(RestElement(duration, id: id));
        } else {
          final sources = parts[0].split('+');
          final pitches = sources.map(Pitch.parse).toList();
          final forced = sources.any(_hasExplicitNatural);
          elements.add(NoteElement(
            pitches: pitches,
            duration: duration,
            showAccidental: forced ? true : null,
            tieToNext: tied,
            articulations: articulations,
            graceNotes: graceNotes,
            id: id,
          ));
          if (closesSlur) {
            if (openSlurStart == null) {
              throw FormatException('")" without an open slur: "$token)"');
            }
            slurs.add(Slur(openSlurStart, id));
            openSlurStart = null;
          }
          if (opensSlur) {
            if (openSlurStart != null) {
              throw const FormatException('Slurs cannot nest');
            }
            openSlurStart = id;
          }
        }
        if (closesTuplet) {
          final open = openTuplet;
          if (open == null) {
            throw FormatException('"]" without an open tuplet: "$token]"');
          }
          tuplets.add(TupletSpan(
            open.$1,
            elements.length - 1,
            actual: open.$2,
            normal: open.$3,
          ));
          openTuplet = null;
        }
      }
      if (openTuplet != null) {
        throw const FormatException('Unclosed tuplet "["');
      }
      measures.add(Measure(
        elements,
        tuplets: tuplets,
        clefChange: clefChange,
        keyChange: keyChange,
        timeChange: timeChange,
        startRepeat: startRepeat,
        endRepeat: endRepeat,
        volta: volta,
      ));
    }
    if (openSlurStart != null) {
      throw const FormatException('Unclosed slur "("');
    }
    return Score(
      clef: clef,
      keySignature: keySignature,
      timeSignature: timeSignature,
      measures: measures,
      slurs: slurs,
    );
  }

  static bool _hasExplicitNatural(String pitchSource) =>
      RegExp(r'^[a-gA-G]n').hasMatch(pitchSource.trim());

  static const Map<String, DurationBase> _durationLetters = {
    'w': DurationBase.whole,
    'h': DurationBase.half,
    'q': DurationBase.quarter,
    'e': DurationBase.eighth,
    's': DurationBase.sixteenth,
    't': DurationBase.thirtySecond,
    'x': DurationBase.sixtyFourth,
    'b': DurationBase.breve,
  };

  static NoteDuration _parseDuration(String source, String token) {
    final match = RegExp(r'^([whqestxb])(\.{0,2})$').firstMatch(source);
    if (match == null) {
      throw FormatException('Invalid duration in token: "$token"');
    }
    return NoteDuration(
      _durationLetters[match[1]]!,
      dots: match[2]!.length,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Score &&
      other.clef == clef &&
      other.keySignature == keySignature &&
      other.timeSignature == timeSignature &&
      listEquals(other.measures, measures) &&
      listEquals(other.slurs, slurs) &&
      listEquals(other.dynamics, dynamics) &&
      listEquals(other.hairpins, hairpins);

  @override
  int get hashCode => Object.hash(
        clef,
        keySignature,
        timeSignature,
        Object.hashAll(measures),
        Object.hashAll(slurs),
        Object.hashAll(dynamics),
        Object.hashAll(hairpins),
      );

  @override
  String toString() =>
      'Score(${clef.name}, $keySignature, ${timeSignature ?? 'unmetered'}, '
      '${measures.length} measures)';
}
