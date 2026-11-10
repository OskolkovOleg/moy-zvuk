import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/listening_stats.dart';

class LibrarySortButton extends StatelessWidget {
  const LibrarySortButton(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('library-sort'),
    tooltip: 'Сортировка: ${app.librarySort.label}',
    icon: const Icon(Icons.sort_rounded),
    onPressed: () async {
      final account = app.account?.id, list = app.listId;
      final selected = await showModalBottomSheet<LibrarySort>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('Сортировка')),
                for (final sort in LibrarySort.values.where(
                  (sort) => sort != LibrarySort.newest || list == 'favorites',
                ))
                  ListTile(
                    key: ValueKey('sort-${sort.name}'),
                    leading: Icon(switch (sort) {
                      LibrarySort.scores => Icons.leaderboard_outlined,
                      LibrarySort.newest => Icons.playlist_add_rounded,
                      LibrarySort.oldest => Icons.history_rounded,
                      LibrarySort.leastPlayed => Icons.date_range_rounded,
                    }),
                    title: Text(sort.label),
                    subtitle: Text(switch (sort) {
                      LibrarySort.scores => 'Сначала больше баллов',
                      LibrarySort.newest =>
                        'Последние добавленные в «Мои песни»',
                      LibrarySort.oldest => 'Сначала самые давние прослушивания. Без даты — в конце.',
                      LibrarySort.leastPlayed =>
                        'Меньше запусков в этом приложении за последние 7 дней',
                    }),
                    trailing: app.librarySort == sort
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => Navigator.pop(sheet, sort),
                  ),
              ],
            ),
          ),
        ),
      );
      if (selected == null ||
          account != app.account?.id ||
          list != app.listId) {
        return;
      }
      await app.setLibrarySort(selected);
    },
  );
}

class LibrarySortSummary extends StatelessWidget {
  const LibrarySortSummary(this.app, {super.key});
  final AppController app;
  @override
  Widget build(BuildContext context) {
    final sort = app.librarySort;
    if (sort == LibrarySort.scores) return const SizedBox.shrink();
    final stats = app.listeningStats, now = DateTime.now();
    final unknown = app.visibleTracks
        .where((t) => stats?.last[t.id] == null)
        .length;
    final description = sort == LibrarySort.newest
        ? 'По порядку добавления в Звук'
        : sort == LibrarySort.oldest
        ? (unknown == 0
              ? 'Сначала самые давние прослушивания'
              : 'Без даты: $unknown — в конце списка')
        : stats == null
        ? 'Счётчик запускается с этой версии приложения'
        : stats.fullWeek(now)
        ? 'Запуски в этом приложении за последние 7 дней'
        : 'Пока данные с ${_date(stats.since)} · полная неделя ещё не накоплена';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sort.label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 3),
          Text(
            sort.needsListeningStats && app.libraryHistoryLoading
                ? 'Обновляем историю…'
                : (sort.needsListeningStats ? app.libraryHistoryError : null) ??
                      description,
            key: const Key('library-sort-description'),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _date(DateTime at) {
  final d = at.toLocal();
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}
