import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/models.dart';
import '../data/personal_models.dart';
import '../data/lyrics_translation.dart';
import '../data/zvuk_api.dart';
import 'catalog_widgets.dart';
import 'widgets.dart';
import 'translation_info.dart';

Future<void> openLyrics(BuildContext context, AppController app, Track track) =>
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => LyricsScreen(app, track)));

class LyricsScreen extends StatefulWidget {
  const LyricsScreen(
    this.app,
    this.track, {
    super.key,
    this.createTranslationEngine = DeviceLyricsTranslationEngine.new,
  });
  final AppController app;
  final Track track;
  final LyricsTranslationEngine Function() createTranslationEngine;
  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  SongLyrics? lyrics;
  String? error;
  bool busy = false, translation = false;
  bool inlineTranslation = true;
  LyricsTranslationController? translated;
  String? lyricsAccount;
  ZvukApi? lyricsApi;
  int request = 0;
  List<GlobalKey> lineKeys = [];
  @override
  void initState() {
    super.initState();
    widget.app.addListener(accountChanged);
    load();
  }

  void accountChanged() {
    if (lyricsAccount != widget.app.account?.id ||
        lyricsApi != widget.app.api) {
      load();
    }
  }

  void translationChanged() {
    if (mounted) {
      setState(() {
        if (translated?.lines != null) translation = false;
      });
    }
  }

  Future<SongLyrics?> cachedLyrics(String account) async {
    try {
      final saved = await widget.app.store.get(
        account,
        'lyrics-source-v1:${widget.track.id}',
      );
      if (saved is! Map<String, dynamic>) return null;
      final result = SongLyrics.fromJson(saved);
      return result.lines.isEmpty ? null : result;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    request++;
    widget.app.removeListener(accountChanged);
    translated?.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final current = ++request, api = widget.app.api;
    final account = widget.app.account?.id;
    lyricsApi = api;
    lyricsAccount = account;
    translated?.dispose();
    translated = null;
    setState(() {
      busy = true;
      error = null;
      lyrics = null;
      translation = false;
      inlineTranslation = true;
    });
    try {
      SongLyrics? result;
      var cached = false;
      try {
        if (api == null) {
          throw const ZvukException('Обнови подключение в настройках.');
        }
        result = await api.lyrics(widget.track.id);
      } catch (_) {
        if (account == null) rethrow;
        result = await cachedLyrics(account);
        if (result == null) rethrow;
        cached = true;
      }
      if (mounted &&
          current == request &&
          api == widget.app.api &&
          account == widget.app.account?.id) {
        setState(() {
          lyrics = result;
          lineKeys = List.generate(
            result?.lines.length ?? 0,
            (_) => GlobalKey(),
          );
        });
        if (result != null && account != null && !cached) {
          try {
            await widget.app.store.put(
              account,
              'lyrics-source-v1:${widget.track.id}',
              result.toJson(),
            );
          } catch (_) {
            // Text remains readable when its local copy cannot be saved.
          }
        }
        if (!mounted ||
            current != request ||
            api != widget.app.api ||
            account != widget.app.account?.id) {
          return;
        }
        if (result != null && account != null) {
          final controller = LyricsTranslationController(
            store: widget.app.store,
            account: account,
            trackId: widget.track.id,
            lyrics: result,
            isCurrent: () =>
                mounted &&
                current == request &&
                api == widget.app.api &&
                account == widget.app.account?.id,
            createEngine: widget.createTranslationEngine,
          );
          translated = controller..addListener(translationChanged);
          unawaited(controller.start());
        }
      }
    } catch (e) {
      if (mounted && current == request) {
        setState(() => error = catalogError(e));
      }
    } finally {
      if (mounted && current == request) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PlayerScaffold(
    widget.app,
    title: 'Текст песни',
    body: busy
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(child: CatalogFailure(error!, load))
        : lyrics == null
        ? const EmptyState(
            icon: Icons.lyrics_outlined,
            title: 'Текста пока нет',
            message: 'У этой песни в Звуке ещё нет текста.',
          )
        : AnimatedBuilder(
            animation: widget.app.music.revision,
            builder: (context, _) => StreamBuilder<Duration>(
              stream: widget.app.music.player.positionStream,
              builder: (context, snapshot) {
                final data = lyrics!, music = widget.app.music;
                final current = music.playlist.current?.id == widget.track.id;
                final active = current && !translation
                    ? data.activeLine(music.position)
                    : -1;
                final scheme = Theme.of(context).colorScheme;
                final pairs = translated?.lines;
                return SingleChildScrollView(
                  key: ValueKey(translation),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.track.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.track.artists,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                            if (data.synced)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  current
                                      ? 'Нажми на строку, чтобы перейти к ней.'
                                      : 'Включи эту песню, чтобы следить за текстом.',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            Wrap(
                              spacing: 12,
                              children: [
                                if (pairs != null ||
                                    data.translation?.trim().isNotEmpty == true)
                                  FilterChip(
                                    label: const Text('Перевод'),
                                    selected: pairs != null
                                        ? inlineTranslation
                                        : translation,
                                    onSelected: (v) => setState(() {
                                      if (pairs != null) {
                                        inlineTranslation = v;
                                        translation = false;
                                      } else {
                                        translation = v;
                                      }
                                    }),
                                  ),
                                if (active >= 0)
                                  TextButton.icon(
                                    onPressed: () {
                                      final target =
                                          lineKeys[active].currentContext;
                                      if (target != null) {
                                        Scrollable.ensureVisible(
                                          target,
                                          alignment: .25,
                                          duration: const Duration(
                                            milliseconds: 250,
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.my_location_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('К текущей строке'),
                                  ),
                              ],
                            ),
                            if (pairs != null &&
                                inlineTranslation &&
                                translated!.machineTranslated)
                              const TranslationAttribution(),
                            if (translated != null && pairs == null)
                              translationStatus(context),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                        child: translation
                            ? SelectableText(
                                data.translation!,
                                style: const TextStyle(
                                  fontSize: 20,
                                  height: 1.65,
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = 0; i < data.lines.length; i++)
                                    Semantics(
                                      selected: i == active,
                                      child: InkWell(
                                        key: lineKeys[i],
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: current && data.synced
                                            ? () =>
                                                  music.seek(data.lines[i].at!)
                                            : null,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: i == active
                                                ? scheme.primaryContainer
                                                : null,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                data.lines[i].text.isEmpty
                                                    ? '♪'
                                                    : data.lines[i].text,
                                                style: TextStyle(
                                                  fontSize: 22,
                                                  height: 1.45,
                                                  fontWeight: i == active
                                                      ? FontWeight.w700
                                                      : FontWeight.w400,
                                                  color: i == active
                                                      ? scheme
                                                            .onPrimaryContainer
                                                      : scheme.onSurface,
                                                ),
                                              ),
                                              if (inlineTranslation &&
                                                  pairs != null &&
                                                  pairs[i].trim().isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4,
                                                      ),
                                                  child: Text(
                                                    pairs[i],
                                                    key: ValueKey(
                                                      'lyrics-translation:$i',
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      height: 1.45,
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
  );

  Widget translationStatus(BuildContext context) {
    final controller = translated!;
    final text = switch (controller.phase) {
      LyricsTranslationPhase.identifying => 'Проверяем язык текста…',
      LyricsTranslationPhase.downloading =>
        'Перевод: скачивается пакет по Wi‑Fi (~30 МБ)…',
      LyricsTranslationPhase.translating =>
        'Переводим строки: ${controller.completed}/${lyrics!.lines.length}…',
      LyricsTranslationPhase.failed =>
        'Перевод недоступен. Для первого запуска нужен Wi‑Fi.',
      _ => null,
    };
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (controller.phase == LyricsTranslationPhase.failed)
            TextButton.icon(
              onPressed: () => unawaited(controller.start()),
              icon: const Icon(Icons.translate_rounded, size: 18),
              label: const Text('Перевести с Google'),
            ),
        ],
      ),
    );
  }
}
