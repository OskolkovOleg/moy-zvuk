import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/models.dart';
import '../data/personal_models.dart';
import '../data/zvuk_api.dart';
import 'catalog_widgets.dart';
import 'widgets.dart';

Future<void> openLyrics(BuildContext context, AppController app, Track track) =>
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => LyricsScreen(app, track)));

class LyricsScreen extends StatefulWidget {
  const LyricsScreen(this.app, this.track, {super.key});
  final AppController app;
  final Track track;
  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  SongLyrics? lyrics;
  String? error;
  bool busy = false, translation = false;
  int request = 0;
  List<GlobalKey> lineKeys = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final current = ++request, api = widget.app.api;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (api == null) {
        throw const ZvukException('Обнови подключение в настройках.');
      }
      final result = await api.lyrics(widget.track.id);
      if (mounted && current == request && api == widget.app.api) {
        setState(() {
          lyrics = result;
          lineKeys = List.generate(
            result?.lines.length ?? 0,
            (_) => GlobalKey(),
          );
        });
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
                return Column(
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
                              if (data.translation?.trim().isNotEmpty == true)
                                FilterChip(
                                  label: const Text('Перевод'),
                                  selected: translation,
                                  onSelected: (v) =>
                                      setState(() => translation = v),
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
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        key: ValueKey(translation),
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
                                          child: Text(
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
                                                  ? scheme.onPrimaryContainer
                                                  : scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
  );
}
