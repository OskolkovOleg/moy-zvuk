import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/models.dart';
import '../playback/music_handler.dart';
import 'widgets.dart';

class QueueView extends StatefulWidget {
  const QueueView(this.app, {super.key});
  final AppController app;
  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView> {
  late final ScrollController scroll;
  int? dragVersion;
  @override
  void initState() {
    super.initState();
    scroll = ScrollController(
      initialScrollOffset: (widget.app.music.playlist.index * 76.0 - 76).clamp(
        0,
        double.infinity,
      ),
    );
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> edit(Future<bool> result) async {
    if (!await result && mounted) {
      notify(context, 'Очередь изменилась. Повтори действие.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final music = widget.app.music, queue = music.playlist;
    final tracks = queue.tracks, version = queue.version;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  trackCountLabel(tracks.length),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Перемешать оставшиеся',
                onPressed: tracks.length - queue.index > 2
                    ? music.shuffleUpcoming
                    : null,
                icon: const Icon(Icons.shuffle_rounded),
              ),
              IconButton(
                tooltip: 'Убрать оставшиеся',
                onPressed: queue.hasNext || music.isWave
                    ? () async {
                        await music.clearUpcoming();
                        if (context.mounted) {
                          notify(
                            context,
                            'Очередь закончится после текущей песни',
                          );
                        }
                      }
                    : null,
                icon: const Icon(Icons.playlist_remove_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            'Перетаскивай песни за ручку справа.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            key: const Key('editable-queue'),
            scrollController: scroll,
            buildDefaultDragHandles: false,
            itemCount: tracks.length,
            onReorderStart: (_) => dragVersion = queue.version,
            onReorderItem: (from, to) =>
                edit(music.moveInQueue(from, to, dragVersion ?? version)),
            itemBuilder: (context, index) {
              final track = tracks[index], current = index == queue.index;
              return Padding(
                key: ValueKey(queue.entryKey(index)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: Material(
                  color: current
                      ? scheme.primary.withValues(alpha: .09)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          contentPadding: const EdgeInsets.only(left: 12),
                          leading: Artwork(track, size: 44),
                          title: Text(
                            track.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: current ? scheme.primary : null,
                            ),
                          ),
                          subtitle: Text(
                            current
                                ? 'Сейчас играет · ${track.artists}'
                                : track.artists,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          onTap: () =>
                              edit(music.playQueueItem(index, version)),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'В очереди: ${track.title}',
                        onSelected: (action) => edit(
                          action == 'remove'
                              ? music.removeFromQueue(index, version)
                              : music.moveNextInQueue(index, version),
                        ),
                        itemBuilder: (_) => [
                          if (!current)
                            const PopupMenuItem(
                              value: 'next',
                              child: Text('Следующей'),
                            ),
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('Убрать из очереди'),
                          ),
                        ],
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: Semantics(
                          label: 'Переместить ${track.title}',
                          child: SizedBox(
                            key: ValueKey('drag:${queue.entryKey(index)}'),
                            width: 40,
                            height: 52,
                            child: Icon(
                              Icons.drag_handle_rounded,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
