import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/catalog_models.dart';
import 'catalog_widgets.dart';
import 'widgets.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) => RefreshIndicator(
      onRefresh: app.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: FilledButton.icon(
              onPressed: app.serverBusy || app.api == null
                  ? null
                  : () => playlistNameDialog(
                      context,
                      save: (name) async {
                        await app.createPlaylist(name);
                      },
                    ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Создать плейлист'),
            ),
          ),
          if (app.busy) const LinearProgressIndicator(minHeight: 2),
          if (app.playlists.isEmpty && !app.busy)
            const EmptyState(
              icon: Icons.queue_music_rounded,
              title: 'Твоя музыка по настроению',
              message: 'Создай свой плейлист или сохрани подборку из поиска и обзора.',
            ),
          for (final p in app.playlists)
            CatalogTile(
              CatalogItem.playlist(p),
              onTap: () => openCatalog(context, app, CatalogItem.playlist(p)),
              trailing: Icon(
                app.owns(p)
                    ? Icons.edit_note_rounded
                    : Icons.chevron_right_rounded,
              ),
            ),
        ],
      ),
    ),
  );
}
