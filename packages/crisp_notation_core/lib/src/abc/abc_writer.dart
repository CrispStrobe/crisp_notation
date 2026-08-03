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
import '../theory/chord_name.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/tempo.dart';
import 'abc_tempo.dart';

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
  // Fall back to the score's OWN title. The `title` parameter used to be the
  // only source, so `scoreToAbc(score)` — the ordinary call — wrote no `T:` at
  // all and every ABC export came out untitled. A self round trip lost it:
  // "001 - Antifona" -> null.
  final t = title ?? score.metadata.title;
  if (t != null && t.isNotEmpty) {
    b.writeln('T:${_oneLine(t)}');
  }
  if (score.metadata.composer case final c?) {
    if (c.isNotEmpty) {
      b.writeln('C:${_oneLine(c)}');
    }
  }
  final ts = score.timeSignature;
  // TimeSignature.toString() is C / C| / beats/beatUnit — exactly the ABC form.
  if (ts != null) b.writeln('M:$ts');
  b.writeln('L:${unit.numerator}/${unit.denominator}');
  // ABC never wrote a `Q:` at all, so every export dropped its tempo. The
  // reader ALSO files the mark as a display annotation, because nothing in the
  // layout draws `Score.tempo` — so writing both would print the metronome
  // twice. The annotation is a DERIVED artifact of the tempo, regenerated on
  // the next read, and is therefore suppressed here (see `_tempoAnnotationId`).
  final tempo = score.tempo;
  if (tempo != null) {
    b.writeln('Q:${abcTempoField(tempo, label: _tempoLabel(score, tempo))}');
  }
  // The header carries the initial clef (ABC `clef=…`); omit it for treble so a
  // plain treble tune's header is byte-unchanged. A non-treble clef was silently
  // dropped before (the reader parses it — see _parseKey).
  final headerClef =
      score.clef == Clef.treble ? '' : ' clef=${_clefName(score.clef)}';
  b.writeln('K:${_keyName(score.keySignature)}$headerClef');

  final chords = {
    for (final c in score.chordSymbols) c.elementId: chordName(c),
  };
  // ⚠️ Annotations go out through the SAME quoted syntax as chord symbols, and
  // the reader now tells them apart by the position prefix. So an annotation
  // whose text happens to read as a chord name ("Am" as a rehearsal note, say)
  // must be written prefixed, or it comes back as harmony. Everything else
  // stays bare, which keeps the output of the 99% case byte-identical.
  // ⚠️ A note may carry SEVERAL annotations, so this is a list per id. Keyed
  // as id -> String it silently kept only the last one, which a note with both
  // a tempo mark and a direction on it makes visible.
  final skipAnn = _tempoAnnotationIndex(score);
  final texts = <String, List<String>>{};
  for (var i = 0; i < score.annotations.length; i++) {
    if (i == skipAnn) continue;
    final a = score.annotations[i];
    (texts[a.elementId] ??= []).add(a.text);
  }
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
    // A `Z` REPLACES the bar's contents, so emit it only when there is nothing
    // to lose. A writer must never silently discard music it was handed, and
    // the model can be built directly by callers as well as read from a file.
    final multiRestIsEmpty =
        measure.voices.every((v) => !v.any((e) => e is NoteElement));
    if (measure.multiRest != null && multiRestIsEmpty) {
      body.write('Z${measure.multiRest} |');
      continue;
    }
    // Which element index each tuplet starts/ends at.
    // A tuplet in ABC is marked by `(p` before its first note and closes
    // implicitly after p notes, so only the start index is needed.
    // ONLY voice 1's spans. A TupletSpan addresses one voice by index, so the
    // whole list keys a voice-2 span by ITS start index and emits a spurious
    // `(3` in the middle of voice 1 — which then re-times three notes that are
    // not in any tuplet, and buries the real group that started there.
    final tupletStart = {
      for (final t in measure.tupletsForVoice(0)) t.startIndex: t
    };

    final acc = <String, int>{}; // measure accidental state, by letter
    for (var i = 0; i < measure.elements.length; i++) {
      final element = measure.elements[i];
      if (tupletStart.containsKey(i)) {
        final t = tupletStart[i]!;
        body.write(_tupletMark(t));
      }
      if (element is RestElement) {
        body.write('z${_lengthOf(element.duration, unit)}');
      } else if (element is NoteElement) {
        final id = element.id;
        if (id != null && chords.containsKey(id)) {
          body.write(_quoted(chords[id]!, isChord: true));
        }
        if (id != null) {
          for (final text in texts[id] ?? const <String>[]) {
            body.write(_quoted(text));
          }
        }
        // Grace notes live on the element itself (unlike the id-keyed chord
        // symbols / dynamics above and below), so they must NOT be gated on the
        // note having an id — that dropped grace notes from any id-less note.
        if (element.graceNotes.isNotEmpty) {
          // `{/…}` is an acciaccatura (slashed), `{…}` an appoggiatura.
          final slash =
              element.graceStyle == GraceStyle.acciaccatura ? '/' : '';
          body.write(
            '{$slash${element.graceNotes.map((g) => _bareNote(g, acc)).join()}}',
          );
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
            // ABC spells both of these as long decorations.
            Articulation.staccatissimo => '!staccatissimo!',
            Articulation.breath => '!breath!',
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
    //
    // An `&` overlay is POSITIONAL, so an empty voice cannot simply be skipped:
    // dropping it moves every later voice up a slot, and a bar whose voice 2 is
    // empty has its voice 3 read back as voice 2. Empty slots are written out
    // up to the last voice that HAS content; trailing ones would invent voices.
    final overlays = [
      (1, measure.voice2),
      (2, measure.voice3),
      (3, measure.voice4),
    ];
    var lastVoice = -1;
    for (var i = 0; i < overlays.length; i++) {
      if (overlays[i].$2.isNotEmpty) lastVoice = i;
    }
    for (var i = 0; i <= lastVoice; i++) {
      final (vi, voice) = overlays[i];
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
        // A syllable with internal whitespace uses `~` (the reader maps it
        // back). ANY whitespace, not just a space: a `w:` line ends at the
        // newline, so a syllable carrying one splits the line and everything
        // after it lands in the TUNE BODY, where it parses as notes. A corpus
        // file picked up four phantom notes from its own lyrics that way.
        // `|` advances to the next BAR in a `w:` line, so a syllable carrying
        // one is cut short there. ABC already spells a literal hyphen `\-`, so
        // the same backslash shields the other syllable-breaking characters;
        // the reader undoes it.
        // Escape the syllable-breaking characters FIRST, then turn whitespace
        // into the hard space `~` — the other way round escapes the separators
        // this very line just created.
        final text = l == null
            ? ''
            : l.text
                .replaceAllMapped(RegExp(r'[\\|*~_%-]'), (m) => '\\${m[0]}')
                // Same rule as everywhere else: a line break (CRLF included)
                // becomes ONE space because it would break the `w:` line, and
                // then each remaining space becomes one `~`. ⚠️ One `~` per
                // SPACE, not per run — the reader turns each back into a
                // single space, so collapsing here reflowed the syllable.
                .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
                .replaceAll(' ', '~');
        final syllable = l == null || text.isEmpty
            ? '*'
            : text + (l.hyphenToNext ? '-' : '');
        tokens.add(syllable);
      }
    }
    while (tokens.isNotEmpty && tokens.last == '*') {
      tokens.removeLast(); // trailing skips are noise
    }
    if (tokens.isNotEmpty) b.writeln('w:${tokens.join(' ')}');
  }
  // `W:` (uppercase) is the unaligned verse text, one line each, printed after
  // the tune. Whitespace is flattened for the same reason a `w:` syllable's is:
  // the field ends at the newline, so an embedded one would end the line and
  // drop the rest into the tune body.
  for (final line in score.metadata.words) {
    // A BLANK `W:` is kept: it separates stanzas, so dropping it silently
    // reflows a four-verse hymn into one block. Only the whitespace inside a
    // line is flattened, for the reason above.
    b.writeln('W:${_oneLine(line)}');
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
      body.write(_tupletMark(t));
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
/// (for grace notes).
///
/// Each grace carries an EXPLICIT accidental — including a natural (`=`) — so
/// it does not inherit a preceding one. It must also RECORD itself in [acc]:
/// ABC keeps an accidental in force for the rest of the measure and a grace
/// note is a note, so `{/^C}E … C` sounds the plain `C` as C sharp. Leaving
/// [acc] untouched meant the writer thought the C was still natural and emitted
/// no natural sign, so the pitch changed on read-back.
String _bareNote(Pitch pitch, Map<String, int> acc) {
  final prefix = switch (pitch.alter) {
    2 => '^^',
    1 => '^',
    0 => '=',
    -1 => '_',
    _ => '__',
  };
  acc['${_letter(pitch.step)}${pitch.octave}'] = pitch.alter;
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

/// A quoted ABC string (chord symbol or annotation) with its content escaped.
///
/// The delimiter is `"`, so a text carrying one closes the string early and the
/// words after it land bare in the tune body, where every a-g letter reads as a
/// NOTE. A hymn whose lyric quotes speech gained six phantom notes that way.
/// A newline would end the tune line outright.
/// The INDEX of the annotation the reader derived from this score's `Q:`, if
/// any — the one the header now carries instead.
///
/// An index, not an element id: a note routinely carries the tempo mark AND a
/// real direction, and skipping by id would drop both.
///
/// Matched on the rendering rather than on position: the tempo annotation is
/// exactly `abcTempoDisplay` of the score's own tempo, optionally prefixed by a
/// text label the model cannot hold. Anything else that merely sits on the
/// first note is a real annotation and stays.
int? _tempoAnnotationIndex(Score score) {
  final tempo = score.tempo;
  if (tempo == null) return null;
  final bare = abcTempoDisplay(tempo);
  for (var i = 0; i < score.annotations.length; i++) {
    final t = score.annotations[i].text;
    if (t == bare || t.endsWith(' $bare')) return i;
  }
  return null;
}

/// The text label on that annotation, if it carried one ("Allegro ♩ = 120").
String? _tempoLabel(Score score, Tempo tempo) {
  final bare = abcTempoDisplay(tempo);
  for (final a in score.annotations) {
    if (a.text.endsWith(' $bare')) {
      return a.text.substring(0, a.text.length - bare.length - 1);
    }
  }
  return null;
}

/// Flattens a value onto ONE line, without touching its spacing.
///
/// ⚠️ Only what would BREAK the format: an ABC field ends at a newline. A run
/// of ordinary SPACES is content — hymn and psalm texts use them for alignment
/// — and collapsing it corrupted every such third-party title and lyric line.
String _oneLine(String value) =>
    value.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();

String _quoted(String text, {bool isChord = false}) {
  // Only what would BREAK the format: a newline ends the tune line. Runs of
  // ordinary spaces are content and collapsing them corrupted hymn texts.
  final flat = text.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
  final escaped = flat
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      // `%` starts a comment in ABC, and comment-stripping runs BEFORE the tune
      // body is parsed — so it must be escaped even inside a quoted string.
      .replaceAll('%', r'\%');
  // Two reasons a text needs an explicit `^` (above) in front of it, and both
  // are the same concern: making the reader route the string back into the
  // channel it came from.
  //
  //  - A leading `^ _ < > @` is ABC's POSITION marker, which the reader
  //    strips, so a text genuinely starting with one loses that character.
  //  - An UNPREFIXED string is a chord symbol by ABC's own rule, so an
  //    annotation whose text happens to read as a chord name ("Eb" as a
  //    rehearsal note) would come back as harmony.
  //
  // A real chord symbol never needs either: it BELONGS in the bare channel.
  // Only texts that need it are shielded, so every ordinary chord symbol —
  // and every annotation that reads as prose — is written exactly as before.
  final needsShield = !isChord &&
      escaped.isNotEmpty &&
      ('^_<>@'.contains(escaped[0]) || parseChordName(escaped) != null);
  return '"${needsShield ? '^' : ''}$escaped"';
}

/// The ABC tuplet mark opening [t].
///
/// `(p` does NOT mean "p notes in the time of p−1". ABC gives each p a DEFAULT
/// q, and it is 2 for every p except 2, 4 and 8, which default to 3. Writing the
/// bare form for any other ratio silently re-times the group: a 5:4 quintuplet
/// read back under the default 5:2 sounds twice as fast, and every ratio in the
/// corpus except 3:2 and 6:4 was being written that way. The explicit `(p:q:r`
/// form is used whenever q is not p's default.
///
/// 5, 7 and 9 always take the explicit form even when q happens to match: the
/// standard makes their default depend on whether the METER is compound, so the
/// bare mark is not portable — a reader in 6/8 would give them q=3.
///
/// The bare form also implies r = p, i.e. that the group spans exactly p
/// written notes. It often does not: tie two members of a triplet together and
/// the span covers 2 elements while p stays 3. Left bare, the reader swallows
/// whatever follows to make up the count, which then loses the NEXT tuplet in
/// the bar — so r is stated whenever it differs from p.
String _tupletMark(TupletSpan t) {
  final count = t.endIndex - t.startIndex + 1;
  final defaultQ = switch (t.actual) {
    2 || 4 || 8 => 3,
    3 || 6 => 2,
    _ => null,
  };
  if (defaultQ != null && t.normal == defaultQ && count == t.actual) {
    return '(${t.actual}';
  }
  return '(${t.actual}:${t.normal}:$count';
}

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
  final (bn, bd) = duration.base.wholeValue;
  final base = Fraction(bn, bd);
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
