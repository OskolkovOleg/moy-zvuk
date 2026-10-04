import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zvuk_personal/data/library_store.dart';
import 'package:zvuk_personal/data/lyrics_translation.dart';
import 'package:zvuk_personal/data/personal_models.dart';

class TranslationMemoryStore implements LibraryStore {
  final values = <String, dynamic>{};
  bool unreadable = false;
  @override
  Future<dynamic> get(String account, String key) async {
    if (unreadable) throw StateError('Cache unavailable');
    return values['$account:$key'];
  }

  @override
  Future<void> put(String account, String key, dynamic value) async {
    values['$account:$key'] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLyricsEngine implements LyricsTranslationEngine {
  String language = 'en';
  bool fail = false, closed = false;
  int prepares = 0;
  final calls = <String>[];
  Completer<String>? identifyWait, translateWait;
  @override
  Future<String> identify(String text) async =>
      identifyWait == null ? language : await identifyWait!.future;
  @override
  Future<void> prepare(void Function() onDownloading) async {
    prepares++;
    onDownloading();
    if (fail) throw StateError('No model');
  }

  @override
  Future<String> translate(String text) async {
    calls.add(text);
    return translateWait == null
        ? 'Русский: $text'
        : await translateWait!.future;
  }

  @override
  Future<void> close() async => closed = true;
}

void main() {
  test('Provider translation aligns by boundaries and timestamps', () {
    expect(
      alignedLyricsTranslation(
        SongLyrics.parse(
          '[00:01]First\n[00:02]Second',
          translation: '[00:01]Первая\n[00:02]Вторая',
        ),
      ),
      ['Первая', 'Вторая'],
    );
    expect(
      alignedLyricsTranslation(
        SongLyrics.parse('First\n\nSecond', translation: 'Первая\n\nВторая'),
      ),
      ['Первая', '', 'Вторая'],
    );
    expect(
      alignedLyricsTranslation(
        SongLyrics.parse(
          '[00:01]First\n[00:02]Second',
          translation: '[00:01]Первая\n[00:03]Вторая',
        ),
      ),
      isNull,
    );
    expect(
      alignedLyricsTranslation(
        SongLyrics.parse('First\nSecond', translation: 'Одна строка'),
      ),
      isNull,
    );
    expect(
      alignedLyricsTranslation(
        SongLyrics.parse(
          'First\n\nSecond',
          translation: 'Первая\nВторая\nТретья',
        ),
      ),
      isNull,
    );
  });

  late TranslationMemoryStore store;
  late FakeLyricsEngine engine;
  var current = true;
  LyricsTranslationController controller({
    SongLyrics? lyrics,
    String account = 'a',
  }) => LyricsTranslationController(
    store: store,
    account: account,
    trackId: 't',
    lyrics: lyrics ?? SongLyrics.parse('Hello\n\nHello\nWorld'),
    isCurrent: () => current,
    createEngine: () => engine,
  );
  setUp(() {
    store = TranslationMemoryStore();
    engine = FakeLyricsEngine();
    current = true;
  });
  test(
    'Provider result does not invoke a model or cache another translation',
    () async {
      final c = controller(
        lyrics: SongLyrics.parse('Hello', translation: 'Привет'),
      );
      await c.start();
      expect(c.lines, ['Привет']);
      expect(c.machineTranslated, false);
      expect(engine.prepares, 0);
      expect(store.values, isEmpty);
      c.dispose();
    },
  );
  test(
    'Translates each distinct line once; keeps pauses and caches exact source',
    () async {
      final c = controller();
      await c.start();
      expect(c.phase, LyricsTranslationPhase.ready);
      expect(c.lines, [
        'Русский: Hello',
        '',
        'Русский: Hello',
        'Русский: World',
      ]);
      expect(engine.calls, ['Hello', 'World']);
      expect(engine.closed, true);
      c.dispose();
      engine = FakeLyricsEngine()..fail = true;
      final cached = controller();
      await cached.start();
      expect(cached.phase, LyricsTranslationPhase.ready);
      expect(cached.machineTranslated, true);
      expect(engine.prepares, 0);
      cached.dispose();
      final changed = controller(lyrics: SongLyrics.parse('Changed source'));
      await changed.start();
      expect(changed.phase, LyricsTranslationPhase.failed);
      changed.dispose();
    },
  );
  test(
    'Cache is account scoped; non-English lyrics do not download a model',
    () async {
      final a = controller();
      await a.start();
      a.dispose();
      engine = FakeLyricsEngine()..language = 'es';
      final b = controller(account: 'b');
      await b.start();
      expect(b.phase, LyricsTranslationPhase.unavailable);
      expect(b.lines, isNull);
      expect(engine.prepares, 0);
      expect(engine.closed, true);
      b.dispose();
    },
  );
  test(
    'A failed download can be retried; cache errors do not hide the original',
    () async {
      store.unreadable = true;
      engine.fail = true;
      final c = controller();
      await c.start();
      expect(c.phase, LyricsTranslationPhase.failed);
      expect(c.lines, isNull);
      engine = FakeLyricsEngine();
      await c.start();
      expect(c.phase, LyricsTranslationPhase.ready);
      c.dispose();
    },
  );
  test(
    'Account change while identifying cannot start a model or publish results',
    () async {
      engine.identifyWait = Completer<String>();
      final c = controller();
      final work = c.start();
      await Future<void>.delayed(Duration.zero);
      current = false;
      engine.identifyWait!.complete('en');
      await work;
      expect(engine.prepares, 0);
      expect(c.lines, isNull);
      expect(store.values, isEmpty);
      expect(engine.closed, true);
      c.dispose();
    },
  );
  test(
    'Closing lyrics while translating ignores late completion and frees engine',
    () async {
      engine.translateWait = Completer<String>();
      final c = controller();
      final work = c.start();
      await Future<void>.delayed(Duration.zero);
      expect(engine.calls, ['Hello']);
      c.dispose();
      engine.translateWait!.complete('Привет');
      await work;
      expect(c.lines, isNull);
      expect(engine.closed, true);
      expect(store.values, isEmpty);
    },
  );
}
