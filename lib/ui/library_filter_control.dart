import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/library_filter.dart';
import '../data/models.dart';
import 'shuffle_sheet.dart';

Future<void> openLibraryFilters(BuildContext context, AppController app) async {
  final account = app.account?.id, list = app.listId;
  final tracks = List<Track>.of(app.tracks);
  final ratings = Map<String, Rating>.of(app.ratings);
  final title = app.listTitle, filter = app.libraryFilter;
  final selection = await showModalBottomSheet<ShuffleSelection>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ShuffleSheet(
      tracks: tracks,
      ratings: ratings,
      title: title,
      libraryMode: true,
      initialFilter: filter,
    ),
  );
  if (selection == null || account != app.account?.id || list != app.listId) {
    return;
  }
  app.setLibraryFilter(selection.filter);
}

class LibraryFilterControl extends StatelessWidget {
  const LibraryFilterControl(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filter = app.libraryFilter;
    final label = filter.label
        .replaceAll('–', '\u2060–\u2060')
        .replaceAll(' баллов', '\u00a0баллов');
    return Material(
      color: filter.isActive
          ? scheme.surfaceContainerHigh
          : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: const Key('library-filter'),
              onTap: () => openLibraryFilters(context, app),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.filter_list_rounded,
                      size: 20,
                      color: filter.isActive
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        filter.isActive ? label : 'Жанры и баллы',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: filter.isActive
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (!filter.isActive)
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ),
          if (filter.isActive)
            IconButton(
              key: const Key('clear-library-filter'),
              tooltip: 'Сбросить фильтры',
              onPressed: () => app.setLibraryFilter(LibraryFilter.all),
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
        ],
      ),
    );
  }
}
