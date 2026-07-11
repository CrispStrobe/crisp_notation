/// The score document model and the `Score.simple` string DSL.
library;

import '../internal/util.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/interval.dart';
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

  /// Lyric syllables attached to note elements (see `Score.simple`'s
  /// `lyrics` parameter for the string shorthand).
  final List<Lyric> lyrics;

  /// Text annotations above the staff — chord symbols, rehearsal marks,
  /// tempo text (see `Score.simple`'s `annotations` parameter).
  final List<Annotation> annotations;

  /// Ottava brackets (model-only; the DSL has no shorthand). Spanned
  /// notes draw an octave off their sounding pitch.
  final List<Ottava> ottavas;

  /// Glissando/slide lines between note elements (model-only).
  final List<Glissando> glissandos;

  /// Sustain-pedal spans between note elements (model-only).
  final List<Pedal> pedals;

  /// Feathered (fanned) beams over note runs (model-only).
  final List<FeatheredBeam> featheredBeams;

  /// Forced beam slants over note runs (model-only).
  final List<BeamSlant> beamSlants;

  /// String bends on tab notes (rendered by the tab engine only).
  final List<Bend> bends;

  /// Vibratos on tab notes (rendered by the tab engine only).
  final List<Vibrato> vibratos;

  /// Palm-mute spans on tab notes (rendered by the tab engine only).
  final List<PalmMute> palmMutes;

  /// Let-ring spans on tab notes (rendered by the tab engine only).
  final List<LetRing> letRings;

  /// Dead ("x") and ghost (parenthesized) tab notes (rendered by the tab
  /// engine only).
  final List<TabNoteMark> tabNoteMarks;

  /// Per-note string assignments pinning tab placement (rendered by the tab
  /// engine only; overrides default lowest-fret placement).
  final List<TabVoicing> tabVoicings;

  /// Tapped tab notes (rendered by the tab engine only).
  final List<Tap> taps;

  /// Tremolo-bar (whammy) dips on tab notes (rendered by the tab engine only).
  final List<TremoloBar> tremoloBars;

  /// Chord/fretboard diagrams placed above note elements (drawn on both the
  /// notation and tab staves).
  final List<PlacedChordDiagram> chordDiagrams;

  /// Creates a score (treat the lists as immutable).
  const Score({
    required this.clef,
    this.keySignature = const KeySignature(0),
    this.timeSignature,
    required this.measures,
    this.slurs = const [],
    this.dynamics = const [],
    this.hairpins = const [],
    this.lyrics = const [],
    this.annotations = const [],
    this.ottavas = const [],
    this.glissandos = const [],
    this.pedals = const [],
    this.featheredBeams = const [],
    this.beamSlants = const [],
    this.bends = const [],
    this.vibratos = const [],
    this.palmMutes = const [],
    this.letRings = const [],
    this.tabNoteMarks = const [],
    this.tabVoicings = const [],
    this.taps = const [],
    this.tremoloBars = const [],
    this.chordDiagrams = const [],
  });

  /// Builds a score from a terse note string, for tests and games.
  ///
  /// Grammar (whitespace-separated tokens, measures separated by `|`,
  /// voices within a measure separated by `;`):
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
  /// - Ornament markers (one per note, drawn above): `%` trill, `\$`
  ///   short trill (upper mordent), `&` mordent, `?` turn.
  /// - Fingering: an `=` suffix with one digit (`c4:q=3`) or a
  ///   comma-separated list for a chord (`c4+e4+g4:h=1,3,5`); may sit
  ///   before other trailing markers (`c4:q=2~`).
  /// - Measure directives (tokens starting with `!`, conventionally first
  ///   in the measure): `!clef=bass`, `!key=-2`, `!time=3/4`, `!repeat`
  ///   (start repeat), `!endrepeat`, `!volta=1`, `!mrest=4` (a
  ///   multi-measure rest standing for 4 silent measures; no notes),
  ///   `!nav=<mark>` (navigation mark: `segno`, `coda`, `toCoda`,
  ///   `daCapo`, `daCapoAlFine`, `daCapoAlCoda`, `dalSegno`,
  ///   `dalSegnoAlFine`, `dalSegnoAlCoda`, `fine`),
  ///   `!barline=<style>` (closing barline: `doubleBar`, `finalBar`,
  ///   `heavy`, `dashed`, `dotted`, `none`).
  /// - A `;` splits a measure into two voices (`c5:q d5 ; c4:h`): voice 1
  ///   (before, stems up) and voice 2 (after, stems down). Directives and
  ///   tuplets belong to voice 1; ids keep counting across voices.
  /// - `3[c4:e d4 e4]` groups a tuplet: `actual[`…`]` or `actual:normal[`
  ///   (default `normal` = the largest power of two below `actual`, and 3
  ///   for duplets). Tuplets cannot cross barlines or nest.
  /// - The accidental `n` parses as an explicit natural and forces the
  ///   accidental to be drawn (`showAccidental: true`).
  /// - Every element is auto-assigned the id `e0`, `e1`, … in reading order,
  ///   so games can address them immediately.
  /// - The optional [lyrics] string attaches syllables to the voice-1
  ///   **note** elements in reading order (rests are skipped):
  ///   whitespace-separated tokens, `*` skips a note, a trailing `-`
  ///   hyphenates to the next syllable, a trailing `_` draws a melisma
  ///   extender (`lyrics: 'Twin- kle * star_'`).
  /// - The optional [annotations] string works the same way but places
  ///   text **above** the staff (chord symbols, tempo/rehearsal text):
  ///   `*` skips a note (`annotations: 'C * G7 *'`).
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
    String? lyrics,
    String? annotations,
  }) {
    var duration = NoteDuration.quarter;
    var nextId = 0;
    final measures = <Measure>[];
    final slurs = <Slur>[];
    String? openSlurStart;
    for (final measureSource in notes.split('|')) {
      final voiceSources = measureSource.split(';');
      if (voiceSources.length > 2) {
        throw const FormatException('At most two voices per measure');
      }
      final elements = <MusicElement>[];
      final voice2 = <MusicElement>[];
      final tuplets = <TupletSpan>[];
      (int start, int actual, int normal)? openTuplet;
      Clef? clefChange;
      KeySignature? keyChange;
      TimeSignature? timeChange;
      var startRepeat = false;
      var endRepeat = false;
      int? volta;
      int? multiRest;
      NavigationMark? navigation;
      var barline = BarlineStyle.normal;
      var voiceIndex = 0;
      for (final voiceSource in voiceSources) {
        final target = voiceIndex == 0 ? elements : voice2;
        for (var token in voiceSource.trim().split(RegExp(r'\s+'))) {
          if (token.isEmpty) continue;
          if (voiceIndex == 1 &&
              (token.startsWith('!') || RegExp(r'^\d').hasMatch(token))) {
            throw FormatException(
                'Directives and tuplets are voice-1 only: "$token"');
          }
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
            } else if (directive.startsWith('mrest=')) {
              multiRest = int.tryParse(directive.substring(6));
              if (multiRest == null || multiRest < 2) {
                throw FormatException('Invalid mrest directive: "$token"');
              }
            } else if (directive.startsWith('nav=')) {
              navigation =
                  NavigationMark.values.asNameMap()[directive.substring(4)];
              if (navigation == null) {
                throw FormatException('Unknown navigation mark: "$token"');
              }
            } else if (directive.startsWith('barline=')) {
              barline =
                  BarlineStyle.values.asNameMap()[directive.substring(8)] ??
                      (throw FormatException('Unknown barline: "$token"'));
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
            var normal =
                tupletMatch[2] == null ? 0 : int.parse(tupletMatch[2]!);
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
          // Fingering `=N` (single digit) or `=1,3,5` for a chord. Anchored
          // to the `=` (unique in a note token), so it may sit before other
          // trailing markers (`c4:q=2~`, `c4:q>=3`).
          var fingerings = const <int>[];
          final fingerMatch = RegExp(r'=([0-9](?:,[0-9])*)').firstMatch(token);
          if (fingerMatch != null) {
            fingerings = [
              for (final d in fingerMatch[1]!.split(',')) int.parse(d)
            ];
            token = token.substring(0, fingerMatch.start) +
                token.substring(fingerMatch.end);
          }
          var tied = false;
          var opensSlur = false;
          var closesSlur = false;
          var closesTuplet = false;
          Ornament? ornament;
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
              case '%':
                ornament = Ornament.trill;
                token = token.substring(0, token.length - 1);
              case r'$':
                ornament = Ornament.shortTrill;
                token = token.substring(0, token.length - 1);
              case '&':
                ornament = Ornament.mordent;
                token = token.substring(0, token.length - 1);
              case '?':
                ornament = Ornament.turn;
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
              throw FormatException(
                  'A rest cannot carry grace notes: "$token"');
            }
            if (fingerings.isNotEmpty) {
              throw FormatException('A rest cannot carry fingerings: "$token"');
            }
            target.add(RestElement(duration, id: id));
          } else {
            final sources = parts[0].split('+');
            final pitches = sources.map(Pitch.parse).toList();
            final forced = sources.any(_hasExplicitNatural);
            target.add(NoteElement(
              pitches: pitches,
              duration: duration,
              showAccidental: forced ? true : null,
              tieToNext: tied,
              articulations: articulations,
              graceNotes: graceNotes,
              ornament: ornament,
              fingerings: fingerings,
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
        voiceIndex++;
      }
      if (openTuplet != null) {
        throw const FormatException('Unclosed tuplet "["');
      }
      if (multiRest != null && elements.isNotEmpty) {
        throw const FormatException('!mrest measures cannot hold notes');
      }
      measures.add(Measure(
        elements,
        voice2: voice2,
        tuplets: tuplets,
        clefChange: clefChange,
        keyChange: keyChange,
        timeChange: timeChange,
        startRepeat: startRepeat,
        endRepeat: endRepeat,
        volta: volta,
        multiRest: multiRest,
        navigation: navigation,
        barline: barline,
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
      lyrics: lyrics == null ? const [] : _parseLyrics(lyrics, measures),
      annotations: annotations == null
          ? const []
          : _parseAnnotations(annotations, measures),
    );
  }

  /// Maps [source]'s tokens onto the voice-1 note elements of [measures]
  /// in reading order (`*` skips a note).
  static List<Annotation> _parseAnnotations(
    String source,
    List<Measure> measures,
  ) {
    final noteIds = <String>[
      for (final measure in measures)
        for (final element in measure.elements)
          if (element is NoteElement && element.id != null) element.id!,
    ];
    final result = <Annotation>[];
    var index = 0;
    for (final token in source.trim().split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      if (index >= noteIds.length) {
        throw FormatException('More annotation tokens than notes: "$token"');
      }
      if (token != '*') result.add(Annotation(noteIds[index], token));
      index++;
    }
    return result;
  }

  /// Maps [source]'s syllable tokens onto the voice-1 note elements of
  /// [measures] in reading order.
  static List<Lyric> _parseLyrics(String source, List<Measure> measures) {
    final noteIds = <String>[
      for (final measure in measures)
        for (final element in measure.elements)
          if (element is NoteElement && element.id != null) element.id!,
    ];
    final result = <Lyric>[];
    var index = 0;
    for (final token in source.trim().split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      if (index >= noteIds.length) {
        throw FormatException('More lyric tokens than notes: "$token"');
      }
      if (token == '*') {
        index++;
        continue;
      }
      final hyphen = token.endsWith('-') && token.length > 1;
      final extender = token.endsWith('_') && token.length > 1;
      final text =
          hyphen || extender ? token.substring(0, token.length - 1) : token;
      result.add(Lyric(
        noteIds[index],
        text,
        hyphenToNext: hyphen,
        extender: extender,
      ));
      index++;
    }
    return result;
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

  /// This score transposed by [interval] (ascending unless
  /// [descending]): every pitch — chords, both voices, grace notes —
  /// plus the key signature and any mid-score key changes move
  /// together. Out-of-range keys wrap enharmonically (e.g. G♯ major
  /// becomes A♭ major). Ids, rhythm, spans and lyrics are unchanged;
  /// chord-symbol annotation **text** is not rewritten.
  Score transposedBy(Interval interval, {bool descending = false}) {
    Pitch move(Pitch pitch) =>
        pitch.transposeBy(interval, descending: descending);
    MusicElement moveElement(MusicElement element) => switch (element) {
          NoteElement() => NoteElement(
              pitches: element.pitches.map(move).toList(),
              duration: element.duration,
              showAccidental: element.showAccidental,
              tieToNext: element.tieToNext,
              articulations: element.articulations,
              graceNotes: element.graceNotes.map(move).toList(),
              ornament: element.ornament,
              fingerings: element.fingerings,
              arpeggio: element.arpeggio,
              tremolo: element.tremolo,
              id: element.id,
            ),
          RestElement() => element,
        };
    return Score(
      clef: clef,
      keySignature:
          _transposedKey(keySignature, interval, descending: descending),
      timeSignature: timeSignature,
      measures: [
        for (final measure in measures)
          Measure(
            measure.elements.map(moveElement).toList(),
            voice2: measure.voice2.map(moveElement).toList(),
            tuplets: measure.tuplets,
            clefChange: measure.clefChange,
            keyChange: measure.keyChange == null
                ? null
                : _transposedKey(measure.keyChange!, interval,
                    descending: descending),
            timeChange: measure.timeChange,
            startRepeat: measure.startRepeat,
            endRepeat: measure.endRepeat,
            volta: measure.volta,
            multiRest: measure.multiRest,
            navigation: measure.navigation,
          ),
      ],
      slurs: slurs,
      dynamics: dynamics,
      hairpins: hairpins,
      lyrics: lyrics,
      annotations: annotations,
      ottavas: ottavas,
      glissandos: glissandos,
      pedals: pedals,
      featheredBeams: featheredBeams,
      beamSlants: beamSlants,
      bends: bends,
      vibratos: vibratos,
      palmMutes: palmMutes,
      letRings: letRings,
      tabNoteMarks: tabNoteMarks,
      tabVoicings: tabVoicings,
      taps: taps,
      tremoloBars: tremoloBars,
      chordDiagrams: chordDiagrams,
    );
  }

  /// Transposes [key] by moving its major tonic along the line of
  /// fifths; results beyond ±7 wrap to the enharmonic key.
  static KeySignature _transposedKey(KeySignature key, Interval interval,
      {required bool descending}) {
    const stepOfFifth = {
      0: Step.c,
      1: Step.g,
      2: Step.d,
      3: Step.a,
      4: Step.e,
      5: Step.b,
      6: Step.f, // -1 mapped via the 6 → -1 shift below
    };
    var base = ((key.fifths % 7) + 7) % 7;
    var shift = 0;
    if (base == 6) {
      base = 6;
      shift = -1; // 6 on the circle is F, one fifth below C
    }
    final step = stepOfFifth[base]!;
    final baseIndex = shift == -1 ? -1 : base;
    final alter = (key.fifths - baseIndex) ~/ 7;
    final tonic = Pitch(step, alter: alter);
    final moved = tonic.transposeBy(interval, descending: descending);
    const indexOfStep = {
      Step.c: 0,
      Step.d: 2,
      Step.e: 4,
      Step.f: -1,
      Step.g: 1,
      Step.a: 3,
      Step.b: 5,
    };
    var fifths = indexOfStep[moved.step]! + 7 * moved.alter;
    while (fifths > 7) {
      fifths -= 12;
    }
    while (fifths < -7) {
      fifths += 12;
    }
    return KeySignature(fifths);
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
      listEquals(other.hairpins, hairpins) &&
      listEquals(other.lyrics, lyrics) &&
      listEquals(other.annotations, annotations) &&
      listEquals(other.ottavas, ottavas) &&
      listEquals(other.glissandos, glissandos) &&
      listEquals(other.pedals, pedals) &&
      listEquals(other.featheredBeams, featheredBeams) &&
      listEquals(other.beamSlants, beamSlants) &&
      listEquals(other.bends, bends) &&
      listEquals(other.vibratos, vibratos) &&
      listEquals(other.palmMutes, palmMutes) &&
      listEquals(other.letRings, letRings) &&
      listEquals(other.tabNoteMarks, tabNoteMarks) &&
      listEquals(other.tabVoicings, tabVoicings) &&
      listEquals(other.taps, taps) &&
      listEquals(other.tremoloBars, tremoloBars) &&
      listEquals(other.chordDiagrams, chordDiagrams);

  @override
  int get hashCode => Object.hash(
        clef,
        keySignature,
        timeSignature,
        Object.hashAll(measures),
        Object.hashAll(slurs),
        Object.hashAll(dynamics),
        Object.hashAll(hairpins),
        Object.hashAll(lyrics),
        Object.hashAll(annotations),
        Object.hashAll(ottavas),
        Object.hashAll(glissandos),
        Object.hashAll(pedals),
        Object.hashAll(featheredBeams),
        Object.hashAll(beamSlants),
        Object.hashAll(bends),
        Object.hashAll(vibratos),
        Object.hashAll(palmMutes),
        // Grouped to stay within Object.hash's 20-argument ceiling as tab
        // marks keep growing.
        Object.hash(
          Object.hashAll(letRings),
          Object.hashAll(tabNoteMarks),
          Object.hashAll(tabVoicings),
          Object.hashAll(taps),
          Object.hashAll(tremoloBars),
          Object.hashAll(chordDiagrams),
        ),
      );

  @override
  String toString() =>
      'Score(${clef.name}, $keySignature, ${timeSignature ?? 'unmetered'}, '
      '${measures.length} measures)';
}
