/// GABC (Gregorian chant) notation import.
///
/// GABC is the plain-text chant format used by the Gregorio project. A `.gabc`
/// file is a header of `key:value;` lines, a `%%` separator, then a body of
/// `syllable(neumes)` pairs — a lyric syllable followed by its notes in
/// parentheses, e.g. `AL(dc)le(fg)lu(h)`.
///
/// This reads a broad slice of the public GABC specification
/// (http://gregorio-project.github.io/gabc/) into a crisp_notation [Score]
/// (pure Dart, web-safe): the clef (`c1`–`c4` do-clef, `f1`–`f4` fa-clef, with
/// an optional `b` flat signature such as `cb3`, and mid-body clef changes),
/// diatonic note letters `a`–`m` (case-insensitive — uppercase is the same
/// pitch, a different glyph), accidentals (`x` flat, `y` natural, `#` sharp,
/// persisting to the next division bar), the mora dot (`.` → a lengthened
/// note), division bars (`,` `;` `:` `::`) that split measures, and lyric
/// syllables (attached to the first note of their neume, hyphenated within a
/// word). Neume-shape and articulation characters (`v w o s ~ / ! _ ' < > `,
/// digits, brackets) carry no pitch and are skipped.
///
/// ## Deriving the letter → pitch mapping (first principles)
///
/// The 13 letters `a`–`m` are consecutive diatonic staff positions, `a` lowest,
/// walking the natural scale (…A B C D E F G…). A `cN` clef puts DO (a C) on
/// staff line `N`; an `fN` clef puts FA (an F) on line `N`. Staff lines are two
/// diatonic steps apart, so with the letters as a step coordinate (a = 0) the
/// four lines fall on fixed coordinates; solving them places DO of any c-clef at
/// middle C (`C4`) and FA of any f-clef at the F a fourth above (`F4`). Each
/// letter's pitch is then that reference shifted by its diatonic distance from
/// the clef's reference line — which yields, for a `c4` clef, `a` = A3 (MIDI 57)
/// and the run `a`…`m` = A3 B3 C4 … F5. See [_baseIndexFor].
library;

import 'dart:math';

import '../layout/layout_engine.dart' show estimateTextHalfWidth;
import '../layout/layout_settings.dart';
import '../layout/score_layout.dart';
import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';

part 'chant_layout.dart';

/// The parsed header fields of a GABC document (the `key:value;` lines before
/// `%%`), with typed getters for the common fields.
class GabcHeader {
  /// The raw header fields, keyed by lower-cased field name.
  final Map<String, String> fields;

  /// Wraps an already-parsed field map.
  const GabcHeader(this.fields);

  /// The piece title (`name:`).
  String? get name => fields['name'];

  /// The liturgical office part (`office-part:`), e.g. `Alleluia`, `Introitus`.
  String? get officePart => fields['office-part'];

  /// The Gregorian mode (`mode:`), kept as written (e.g. `1`, `VIII`).
  String? get mode => fields['mode'];

  /// The transcriber (`transcriber:`).
  String? get transcriber => fields['transcriber'];

  /// The source book (`book:`).
  String? get book => fields['book'];

  @override
  String toString() => 'GabcHeader($fields)';
}

/// Parses the header (the fields before `%%`) of a GABC [gabc] document.
GabcHeader gabcHeader(String gabc) {
  final separator = gabc.indexOf('%%');
  final header = separator < 0 ? gabc : gabc.substring(0, separator);
  return GabcHeader(_parseHeaderFields(header));
}

/// Parses a full GABC [gabc] document into a single-staff [Score].
///
/// Chant is unmetered, so the score carries [Clef.treble], an empty
/// [KeySignature] and no time signature; notes are eighths by default and a
/// mora dot lengthens a note to a quarter; division bars split measures and
/// reset in-measure accidentals; each syllable's text is attached as a [Lyric]
/// to the first note of its neume, hyphenated to the next syllable when the
/// word continues.
///
/// Throws a [FormatException] if the `%%` header separator is missing.
Score scoreFromGabc(String gabc) {
  final separator = gabc.indexOf('%%');
  if (separator < 0) {
    throw const FormatException('GABC: missing "%%" header separator');
  }
  final body = gabc.substring(separator + 2);

  final measures = <Measure>[];
  var current = <MusicElement>[];
  final syllables = <_Syllable>[];
  final accidentals = <int, int>{}; // diatonic index → alter, reset per bar
  var nextId = 0;

  // Clef state. Defaults to a do-clef on line 4 until the body declares one.
  var clefIsDo = true;
  var clefLine = 4;
  var flatSignature = false;
  var baseIndex = _baseIndexFor(clefIsDo, clefLine);

  _Pending? pending;
  NoteElement? lastNote;
  var firstSyllable = true;

  void flushMeasure() {
    if (current.isNotEmpty) {
      measures.add(Measure(List.of(current)));
      current = <MusicElement>[];
    }
    accidentals.clear();
    lastNote = null;
  }

  void emitNote(Pitch pitch) {
    final id = 'n${nextId++}';
    final note = NoteElement.note(pitch, NoteDuration.eighth, id: id);
    current.add(note);
    lastNote = note;
    if (pending != null) {
      syllables.add(_Syllable(id, pending!.text, pending!.wordStart));
      pending = null;
    }
  }

  void applyMora() {
    final last = lastNote;
    if (last != null && current.isNotEmpty && identical(current.last, last)) {
      current[current.length - 1] = NoteElement(
        pitches: last.pitches,
        duration: NoteDuration.quarter,
        id: last.id,
      );
      lastNote = current.last as NoteElement;
    }
  }

  void parseNeume(String group) {
    var k = 0;
    while (k < group.length) {
      final ch = group[k];
      final code = ch.toLowerCase().codeUnitAt(0);
      final isPitch = code >= _aCode && code <= _mCode;
      if (isPitch) {
        final diatonic = baseIndex + (code - _aCode);
        final next = k + 1 < group.length ? group[k + 1] : '';
        if (next == 'x' || next == 'y' || next == '#') {
          // Not a sounding note — sets an accidental at this staff position
          // that persists until the next division bar.
          accidentals[diatonic] = next == 'x'
              ? -1
              : next == '#'
                  ? 1
                  : 0;
          k += 2;
          continue;
        }
        final step = Step.values[diatonic % 7];
        final octave = diatonic ~/ 7;
        int alter;
        if (accidentals.containsKey(diatonic)) {
          alter = accidentals[diatonic]!;
        } else if (flatSignature && step == Step.b) {
          alter = -1; // a b-flat clef signature flats every si (B)
        } else {
          alter = 0;
        }
        emitNote(Pitch(step, alter: alter, octave: octave));
        k += 1;
        continue;
      }
      if (ch == '.') {
        applyMora();
      }
      // Every other character (neume shapes, spacing, episemata, brackets,
      // digits) carries no pitch and is skipped.
      k += 1;
    }
  }

  void handleGroup(String rawText, String group) {
    final wordStart = firstSyllable || _startsWithSpace(rawText);
    final text = _stripLyric(rawText);
    if (text.isNotEmpty) {
      pending = _Pending(text, wordStart);
      firstSyllable = false;
    }

    final trimmed = group.trim();
    final clef = _clefPattern.firstMatch(trimmed);
    if (clef != null) {
      clefIsDo = clef[1] == 'c';
      flatSignature = clef[2] == 'b';
      clefLine = int.parse(clef[3]!);
      baseIndex = _baseIndexFor(clefIsDo, clefLine);
      return;
    }
    if (trimmed.isNotEmpty && _divisionPattern.hasMatch(trimmed)) {
      flushMeasure();
      return;
    }
    parseNeume(group);
  }

  // Scan the body as a sequence of `text(group)` pairs.
  final buffer = StringBuffer();
  var i = 0;
  while (i < body.length) {
    final ch = body[i];
    if (ch == '(') {
      final rawText = buffer.toString();
      buffer.clear();
      var j = i + 1;
      while (j < body.length && body[j] != ')') {
        j++;
      }
      handleGroup(rawText, body.substring(i + 1, j));
      i = j < body.length ? j + 1 : j;
    } else {
      buffer.write(ch);
      i++;
    }
  }
  flushMeasure();

  // A syllable hyphenates to the next when the next one is not a new word.
  final lyrics = <Lyric>[
    for (var s = 0; s < syllables.length; s++)
      Lyric(
        syllables[s].id,
        syllables[s].text,
        hyphenToNext: s + 1 < syllables.length && !syllables[s + 1].wordStart,
      ),
  ];

  return Score(
    clef: Clef.treble,
    keySignature: const KeySignature(0),
    timeSignature: null,
    measures: measures,
    lyrics: lyrics,
  );
}

/// The absolute diatonic index (as used by `octave * 7 + Step.index`, C0 == 0)
/// of the GABC letter `a` for a clef.
///
/// A c-clef anchors DO to middle C (`C4`, index 28); an f-clef anchors FA to
/// the F a fourth above (`F4`, index 31). The clef's reference sits on line
/// [line]; letter `a` lies `6 - 2*line` diatonic steps from that line (lines
/// being two steps apart, with `a` two lines below line 3), so the index of
/// `a` is the reference index plus that offset.
int _baseIndexFor(bool isDo, int line) => (isDo ? 28 : 31) + (6 - 2 * line);

const int _aCode = 0x61; // 'a'
const int _mCode = 0x6d; // 'm'

final RegExp _clefPattern = RegExp(r'^([cf])(b?)([1-4])$');
final RegExp _divisionPattern = RegExp(r'^[,;:`]+$');
final RegExp _leadingSpace = RegExp(r'^\s');
final RegExp _braces = RegExp(r'\{[^}]*\}');
final RegExp _tags = RegExp(r'<[^>]*>');
final RegExp _choirMarks = RegExp(r'[*+]');

bool _startsWithSpace(String text) => _leadingSpace.hasMatch(text);

/// Strips GABC/HTML markup (`<i>…</i>`, `<sp>…</sp>`, `{…}`) and choir marks
/// (`*`, `+`) from a syllable's raw text, leaving the sung text.
String _stripLyric(String raw) => raw
    .replaceAll(_braces, '')
    .replaceAll(_tags, '')
    .replaceAll(_choirMarks, '')
    .trim();

/// Parses `key:value;` header fields into a lower-cased-key map (first wins).
Map<String, String> _parseHeaderFields(String header) {
  final map = <String, String>{};
  final withoutComments = header
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('%'))
      .join('\n');
  for (final field in withoutComments.split(';')) {
    final trimmed = field.trim();
    if (trimmed.isEmpty) continue;
    final colon = trimmed.indexOf(':');
    if (colon < 0) continue;
    final key = trimmed.substring(0, colon).trim().toLowerCase();
    final value = trimmed.substring(colon + 1).trim();
    map.putIfAbsent(key, () => value);
  }
  return map;
}

/// A syllable's attachment: the note id it sits on, its text, and whether it
/// begins a new word (used to decide hyphenation).
class _Syllable {
  final String id;
  final String text;
  final bool wordStart;
  const _Syllable(this.id, this.text, this.wordStart);
}

/// A syllable's text awaiting the first note of its neume.
class _Pending {
  final String text;
  final bool wordStart;
  const _Pending(this.text, this.wordStart);
}
