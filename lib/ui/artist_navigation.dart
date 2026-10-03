import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/catalog_models.dart';
import '../data/models.dart';
import '../data/zvuk_api.dart';
import 'catalog_widgets.dart';

Future<void> openTrackArtist(
  BuildContext context,
  AppController app,
  Track track,
) async {
  final api = app.api;
  try {
    if (track.artistIds.isEmpty ||
        (track.artistIds.length > 1 &&
            track.artistNames.length != track.artistIds.length)) {
      if (api == null) {
        throw const ZvukException('Обнови подключение в настройках.');
      }
      final tracks = await api.tracks([track.id]);
      if (!context.mounted || app.api != api) return;
      if (tracks.isNotEmpty) track = tracks.first;
    }
    if (track.artistIds.isEmpty) {
      throw const ZvukException('Исполнитель этой песни сейчас недоступен.');
    }
    if (!context.mounted) return;
    var index = 0;
    if (track.artistIds.length > 1) {
      final selected = await showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Выбери исполнителя')),
              for (var i = 0; i < track.artistIds.length; i++)
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text(
                    i < track.artistNames.length
                        ? track.artistNames[i]
                        : 'Артист ${i + 1}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(sheet, i),
                ),
            ],
          ),
        ),
      );
      if (selected == null || !context.mounted || app.api != api) return;
      index = selected;
    }
    await openCatalog(
      context,
      app,
      CatalogItem(
        id: track.artistIds[index],
        title: track.artistNames.length > index
            ? track.artistNames[index]
            : track.artists,
        kind: CatalogKind.artist,
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(catalogError(e))));
    }
  }
}

class ArtistLink extends StatelessWidget {
  const ArtistLink(this.app, this.track, {super.key, required this.style});
  final AppController app;
  final Track track;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (track.artists.isEmpty) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: 'Открыть исполнителя: ${track.artists}',
      child: Tooltip(
        message: 'Открыть исполнителя',
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => openTrackArtist(context, app, track),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    track.artists,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  size: style.fontSize ?? 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
