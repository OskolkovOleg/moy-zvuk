import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/catalog_models.dart';
import '../data/models.dart';
import 'saved_catalog_screen.dart';
import 'history_screen.dart';
import 'widgets.dart';
import 'shuffle_sheet.dart';
import 'downloads_screen.dart';
import 'download_widgets.dart';
import 'library_shortcut.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen(this.app, {super.key, this.onSettings});
  final AppController app;
  final VoidCallback? onSettings;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _scroll = ScrollController();
  bool _showBackToTop = false;
  late String _source;
  AppController get app => widget.app;
  VoidCallback? get onSettings => widget.onSettings;

  @override
  void initState() {
    super.initState();
    _source = '${app.account?.id}:${app.listId}';
    _scroll.addListener(_updateBackToTop);
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final source = '${app.account?.id}:${app.listId}';
    if (_source != source) {
      _source = source;
      _showBackToTop = false;
    }
  }

  void _updateBackToTop() {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final show = _scroll.offset > _scroll.position.viewportDimension;
    if (show != _showBackToTop && mounted) {
      setState(() => _showBackToTop = show);
    }
  }

  void _backToTop() {
    if (!_scroll.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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
                    leading: const Icon(Icons.library_music_rounded),
                    title: const Text('Мои песни'),
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
      trackCountLabel(tracks.length),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
    );
    final playButton = FilledButton.icon(
      key: const Key('play-from-top'),
      onPressed: tracks.isEmpty ? null : () => app.playVisible(),
      icon: const Icon(Icons.play_arrow_rounded, size: 22),
      label: const Text('Слушать'),
    );
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: app.refresh,
          child: CustomScrollView(
            controller: _scroll,
            key: PageStorageKey('library:${app.listId}'),
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
                          Expanded(
                            child: Text(
                              'Мой Звук',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (onSettings != null)
                            IconButton(
                              tooltip: 'Настройки',
                              onPressed: onSettings,
                              icon: const Icon(Icons.tune_rounded, size: 22),
                            ),
                          DownloadListButton(app, tracks, compact: true),
                          IconButton(
                            tooltip: 'Обновить библиотеку',
                            onPressed: app.busy ? null : app.refresh,
                            icon: const Icon(Icons.refresh_rounded, size: 22),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height:
                          88 + MediaQuery.textScalerOf(context).scale(13) * 2.5,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(20, 8, 10, 12),
                        children: [
                          LibraryShortcut(
                            icon: Icons.download_for_offline_outlined,
                            label: 'Скачанное',
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => DownloadsScreen(app),
                              ),
                            ),
                          ),
                          for (final kind in [
                            CatalogKind.album,
                            CatalogKind.artist,
                          ])
                            LibraryShortcut(
                              icon: kind == CatalogKind.album
                                  ? Icons.album_outlined
                                  : Icons.person_outline_rounded,
                              label: kind.label,
                              onTap: () => Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => SavedCatalogScreen(app, kind),
                                ),
                              ),
                            ),
                          LibraryShortcut(
                            icon: Icons.history_rounded,
                            label: 'История',
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => HistoryScreen(app),
                              ),
                            ),
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
                                      style: TextStyle(
                                        fontSize: largeText ? 26 : 32,
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
                          if (largeText) ...[
                            trackCount,
                            const SizedBox(height: 8),
                          ],
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
                          const SizedBox(height: 12),
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
                    title: 'Здесь пока тихо',
                    message: 'Потяни вниз, чтобы обновить библиотеку, или выбери другой плейлист.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(top: 4, bottom: 84),
                  sliver: SliverList.builder(
                    itemCount: tracks.length,
                    itemBuilder: (_, index) => TrackTile(
                      track: tracks[index],
                      app: app,
                      onPlay: () => app.playVisible(index: index),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_showBackToTop)
          Positioned(
            right: 20,
            bottom: 16,
            child: FloatingActionButton.small(
              key: const Key('library-back-to-top'),
              heroTag: 'library-back-to-top',
              tooltip: 'Наверх',
              onPressed: _backToTop,
              child: const Icon(Icons.arrow_upward_rounded),
            ),
          ),
      ],
    );
  }
}
