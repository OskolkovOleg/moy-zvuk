import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/catalog_models.dart';
import '../data/zvuk_api.dart';
import '../data/models.dart';
import 'catalog_widgets.dart';
import 'widgets.dart';
import 'radio_actions.dart';
import '../data/wave_source.dart';

class CatalogDetailScreen extends StatefulWidget {
  const CatalogDetailScreen(this.app, this.item, {super.key});
  final AppController app;
  final CatalogItem item;
  @override
  State<CatalogDetailScreen> createState() => _CatalogDetailScreenState();
}

class _CatalogDetailScreenState extends State<CatalogDetailScreen> {
  CatalogDetail? detail;
  String? error;
  bool busy = false, editing = false;
  int request = 0;
  @override
  void initState() {
    super.initState();
    load();
    if (widget.item.kind == CatalogKind.album ||
        widget.item.kind == CatalogKind.artist) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.app.refreshSavedCatalog();
      });
    }
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
      final result = await api.catalogDetail(widget.item);
      if (mounted && current == request && api == widget.app.api) {
        setState(() => detail = result);
      }
    } catch (e) {
      if (mounted && current == request) {
        setState(() => error = catalogError(e));
      }
    } finally {
      if (mounted && current == request) setState(() => busy = false);
    }
  }

  Future<void> change(Future<void> Function() action) async {
    if (editing) return;
    setState(() => editing = true);
    try {
      await action();
      if (mounted) await load();
    } catch (e) {
      if (mounted) notify(context, catalogError(e));
    } finally {
      if (mounted) setState(() => editing = false);
    }
  }

  Future<void> menu(String action) async {
    final p = detail!.playlist!, app = widget.app;
    if (action == 'rename') {
      final name = await playlistNameDialog(
        context,
        initial: p.title,
        save: (name) => app.renamePlaylist(p, name),
      );
      if (name != null && mounted) await load();
    } else if (action == 'delete') {
      final yes = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Удалить плейлист?'),
          content: Text('«${p.title}» будет удалён из Звука.'),
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
      if (yes != true || !mounted) return;
      setState(() => editing = true);
      try {
        await app.deletePlaylist(p);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          notify(context, catalogError(e));
          setState(() => editing = false);
        }
      }
    } else if (action == 'library') {
      await app.openLibrary(p);
      if (mounted) {
        notify(context, 'Выбрано в библиотеке: ${p.title}');
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final app = widget.app, data = detail, p = data?.playlist;
      return PlayerScaffold(
        app,
        title: data?.item.title ?? widget.item.title,
        actions: [
          if (p != null)
            PopupMenuButton<String>(
              tooltip: 'Плейлист',
              enabled: !editing && !app.serverBusy,
              onSelected: menu,
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'library',
                  child: Text('Открыть в библиотеке'),
                ),
                if (app.owns(p)) ...[
                  const PopupMenuItem(
                    value: 'rename',
                    child: Text('Переименовать'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Удалить плейлист'),
                  ),
                ],
              ],
            ),
        ],
        body: busy && data == null
            ? const Center(child: CircularProgressIndicator())
            : error != null
            ? Center(child: CatalogFailure(error!, load))
            : data == null
            ? const SizedBox.shrink()
            : RefreshIndicator(
                onRefresh: load,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Artwork(
                                Track(
                                  id: data.item.id,
                                  title: data.item.title,
                                  imageUrl: data.item.imageUrl,
                                ),
                                size: 164,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              data.item.title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${data.item.kind == CatalogKind.artist ? 'Популярные треки' : data.item.subtitle} · ${trackCountLabel(data.tracks.length)}',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            if (p != null && p.description.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  p.description,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: data.tracks.isEmpty
                                      ? null
                                      : () => app.music.playList(
                                          data.tracks,
                                          0,
                                          title: data.item.title,
                                        ),
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('Слушать'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: data.tracks.isEmpty
                                      ? null
                                      : () {
                                          final shuffled = [...data.tracks]
                                            ..shuffle();
                                          app.music.playList(
                                            shuffled,
                                            0,
                                            title: data.item.title,
                                            shuffled: true,
                                          );
                                        },
                                  icon: const Icon(Icons.shuffle_rounded),
                                  label: const Text('Перемешать'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: app.api == null
                                      ? null
                                      : () => openRadioAction(
                                          context,
                                          app,
                                          WaveSource.fromCatalog(data.item),
                                        ),
                                  icon: const Icon(Icons.sensors_rounded),
                                  label: const Text('Слушать похожее'),
                                ),
                                if (data.item.kind == CatalogKind.album ||
                                    data.item.kind == CatalogKind.artist)
                                  OutlinedButton.icon(
                                    onPressed:
                                        editing ||
                                            app.serverBusy ||
                                            !app.savedCatalogKnown
                                        ? null
                                        : () => change(
                                            () => app.saveCatalogItem(
                                              data.item,
                                              !app.hasCatalogItem(data.item),
                                            ),
                                          ),
                                    icon: Icon(
                                      app.hasCatalogItem(data.item)
                                          ? Icons.bookmark_rounded
                                          : Icons.bookmark_border_rounded,
                                    ),
                                    label: Text(
                                      app.hasCatalogItem(data.item)
                                          ? 'Сохранено'
                                          : 'Сохранить',
                                    ),
                                  ),
                                if (p != null && !app.owns(p))
                                  OutlinedButton.icon(
                                    onPressed: editing || app.serverBusy
                                        ? null
                                        : () => change(
                                            () => app.savePlaylist(
                                              p,
                                              !app.hasPlaylist(p.id),
                                            ),
                                          ),
                                    icon: Icon(
                                      app.hasPlaylist(p.id)
                                          ? Icons.bookmark_rounded
                                          : Icons.bookmark_border_rounded,
                                    ),
                                    label: Text(
                                      app.hasPlaylist(p.id)
                                          ? 'Сохранён'
                                          : 'Сохранить',
                                    ),
                                  ),
                              ],
                            ),
                            if (p == null && app.savedCatalogError != null)
                              CatalogFailure(
                                app.savedCatalogError!,
                                app.refreshSavedCatalog,
                              ),
                            if (editing || busy)
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: LinearProgressIndicator(minHeight: 2),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (data.tracks.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'Здесь пока нет песен. Добавляй их из поиска через меню трека.',
                          ),
                        ),
                      ),
                    SliverList.builder(
                      itemCount: data.tracks.length,
                      itemBuilder: (context, index) => TrackTile(
                        app: app,
                        track: data.tracks[index],
                        catalog: true,
                        onActions: () => openTrackActions(
                          context,
                          app,
                          data.tracks[index],
                          remove: p != null && app.owns(p) && !editing
                              ? () => change(
                                  () => app.removeFromPlaylist(
                                    p,
                                    data.tracks,
                                    index,
                                  ),
                                )
                              : null,
                        ),
                        onPlay: () => app.music.playList(
                          data.tracks,
                          index,
                          title: data.item.title,
                        ),
                      ),
                    ),
                    if (data.albums.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                          child: Text(
                            'Альбомы и синглы',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ),
                      SliverList.builder(
                        itemCount: data.albums.length,
                        itemBuilder: (context, index) => CatalogTile(
                          data.albums[index],
                          onTap: () =>
                              openCatalog(context, app, data.albums[index]),
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  ],
                ),
              ),
      );
    },
  );
}
