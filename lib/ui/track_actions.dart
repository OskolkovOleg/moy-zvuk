import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/models.dart';
import '../data/catalog_models.dart';
import 'catalog_widgets.dart';
import 'artist_navigation.dart';
import 'widgets.dart';
import 'lyrics_screen.dart';
import 'radio_actions.dart';
import '../data/wave_source.dart';

Future<void> openTrackActions(
  BuildContext context,
  AppController app,
  Track track, {
  Future<void> Function()? remove,
}) async {
  final value = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Artwork(track),
              title: Text(track.title),
              subtitle: Text(track.artists),
            ),
            for (final action in <(String, IconData, String)>[
              ('next', Icons.playlist_play_rounded, 'Следующим'),
              ('last', Icons.playlist_add_rounded, 'В конец очереди'),
              ('radio', Icons.sensors_rounded, 'Поток по песне'),
              (
                'similar',
                Icons.auto_awesome_rounded,
                'Добавить похожие в очередь',
              ),
              (
                'like',
                app.isFavorite(track.id)
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                app.isFavorite(track.id) ? 'Убрать из любимого' : 'В любимое',
              ),
              ('playlist', Icons.library_add_outlined, 'В плейлист'),
              ('lyrics', Icons.lyrics_outlined, 'Текст песни'),
              if (track.artists.isNotEmpty || track.artistIds.isNotEmpty)
                ('artist', Icons.person_outline_rounded, 'К артисту'),
              if (track.releaseId != null)
                ('album', Icons.album_outlined, 'К альбому'),
              if (remove != null)
                (
                  'remove',
                  Icons.remove_circle_outline_rounded,
                  'Убрать из этого плейлиста',
                ),
            ])
              ListTile(
                leading: Icon(action.$2),
                title: Text(action.$3),
                onTap: () => Navigator.pop(sheet, action.$1),
              ),
          ],
        ),
      ),
    ),
  );
  if (value == null || !context.mounted) return;
  try {
    switch (value) {
      case 'radio':
      case 'similar':
        await openRadioAction(
          context,
          app,
          WaveSource.fromTrack(track),
          appendFor: value == 'similar' ? track : null,
        );
      case 'next':
      case 'last':
        await app.music.enqueueTrack(track, next: value == 'next');
        if (context.mounted) {
          notify(
            context,
            value == 'next' ? 'Будет следующей' : 'Добавлено в конец очереди',
          );
        }
      case 'like':
        await app.setFavorite(track, !app.isFavorite(track.id));
        if (context.mounted) {
          notify(
            context,
            app.isFavorite(track.id)
                ? 'Добавлено в любимое'
                : 'Убрано из любимого',
          );
        }
      case 'lyrics':
        await openLyrics(context, app, track);
      case 'playlist':
        await chooseTrackPlaylist(context, app, track);
      case 'artist':
        await openTrackArtist(context, app, track);
      case 'album':
        await openCatalog(
          context,
          app,
          CatalogItem(
            id: track.releaseId!,
            title: 'Альбом',
            kind: CatalogKind.album,
          ),
        );
      case 'remove':
        await remove!();
    }
  } catch (e) {
    if (context.mounted) notify(context, catalogError(e));
  }
}

Future<void> chooseTrackPlaylist(
  BuildContext context,
  AppController app,
  Track track,
) async {
  final own = app.playlists.where(app.owns).toList();
  final id = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Добавить в плейлист')),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('Новый плейлист'),
            onTap: () => Navigator.pop(sheet, 'new'),
          ),
          for (final p in own)
            ListTile(
              title: Text(p.title),
              leading: const Icon(Icons.queue_music_rounded),
              onTap: () => Navigator.pop(sheet, p.id),
            ),
        ],
      ),
    ),
  );
  if (id == null || !context.mounted) return;
  if (id == 'new') {
    await playlistNameDialog(
      context,
      save: (name) async {
        await app.createPlaylist(name, trackIds: [track.id]);
      },
    );
  } else {
    await app.addToPlaylist(own.firstWhere((p) => p.id == id), track);
    if (context.mounted) notify(context, 'Добавлено в плейлист');
  }
}
