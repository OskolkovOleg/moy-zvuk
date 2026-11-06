import 'dart:math';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/catalog_models.dart';
import '../data/discovery_models.dart';
import '../data/models.dart';
import '../discovery_controller.dart';
import 'catalog_widgets.dart';
import 'widgets.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen(
    this.app,
    this.mode, {
    super.key,
    this.seed,
    this.controller,
  });
  final AppController app;
  final DiscoveryMode mode;
  final Track? seed;
  final DiscoveryController? controller;
  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  late final controller =
      widget.controller ??
      DiscoveryController(
        widget.app,
        widget.mode,
        seed:
            widget.seed ??
            widget.app.music.playlist.current ??
            widget.app.favoriteTracks.firstOrNull,
      );
  bool acting = false;
  late final _account = widget.app.account?.id;
  bool get sameAccount => widget.app.account?.id == _account;
  @override
  void initState() {
    super.initState();
    if (widget.controller == null) controller.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  List<Track> get snapshot =>
      controller.candidates.map((c) => c.track).toList();

  Future<void> playback(String action, {int index = 0}) async {
    if (!sameAccount || acting || controller.loading || snapshot.isEmpty) {
      return;
    }
    final tracks = snapshot;
    setState(() => acting = true);
    try {
      if (action == 'queue') {
        final count = await widget.app.music.appendDiscoveries(tracks);
        if (mounted) {
          notify(
            context,
            count == 0
                ? 'Эти песни уже в очереди'
                : 'В очередь: ${trackCountLabel(count)}',
          );
        }
      } else {
        if (action == 'shuffle') tracks.shuffle(Random());
        await widget.app.music.playList(
          tracks,
          action == 'shuffle' ? 0 : index,
          title: controller.mode.label,
          shuffled: action == 'shuffle',
        );
      }
    } catch (e) {
      if (mounted) notify(context, catalogError(e));
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> chooseSeed() async {
    if (!sameAccount) return;
    final track = await showModalBottomSheet<Track>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SeedPicker(widget.app),
    );
    if (!mounted || track == null) return;
    controller.seed = track;
    await controller.load();
  }

  Future<void> options() async {
    if (!sameAccount) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Не предлагать'),
              subtitle: const Text('Посмотреть скрытые песни и вернуть их'),
              onTap: () => Navigator.pop(sheet, 'hidden'),
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('Повторить недавние предложения'),
              subtitle: const Text('Скрытые песни останутся скрытыми'),
              onTap: () => Navigator.pop(sheet, 'recent'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'recent') await controller.load(resetRecent: true);
    if (action == 'hidden') await showHidden();
  }

  Future<void> showHidden() async {
    final account = widget.app.account?.id;
    if (account == null) return;
    try {
      final memory = await controller.memory.load(account);
      if (!mounted || widget.app.account?.id != account) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => StatefulBuilder(
          builder: (sheet, update) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheet).height * .65,
              child: Column(
                children: [
                  const ListTile(title: Text('Не предлагать')),
                  if (memory.hidden.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Скрытых песен нет'),
                    ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final track in memory.hidden)
                          ListTile(
                            title: Text(track.title),
                            subtitle: Text(track.artists),
                            trailing: IconButton(
                              tooltip: 'Вернуть: ${track.title}',
                              icon: const Icon(Icons.undo_rounded),
                              onPressed: () async {
                                try {
                                  await controller.memory.restore(
                                    account,
                                    track,
                                  );
                                  if (sheet.mounted) {
                                    update(() => memory.hidden.remove(track));
                                  }
                                } catch (e) {
                                  if (sheet.mounted) {
                                    notify(sheet, catalogError(e));
                                  }
                                }
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
        ),
      );
    } catch (e) {
      if (mounted) notify(context, catalogError(e));
    }
  }

  Future<void> songActions(Track track) async {
    if (!sameAccount) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Artwork(track),
              title: Text(track.title),
              subtitle: Text(track.artists),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Не предлагать'),
              onTap: () => Navigator.pop(sheet, 'hide'),
            ),
            ListTile(
              leading: const Icon(Icons.more_horiz_rounded),
              title: const Text('Действия с песней'),
              onTap: () => Navigator.pop(sheet, 'actions'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    try {
      if (action == 'hide') await controller.hide(track);
      if (action == 'actions' && mounted) {
        await openTrackActions(context, widget.app, track);
      }
    } catch (e) {
      if (mounted) notify(context, catalogError(e));
    }
  }

  @override
  Widget build(BuildContext context) => PlayerScaffold(
    widget.app,
    title: widget.mode.label,
    actions: [
      IconButton(
        tooltip: 'Настройки открытий',
        onPressed: options,
        icon: const Icon(Icons.more_horiz_rounded),
      ),
    ],
    body: AnimatedBuilder(
      animation: Listenable.merge([controller, widget.app]),
      builder: (context, _) {
        if (!sameAccount) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Аккаунт изменился. Открой подборку заново.'),
            ),
          );
        }
        final scheme = Theme.of(context).colorScheme;
        return RefreshIndicator(
          onRefresh: controller.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.mode.description,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      if (widget.mode == DiscoveryMode.song)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.music_note_rounded),
                          title: Text(controller.seed?.title ?? 'Выбери песню'),
                          subtitle: controller.seed == null
                              ? null
                              : Text(controller.seed!.artists),
                          trailing: const Icon(Icons.expand_more_rounded),
                          onTap: chooseSeed,
                        ),
                      if (widget.mode == DiscoveryMode.explore) ...[
                        Text(
                          'Знакомство с направлением',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            ChoiceChip(
                              label: const Text('Разное'),
                              selected: controller.direction == null,
                              onSelected: (_) {
                                controller.direction = null;
                                controller.load();
                              },
                            ),
                            for (final direction in discoveryDirections)
                              ChoiceChip(
                                label: Text(direction.label),
                                selected: controller.direction == direction.id,
                                onSelected: (_) {
                                  controller.direction = direction.id;
                                  controller.load();
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Чарты и тематические подборки Звука. Нажми на имя артиста, чтобы послушать его популярные песни.',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (widget.mode == DiscoveryMode.releases) ...[
                        Text(
                          'За последние 90 дней · по артистам из коллекции и лучших песен',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilterChip(
                            label: const Text('Цензурные'),
                            selected: controller.censoredOnly,
                            onSelected: (value) {
                              controller.censoredOnly = value;
                              controller.load();
                            },
                          ),
                          TextButton.icon(
                            onPressed: controller.loading
                                ? null
                                : () => controller.load(),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Ещё подборка'),
                          ),
                        ],
                      ),
                      if (!controller.loading &&
                          controller.candidates.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          trackCountLabel(controller.candidates.length),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: acting ? null : () => playback('play'),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Слушать'),
                            ),
                            OutlinedButton.icon(
                              onPressed: acting
                                  ? null
                                  : () => playback('shuffle'),
                              icon: const Icon(Icons.shuffle_rounded),
                              label: const Text('Перемешать'),
                            ),
                            TextButton.icon(
                              onPressed: acting
                                  ? null
                                  : () => playback('queue'),
                              icon: const Icon(Icons.playlist_add_rounded),
                              label: const Text('В очередь'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Понравилась — поставь плюс. Песня сохранится в библиотеке.',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      if (controller.note != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(controller.note!),
                        ),
                    ],
                  ),
                ),
              ),
              if (controller.loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: LinearProgressIndicator(),
                  ),
                ),
              if (!controller.loading && controller.error != null)
                SliverToBoxAdapter(
                  child: CatalogFailure(
                    controller.error!,
                    () => controller.load(),
                  ),
                ),
              if (!controller.loading &&
                  controller.error == null &&
                  controller.candidates.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 36,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Свежих предложений пока нет',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Попробуй другую песню или направление, отключи фильтр «Цензурные» или повтори недавние предложения.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => controller.load(resetRecent: true),
                          child: const Text('Повторить предложения'),
                        ),
                      ],
                    ),
                  ),
                ),
              SliverList.builder(
                itemCount: controller.candidates.length,
                itemBuilder: (context, index) {
                  final item = controller.candidates[index];
                  return Column(
                    key: ValueKey('discovery:${item.track.id}'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TrackTile(
                        track: item.track,
                        app: widget.app,
                        onPlay: () => playback('play', index: index),
                        onActions: () => songActions(item.track),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 20, 12),
                        child: InkWell(
                          onTap:
                              item.source == null ||
                                  item.source!.kind == CatalogKind.track
                              ? null
                              : () => openCatalog(
                                  context,
                                  widget.app,
                                  item.source!,
                                ),
                          onLongPress: () => songActions(item.track),
                          child: Text(
                            item.reason,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    ),
  );
}

class _SeedPicker extends StatefulWidget {
  const _SeedPicker(this.app);
  final AppController app;
  @override
  State<_SeedPicker> createState() => _SeedPickerState();
}

class _SeedPickerState extends State<_SeedPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final tracks =
        [
              ?widget.app.music.playlist.current,
              ...rankedTracks(widget.app.favoriteTracks, widget.app.ratings),
            ]
            .where(
              (t) =>
                  seen.add(t.id) &&
                  '${t.title} ${t.artists}'.toLowerCase().contains(
                    query.toLowerCase(),
                  ),
            )
            .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Песня из библиотеки',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, i) => ListTile(
                    leading: Artwork(tracks[i]),
                    title: Text(tracks[i].title),
                    subtitle: Text(tracks[i].artists),
                    onTap: () => Navigator.pop(context, tracks[i]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
