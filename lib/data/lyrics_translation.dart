import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'library_store.dart';
import 'personal_models.dart';

/// Use provider lines only when their boundaries match the original exactly.
List<String>? alignedLyricsTranslation(SongLyrics lyrics) {
  final raw = lyrics.translation;
  if (raw == null || raw.trim().isEmpty) return null;
  final translated = SongLyrics.parse(raw);
  if (translated.lines.length != lyrics.lines.length) return null;
  for (var i = 0; i < lyrics.lines.length; i++) {
    final original = lyrics.lines[i], target = translated.lines[i];
    if (original.text.trim().isEmpty != target.text.trim().isEmpty) {
      return null;
    }
    if (translated.synced && (!lyrics.synced || original.at != target.at)) {
      return null;
    }
  }
  return translated.lines.map((line) => line.text).toList();
}

abstract interface class LyricsTranslationEngine {
  Future<String> identify(String text);
  Future<void> prepare(void Function() onDownloading);
  Future<String> translate(String text);
  Future<void> close();
}

class DeviceLyricsTranslationEngine implements LyricsTranslationEngine {
  final _identifier = LanguageIdentifier(confidenceThreshold: .65);
  final _models = OnDeviceTranslatorModelManager();
  OnDeviceTranslator? _translator;
  bool _closed = false;

  @override
  Future<String> identify(String text) => _identifier.identifyLanguage(text);

  @override
  Future<void> prepare(void Function() onDownloading) async {
    // English is the shared base; en→ru needs the Russian remote model.
    final model = TranslateLanguage.russian.bcpCode;
    if (!await _models.isModelDownloaded(model)) {
      onDownloading();
      final downloaded = await _models.downloadModel(
        model,
        isWifiRequired: true,
      );
      if (!downloaded) throw StateError('Translation model unavailable');
    }
    if (_closed) throw StateError('Translation closed');
    _translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: TranslateLanguage.russian,
    );
  }

  @override
  Future<String> translate(String text) => _translator!.translateText(text);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _identifier.close();
    await _translator?.close();
  }
}

enum LyricsTranslationPhase {
  identifying,
  downloading,
  translating,
  ready,
  unavailable,
  failed,
}

class LyricsTranslationController extends ChangeNotifier {
  LyricsTranslationController({
    required this.store,
    required this.account,
    required this.trackId,
    required this.lyrics,
    required this.isCurrent,
    this.createEngine = DeviceLyricsTranslationEngine.new,
  });

  final LibraryStore store;
  final String account, trackId;
  final SongLyrics lyrics;
  final bool Function() isCurrent;
  final LyricsTranslationEngine Function() createEngine;
  LyricsTranslationPhase phase = LyricsTranslationPhase.identifying;
  List<String>? lines;
  bool machineTranslated = false;
  int completed = 0;
  int _generation = 0;
  bool _disposed = false;
  String get _cacheKey => 'lyrics-en-ru-v1:$trackId';
  bool _valid(int generation) =>
      !_disposed && generation == _generation && isCurrent();

  void _update(int generation, LyricsTranslationPhase value) {
    if (!_valid(generation)) return;
    phase = value;
    notifyListeners();
  }

  Future<void> start() async {
    final generation = ++_generation;
    if (!_valid(generation)) return;
    lines = null;
    completed = 0;
    machineTranslated = false;
    _update(generation, LyricsTranslationPhase.identifying);
    final provider = alignedLyricsTranslation(lyrics);
    if (provider != null) {
      lines = provider;
      _update(generation, LyricsTranslationPhase.ready);
      return;
    }
    final source = lyrics.lines.map((line) => line.text).toList();
    try {
      final cached = await store.get(account, _cacheKey);
      if (!_valid(generation)) return;
      if (cached is Map &&
          cached['source'] is List &&
          listEquals(cached['source'] as List, source) &&
          cached['translated'] is List &&
          (cached['translated'] as List).length == source.length &&
          (cached['translated'] as List).every((line) => line is String)) {
        lines = List<String>.from(cached['translated']);
        machineTranslated = true;
        _update(generation, LyricsTranslationPhase.ready);
        return;
      }
    } catch (_) {
      // An unreadable cache must not prevent reading or translating lyrics.
    }
    if (!_valid(generation)) return;
    LyricsTranslationEngine? engine;
    try {
      engine = createEngine();
      final language = await engine.identify(source.join('\n'));
      if (!_valid(generation)) return;
      if (language != 'en') {
        _update(generation, LyricsTranslationPhase.unavailable);
        return;
      }
      await engine
          .prepare(
            () => _update(generation, LyricsTranslationPhase.downloading),
          )
          .timeout(const Duration(seconds: 90));
      if (!_valid(generation)) return;
      _update(generation, LyricsTranslationPhase.translating);
      final translated = <String>[], repeated = <String, String>{};
      for (final text in source) {
        if (!_valid(generation)) return;
        if (text.trim().isEmpty) {
          translated.add('');
        } else {
          final target =
              repeated[text] ??
              await engine.translate(text).timeout(const Duration(seconds: 20));
          if (!_valid(generation)) return;
          if (target.trim().isEmpty) throw StateError('Empty translation');
          repeated[text] = target;
          translated.add(target);
        }
        completed = translated.length;
        _update(generation, LyricsTranslationPhase.translating);
      }
      if (!_valid(generation)) return;
      lines = translated;
      machineTranslated = true;
      _update(generation, LyricsTranslationPhase.ready);
      try {
        await store.put(account, _cacheKey, {
          'source': source,
          'translated': translated,
        });
      } catch (_) {
        // The displayed result is still usable if the cache cannot be saved.
      }
    } catch (_) {
      _update(generation, LyricsTranslationPhase.failed);
    } finally {
      try {
        await engine?.close();
      } catch (_) {
        // Closing a platform resource must not replace the user's result.
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
