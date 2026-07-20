/// ABC notation export.
///
/// Serializes a [Score] to an ABC tune string — the inverse of
/// [scoreFromAbc]. Emits the `M`/`L`/`K` header then a body with pitched notes
/// (accidental, octave marks, `L`-relative length), rests, chords, ties,
/// tuplets, slurs, grace notes, staccato, `"C"` chord symbols and bar lines
/// (repeats, double/final). A single lyric verse is written as a `w:` line.
/// Because both codecs funnel through the one [Score] model, a score
/// round-trips through ABC for the data ABC can represent.
library;

import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';

/// Serializes [score] to an ABC tune. [unitLength] is the `L:` field (default
/// 1/8); [index] is the `X:` tune number; [title] the optional `T:` field.
String scoreToAbc(
  Score score, {
  Fraction? unitLength,
  int index = 1,
  String? title,
}) {
  final unit = unitLength ?? Fraction(1, 8);
  final b = StringBuffer();
  b.writeln('X:$index');
  if (title != null) b.writeln('T:$title');
  final ts = score.timeSignature;
  // TimeSignature.toString() is C / C| / beats/beatUnit — exactly the ABC form.
  if (ts != null) b.writeln('M:$ts');
  b.writeln('L:${unit.numerator}/${unit.denominator}');
  // The header carries the initial clef (ABC `clef=…`); omit it for treble so a
  // plain treble tune's header is byte-unchanged. A non-treble clef was silently
  // dropped before (the reader parses it — see _parseKey).
  final headerClef =
      score.clef == Clef.treble ? '' : ' clef=${_clefName(score.clef)}';
  b.writeln('K:${_keyName(score.keySignature)}$headerClef');

  final chordSymbols = {for (final a in score.annotations) a.elementId: a.text};
  final dynamicsById = {for (final d in score.dynamics) d.elementId: d.level};
  final slurStarts = <String, int>{};
  final slurEnds = <String, int>{};
  for (final s in score.slurs) {
    slurStarts[s.startId] = (slurStarts[s.startId] ?? 0) + 1;
    slurEnds[s.endId] = (slurEnds[s.endId] ?? 0) + 1;
  }

  final body = StringBuffer();
  // The key in force, updated by mid-tune `[K:…]` changes. Accidentals are
  // written relative to *this* key, not the initial one — otherwise, after a
  // key change, a note the new key alters (e.g. E under 2 flats) would be
  // written bare and read back a semitone off.
  var currentKey = score.keySignature;
  for (var m = 0; m < score.measures.length; m++) {
    final measure = score.measures[m];
    if (measure.startRepeat) body.write('|:');
    if (measure.volta != null) body.write('[${measure.volta}');
    if (measure.navigation != null) {
      body.write(switch (measure.navigation!) {
        NavigationMark.segno => '!segno!',
        NavigationMark.coda => '!coda!',
        NavigationMark.toCoda => '!dacoda!',
        NavigationMark.daCapo => '!D.C.!',
        NavigationMark.daCapoAlFine => '!D.C.alfine!',
        NavigationMark.daCapoAlCoda => '!D.C.alcoda!',
        NavigationMark.dalSegno => '!D.S.!',
        NavigationMark.dalSegnoAlFine => '!D.S.alfine!',
        NavigationMark.dalSegnoAlCoda => '!D.S.alcoda!',
        NavigationMark.fine => '!fine!',
      });
    }
    // Mid-tune key / meter / unit changes, and multi-measure rests.
    // A mid-tune key and/or clef change share one `[K:…]` field. The key name
    // is always written (the reader needs a tonic to anchor `clef=…`, else a
    // bare `[K:clef=bass]` misreads "clef" as the tonic C); a clef-only change
    // re-states the running key, which the reader treats as no key change.
    if (measure.keyChange != null || measure.clefChange != null) {
      final keyName = _keyName(measure.keyChange ?? currentKey);
      final clef = measure.clefChange != null
          ? ' clef=${_clefName(measure.clefChange!)}'
          : '';
      body.write('[K:$keyName$clef]');
      if (measure.keyChange != null) currentKey = measure.keyChange!;
    }
    if (measure.timeChange != null) {
      body.write('[M:${measure.timeChange}]');
    }
    if (measure.multiRest != null) {
      body.write('Z${measure.multiRest} |');
      continue;
    }
    // Which element index each tuplet starts/ends at.
    // A tuplet in ABC is marked by `(p` before its first note and closes
    // implicitly after p notes, so only the start index is needed.
    final tupletStart = {for (final t in measure.tuplets) t.startIndex: t};

    final acc = <String, int>{}; // measure accidental state, by letter
    for (var i = 0; i < measure.elements.length; i++) {
      final element = measure.elements[i];
      if (tupletStart.containsKey(i)) {
        final t = tupletStart[i]!;
        body.write(t.actual == 3 && t.normal == 2 ? '(3' : '(${t.actual}');
      }
      if (element is RestElement) {
        body.write('z${_lengthOf(element.duration, unit)}');
      } else if (element is NoteElement) {
        final id = element.id;
        if (id != null && chordSymbols.containsKey(id)) {
          body.write('"${chordSymbols[id]}"');
        }
        // Grace notes live on the element itself (unlike the id-keyed chord
        // symbols / dynamics above and below), so they must NOT be gated on the
        // note having an id — that dropped grace notes from any id-less note.
        if (element.graceNotes.isNotEmpty) {
          // `{/…}` is an acciaccatura (slashed), `{…}` an appoggiatura.
          final slash =
              element.graceStyle == GraceStyle.acciaccatura ? '/' : '';
          body.write('{$slash${element.graceNotes.map(_bareNote).join()}}');
        }
        if (id != null && dynamicsById.containsKey(id)) {
          body.write('!${dynamicsById[id]!.name}!');
        }
        // Decorations: `.` for staccato, `!…!` for the rest and ornaments.
        for (final a in element.articulations) {
          body.write(switch (a) {
            Articulation.staccato => '.',
            Articulation.accent => '!accent!',
            Articulation.tenuto => '!tenuto!',
            Articulation.marcato => '!marcato!',
            Articulation.fermata => '!fermata!',
            Articulation.upBow => 'u',
            Articulation.downBow => 'v',
          });
        }
        final orn = switch (element.ornament) {
          Ornament.trill => '!trill!',
          Ornament.shortTrill => '!uppermordent!',
          Ornament.mordent => '!lowermordent!',
          Ornament.turn => '!turn!',
          Ornament.invertedTurn => '!invertedturn!',
          // ABC has no trill-with-accidental sign; fall back to a plain trill.
          Ornament.trillSharp ||
          Ornament.trillFlat ||
          Ornament.trillNatural =>
            '!trill!',
          null => '',
        };
        body.write(orn);
        for (var k = 0; k < (id == null ? 0 : slurStarts[id] ?? 0); k++) {
          body.write('(');
        }
        final len = _lengthOf(element.duration, unit);
        if (element.pitches.length == 1) {
          body.write(
            '${_noteToken(element.pitches.single, acc, currentKey)}$len',
          );
        } else {
          final inner =
              element.pitches.map((p) => _noteToken(p, acc, currentKey)).join();
          body.write('[$inner]$len');
        }
        if (element.tieToNext) body.write('-');
        for (var k = 0; k < (id == null ? 0 : slurEnds[id] ?? 0); k++) {
          body.write(')');
        }
      }
      body.write(' ');
    }
    // Inner voices (stems-down voice 2, etc.) are written as ABC voice overlays:
    // `voice1 … & voice2 …` within the same bar. Each overlay carries its own
    // tuplets (voiceAt index: voice2→1 … voice4→3); slurs/lyrics stay voice 1.
    for (final (vi, voice) in [
      (1, measure.voice2),
      (2, measure.voice3),
      (3, measure.voice4),
    ]) {
      if (voice.isEmpty) continue;
      body.write('& ');
      _emitOverlayVoice(
          body, voice, unit, currentKey, measure.tupletsForVoice(vi));
    }
    if (measure.endRepeat) {
      body.write(':|');
    } else {
      body.write(switch (measure.barline) {
        BarlineStyle.doubleBar => '||',
        // `|]` (thin-thick) is valid at any position — a mid-piece final barline
        // is a real section marker, and the reader reads `|]` → finalBar
        // regardless of position, so writing plain `|` here lost the style.
        BarlineStyle.finalBar => '|]',
        BarlineStyle.dotted => '.|',
        _ => '|',
      });
    }
    // Wrap bodies at a sensible width by breaking every 4 bars.
    if ((m + 1) % 4 == 0) body.write('\n');
  }
  b.writeln(body.toString().trimRight());

  // Align w: syllables to the NOTES by id (rests carry none), emitting `*` for
  // an unsung note. The previous positional join of only the present lyrics
  // shifted every syllable after a gap onto the wrong note on reopen (a lyric on
  // notes 1 and 3 wrote `w:la la`, which the reader aligned to notes 1 and 2).
  final byId = {
    for (final l in score.lyrics)
      if (l.verse == 1) l.elementId: l,
  };
  if (byId.isNotEmpty) {
    final tokens = <String>[];
    for (final m in score.measures) {
      for (final e in m.elements) {
        if (e is! NoteElement) continue; // rests take no syllable
        final l = e.id == null ? null : byId[e.id];
        // A syllable with an internal space uses `~` (the reader maps it back).
        final syllable = l == null
            ? '*'
            : l.text.replaceAll(' ', '~') + (l.hyphenToNext ? '-' : '');
        tokens.add(syllable);
      }
    }
    while (tokens.isNotEmpty && tokens.last == '*') {
      tokens.removeLast(); // trailing skips are noise
    }
    if (tokens.isNotEmpty) b.writeln('w:${tokens.join(' ')}');
  }
  return b.toString();
}

/// Emits an overlay voice's notes/chords/rests (with durations, ties and
/// tuplets) into [body] — the part after an `&` in a bar. Slurs, lyrics and
/// chord symbols still ride voice 1, so this stays compact.
void _emitOverlayVoice(
  StringBuffer body,
  List<MusicElement> elements,
  Fraction unit,
  KeySignature key,
  List<TupletSpan> tuplets,
) {
  final acc = <String, int>{}; // fresh accidental state for this overlay voice
  final tupletStart = {for (final t in tuplets) t.startIndex: t};
  for (var i = 0; i < elements.length; i++) {
    final element = elements[i];
    if (tupletStart.containsKey(i)) {
      final t = tupletStart[i]!;
      body.write(t.actual == 3 && t.normal == 2 ? '(3' : '(${t.actual}');
    }
    if (element is RestElement) {
      body.write('z${_lengthOf(element.duration, unit)}');
    } else if (element is NoteElement) {
      final len = _lengthOf(element.duration, unit);
      if (element.pitches.length == 1) {
        body.write('${_noteToken(element.pitches.single, acc, key)}$len');
      } else {
        final inner =
            element.pitches.map((p) => _noteToken(p, acc, key)).join();
        body.write('[$inner]$len');
      }
      if (element.tieToNext) body.write('-');
    }
    body.write(' ');
  }
}

/// The ABC token for [pitch] — octave letter with an explicit accidental only
/// when it differs from the running accidental ([acc], keyed per pitch+octave to
/// match the reader) or the [key].
String _noteToken(Pitch pitch, Map<String, int> acc, KeySignature key) {
  final letter = _letter(pitch.step);
  final keyAlter =
      key.alteredSteps.contains(pitch.step) ? (key.fifths >= 0 ? 1 : -1) : 0;
  // The running accidental carries only to the same pitch in the same octave
  // (ABC 2.1); the key signature still applies per letter.
  final accKey = '$letter${pitch.octave}';
  final effective = acc[accKey] ?? keyAlter;
  var prefix = '';
  if (pitch.alter != effective) {
    prefix = switch (pitch.alter) {
      2 => '^^',
      1 => '^',
      0 => '=',
      -1 => '_',
      _ => '__',
    };
    acc[accKey] = pitch.alter;
  }
  return '$prefix${_octaveLetter(pitch)}';
}

/// The pitch as a bare octave letter with an always-explicit accidental
/// (for grace notes, where measure state is not tracked).
// Grace notes are written without measure accidental tracking, so each one
// carries an **explicit** accidental — including a natural (`=`) — otherwise a
// natural grace note inherits a preceding grace note's accidental (ABC keeps an
// accidental in force for the rest of the measure).
String _bareNote(Pitch pitch) {
  final prefix = switch (pitch.alter) {
    2 => '^^',
    1 => '^',
    0 => '=',
    -1 => '_',
    _ => '__',
  };
  return '$prefix${_octaveLetter(pitch)}';
}

String _octaveLetter(Pitch pitch) {
  final letter = _letter(pitch.step);
  if (pitch.octave >= 5) {
    return letter.toLowerCase() + "'" * (pitch.octave - 5);
  }
  return letter + ',' * (4 - pitch.octave);
}

String _letter(Step step) => switch (step) {
      Step.c => 'C',
      Step.d => 'D',
      Step.e => 'E',
      Step.f => 'F',
      Step.g => 'G',
      Step.a => 'A',
      Step.b => 'B',
    };

/// The ABC length suffix for [duration] relative to the [unit] note length.
String _lengthOf(NoteDuration duration, Fraction unit) {
  final whole = _wholeFraction(duration);
  final mult = whole * Fraction(unit.denominator, unit.numerator);
  final n = mult.numerator, d = mult.denominator;
  if (n == 1 && d == 1) return '';
  if (d == 1) return '$n';
  if (n == 1) return '/$d';
  return '$n/$d';
}

Fraction _wholeFraction(NoteDuration duration) {
  final base = switch (duration.base) {
    DurationBase.breve => Fraction(2, 1),
    DurationBase.whole => Fraction(1, 1),
    DurationBase.half => Fraction(1, 2),
    DurationBase.quarter => Fraction(1, 4),
    DurationBase.eighth => Fraction(1, 8),
    DurationBase.sixteenth => Fraction(1, 16),
    DurationBase.thirtySecond => Fraction(1, 32),
    DurationBase.sixtyFourth => Fraction(1, 64),
  };
  // Dots: 1 → ×3/2, 2 → ×7/4.
  final dotMul = switch (duration.dots) {
    1 => Fraction(3, 2),
    2 => Fraction(7, 4),
    _ => Fraction(1, 1),
  };
  return base * dotMul;
}

const _fifthsToKey = {
  0: 'C', 1: 'G', 2: 'D', 3: 'A', 4: 'E', 5: 'B', 6: 'F#', 7: 'C#', //
  -1: 'F', -2: 'Bb', -3: 'Eb', -4: 'Ab', -5: 'Db', -6: 'Gb', -7: 'Cb',
};

String _keyName(KeySignature key) => _fifthsToKey[key.fifths] ?? 'C';

/// The ABC `clef=` token for [clef]. ABC — as this library's reader parses it —
/// represents the five common clefs (treble/bass/alto/tenor/perc); the
/// octave-displaced and rarer C/F clefs collapse to their nearest base clef on
/// round-trip.
String _clefName(Clef clef) => switch (clef) {
      Clef.treble ||
      Clef.treble8va ||
      Clef.treble8vb ||
      Clef.frenchViolin =>
        'treble',
      Clef.bass || Clef.bass8vb || Clef.subbass || Clef.baritone => 'bass',
      Clef.alto || Clef.soprano || Clef.mezzoSoprano => 'alto',
      Clef.tenor => 'tenor',
      Clef.percussion => 'perc',
    };
