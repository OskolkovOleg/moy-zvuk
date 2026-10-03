import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'widgets.dart';
import 'shuffle_sheet.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen(this.app, {super.key, this.onSettings});
  final AppController app;
  final VoidCallback? onSettings;

  void chooseLibrary(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Text(
                'Твоя библиотека',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.favorite_rounded),
                    title: const Text('Любимое'),
                    selected: app.listId == 'favorites',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      app.selectPlaylist(null);
                    },
                  ),
                  ...app.playlists.map(
                    (p) => ListTile(
                      leading: const Icon(Icons.queue_music_rounded),
                      title: Text(p.title),
                      selected: app.listId == p.id,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        app.selectPlaylist(p);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tracks = app.visibleTracks;
    final scheme = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(13) > 17;
    final trackCount = Text(
      '${tracks.length} треков',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
    );
    final playButton = FilledButton.icon(
      key: const Key('play-from-top'),
      onPressed: tracks.isEmpty ? null : () => app.playVisible(),
      icon: const Icon(Icons.play_arrow_rounded, size: 22),
      label: const Text('Слушать сверху'),
    );
    return RefreshIndicator(
      onRefresh: app.refresh,
      child: CustomScrollView(
        key: PageStorageKey('library:${app.listId}:${app.ranked}'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/brand/icon.png',
                        width: 28,
                        height: 28,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Мой Звук',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (onSettings != null)
                        IconButton(
                          tooltip: 'Настройки',
                          onPressed: onSettings,
                          icon: const Icon(Icons.tune_rounded, size: 22),
                        ),
                      IconButton(
                        tooltip: 'Обновить библиотеку',
                        onPressed: app.busy ? null : app.refresh,
                        icon: const Icon(Icons.refresh_rounded, size: 22),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => chooseLibrary(context),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  app.listTitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700,
                                    height: 1.15,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.keyboard_arrow_down_rounded),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (largeText) ...[trackCount, const SizedBox(height: 8)],
                      Row(
                        children: [
                          if (!largeText) Expanded(child: trackCount),
                          if (largeText)
                            Expanded(child: playButton)
                          else
                            playButton,
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            key: const Key('shuffle-list'),
                            tooltip: 'Перемешать',
                            onPressed: app.tracks.isEmpty
                                ? null
                                : () => openShuffle(context, app),
                            icon: const Icon(Icons.shuffle_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<bool>(
                          showSelectedIcon: false,
                          style: ButtonStyle(
                            visualDensity: VisualDensity.standard,
                            textStyle: const WidgetStatePropertyAll(
                              TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            side: WidgetStatePropertyAll(
                              BorderSide(color: scheme.outlineVariant),
                            ),
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (s) => s.contains(WidgetState.selected)
                                  ? scheme.surfaceContainerHighest
                                  : scheme.surface,
                            ),
                            foregroundColor: WidgetStateProperty.resolveWith(
                              (s) => s.contains(WidgetState.selected)
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Мой порядок'),
                              icon: Icon(Icons.swap_vert_rounded, size: 18),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('По баллам'),
                              icon: Icon(
                                Icons.favorite_outline_rounded,
                                size: 18,
                              ),
                            ),
                          ],
                          selected: {app.ranked},
                          onSelectionChanged: (value) =>
                              app.setSort(value.first),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (app.ranked) ...[
                        FilterChip(
                          label: const Text('Без оценок'),
                          selected: app.unrated,
                          onSelected: app.setUnrated,
                        ),
                        Text(
                          'Старт — 10 баллов. Минус не удаляет песню.',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ] else
                        Text(
                          '↑ ↓ меняют соседние песни местами',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 2,
                  child: app.busy
                      ? const LinearProgressIndicator(minHeight: 2)
                      : null,
                ),
              ],
            ),
          ),
          if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.library_music_outlined,
                title: app.unrated ? 'Всё уже оценено' : 'Здесь пока тихо',
                message: app.unrated
                    ? 'Выключи фильтр, чтобы увидеть все треки.'
                    : 'Потяни вниз, чтобы обновить библиотеку, или выбери другой плейлист.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              sliver: SliverList.builder(
                itemCount: tracks.length,
                itemBuilder: (_, index) => TrackTile(
                  track: tracks[index],
                  app: app,
                  orderIndex: index,
                  orderLength: tracks.length,
                  onPlay: () => app.playVisible(index: index),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
