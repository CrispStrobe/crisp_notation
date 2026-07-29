// `ScoreMetadata.extras` — per-part data this model does not name.
//
// The need behind it: applications keep settings that belong to a PART rather
// than to a project — an effect chain, a mix level — and with no slot for them
// they end up either beside the score (lost the moment the part is copied or
// exported) or smuggled into a field that means something else. `copyright` is
// the usual victim, and a score that lies about its rights is a worse outcome
// than a dropped setting.
//
// So the field is deliberately untyped and uninterpreted, and these tests pin
// the two things a free-form slot has to get right: it must not disturb a score
// that does not use it, and where it IS carried, it must survive a round trip
// intact rather than partly.

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

Score _score(ScoreMetadata metadata) => Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c4:q d4 e4 f4',
      metadata: metadata,
    );

void main() {
  const chain = 'highpass freq=120 | reverb mix=20%';

  group('a score that does not use it is unaffected', () {
    test('the default is empty, and empty metadata is still empty', () {
      const meta = ScoreMetadata();
      expect(meta.extras, isEmpty);
      expect(
        meta.isEmpty,
        isTrue,
        reason: 'a new field must not give every score a header to emit',
      );
    });

    test('a title-only score does not gain a miscellaneous block', () {
      final xml = scoreToMusicXml(_score(const ScoreMetadata(title: 'Air')));
      expect(xml, isNot(contains('miscellaneous')));
    });
  });

  group('equality', () {
    test('metadata differing only in extras is not equal', () {
      // The reason this matters: an editor comparing before/after to decide
      // whether a document is dirty would otherwise miss the change and not
      // offer to save it.
      const bare = ScoreMetadata(title: 'Air');
      const withFx = ScoreMetadata(title: 'Air', extras: {'app.fx': chain});
      expect(withFx, isNot(bare));
    });

    test('the same pairs in a different order are equal, and hash alike', () {
      const a = ScoreMetadata(extras: {'x': '1', 'y': '2'});
      const b = ScoreMetadata(extras: {'y': '2', 'x': '1'});
      expect(a, b);
      expect(
        {a, b},
        hasLength(1),
        reason: 'equal values that hash differently would both sit in a Set',
      );
    });

    test('a value change is caught', () {
      expect(
        const ScoreMetadata(extras: {'x': '1'}),
        isNot(const ScoreMetadata(extras: {'x': '2'})),
      );
    });
  });

  group('copyWith', () {
    test('it sets extras without disturbing the rest', () {
      const meta = ScoreMetadata(title: 'Air', composer: 'Bach');
      final tagged = meta.copyWith(extras: const {'app.fx': chain});
      expect(tagged.extras, {'app.fx': chain});
      expect(tagged.title, 'Air');
      expect(tagged.composer, 'Bach');
    });

    test('it carries existing extras through an unrelated change', () {
      // The silent-drop this guards: setting a title should not wipe a part's
      // effect chain. (`copy_with_test.dart` guards the same thing
      // structurally, by reading the source.)
      const meta = ScoreMetadata(extras: {'app.fx': chain});
      expect(meta.copyWith(title: 'Air').extras, {'app.fx': chain});
    });
  });

  group('MusicXML carries it — in the slot the format provides', () {
    // `<miscellaneous-field>` is MusicXML's own answer to "data this format
    // does not name", so this is not a private convention: another reader knows
    // to leave it alone, and ours knows where to look.
    test('it round-trips', () {
      final source = _score(
        const ScoreMetadata(title: 'Air', extras: {'app.fx': chain}),
      );
      final back = scoreFromMusicXml(scoreToMusicXml(source));
      expect(back.metadata.extras, {'app.fx': chain});
      expect(back.metadata.title, 'Air', reason: 'and the rest is intact');
    });

    test('several keys round-trip, and only the ones written', () {
      final source = _score(
        const ScoreMetadata(extras: {'a.one': '1', 'b.two': 'two'}),
      );
      expect(scoreFromMusicXml(scoreToMusicXml(source)).metadata.extras, {
        'a.one': '1',
        'b.two': 'two',
      });
    });

    test('extras alone are enough to emit an identification block', () {
      // They live inside `<identification>`, which the writer used to emit only
      // for a creator or a rights statement — so extras on an otherwise bare
      // score would have had nowhere to go.
      final source = _score(const ScoreMetadata(extras: {'app.fx': chain}));
      expect(scoreFromMusicXml(scoreToMusicXml(source)).metadata.extras, {
        'app.fx': chain,
      });
    });

    test('a value with XML in it survives', () {
      // A chain string is user-typed text; `<` and `&` in it must not produce a
      // document that fails to parse.
      const nasty = r'gain db=-3 & <weird> "quoted"';
      final source = _score(const ScoreMetadata(extras: {'app.fx': nasty}));
      expect(
        scoreFromMusicXml(scoreToMusicXml(source)).metadata.extras['app.fx'],
        nasty,
      );
    });

    test('a document with no miscellaneous block reads back as empty', () {
      final source = _score(const ScoreMetadata(title: 'Air'));
      expect(
          scoreFromMusicXml(scoreToMusicXml(source)).metadata.extras, isEmpty);
    });
  });

  group('in a MULTI-part score each part keeps its OWN', () {
    // The hard part of the whole feature: extras are per-PART, but MusicXML has
    // one `<identification>` for the entire document. Writing them all into it
    // unscoped would read back with every part holding every other part's
    // settings — a bass line playing the lead's effect chain.
    MultiPartScore multi() => MultiPartScore([
          _score(const ScoreMetadata(instrument: 'Lead', extras: {'fx': 'a'})),
          _score(const ScoreMetadata(instrument: 'Bass', extras: {'fx': 'b'})),
        ]);

    test('two parts round-trip with different values under one key', () {
      final back = multiPartScoreFromMusicXml(multiPartToMusicXml(multi()));
      expect(back.parts[0].metadata.extras, {'fx': 'a'});
      expect(back.parts[1].metadata.extras, {'fx': 'b'});
    });

    test('a part with none stays empty', () {
      final back = multiPartScoreFromMusicXml(
        multiPartToMusicXml(
          MultiPartScore([
            _score(const ScoreMetadata(extras: {'fx': 'a'})),
            _score(const ScoreMetadata(instrument: 'Bass')),
          ]),
        ),
      );
      expect(back.parts[1].metadata.extras, isEmpty);
    });

    test("a KEY containing a slash is not mistaken for another part's", () {
      // The scoping splits on `/`, so a key that legitimately contains one —
      // a path, a URL — must not be truncated into somebody else's namespace.
      final back = scoreFromMusicXml(
        scoreToMusicXml(
          _score(const ScoreMetadata(extras: {'app/preset': 'warm'})),
        ),
      );
      expect(back.metadata.extras, {'app/preset': 'warm'});
    });
  });

  group('⚠️ a multi-part export used to lose its whole header', () {
    // Found while adding extras, and older than them: the multi-part writer
    // passed `const ScoreMetadata()`, so a two-part save dropped the title,
    // composer, lyricist and rights statement that a one-part save kept. The
    // rest of the library takes a document-level header from the first part
    // (MEI, MuseScore, kern and LilyPond writers all do); this now matches.
    test('title, composer, lyricist and rights survive', () {
      final source = MultiPartScore([
        _score(
          const ScoreMetadata(
            title: 'Air',
            composer: 'Bach',
            lyricist: 'Anon.',
            copyright: '© Public Domain',
            instrument: 'Lead',
          ),
        ),
        _score(const ScoreMetadata(instrument: 'Bass')),
      ]);
      final head = multiPartScoreFromMusicXml(multiPartToMusicXml(source))
          .parts
          .first
          .metadata;
      expect(head.title, 'Air');
      expect(head.composer, 'Bach');
      expect(head.lyricist, 'Anon.');
      expect(head.copyright, '© Public Domain');
      expect(head.instrument, 'Lead', reason: 'and part names still work');
    });
  });

  group('every other format DROPS it, and says so here', () {
    // Stated as tests rather than left to be discovered. MusicXML is the only
    // format in this library with a slot MEANT for unnamed data; the others
    // would need a key convention invented inside a namespace that is already
    // somebody else's — Humdrum's reference records take short standard codes,
    // MuseScore's `metaTag` names are MuseScore's — and private data sitting
    // where another tool reads something else is worse than a dropped setting.
    // So it drops, exactly like any other unrepresentable detail.
    final source = _score(
      const ScoreMetadata(title: 'Air', extras: {'app.fx': chain}),
    );

    test('Humdrum kern keeps the composer but not the extras', () {
      final back = scoreFromKern(
        scoreToKern(
          _score(
            const ScoreMetadata(composer: 'Bach', extras: {'app.fx': chain}),
          ),
        ),
      );
      expect(back.metadata.composer, 'Bach');
      expect(back.metadata.extras, isEmpty);
    });

    test('MIDI keeps the title but not the extras', () {
      expect(scoreFromMidi(scoreToMidi(source)).metadata.extras, isEmpty);
    });

    test('MuseScore keeps the title but not the extras', () {
      final back = scoreFromMscx(scoreToMscx(source));
      expect(back.metadata.title, 'Air');
      expect(back.metadata.extras, isEmpty);
    });

    test('MEI keeps the title but not the extras', () {
      final back = scoreFromMei(scoreToMei(source));
      expect(back.metadata.title, 'Air');
      expect(back.metadata.extras, isEmpty);
    });
  });
}
