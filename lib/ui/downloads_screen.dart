import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/models.dart';
import '../data/genre_filter.dart';
import '../downloads/download_record.dart';
import '../playback/shuffle_tracks.dart';
import 'catalog_widgets.dart';
import 'download_widgets.dart';
import 'shuffle_sheet.dart';
import 'widgets.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen(this.app, {super.key});
  final AppController app;
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  Future<void> clear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Удалить скачанную музыку?'),
        content: const Text(
          'Освободится место на устройстве. Любимое, плейлисты и баллы сохранятся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (yes == true) await change(widget.app.music.downloads.clear);
  }

  Future<void> change(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        notify(context, 'Не удалось изменить загрузки. Попробуй снова.');
      }
    }
  }

  Future<void> shuffle(List<Track> tracks) async {
    final app = widget.app;
    final account = app.account?.id,
        ratings = Map<String, Rating>.of(app.ratings);
    final known = {for (final track in app.favoriteTracks) track.id: track};
    final snapshot = [
      for (final track in tracks)
        track.genres.isEmpty ? known[track.id] ?? track : track,
    ];
    final selection = await showModalBottomSheet<ShuffleSelection>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) =>
          ShuffleSheet(tracks: snapshot, ratings: ratings, title: 'Скачанное'),
    );
    if (selection == null || account != app.account?.id) return;
    final selected = shuffledTracks(
      filterTracksByGenreAndScore(snapshot, ratings, groups: selection.genres),
      ratings,
      minScore: selection.scores.min,
      maxScore: selection.scores.max,
    );
    if (selected.isEmpty) return;
    await app.music.playList(
      selected,
      0,
      title: selection.titleFor('Скачанное'),
      shuffled: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app, downloads = app.music.downloads;
    return AnimatedBuilder(
      animation: Listenable.merge([app, downloads]),
      builder: (context, _) {
        final tracks = rankedTracks(downloads.tracks, app.ratings);
        final transfers = downloads.items
            .where((item) => item.state != DownloadState.ready)
            .toList();
        final scheme = Theme.of(context).colorScheme;
        return PlayerScaffold(
          app,
          title: 'Скачанное',
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Управление загрузками',
              enabled: downloads.items.isNotEmpty,
              onSelected: (_) => clear(),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'clear',
                  child: Text('Удалить все загрузки'),
                ),
              ],
            ),
          ],
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${trackCountLabel(tracks.length)} · ${downloadSize(downloads.storedBytes)}',
                        key: const Key('download-storage'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Готовые песни можно слушать без интернета.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            key: const Key('play-downloads'),
                            onPressed: tracks.isEmpty
                                ? null
                                : () => app.music.playList(
                                    tracks,
                                    0,
                                    title: 'Скачанное',
                                  ),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Слушать'),
                          ),
                          OutlinedButton.icon(
                            onPressed: tracks.isEmpty
                                ? null
                                : () => shuffle(tracks),
                            icon: const Icon(Icons.shuffle_rounded),
                            label: const Text('Перемешать'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (transfers.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      'Загрузки',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: transfers.length,
                  itemBuilder: (context, index) {
                    final item = transfers[index];
                    final failed = item.state == DownloadState.failed;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                      child: Row(
                        children: [
                          Artwork(item.track),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  failed
                                      ? item.error ?? 'Не удалось скачать'
                                      : item.state == DownloadState.queued
                                      ? 'В очереди'
                                      : '${downloadSize(item.bytes)}${item.total == null ? '' : ' из ${downloadSize(item.total!)}'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: failed
                                        ? scheme.error
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                                if (item.state == DownloadState.downloading)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: LinearProgressIndicator(
                                      value: item.progress,
                                      minHeight: 3,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (failed)
                            IconButton(
                              tooltip: 'Повторить: ${item.track.title}',
                              onPressed: () =>
                                  downloadTracks(context, app, [item.track]),
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          IconButton(
                            tooltip:
                                '${failed ? 'Удалить загрузку' : 'Отменить'}: ${item.track.title}',
                            onPressed: () =>
                                change(() => downloads.remove(item.track.id)),
                            icon: Icon(
                              failed
                                  ? Icons.delete_outline_rounded
                                  : Icons.close_rounded,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              if (tracks.isNotEmpty)
                SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) => TrackTile(
                    app: app,
                    track: tracks[index],
                    onPlay: () =>
                        app.music.playList(tracks, index, title: 'Скачанное'),
                  ),
                ),
              if (downloads.items.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.download_for_offline_outlined,
                    title: 'Музыка с собой',
                    message: 'В меню песни выбери «Скачать». Альбомы и плейлисты можно сохранить целиком.',
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  child: Text(
                    'Скачивание использует текущую сеть, в том числе мобильную. Прерванные загрузки можно повторить здесь.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
