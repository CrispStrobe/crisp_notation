/// LilyPond export: [Score] → a `.ly` source string for the LilyPond engraver.
///
/// Export-only — LilyPond input is a full (Turing-complete) language, so there
/// is no importer. Generated from the documented syntax (no LilyPond code is
/// used), pure Dart. Covers clef (with mid-score changes), key/time
/// signatures, notes/chords, rests, durations (breve…64th with dots), two
/// voices, ties, pickup (`\partial`), articulations, ornaments, slurs
/// (`(`/`)`) and tuplets (`\tuplet a/n { … }`). Lyrics, dynamics and repeat
/// structure are out of scope.
/// Pitch
/// names use LilyPond's default Dutch note language.
library;

import '../layout/multi_part.dart';
import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/time_signature.dart';

/// The LilyPond version tag emitted at the top of the file.
const _lilyVersion = '2.24.0';

const _clefNames = {
  Clef.treble: 'treble',
  Clef.bass: 'bass',
  Clef.alto: 'alto',
  Clef.tenor: 'tenor',
  Clef.treble8va: '"treble^8"',
  Clef.treble8vb: '"treble_8"',
  Clef.bass8vb: '"bass_8"',
  Clef.frenchViolin: 'french',
  Clef.soprano: 'soprano',
  Clef.mezzoSoprano: 'mezzosoprano',
  Clef.baritone: 'varbaritone', // F-clef baritone (crisp_notation's baritone)
  Clef.subbass: 'subbass',
  Clef.percussion: 'percussion',
};

/// Major-key tonic (Dutch note name) for a signature of `fifths`.
const _keyTonics = {
  0: 'c', 1: 'g', 2: 'd', 3: 'a', 4: 'e', 5: 'b', 6: 'fis', 7: 'cis', //
  -1: 'f', -2: 'bes', -3: 'ees', -4: 'aes', -5: 'des', -6: 'ges', -7: 'ces',
};

const _durValues = {
  // Values longer than a whole note are WORDS in LilyPond, not numbers, and
  // the shortest ones continue the numeric series. A base with no entry here
  // emitted no duration at all, so the note silently vanished on read-back.
  DurationBase.long: r'\longa',
  DurationBase.breve: r'\breve',
  DurationBase.whole: '1',
  DurationBase.half: '2',
  DurationBase.quarter: '4',
  DurationBase.eighth: '8',
  DurationBase.sixteenth: '16',
  DurationBase.thirtySecond: '32',
  DurationBase.sixtyFourth: '64',
  DurationBase.oneHundredTwentyEighth: '128',
  DurationBase.twoHundredFiftySixth: '256',
  DurationBase.fiveHundredTwelfth: '512',
  DurationBase.oneThousandTwentyFourth: '1024',
};

/// Serializes [score] as a LilyPond `.ly` document.
String scoreToLilyPond(Score score) {
  final meta = score.metadata;
  final out = StringBuffer()..writeln('\\version "$_lilyVersion"');
  final header = [
    for (final (field, value) in [
      ('title', meta.title),
      ('composer', meta.composer),
      ('poet', meta.lyricist),
      ('copyright', meta.copyright),
    ])
      if (value != null) '  $field = ${_lyString(value)}',
  ];
  if (header.isNotEmpty) {
    out.writeln('\\header {\n${header.join('\n')}\n}');
  }
  out.writeln('\\score {');
  final chords = _chordNamesBlock(score);
  final figures = _figuredBassBlock(score);
  final grouped = score.lyrics.isNotEmpty || chords != null || figures != null;
  if (grouped) out.writeln('  <<');
  if (chords != null) out.writeln(chords);
  if (figures != null) out.writeln(figures);
  out.writeln(_staffBlock(score));
  if (score.lyrics.isNotEmpty) out.writeln(_lyricsBlocks(score));
  if (grouped) out.writeln('  >>');
  out.writeln('  \\layout { }');
  out.writeln('}');
  return out.toString();
}

/// A `\new ChordNames \chordmode { … }` track for [score], or null when it
/// carries no harmony.
///
/// The track MIRRORS THE MELODY'S RHYTHM — each element becomes either its
/// chord or a skip of the same length. The reader anchors chords by walking
/// both streams' elapsed time, so mirroring makes the onsets exact by
/// construction; emitting each chord with a gap-length duration instead would
/// need arbitrary fractions that no plain LilyPond duration can spell.
String? _chordNamesBlock(Score score) {
  if (score.chordSymbols.isEmpty) return null;
  final byId = {for (final c in score.chordSymbols) c.elementId: c};
  final body = StringBuffer();
  var any = false;
  for (final measure in score.measures) {
    for (final e in measure.elements) {
      if (e is! NoteElement && e is! RestElement) continue;
      final chord = e.id == null ? null : byId[e.id!];
      if (chord != null) any = true;
      body.write(chord == null
          ? 's${_dur(e.duration)} '
          : '${_lyChord(chord, _dur(e.duration))} ');
    }
  }
  if (!any) return null;
  return '  \\new ChordNames \\chordmode {\n'
      '    ${body.toString().trimRight()}\n  }';
}

/// A `\new FiguredBass \figuremode { … }` track, or null when the score has
/// none.
///
/// Mirrors the melody's rhythm exactly, like the chord track: each element
/// becomes either its figures or a skip of the same length, so the onsets are
/// right by construction rather than by arithmetic.
String? _figuredBassBlock(Score score) {
  if (score.figuredBass.isEmpty) return null;
  final byId = {for (final f in score.figuredBass) f.noteId: f.figures};
  final body = StringBuffer();
  var any = false;
  for (final measure in score.measures) {
    for (final e in measure.elements) {
      if (e is! NoteElement && e is! RestElement) continue;
      final figs = e.id == null ? null : byId[e.id!];
      if (figs != null) any = true;
      body.write(figs == null
          ? 's${_dur(e.duration)} '
          : '<${figs.join(' ')}>${_dur(e.duration)} ');
    }
  }
  if (!any) return null;
  return '  \\new FiguredBass \\figuremode {\n'
      '    ${body.toString().trimRight()}\n  }';
}

/// A chord in LilyPond's `\chordmode` spelling: `c4`, `a4:m7`, `g4/b`.
///
/// ⚠️ The DURATION belongs on the root, before the `:` — `a4:m7`, never
/// `a:m74`. Appending it after the quality glues it onto the modifier, which
/// then matches nothing and degrades to a bare major triad while the chord
/// also keeps the previous chord's length, so every later onset shifts.
///
/// ⚠️ The root is written in the OCTAVE THE MODEL HOLDS, not normalised — the
/// reader parses it as a pitch and a chord track written low (`f,2/c`) is
/// conventional, so dropping the octave mark would move the root.
String _lyChord(ChordSymbol c, String duration) {
  final mod = _lyChordMods[c.quality] ?? '';
  final bass = c.bass == null ? '' : '/${_pitch(c.bass!)}';
  return '${_pitch(c.root)}$duration${mod.isEmpty ? '' : ':$mod'}$bass';
}

/// The model's qualities in LilyPond's own modifier spelling. `maj` already
/// MEANS a major seventh in LilyPond, so a plain triad takes no modifier at
/// all, and `7+` is its raised seventh — hence `m7+` for minor-major.
const Map<ChordSymbolKind, String> _lyChordMods = {
  ChordSymbolKind.major: '',
  ChordSymbolKind.minor: 'm',
  ChordSymbolKind.diminished: 'dim',
  ChordSymbolKind.augmented: 'aug',
  ChordSymbolKind.dominantSeventh: '7',
  ChordSymbolKind.majorSeventh: 'maj7',
  ChordSymbolKind.minorSeventh: 'm7',
  ChordSymbolKind.halfDiminishedSeventh: 'm7.5-',
  ChordSymbolKind.diminishedSeventh: 'dim7',
  ChordSymbolKind.minorMajorSeventh: 'm7+',
  ChordSymbolKind.sixth: '6',
  ChordSymbolKind.minorSixth: 'm6',
  ChordSymbolKind.dominantNinth: '9',
  ChordSymbolKind.suspendedFourth: 'sus4',
  ChordSymbolKind.suspendedSecond: 'sus2',
};

String _lyricsBlocks(Score score) {
  final byVerse = <int, Map<String, Lyric>>{};
  for (final l in score.lyrics) {
    (byVerse[l.verse] ??= {})[l.elementId] = l;
  }

  final buf = StringBuffer();
  for (final verse in byVerse.keys.toList()..sort()) {
    final byId = byVerse[verse]!;
    final tokens = <String>[];
    for (final m in score.measures) {
      for (final e in m.elements) {
        if (e is! NoteElement) continue;
        final l = e.id == null ? null : byId[e.id];
        if (l == null) {
          tokens.add('_');
        } else {
          String syllable = _lyString(l.text);
          if (l.hyphenToNext) {
            syllable += ' --';
          } else if (l.extender) {
            syllable += ' __';
          }
          tokens.add(syllable);
        }
      }
    }
    while (tokens.isNotEmpty && tokens.last == '_') {
      tokens.removeLast();
    }
    if (tokens.isNotEmpty) {
      buf.writeln('  \\addlyrics { ${tokens.join(' ')} }');
    }
  }
  return buf.toString().trimRight();
}

/// A `\new Staff\with { instrumentName } { … }` block for one [score] — the
/// clef/key/meter/tempo prologue then the measures (with mid-score changes,
/// pickups, tuplets and a second voice). Shared by [scoreToLilyPond] (one
/// staff) and [multiPartToLilyPond] (one per part).
String _staffBlock(Score score, {String? nameOverride}) {
  final slurStarts = {for (final s in score.slurs) s.startId};
  final slurEnds = {for (final s in score.slurs) s.endId};
  // Dynamics and hairpins were emitted by NO other path — the model has carried
  // both since long before this writer, and every other codec round-trips them.
  final dynamics = {for (final d in score.dynamics) d.elementId: d.level};
  // Text marks (ABC's quoted `"Eb"` chord symbols land here). LilyPond writes
  // them on the note as `^"text"` above or `_"text"` below. 4,150 of the 10,000
  // held-control ABC files carry at least one and we dropped every one.
  final annotations = {
    for (final a in score.annotations)
      a.elementId: (a.text, a.placement == AnnotationPlacement.below),
  };
  final hairpinOpen = {for (final h in score.hairpins) h.startId: h.type};
  final hairpinClose = {for (final h in score.hairpins) h.endId};
  final glissStarts = {for (final g in score.glissandos) g.startId};
  final pedalOn = {for (final p in score.pedals) p.startId};
  final pedalOff = {for (final p in score.pedals) p.endId};
  // `down` in the model means the notes are WRITTEN LOWER — an 8va bracket
  // ABOVE them — which is LilyPond's `#1`.
  final ottavaOpen = {
    for (final o in score.ottavas) o.startId: o.down ? 1 : -1
  };
  final ottavaClose = {for (final o in score.ottavas) o.endId};
  final trillOpen = {for (final t in score.trillExtensions) t.startId};
  final trillClose = {for (final t in score.trillExtensions) t.endId};
  final lvIds = {for (final l in score.laissezVibrer) l.noteId};
  final marks = _Marks(
    dynamics: dynamics,
    hairpinOpen: hairpinOpen,
    hairpinClose: hairpinClose,
    annotations: annotations,
    glissStarts: glissStarts,
    pedalOn: pedalOn,
    pedalOff: pedalOff,
    ottavaOpen: ottavaOpen,
    ottavaClose: ottavaClose,
    trillOpen: trillOpen,
    trillClose: trillClose,
    lvIds: lvIds,
  );
  final name = nameOverride ?? score.metadata.instrument;
  final staffWith =
      name == null ? '' : ' \\with { instrumentName = ${_lyString(name)} }';

  final body = StringBuffer();
  body.write('    ${_clef(score.clef)} ${_key(score.keySignature)} ');
  if (score.timeSignature != null) {
    body.write('${_time(score.timeSignature!)} ');
  }
  if (score.tempo != null) {
    final t = score.tempo!;
    // ALWAYS an integer. `\tempo 4 = 91.99980000000001` is not a tempo LilyPond
    // renders imprecisely — it is a SYNTAX ERROR ("unexpected REAL") and the
    // whole file fails to compile, so a score with a fractional tempo produced
    // a `.ly` nobody could open. A MuseScore tempo of 1.5333 quarters/second
    // arrives here as 91.9998 and is plainly meant to be 92.
    //
    // Our own reader parses the float happily, which is why no round trip ever
    // saw this; LilyPond itself rejecting the file is what surfaced it.
    // Rounding loses at most half a beat per minute, and an uncompilable file
    // loses everything.
    final bpm = t.bpm.round().toString();
    body.write('\\tempo ${_durValues[t.beatUnit]}${'.' * t.dots} = $bpm ');
  }

  // A repeat opening the very first bar has no preceding barline to ride on.
  if (score.measures.isNotEmpty && score.measures.first.startRepeat) {
    body.write('\\bar ".|:" ');
  }
  for (var m = 0; m < score.measures.length; m++) {
    final measure = score.measures[m];
    if (m > 0) {
      if (measure.clefChange != null) {
        body.write('${_clef(measure.clefChange!)} ');
      }
      if (measure.keyChange != null) body.write('${_key(measure.keyChange!)} ');
      if (measure.timeChange != null) {
        body.write('${_time(measure.timeChange!)} ');
      }
    }
    if (measure.pickup) {
      final dur = _durationOf(measure.totalDuration);
      if (dur != null) body.write('\\partial $dur ');
    }
    // A mid-score tempo change. The reader has read these since `b65f7d0`;
    // the writer emitted only the score's INITIAL tempo, so every later
    // marking was dropped on export.
    final tc = measure.tempoChange;
    if (tc != null) {
      body.write('\\tempo ${_durValues[tc.beatUnit]}${'.' * tc.dots} '
          '= ${tc.bpm.round()} ');
    }
    // Voices 2–4 (any non-empty) become parallel `<< {v1} \\ {v2} \\ … >>`
    // voices, each carrying its own tuplets (voiceAt index: voice2→1 … voice4→3).
    //
    // A `\\` branch is POSITIONAL, so an empty voice cannot simply be skipped:
    // dropping it moves every later voice up a slot, and a staff whose voice 2
    // is empty has its voice 3 read back as voice 2. Empty slots are written out
    // as `{ }` up to the last voice that HAS content — trailing ones would
    // invent voices the score does not have.
    final all = [
      (1, measure.voice2),
      (2, measure.voice3),
      (3, measure.voice4),
    ];
    var lastUsed = -1;
    for (var i = 0; i < all.length; i++) {
      if (all[i].$2.isNotEmpty) lastUsed = i;
    }
    final extra = <(int, List<MusicElement>)>[
      for (var i = 0; i <= lastUsed; i++) all[i],
    ];
    if (extra.isEmpty) {
      body.write(
          '${_elements(measure.elements, slurStarts, slurEnds, measure.tupletsForVoice(0), marks, inlineClefs: measure.inlineClefs)} ');
    } else {
      // Voice 1 gets ITS OWN spans, not every span in the measure. Passing
      // `measure.tuplets` here applied voice-2/3/4 spans to voice-1's element
      // indices: the wrong notes were wrapped in `\tuplet`, and because such a
      // span's endIndex is usually out of range for voice 1 the closing brace
      // was never emitted at all, producing malformed nesting that no longer
      // round-tripped.
      final voices = <String>[
        '{ ${_elements(measure.elements, slurStarts, slurEnds, measure.tupletsForVoice(0), marks, inlineClefs: measure.inlineClefs)} }',
        for (final (vi, v) in extra)
          '{ ${_elements(v, slurStarts, slurEnds, measure.tupletsForVoice(vi), marks)} }',
      ];
      body.write('<< ${voices.join(' \\\\ ')} >> ');
    }
    // A barcheck after EVERY measure, not just after a voice split. The reader
    // closes a bar either when it fills or on an explicit `|`, so without one
    // any measure that is not exactly full merges into the next: Brahms'
    // Schicksalslied is full of short bars and lost 61 of them on a round trip
    // through our own writer. It is also what LilyPond wants — it validates the
    // mark against its own bar counting.
    // The barline STYLE precedes the barcheck: `\bar "||" |`. LilyPond applies
    // a `\bar` to the bar line that follows it.
    //
    // Repeats ride the SAME `\bar`, and they win the slot over the style — the
    // writer emitted no repeat structure at all before this, so every
    // `startRepeat`/`endRepeat` was lost on export while the reader happily
    // read `\repeat volta`. A repeat that ENDS here and one that STARTS the
    // next bar combine into a single `:|.|:`.
    final endsRepeat = measure.endRepeat;
    final startsNext =
        m + 1 < score.measures.length && score.measures[m + 1].startRepeat;
    final bar = endsRepeat && startsNext
        ? ':|.|:'
        : endsRepeat
            ? ':|.'
            : startsNext
                ? '.|:'
                : _lyBarline[measure.barline];
    if (bar != null) body.write('\\bar "$bar" ');
    body.write('| ');
  }

  return '  \\new Staff$staffWith {\n${body.toString().trimRight()}\n  }';
}

/// A [multiPart] score → a LilyPond document whose `\score` holds a
/// `\new StaffGroup << … >>` with one `\new Staff` per part — so a full/
/// orchestral score typesets every instrument (unlike [scoreToLilyPond], which
/// writes one staff). Each part keeps its own clef/key/instrument name; header
/// metadata comes from the first part. [partNames] override the instrument
/// labels.
String multiPartToLilyPond(MultiPartScore multiPart,
    {List<String>? partNames}) {
  final parts = multiPart.parts;
  if (parts.isEmpty) {
    return scoreToLilyPond(Score(clef: Clef.treble, measures: const []));
  }
  if (parts.length == 1 && partNames == null) {
    return scoreToLilyPond(parts.first);
  }

  final meta = parts.first.metadata;
  final out = StringBuffer()..writeln('\\version "$_lilyVersion"');
  final header = [
    for (final (field, value) in [
      ('title', meta.title),
      ('composer', meta.composer),
      ('poet', meta.lyricist),
      ('copyright', meta.copyright),
    ])
      if (value != null) '  $field = ${_lyString(value)}',
  ];
  if (header.isNotEmpty) {
    out.writeln('\\header {\n${header.join('\n')}\n}');
  }
  out
    ..writeln('\\score {')
    ..writeln('  \\new StaffGroup <<');
  for (var p = 0; p < parts.length; p++) {
    final name = (partNames != null && p < partNames.length)
        ? partNames[p]
        : parts[p].metadata.instrument;

    final staffStr = _staffBlock(parts[p], nameOverride: name);
    if (parts[p].lyrics.isEmpty) {
      out.writeln(staffStr.split('\n').map((l) => '  $l').join('\n'));
    } else {
      out.writeln('  <<');
      out.writeln(staffStr.split('\n').map((l) => '    $l').join('\n'));
      out.writeln(
          _lyricsBlocks(parts[p]).split('\n').map((l) => '  $l').join('\n'));
      out.writeln('  >>');
    }
  }
  out
    ..writeln('  >>')
    ..writeln('  \\layout { }')
    ..writeln('}');
  return out.toString();
}

/// A LilyPond double-quoted string literal (backslashes and quotes escaped).
String _lyString(String text) =>
    '"${text.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

String _clef(Clef clef) => '\\clef ${_clefNames[clef]}';

String _key(KeySignature key) => '\\key ${_keyTonics[key.fifths]} \\major';

String _time(TimeSignature time) {
  // 4/4 and 2/2 render as C / cut-C by LilyPond default; force numerals
  // otherwise so a numeric 4/4 doesn't come out as the C symbol.
  //
  // ⚠️ Both directions must be EXPLICIT, because `\numericTimeSignature` is
  // sticky: a numeric section followed by a common-time one would keep drawing
  // numerals if the second said nothing.
  final numeric = time.symbol == TimeSymbol.numeric
      ? '\\numericTimeSignature '
      : '\\defaultTimeSignature ';
  final beats = time.components?.reduce((a, b) => a + b) ?? time.beats;
  return '$numeric\\time $beats/${time.beatUnit}';
}

/// The id-keyed marks a note may carry beyond its own fields.
class _Marks {
  /// ⚠️ NAMED, deliberately. Half of these are `Set<String>` and they come in
  /// same-typed PAIRS — `pedalOn`/`pedalOff`, `trillOpen`/`trillClose`,
  /// `ottavaOpen`/`ottavaClose`. Positionally, transposing a pair compiles
  /// cleanly and silently swaps the two ends of every span.
  const _Marks({
    required this.dynamics,
    required this.hairpinOpen,
    required this.hairpinClose,
    required this.annotations,
    required this.glissStarts,
    required this.pedalOn,
    required this.pedalOff,
    required this.ottavaOpen,
    required this.ottavaClose,
    required this.trillOpen,
    required this.trillClose,
    required this.lvIds,
  });
  final Map<String, DynamicLevel> dynamics;
  final Map<String, HairpinType> hairpinOpen;
  final Set<String> hairpinClose;
  final Map<String, (String, bool)> annotations;

  /// Notes a glissando starts FROM. LilyPond marks only the departure note —
  /// `c4\glissando d4` — because the line always runs to the next one.
  final Set<String> glissStarts;

  /// Pedal down / up, written `c4\sustainOn` and `c4\sustainOff`.
  final Set<String> pedalOn;
  final Set<String> pedalOff;

  /// `\ottava #N` by the note the span starts on, and the notes it ends on.
  ///
  /// ⚠️ Unlike every other mark here, the OPENING one is a PREFIX: `\ottava #1`
  /// applies from the note that FOLLOWS it, so appending it after the start
  /// note would shift the whole bracket one note late. The closing `\ottava #0`
  /// is an ordinary suffix.
  final Map<String, int> ottavaOpen;
  final Set<String> ottavaClose;

  /// Extended trills: `c4\startTrillSpan … d4\stopTrillSpan`.
  final Set<String> trillOpen;
  final Set<String> trillClose;

  /// Let-ring: `c4\laissezVibrer`.
  final Set<String> lvIds;

  /// What goes BEFORE the note rather than after it.
  String prefixFor(String? id) => id != null && ottavaOpen.containsKey(id)
      ? '\\ottava #${ottavaOpen[id]} '
      : '';

  /// LilyPond writes these AFTER the note: `c4\p`, `c4\<`, `c4\!`.
  String forId(String? id) {
    if (id == null) return '';
    final buf = StringBuffer();
    if (dynamics[id] case final level?) buf.write('\\${level.name}');
    // ⚠️ CLOSE BEFORE OPEN. `\!` terminates the hairpin currently running, so
    // on a note that ends one and starts the next — ordinary in a phrase
    // shaped `<` then `>` — emitting `\>\!` opened a new hairpin and killed it
    // on the spot, while the one that should have ended there was left
    // dangling and lost. `\!\>` says what is meant.
    if (hairpinClose.contains(id)) buf.write(r'\!');
    if (hairpinOpen[id] case final type?) {
      buf.write(type == HairpinType.crescendo ? r'\<' : r'\>');
    }
    if (glissStarts.contains(id)) buf.write(r'\glissando');
    if (pedalOn.contains(id)) buf.write(r'\sustainOn');
    if (pedalOff.contains(id)) buf.write(r'\sustainOff');
    if (ottavaClose.contains(id)) buf.write(r' \ottava #0');
    if (trillOpen.contains(id)) buf.write(r'\startTrillSpan');
    if (trillClose.contains(id)) buf.write(r'\stopTrillSpan');
    if (lvIds.contains(id)) buf.write(r'\laissezVibrer');
    if (annotations[id] case (final text, final below)) {
      // A `"` inside the mark would close the string early, the same trap as
      // the ABC annotation delimiter.
      final safe = text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      buf.write('${below ? '_' : '^'}"$safe"');
    }
    return buf.toString();
  }
}

String _elements(List<MusicElement> elements, Set<String> slurStarts,
    Set<String> slurEnds, List<TupletSpan> tuplets, _Marks marks,
    {List<InlineClefChange> inlineClefs = const []}) {
  final parts = <String>[];
  // A MID-BAR clef is a `\clef` between notes at its own onset; emitting it at
  // the barline re-clefs every note before it.
  var at = Fraction.zero;
  for (var i = 0; i < elements.length; i++) {
    for (final ic in inlineClefs) {
      if (ic.onset == at) parts.add(_clef(ic.clef));
    }
    at = at + elements[i].duration.toFraction();
    for (final t in tuplets) {
      if (t.startIndex == i) parts.add('\\tuplet ${t.actual}/${t.normal} {');
    }
    parts.add(_element(elements[i], slurStarts, slurEnds, marks));
    for (final t in tuplets) {
      if (t.endIndex == i) parts.add('}');
    }
  }
  return parts.join(' ');
}

String _element(MusicElement element, Set<String> slurStarts,
    Set<String> slurEnds, _Marks marks) {
  // LilyPond slurs are `(`/`)` appended after the note: `c4( d e f)`.
  final id = element.id;
  // ⚠️ CLOSE BEFORE OPEN, exactly as for hairpins. A note that ends one slur
  // and starts the next is `e)(` — writing `()` opens a slur and closes it on
  // the spot while the one that should have ended there dangles and is lost.
  final slur = (id != null && slurEnds.contains(id) ? ')' : '') +
      (id != null && slurStarts.contains(id) ? '(' : '');
  final extra = marks.forId(id);
  final pre = marks.prefixFor(id);
  if (element is RestElement) {
    return '$pre' 'r${_dur(element.duration)}$slur$extra';
  }
  final note = element as NoteElement;
  final tie = note.tieToNext ? '~' : '';
  // ⚠️ A note that STARTS a trill extension must not also emit `\trill`:
  // `\startTrillSpan` already draws the "tr" and the wavy line, so both would
  // print the sign twice. An extended trill is the span alone — the same
  // convention the MusicXML and MEI readers apply.
  final ornament =
      id != null && marks.trillOpen.contains(id) ? null : note.ornament;
  final noteMarks = '${_artic(note.articulations)}${_ornament(ornament)}'
      '${note.fingerings.map((f) => '-$f').join()}'
      // `\arpeggio` follows the chord; the arrow direction is a context
      // property set just before it.
      '${note.arpeggio == null ? '' : '\\arpeggio'}';
  // A tremolo is a duration SUFFIX in LilyPond (`c4:32`), not a script: the
  // number is the subdivision it is beamed at, which is 2^(2+slashes).
  final trem = note.tremolo == null ? '' : ':${4 << note.tremolo!}';
  // The notehead style is a `\tweak` PREFIX on the note.
  final headTweak = _lyHead[note.notehead] == null
      ? ''
      : "\\tweak NoteHead.style #'${_lyHead[note.notehead]} ";
  final arpDir = note.arpeggio == null
      ? ''
      : (note.arpeggio == Arpeggio.down
          ? '\\arpeggioArrowDown '
          : '\\arpeggioArrowUp ');
  // Grace notes prefix the principal: `\acciaccatura`/`\appoggiatura` for one,
  // `\grace { … }` for several (LilyPond has no multi-note slashed grace).
  final grace = note.graceNotes.isEmpty ? '' : _grace(note);
  // `!` forces the accidental to print. It belongs between the octave marks
  // and the duration.
  final forced = note.showAccidental == true ? '!' : '';
  if (note.pitches.length == 1) {
    return '$pre$arpDir$headTweak$grace${_pitch(note.pitches.single)}$forced'
        '${_dur(note.duration)}$trem$noteMarks$tie$slur$extra';
  }
  final inner = note.pitches.map((p) => '${_pitch(p)}$forced').join(' ');
  return '$pre$arpDir$headTweak$grace<$inner>${_dur(note.duration)}$trem'
      '$noteMarks$tie$slur$extra';
}

/// The LilyPond grace-note prefix for [note], written as small eighths.
String _grace(NoteElement note) {
  final notes = note.graceNotes.map((p) => '${_pitch(p)}8').join(' ');
  if (note.graceNotes.length == 1) {
    final cmd = note.graceStyle == GraceStyle.appoggiatura
        ? '\\appoggiatura'
        : '\\acciaccatura';
    return '$cmd $notes ';
  }
  return '\\grace { $notes } ';
}

/// LilyPond ornament script appended to a note.
String _ornament(Ornament? ornament) => switch (ornament) {
      Ornament.trill => '\\trill',
      Ornament.shortTrill => '\\prall',
      Ornament.mordent => '\\mordent',
      Ornament.turn => '\\turn',
      Ornament.invertedTurn => '\\reverseturn',
      // LilyPond has no built-in trill-with-accidental; fall back to a trill.
      Ornament.trillSharp ||
      Ornament.trillFlat ||
      Ornament.trillNatural =>
        '\\trill',
      null => '',
    };

/// LilyPond articulation scripts appended to a note.
String _artic(Set<Articulation> a) {
  final b = StringBuffer();
  if (a.contains(Articulation.staccato)) b.write('-.');
  if (a.contains(Articulation.tenuto)) b.write('--');
  if (a.contains(Articulation.accent)) b.write('->');
  if (a.contains(Articulation.marcato)) b.write('-^');
  if (a.contains(Articulation.fermata)) b.write('\\fermata');
  if (a.contains(Articulation.upBow)) b.write('\\upbow');
  if (a.contains(Articulation.downBow)) b.write('\\downbow');
  if (a.contains(Articulation.staccatissimo)) b.write('\\staccatissimo');
  // `\breathe` is a standalone music event, not a note script — it follows the
  // note rather than attaching to it, which is exactly where a breath belongs.
  if (a.contains(Articulation.breath)) b.write(' \\breathe');
  return b.toString();
}

String _dur(NoteDuration duration) =>
    '${_durValues[duration.base]}${'.' * duration.dots}';

String _pitch(Pitch pitch) {
  const accid = {1: 'is', 2: 'isis', -1: 'es', -2: 'eses', 0: ''};
  final marks =
      pitch.octave >= 3 ? "'" * (pitch.octave - 3) : ',' * (3 - pitch.octave);
  return '${pitch.step.name}${accid[pitch.alter]}$marks';
}

/// A whole-note fraction as a single LilyPond duration, or null if it is not
/// one plain base(+dots) value (e.g. a 5/4 pickup).
String? _durationOf(Fraction fraction) {
  for (final base in DurationBase.values) {
    final (bn, bd) = base.wholeValue;
    for (var dots = 0; dots <= 2; dots++) {
      final mulN = (1 << (dots + 1)) - 1;
      final mulD = 1 << dots;
      if (bn * mulN * fraction.denominator == fraction.numerator * bd * mulD) {
        return '${_durValues[base]}${'.' * dots}';
      }
    }
  }
  return null;
}

/// The model's barline styles in LilyPond's `\bar` vocabulary. `normal` writes
/// nothing, so an ordinary bar stays byte-identical.
const Map<BarlineStyle, String?> _lyBarline = {
  BarlineStyle.normal: null,
  BarlineStyle.doubleBar: '||',
  BarlineStyle.finalBar: '|.',
  BarlineStyle.heavy: '.',
  BarlineStyle.dashed: '!',
  BarlineStyle.dotted: ';',
  BarlineStyle.tick: "'",
  BarlineStyle.short: ',',
  BarlineStyle.reverseFinal: '.|',
  BarlineStyle.none: '',
};

/// The model's notehead shapes as LilyPond `NoteHead.style` values.
const Map<NoteheadShape, String?> _lyHead = {
  NoteheadShape.normal: null,
  NoteheadShape.x: 'cross',
  NoteheadShape.diamond: 'diamond',
  NoteheadShape.triangleUp: 'triangle',
  NoteheadShape.slash: 'slash',
  NoteheadShape.circleX: 'xcircle',
};
