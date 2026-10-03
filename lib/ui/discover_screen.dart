import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/catalog_models.dart';
import '../data/models.dart';
import '../data/zvuk_api.dart';
import 'catalog_widgets.dart';
import 'radio_actions.dart';
import '../data/wave_source.dart';
import 'wave_settings.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen(this.app, {super.key});
  final AppController app;
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  bool starting = false;
  Future<void> start() async {
    setState(() => starting = true);
    try {
      await widget.app.music.startWave();
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Material(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.waves_rounded,
                    size: 40,
                    color: scheme.onPrimaryContainer,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Мой поток',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Знакомые песни и новые открытия\nПо твоему вкусу, без конца',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: starting || widget.app.api == null
                        ? null
                        : start,
                    icon: Icon(
                      starting
                          ? Icons.hourglass_top_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(
                      starting ? 'Подбираем музыку…' : 'Включить поток',
                    ),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder(
                    valueListenable: widget.app.music.revision,
                    builder: (_, _, _) => TextButton.icon(
                      onPressed: starting || widget.app.account == null
                          ? null
                          : () => openWaveSettings(context, widget.app),
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.onPrimaryContainer,
                        alignment: Alignment.centerLeft,
                      ),
                      icon: const Icon(Icons.tune_rounded),
                      label: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Настроить поток'),
                          Text(
                            widget.app.music.waveOptions.summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: starting || widget.app.api == null
                        ? null
                        : () => openRadioAction(
                            context,
                            widget.app,
                            const WaveSource.favorites(),
                          ),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onPrimaryContainer,
                    ),
                    icon: const Icon(Icons.favorite_border_rounded),
                    label: const Text('Поток по любимому'),
                  ),
                  ValueListenableBuilder(
                    valueListenable: widget.app.music.error,
                    builder: (_, error, _) => error == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              error,
                              style: TextStyle(
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _PlaylistSection(
          widget.app,
          title: 'Для тебя',
          load: () => widget.app.api!.personalPlaylists(),
        ),
        _PlaylistSection(
          widget.app,
          title: 'Чарты',
          load: () => widget.app.api!.chartPlaylists(),
        ),
        _PlaylistSection(
          widget.app,
          title: 'Выбор редакции',
          load: () => widget.app.api!.editorialPlaylists(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _PlaylistSection extends StatefulWidget {
  const _PlaylistSection(this.app, {required this.title, required this.load});
  final AppController app;
  final String title;
  final Future<List<PlaylistInfo>> Function() load;
  @override
  State<_PlaylistSection> createState() => _PlaylistSectionState();
}

class _PlaylistSectionState extends State<_PlaylistSection> {
  late Future<List<PlaylistInfo>> result = load();
  Future<List<PlaylistInfo>> load() => widget.app.api == null
      ? Future.error(const ZvukException('Обнови подключение в настройках.'))
      : widget.load();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text(
          widget.title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      FutureBuilder(
        future: result,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return CatalogFailure(
              catalogError(snapshot.error!),
              () => setState(() => result = load()),
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: LinearProgressIndicator(),
            );
          }
          if (snapshot.data!.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Подборки пока не появились'),
            );
          }
          return Column(
            children: snapshot.data!.map((p) {
              final item = CatalogItem.playlist(p);
              return CatalogTile(
                item,
                onTap: () => openCatalog(context, widget.app, item),
              );
            }).toList(),
          );
        },
      ),
      const SizedBox(height: 20),
    ],
  );
}
